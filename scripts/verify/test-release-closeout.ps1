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
        schema = "codex-praetor-generation-readiness/v1"
        status = "passed"
        generation_id = [string]$generation.generation_id
        provider = "test"
        tuple = [ordered]@{ cli = "test"; model = "test"; mode = "readonly" }
    }
    $readiness | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $readinessPath -Encoding UTF8
    & $closeoutScript -Phase activate -Channel stable -ProjectRoot $projectPath -UserProfileRoot $profileRoot -FreshContextProofPath $proofPath -ProviderReadinessPath $readinessPath -Apply
    if ($LASTEXITCODE -ne 0) { throw "Release activation failed in closeout smoke." }
    Assert-True (Test-Path -LiteralPath $activeReceipt -PathType Leaf) "Activation must write an active receipt."

    & $healthScript -Repo $projectPath -Channel stable -UserProfileRoot $profileRoot -Json | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) "Healthy isolated generation must pass the health gate."

    Add-Content -LiteralPath (Join-Path $profileRoot "plugins\codex-praetor\mcp\README.md") -Value "tamper"
    & $healthScript -Repo $projectPath -Channel stable -UserProfileRoot $profileRoot -Json | Out-Null
    Assert-True ($LASTEXITCODE -eq 2) "Plugin drift must block the health gate."

    Write-Host "[PASS] Release closeout smoke passed: stage, activation, and drift rejection are verified."
} finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
