param(
    [string]$ProjectRoot = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $ProjectRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
}

$projectPath = [System.IO.Path]::GetFullPath($ProjectRoot)
$testRoot = Join-Path $projectPath (".codex-praetor\closeout-smoke-" + [Guid]::NewGuid().ToString("N"))
$releaseRoot = Join-Path $testRoot "release"
$releaseRootRelative = $releaseRoot.Substring($projectPath.Length).TrimStart("\\")
$profileRoot = Join-Path $testRoot "profile"
$observedToolsPath = Join-Path $testRoot "observed-tools.json"
$proofPath = Join-Path $testRoot "fresh-context-proof.json"
$readinessPath = Join-Path $testRoot "provider-readiness.json"
$noReceiptProfileRoot = Join-Path $testRoot "no-active-receipt-profile"
$generationScript = Join-Path $projectPath "scripts\release\get-codex-praetor-generation.ps1"
$buildScript = Join-Path $projectPath "scripts\release\build-codex-praetor-release.ps1"
$closeoutScript = Join-Path $projectPath "scripts\release\complete-codex-praetor-release.ps1"
$proofScript = Join-Path $projectPath "scripts\verify\new-codex-praetor-fresh-context-proof.ps1"
$healthScript = Join-Path $projectPath "scripts\verify\get-codex-praetor-health.ps1"

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

try {
    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
    $generation = (& $generationScript -ProjectRoot $projectPath -Json | ConvertFrom-Json)
    $version = [string]$generation.version
    $tag = "v$version"

    & $buildScript -Version $version -OutputRoot $releaseRootRelative -Apply
    if ($LASTEXITCODE -ne 0) { throw "Release build failed in closeout smoke." }
    $releaseZip = Join-Path $releaseRoot "codex-praetor-setup-$version.zip"
    Assert-True (Test-Path -LiteralPath $releaseZip -PathType Leaf) "Closeout smoke release zip is missing."

    $invalidZip = Join-Path $testRoot "invalid.zip"
    [IO.File]::WriteAllText($invalidZip, "not a release zip", (New-Object Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText("$invalidZip.sha256", "$(Get-FileHash -LiteralPath $invalidZip -Algorithm SHA256 | Select-Object -ExpandProperty Hash)  invalid.zip`n", (New-Object Text.UTF8Encoding($false)))
    $invalidFailed = $false
    try {
        & $closeoutScript -Phase stage -Channel stable -ProjectRoot $projectPath -UserProfileRoot $profileRoot -ReleaseZip $invalidZip -ReleaseTag $tag -Apply
    } catch {
        $invalidFailed = $true
    }
    Assert-True $invalidFailed "Invalid release zip must fail before staging."
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $profileRoot ".codex\codex-praetor-releases\stable\active.json"))) "Invalid stage must not write an active receipt."

    & $closeoutScript -Phase stage -Channel stable -ProjectRoot $projectPath -UserProfileRoot $profileRoot -ReleaseZip $releaseZip -ReleaseTag $tag -Apply
    if ($LASTEXITCODE -ne 0) { throw "Release stage failed in closeout smoke." }
    $activeReceipt = Join-Path $profileRoot ".codex\codex-praetor-releases\stable\active.json"
    Assert-True (-not (Test-Path -LiteralPath $activeReceipt)) "Stage must not activate a release receipt."
    $stagedReceipt = Join-Path $profileRoot ".codex\codex-praetor-releases\stable\receipts\$($generation.generation_id).json"
    Assert-True (Test-Path -LiteralPath $stagedReceipt -PathType Leaf) "Stage must write a generation receipt."
    $stageReceiptPayload = Get-Content -LiteralPath $stagedReceipt -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True (Test-Path -LiteralPath ([string]$stageReceiptPayload.release.artifact.generation_manifest) -PathType Leaf) "Stage receipt must point at the extracted release generation manifest."
    Assert-True ([string]$stageReceiptPayload.surfaces.skill.tree_sha256 -eq [string]$generation.trees.skill.sha256) "Staged Skill surface must match the release generation."
    Assert-True ([string]$stageReceiptPayload.surfaces.plugin.tree_sha256 -eq [string]$generation.trees.plugin.sha256) "Staged plugin surface must match the release generation."
    Assert-True ([string]$stageReceiptPayload.surfaces.cache.tree_sha256 -eq [string]$generation.trees.plugin.sha256) "Staged cache surface must match the release generation."

    $observed = [ordered]@{ source = "isolated-closeout-smoke"; tool_names = @($generation.required_mcp_tools) }
    $observed | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $observedToolsPath -Encoding UTF8
    & $proofScript -ProjectRoot $projectPath -ObservedToolsPath $observedToolsPath -OutputPath $proofPath -Apply
    if ($LASTEXITCODE -ne 0) { throw "Fresh-context proof failed in closeout smoke." }
    $readiness = [ordered]@{
        schema = "codex-praetor-generation-readiness/v2"
        status = "passed"
        generation_id = [string]$generation.generation_id
        runtime_contract_sha256 = [string]$generation.runtime_contract_sha256
        task_contract_schema = [string]$generation.task_contract_schema
        provider = "test"
        tuple = [ordered]@{ cli = "test"; model = "test"; mode = "readonly" }
    }
    $readiness | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $readinessPath -Encoding UTF8
    & $closeoutScript -Phase activate -Channel stable -ProjectRoot $projectPath -UserProfileRoot $profileRoot -FreshContextProofPath $proofPath -ProviderReadinessPath $readinessPath -Apply -SkipMaintenance
    if ($LASTEXITCODE -ne 0) { throw "Release activation failed in closeout smoke." }
    Assert-True (Test-Path -LiteralPath $activeReceipt -PathType Leaf) "Activation must write an active receipt."

    & $healthScript -Repo $projectPath -Channel stable -UserProfileRoot $profileRoot -Json | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) "Healthy isolated generation must pass the health gate."

    Add-Content -LiteralPath (Join-Path $profileRoot "plugins\codex-praetor\mcp\README.md") -Value "tamper"
    & $healthScript -Repo $projectPath -Channel stable -UserProfileRoot $profileRoot -Json | Out-Null
    Assert-True ($LASTEXITCODE -eq 2) "Plugin drift must block the health gate."

    $cacheRoot = Join-Path $profileRoot (Join-Path ('.' + 'codex') (Join-Path "plugins" (Join-Path "cache" (Join-Path "personal" "codex-praetor"))))
    $activeCachePath = Join-Path $cacheRoot ([string]$generation.version)
    Assert-True (Test-Path -LiteralPath $activeCachePath -PathType Container) "Active cache generation must remain present."

    $stalePath = Join-Path $cacheRoot "0.1.0-alpha"
    New-Item -ItemType Directory -Path $stalePath -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $stalePath "stale.txt") -Value "stale" -Encoding ASCII
    (Get-Item -LiteralPath $stalePath).LastWriteTimeUtc = [DateTime]::UtcNow.AddMinutes(-2)
    & (Join-Path $projectPath "scripts\maintenance\reconcile-codex-praetor-generations.ps1") -UserProfileRoot $profileRoot -Channel stable -RetentionDays 0 -Apply
    Assert-True (-not (Test-Path -LiteralPath $stalePath)) "Expired inactive cache generation must be deleted."
    Assert-True (Test-Path -LiteralPath $activeCachePath -PathType Container) "Retirement reconcile must not delete the active cache generation."

    $noReceiptCacheRoot = Join-Path $noReceiptProfileRoot (Join-Path ('.' + 'codex') (Join-Path "plugins" (Join-Path "cache" (Join-Path "personal" "codex-praetor"))))
    $noReceiptStalePath = Join-Path $noReceiptCacheRoot "0.0.1-alpha"
    New-Item -ItemType Directory -Path $noReceiptStalePath -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $noReceiptStalePath "stale.txt") -Value "stale" -Encoding ASCII
    & (Join-Path $projectPath "scripts\maintenance\reconcile-codex-praetor-generations.ps1") -UserProfileRoot $noReceiptProfileRoot -Channel stable -RetentionDays 0 -Apply
    Assert-True (Test-Path -LiteralPath $noReceiptStalePath -PathType Container) "Without an active receipt, retirement must defer deletion."

    $lockedPath = Join-Path $cacheRoot "0.1.1-alpha"
    $lockedFilePath = Join-Path $lockedPath "locked.txt"
    New-Item -ItemType Directory -Path $lockedPath -Force | Out-Null
    Set-Content -LiteralPath $lockedFilePath -Value "locked" -Encoding ASCII
    (Get-Item -LiteralPath $lockedPath).LastWriteTimeUtc = [DateTime]::UtcNow.AddMinutes(-2)
    $lockStream = [IO.File]::Open($lockedFilePath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
    try {
        & (Join-Path $projectPath "scripts\maintenance\reconcile-codex-praetor-generations.ps1") -UserProfileRoot $profileRoot -Channel stable -RetentionDays 0 -Apply
        $retirementPath = Join-Path $profileRoot ".codex\codex-praetor-releases\stable\retirement.json"
        $retirementPayload = Get-Content -LiteralPath $retirementPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $lockedEntry = @($retirementPayload.entries | Where-Object { [string]$_.path -ieq ([IO.Path]::GetFullPath($lockedPath)) } | Select-Object -First 1)
        Assert-True ($lockedEntry.Count -eq 1 -and [string]$lockedEntry[0].status -eq "blocked_by_process") "Locked retired generation must be recorded as blocked_by_process."
    } finally {
        $lockStream.Dispose()
    }
    & (Join-Path $projectPath "scripts\maintenance\reconcile-codex-praetor-generations.ps1") -UserProfileRoot $profileRoot -Channel stable -RetentionDays 0 -Apply
    Assert-True (-not (Test-Path -LiteralPath $lockedPath)) "A previously locked retired generation must be removed on a later retry."

    Write-Host "[PASS] Release closeout smoke passed: stage, activation, drift rejection, and retirement lifecycle are verified."
} finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
