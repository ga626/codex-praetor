param(
    [ValidateSet("stage", "activate")]
    [string]$Phase = "stage",
    [ValidateSet("stable", "dev")]
    [string]$Channel = "stable",
    [string]$ProjectRoot = "",
    [string]$UserProfileRoot = $env:USERPROFILE,
    [string]$ReleaseZip = "",
    [string]$ReleaseTag = "",
    [string]$ExpectedArtifactSha256 = "",
    [string]$FreshContextProofPath = "",
    [string]$ProviderReadinessPath = "",
    [switch]$Apply,
    [switch]$SkipMaintenance
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $ProjectRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
}

$projectPath = [System.IO.Path]::GetFullPath($ProjectRoot)
$profilePath = [System.IO.Path]::GetFullPath($UserProfileRoot)
if ($Channel -eq "dev" -and $profilePath -eq [System.IO.Path]::GetFullPath($env:USERPROFILE)) {
    throw "The dev channel requires an explicit isolated UserProfileRoot; it must not overwrite the stable user profile."
}

$generationScript = Join-Path $projectPath "scripts\release\get-codex-praetor-generation.ps1"
$installScript = Join-Path $projectPath "scripts\install\install-user.ps1"
$skillPublishScript = Join-Path $projectPath "scripts\release\publish-codex-praetor-skill.ps1"
$cachePublishScript = Join-Path $projectPath "scripts\release\publish-codex-praetor-personal-cache.ps1"
foreach ($path in @($generationScript, $installScript, $skillPublishScript, $cachePublishScript)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Release closeout dependency is missing: $path" }
}

$generation = (& $generationScript -ProjectRoot $projectPath -Json | ConvertFrom-Json)
if ([string]::IsNullOrWhiteSpace($ReleaseTag)) { $ReleaseTag = "v$($generation.version)" }

$codexRoot = Join-Path $profilePath ('.' + 'codex')
$skillPath = Join-Path $codexRoot "skills\codex-praetor"
$pluginPath = Join-Path $profilePath "plugins\codex-praetor"
$marketplacePath = Join-Path $profilePath ".agents\plugins\marketplace.json"
$cacheRoot = Join-Path $codexRoot (Join-Path "plugins" (Join-Path "cache" (Join-Path "personal" "codex-praetor")))
$skillBackupRoot = Join-Path $codexRoot "codex-praetor-backups\skills"
$cachePath = Join-Path $cacheRoot ([string]$generation.version)
$receiptRoot = Join-Path $codexRoot "codex-praetor-releases\$Channel"
$receiptPath = Join-Path $receiptRoot "receipts\$($generation.generation_id).json"
$activeReceiptPath = Join-Path $receiptRoot "active.json"
$artifactRoot = Join-Path $receiptRoot "artifacts"
$artifactExtractPath = Join-Path $artifactRoot $generation.generation_id

$tagConflict = $false
if (Test-Path -LiteralPath $activeReceiptPath -PathType Leaf) {
    try {
        $existingActive = Get-Content -LiteralPath $activeReceiptPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([string]$existingActive.release.tag -eq $ReleaseTag -and [string]$existingActive.generation.generation_id -ne [string]$generation.generation_id) {
            $tagConflict = $true
        }
    } catch {
        throw "Active receipt is unreadable; refusing to decide whether release tag '$ReleaseTag' can be reused: $($_.Exception.Message)"
    }
}
if ($tagConflict) {
    throw "Release tag '$ReleaseTag' is already active for another generation; immutable release tags cannot be reused."
}

function Get-TreeDigest {
    param([string]$Root)
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { throw "Tree is missing: $Root" }
    $rows = @(
        Get-ChildItem -LiteralPath $Root -Recurse -File -Force |
            Sort-Object FullName |
            ForEach-Object {
                $relative = $_.FullName.Substring($Root.Length).TrimStart("\\") -replace "\\", "/"
                "$relative|$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant())"
            }
    )
    $bytes = [Text.Encoding]::UTF8.GetBytes(($rows -join "`n"))
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant() } finally { $sha.Dispose() }
}

function Write-JsonAtomically {
    param([string]$Path, [object]$Value)
    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $temp = "$Path.tmp-$([Guid]::NewGuid().ToString('N'))"
    $json = ($Value | ConvertTo-Json -Depth 20) + [Environment]::NewLine
    [IO.File]::WriteAllText($temp, $json, (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $temp -Destination $Path -Force
}

function Assert-GenerationMatches {
    param([object]$ArtifactGeneration)

    $comparisons = @(
        @("generation_id", [string]$ArtifactGeneration.generation_id, [string]$generation.generation_id),
        @("version", [string]$ArtifactGeneration.version, [string]$generation.version),
        @("commit", [string]$ArtifactGeneration.commit, [string]$generation.commit),
        @("content_manifest_sha256", [string]$ArtifactGeneration.content_manifest_sha256, [string]$generation.content_manifest_sha256),
        @("runtime_contract_sha256", [string]$ArtifactGeneration.runtime_contract_sha256, [string]$generation.runtime_contract_sha256),
        @("wrapper_protocol", [string]$ArtifactGeneration.wrapper_protocol, [string]$generation.wrapper_protocol),
        @("task_contract_schema", [string]$ArtifactGeneration.task_contract_schema, [string]$generation.task_contract_schema),
        @("skill_tree_sha256", [string]$ArtifactGeneration.trees.skill.sha256, [string]$generation.trees.skill.sha256),
        @("plugin_tree_sha256", [string]$ArtifactGeneration.trees.plugin.sha256, [string]$generation.trees.plugin.sha256)
    )
    foreach ($comparison in $comparisons) {
        if ($comparison[1] -ne $comparison[2]) {
            throw "Release artifact generation mismatch for $($comparison[0])."
        }
    }

    $artifactTools = @($ArtifactGeneration.required_mcp_tools | ForEach-Object { [string]$_ })
    $sourceTools = @($generation.required_mcp_tools | ForEach-Object { [string]$_ })
    if (($artifactTools -join "`n") -ne ($sourceTools -join "`n")) {
        throw "Release artifact required MCP tools do not match the current generation."
    }
}

function Get-Artifact {
    param([switch]$PersistExtraction)

    if ([string]::IsNullOrWhiteSpace($ReleaseZip)) {
        if ($Channel -eq "stable") { throw "Stable staging requires a downloaded GitHub Release zip." }
        return $null
    }
    $zip = [IO.Path]::GetFullPath($ReleaseZip)
    if (-not (Test-Path -LiteralPath $zip -PathType Leaf)) { throw "Release zip is missing: $zip" }
    $hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
    if (-not [string]::IsNullOrWhiteSpace($ExpectedArtifactSha256) -and $hash -ne $ExpectedArtifactSha256.Trim().ToLowerInvariant()) {
        throw "Release zip SHA256 does not match ExpectedArtifactSha256."
    }
    $sidecar = "$zip.sha256"
    if ($Channel -eq "stable" -and -not (Test-Path -LiteralPath $sidecar -PathType Leaf)) {
        throw "Stable staging requires the downloaded .sha256 sidecar: $sidecar"
    }
    if (Test-Path -LiteralPath $sidecar -PathType Leaf) {
        $sidecarHash = ((Get-Content -LiteralPath $sidecar -Raw -Encoding UTF8) -split "\s+")[0].Trim().ToLowerInvariant()
        if ($sidecarHash -ne $hash) { throw "Release zip SHA256 does not match its sidecar file." }
    }
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($zip)
    try {
        $entryNames = @($archive.Entries | ForEach-Object { $_.FullName })
        foreach ($required in @("setup.ps1", "plugin/.codex-plugin/plugin.json", "plugin/mcp/dist/server.js", "skill/codex-praetor/SKILL.md", "codex-praetor-release-generation.json")) {
            if ($entryNames -notcontains $required) { throw "Release zip is missing required entry: $required" }
        }
    } finally { $archive.Dispose() }

    $tempExtractPath = Join-Path $receiptRoot "artifact-extract-$([Guid]::NewGuid().ToString('N')).tmp"
    if (Test-Path -LiteralPath $tempExtractPath) {
        Remove-Item -LiteralPath $tempExtractPath -Recurse -Force
    }
    New-Item -ItemType Directory -Path $tempExtractPath -Force | Out-Null
    try {
        [IO.Compression.ZipFile]::ExtractToDirectory($zip, $tempExtractPath)
        $generationManifestPath = Join-Path $tempExtractPath "codex-praetor-release-generation.json"
        $artifactGeneration = Get-Content -LiteralPath $generationManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        Assert-GenerationMatches -ArtifactGeneration $artifactGeneration
        if ($PersistExtraction) {
            if (Test-Path -LiteralPath $artifactExtractPath) {
                Remove-Item -LiteralPath $artifactExtractPath -Recurse -Force
            }
            New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null
            Move-Item -LiteralPath $tempExtractPath -Destination $artifactExtractPath -Force
            $tempExtractPath = ""
        }
    } finally {
        if (-not [string]::IsNullOrWhiteSpace($tempExtractPath) -and (Test-Path -LiteralPath $tempExtractPath)) {
            Remove-Item -LiteralPath $tempExtractPath -Recurse -Force
        }
    }

    return [ordered]@{
        path = $zip
        sha256 = $hash
        sidecar = if (Test-Path -LiteralPath $sidecar) { $sidecar } else { "" }
        generation_manifest = if ($PersistExtraction) { Join-Path $artifactExtractPath "codex-praetor-release-generation.json" } else { "" }
        extracted_root = if ($PersistExtraction) { $artifactExtractPath } else { "" }
    }
}

function Get-Surfaces {
    $marketplaceEntry = $null
    if (Test-Path -LiteralPath $marketplacePath -PathType Leaf) {
        $marketplace = Get-Content -LiteralPath $marketplacePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $marketplaceEntry = @($marketplace.plugins | Where-Object { $_.name -eq "codex-praetor" } | Select-Object -First 1)
    }
    if (@($marketplaceEntry).Count -ne 1 -or [string]$marketplaceEntry[0].source.path -ne "./plugins/codex-praetor") {
        throw "Marketplace does not point at the staged Codex Praetor plugin."
    }
    return [ordered]@{
        skill = [ordered]@{ path = $skillPath; tree_sha256 = Get-TreeDigest $skillPath }
        plugin = [ordered]@{ path = $pluginPath; tree_sha256 = Get-TreeDigest $pluginPath }
        cache = [ordered]@{ path = $cachePath; tree_sha256 = Get-TreeDigest $cachePath }
        marketplace = [ordered]@{ path = $marketplacePath; plugin_path = [string]$marketplaceEntry[0].source.path }
    }
}

if ($Phase -eq "stage") {
    $artifact = Get-Artifact -PersistExtraction:$Apply
    $stageSourceRoot = if ($null -ne $artifact -and -not [string]::IsNullOrWhiteSpace([string]$artifact.extracted_root)) { [string]$artifact.extracted_root } else { $projectPath }
    $stagePluginRoot = Join-Path $stageSourceRoot "plugin"
    $stageSkillRoot = Join-Path $stageSourceRoot "skill\codex-praetor"
    Write-Host "Codex Praetor release stage plan"
    Write-Host "Channel: $Channel"
    Write-Host "Generation: $($generation.generation_id)"
    Write-Host "Stage source: $stageSourceRoot"
    Write-Host "Profile: $profilePath"
    Write-Host "Receipt: $receiptPath"
    if (-not $Apply) {
        Write-Host "Dry run only. No install surface or receipt will be changed."
        exit 0
    }

    if (-not (Test-Path -LiteralPath (Join-Path $stagePluginRoot ".codex-plugin\plugin.json") -PathType Leaf)) {
        throw "Stage artifact plugin tree is missing or invalid: $stagePluginRoot"
    }
    if (-not (Test-Path -LiteralPath (Join-Path $stageSkillRoot "SKILL.md") -PathType Leaf)) {
        throw "Stage artifact skill tree is missing or invalid: $stageSkillRoot"
    }

    New-Item -ItemType Directory -Path (Split-Path -Parent $skillPath) -Force | Out-Null
    & $installScript -SourcePlugin $stagePluginRoot -InstallRoot $pluginPath -MarketplacePath $marketplacePath -Apply
    if ($LASTEXITCODE -ne 0) { throw "Plugin stage failed." }
    & $skillPublishScript -SourceSkill $stageSkillRoot -InstalledSkill $skillPath -BackupRoot $skillBackupRoot -Apply
    if ($LASTEXITCODE -ne 0) { throw "Skill stage failed." }
    & $cachePublishScript -InstallRoot $pluginPath -CacheRoot $cacheRoot -Apply
    if ($LASTEXITCODE -ne 0) { throw "Cache stage failed." }

    $surfaces = Get-Surfaces
    if ($surfaces.skill.tree_sha256 -ne [string]$generation.trees.skill.sha256 -or $surfaces.plugin.tree_sha256 -ne [string]$generation.trees.plugin.sha256 -or $surfaces.cache.tree_sha256 -ne [string]$generation.trees.plugin.sha256) {
        throw "Staged install surfaces do not match the source generation."
    }
    $receipt = [ordered]@{
        schema = "codex-praetor-release-receipt/v2"
        status = "staged"
        channel = $Channel
        staged_at = [DateTime]::UtcNow.ToString("o")
        generation = $generation
        release = [ordered]@{ tag = $ReleaseTag; artifact = $artifact }
        surfaces = $surfaces
        fresh_context = [ordered]@{ status = "pending" }
        provider_readiness = [ordered]@{ status = "pending"; generation_id = [string]$generation.generation_id; runtime_contract_sha256 = [string]$generation.runtime_contract_sha256; task_contract_schema = [string]$generation.task_contract_schema }
        rollback = [ordered]@{ previous_active_receipt = if (Test-Path -LiteralPath $activeReceiptPath) { $activeReceiptPath } else { "" } }
    }
    Write-JsonAtomically -Path $receiptPath -Value $receipt
    Write-Host "[PASS] Generation staged. It is not active until fresh-context and provider evidence are accepted."
    Write-Host "receipt=$receiptPath"
    exit 0
}

if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf)) { throw "Staged receipt is missing: $receiptPath" }
if ([string]::IsNullOrWhiteSpace($FreshContextProofPath) -or [string]::IsNullOrWhiteSpace($ProviderReadinessPath)) {
    throw "Activation requires FreshContextProofPath and ProviderReadinessPath."
}
if (-not (Test-Path -LiteralPath $FreshContextProofPath -PathType Leaf) -or -not (Test-Path -LiteralPath $ProviderReadinessPath -PathType Leaf)) {
    throw "Activation evidence path is missing."
}

$receipt = Get-Content -LiteralPath $receiptPath -Raw -Encoding UTF8 | ConvertFrom-Json
$proof = Get-Content -LiteralPath $FreshContextProofPath -Raw -Encoding UTF8 | ConvertFrom-Json
$readiness = Get-Content -LiteralPath $ProviderReadinessPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$receipt.status -ne "staged" -or [string]$receipt.generation.generation_id -ne [string]$generation.generation_id) { throw "Staged receipt does not match the current generation." }
if ([string]$receipt.schema -ne "codex-praetor-release-receipt/v2") { throw "Staged receipt uses an unsupported schema." }
if ([string]$proof.status -ne "passed" -or [string]$proof.generation_id -ne [string]$generation.generation_id) { throw "Fresh-context proof does not pass for this generation." }
if ([string]$readiness.schema -ne "codex-praetor-generation-readiness/v2" -or [string]$readiness.status -ne "passed" -or [string]$readiness.generation_id -ne [string]$generation.generation_id) { throw "Provider readiness does not pass for this generation." }
if ([string]$readiness.runtime_contract_sha256 -ne [string]$generation.runtime_contract_sha256 -or [string]$readiness.task_contract_schema -ne [string]$generation.task_contract_schema) { throw "Provider readiness does not match the runtime contract." }

$surfaces = Get-Surfaces
foreach ($surfaceName in @("skill", "plugin", "cache")) {
    if ([string]$surfaces.$surfaceName.tree_sha256 -ne [string]$receipt.surfaces.$surfaceName.tree_sha256) {
        throw "Activation surface drift detected: $surfaceName"
    }
}

Write-Host "Codex Praetor release activation plan"
Write-Host "Generation: $($generation.generation_id)"
Write-Host "Receipt: $activeReceiptPath"
if (-not $Apply) {
    Write-Host "Dry run only. The staged generation remains inactive."
    exit 0
}

$receipt.status = "active"
$receipt | Add-Member -NotePropertyName "activated_at" -NotePropertyValue ([DateTime]::UtcNow.ToString("o")) -Force
$receipt.surfaces = $surfaces
$receipt.fresh_context = $proof
$receipt.provider_readiness = $readiness
Write-JsonAtomically -Path $receiptPath -Value $receipt
Write-JsonAtomically -Path $activeReceiptPath -Value $receipt
$reconcileScript = Join-Path $projectPath "scripts\maintenance\reconcile-codex-praetor-generations.ps1"
if (-not (Test-Path -LiteralPath $reconcileScript -PathType Leaf)) { throw "Generation reconcile script is missing: $reconcileScript" }
& $reconcileScript -UserProfileRoot $profilePath -Channel $Channel -Apply
if ($LASTEXITCODE -ne 0) { throw "Generation retirement reconcile failed with exit code $LASTEXITCODE." }
$maintenanceScript = Join-Path $projectPath "scripts\install\install-codex-praetor-maintenance.ps1"
if ($Channel -eq "stable" -and -not $SkipMaintenance) {
    if (-not (Test-Path -LiteralPath $maintenanceScript -PathType Leaf)) { throw "Generation maintenance script is missing: $maintenanceScript" }
    & $maintenanceScript -UserProfileRoot $profilePath -SourceRoot $projectPath -Apply
    if ($LASTEXITCODE -ne 0) { throw "Generation maintenance task installation failed with exit code $LASTEXITCODE." }
} elseif ($SkipMaintenance) {
    Write-Host "[INFO] Maintenance task installation skipped. Only isolated validation may use this switch." -ForegroundColor Yellow
}
Write-Host "[PASS] Active release receipt written. Real dispatch may now rely on the generation health gate."
Write-Host "active_receipt=$activeReceiptPath"
