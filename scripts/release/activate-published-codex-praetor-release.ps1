param(
    [string]$Version = "0.9.4-alpha",
    [string]$Tag = "",
    [string]$Repository = "ga626/codex-praetor",
    [string]$ReleaseZip = "",
    [string]$ReleaseSha256 = "",
    [string]$UserProfileRoot = $env:USERPROFILE,
    [string]$CodexCommand = "codex",
    [string]$HostRuntimeInfoPath = "",
    [switch]$SkipMaintenance,
    [switch]$Json
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($Tag)) { $Tag = "v$Version" }
$releaseName = "codex-praetor-setup-$Version"
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-praetor-activate-" + [Guid]::NewGuid().ToString("N"))

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Read-ReleaseGeneration([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Release generation is missing: $Path" }
    $generation = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($name in @("product", "version", "generation_id", "commit", "runtime_contract_sha256")) {
        if ([string]::IsNullOrWhiteSpace([string]$generation.$name)) { throw "Release generation lacks ${name}: $Path" }
    }
    if ([string]$generation.product -ne "codex-praetor") { throw "Unexpected release product: $($generation.product)" }
    if ([string]$generation.version -ne $Version) { throw "Release generation version differs from requested version: $($generation.version)" }
    return $generation
}

function Read-SidecarHash([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Release SHA256 sidecar is missing: $Path" }
    $text = (Get-Content -LiteralPath $Path -Raw -Encoding UTF8).Trim()
    if ($text -notmatch '^(?<hash>[0-9A-Fa-f]{64})(?:\s+\*?.*)?$') { throw "Release SHA256 sidecar is invalid: $Path" }
    return $Matches.hash.ToLowerInvariant()
}

function Resolve-GitHubTagCommit([string]$Repo, [string]$ReleaseTag) {
    $ref = (& gh api "repos/$Repo/git/ref/tags/$ReleaseTag" | ConvertFrom-Json).object
    if ([string]$ref.type -eq "tag") { $ref = (& gh api "repos/$Repo/git/tags/$($ref.sha)" | ConvertFrom-Json).object }
    if ([string]$ref.type -ne "commit" -or [string]$ref.sha -notmatch '^[0-9a-f]{40}$') { throw "GitHub tag $Repo@$ReleaseTag does not resolve to a commit." }
    return ([string]$ref.sha).ToLowerInvariant()
}

try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    $zipPath = ""
    $shaPath = ""
    $sourceKind = "published_release"
    if (-not [string]::IsNullOrWhiteSpace($ReleaseZip)) {
        $zipPath = [System.IO.Path]::GetFullPath($ReleaseZip)
        $shaPath = if ([string]::IsNullOrWhiteSpace($ReleaseSha256)) { "$zipPath.sha256" } else { [System.IO.Path]::GetFullPath($ReleaseSha256) }
        $sourceKind = "explicit_release_fixture"
    } else {
        if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw "GitHub CLI is required to activate a published Release." }
        $release = (& gh release view $Tag --repo $Repository --json isDraft,assets | ConvertFrom-Json)
        if ([bool]$release.isDraft) { throw "GitHub Release $Tag is still a draft." }
        $assets = @($release.assets | ForEach-Object { [string]$_.name })
        if ($assets -notcontains "$releaseName.zip" -or $assets -notcontains "$releaseName.zip.sha256") { throw "GitHub Release $Tag is missing its immutable zip or SHA256 sidecar." }
        & gh release download $Tag --repo $Repository --pattern "$releaseName.zip" --dir $tempRoot
        if ($LASTEXITCODE -ne 0) { throw "Failed to download the published Release zip." }
        & gh release download $Tag --repo $Repository --pattern "$releaseName.zip.sha256" --dir $tempRoot
        if ($LASTEXITCODE -ne 0) { throw "Failed to download the published Release SHA256 sidecar." }
        $zipPath = Join-Path $tempRoot "$releaseName.zip"
        $shaPath = Join-Path $tempRoot "$releaseName.zip.sha256"
    }
    if (-not (Test-Path -LiteralPath $zipPath -PathType Leaf)) { throw "Release zip is missing: $zipPath" }
    if ($SkipMaintenance -and $sourceKind -eq "published_release") { throw "Published Release activation may not skip generation maintenance installation." }
    $expectedHash = Read-SidecarHash -Path $shaPath
    $actualHash = Get-Sha256 -Path $zipPath
    if ($actualHash -ne $expectedHash) { throw "Release zip hash differs from its SHA256 sidecar." }

    $stage = Join-Path $tempRoot "stage"
    Expand-Archive -LiteralPath $zipPath -DestinationPath $stage -Force
    $generationPath = Join-Path $stage "codex-praetor-release-generation.json"
    $generation = Read-ReleaseGeneration -Path $generationPath
    if ($sourceKind -eq "published_release") {
        $tagCommit = Resolve-GitHubTagCommit -Repo $Repository -ReleaseTag $Tag
        if ([string]$generation.commit -ne $tagCommit) { throw "Downloaded Release generation does not match the immutable GitHub tag commit." }
    }

    $installScript = Join-Path $stage "scripts\install\install-user.ps1"
    $maintenanceScript = Join-Path $stage "scripts\install\install-codex-praetor-maintenance.ps1"
    $stateScript = Join-Path $stage "scripts\verify\get-codex-praetor-installation-state.ps1"
    foreach ($path in @($installScript, $maintenanceScript, $stateScript)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Release bundle is missing required activation script: $path" }
    }

    $profileRoot = [System.IO.Path]::GetFullPath($UserProfileRoot)
    $installRoot = Join-Path $profileRoot "plugins\codex-praetor"
    $marketplacePath = Join-Path $profileRoot ".agents\plugins\marketplace.json"
    $installOutput = (& powershell -NoProfile -ExecutionPolicy Bypass -File $installScript -SourcePlugin (Join-Path $stage "plugin") -ExpectedGenerationPath $generationPath -InstallRoot $installRoot -MarketplacePath $marketplacePath -Apply | Out-String)
    if ($LASTEXITCODE -ne 0) { throw "Bundled user installer failed." }
    if (-not $Json -and -not [string]::IsNullOrWhiteSpace($installOutput)) { Write-Host $installOutput.TrimEnd() }

    $pluginAddOutput = (& $CodexCommand plugin add "codex-praetor@personal" | Out-String)
    if ($LASTEXITCODE -ne 0) { throw "Official 'codex plugin add codex-praetor@personal' failed." }
    if (-not $Json -and -not [string]::IsNullOrWhiteSpace($pluginAddOutput)) { Write-Host $pluginAddOutput.TrimEnd() }
    $pluginList = (& $CodexCommand plugin list | Out-String)
    if ($LASTEXITCODE -ne 0) { throw "Official 'codex plugin list' failed after installation." }
    $pluginListPattern = "(?m)^\s*" + [regex]::Escape("codex-praetor@personal") + "\s+.*?\s+" + [regex]::Escape($Version) + "(?:\s|$)"
    if ($pluginList -notmatch $pluginListPattern) { throw "codex plugin list does not show an installed codex-praetor@personal $Version row." }

    if (-not $SkipMaintenance) {
        $maintenanceOutput = (& powershell -NoProfile -ExecutionPolicy Bypass -File $maintenanceScript -UserProfileRoot $profileRoot -SourceRoot $stage -Apply | Out-String)
        if ($LASTEXITCODE -ne 0) { throw "Generation maintenance installation failed." }
        if (-not $Json -and -not [string]::IsNullOrWhiteSpace($maintenanceOutput)) { Write-Host $maintenanceOutput.TrimEnd() }
    }
    $stateArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $stateScript, "-ExpectedGenerationPath", $generationPath, "-InstallRoot", $installRoot, "-MarketplacePath", $marketplacePath, "-Json")
    if (-not [string]::IsNullOrWhiteSpace($HostRuntimeInfoPath)) { $stateArgs += @("-HostRuntimeInfoPath", [System.IO.Path]::GetFullPath($HostRuntimeInfoPath)) }
    $state = (& powershell @stateArgs | Out-String | ConvertFrom-Json)
    if ([string]$state.status -eq "needs_install") { throw "Stable marketplace identity does not match the verified Release after activation." }
    $payload = [ordered]@{
        schema = "codex-praetor-published-activation/v1"
        status = [string]$state.status
        source_kind = $sourceKind
        version = $Version
        tag = $Tag
        generation = $generation
        release_sha256 = $actualHash
        installation_state = $state
        next_action = [string]$state.next_action
    }
    if ($Json) { $payload | ConvertTo-Json -Depth 14 } else { Write-Host "Activation status: $($payload.status)"; Write-Host "Next: $($payload.next_action)" }
} finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
