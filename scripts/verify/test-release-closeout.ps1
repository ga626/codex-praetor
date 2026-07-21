param([string]$ProjectRoot = "")

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}
$projectPath = [IO.Path]::GetFullPath($ProjectRoot)
$testRoot = Join-Path $projectPath (".codex-praetor\plugin-boundary-smoke-" + [guid]::NewGuid().ToString("N"))
$releaseRoot = Join-Path $testRoot "release"
$releaseRootRelative = $releaseRoot.Substring($projectPath.Length).TrimStart("\\")
$profileRoot = Join-Path $testRoot "profile"
$buildScript = Join-Path $projectPath "scripts\release\build-codex-praetor-release.ps1"
$artifactRuntimeScript = Join-Path $projectPath "scripts\verify\test-release-artifact-runtime.ps1"
$installScript = Join-Path $projectPath "scripts\install\install-user.ps1"
$generationScript = Join-Path $projectPath "scripts\release\get-codex-praetor-generation.ps1"
$installationStateScript = Join-Path $projectPath "scripts\verify\get-codex-praetor-installation-state.ps1"

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

try {
    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
    $generation = (& $generationScript -ProjectRoot $projectPath -Json | ConvertFrom-Json)
    $version = [string]$generation.version
    & $buildScript -Version $version -OutputRoot $releaseRootRelative -Apply
    if ($LASTEXITCODE -ne 0) { throw "Release build failed in plugin-boundary smoke." }

    $stage = Join-Path $releaseRoot "codex-praetor-setup-$version"
    $zip = Join-Path $releaseRoot "codex-praetor-setup-$version.zip"
    Assert-True (Test-Path -LiteralPath $zip -PathType Leaf) "Release zip is missing."
    Assert-True (Test-Path -LiteralPath (Join-Path $stage "plugin\skills\codex-praetor\SKILL.md") -PathType Leaf) "Bundled Skill is missing."
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $stage "skill\codex-praetor\SKILL.md"))) "Release must not contain a second root Skill."

    $topGeneration = Get-Content -LiteralPath (Join-Path $stage "codex-praetor-release-generation.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    $pluginGeneration = Get-Content -LiteralPath (Join-Path $stage "plugin\release-generation.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ([string]$topGeneration.generation_id -eq [string]$pluginGeneration.generation_id) "Bundled plugin generation must equal the promoted artifact generation."
    Assert-True ([string]$pluginGeneration.runtime_contract_sha256 -eq [string]$generation.runtime_contract_sha256) "Bundled plugin generation must carry the canonical contract SHA."

    & $artifactRuntimeScript -Version $version -OutputRoot $releaseRootRelative -ProjectRoot $projectPath
    if ($LASTEXITCODE -ne 0) { throw "Bundled artifact runtime proof failed." }

    $pluginSource = Join-Path $stage "plugin"
    $marketplace = Join-Path $profileRoot ".agents\plugins\marketplace.json"
    $installRoot = Join-Path $profileRoot "plugins\codex-praetor"
    $expectedGenerationPath = Join-Path $stage "codex-praetor-release-generation.json"
    $beforeInstall = (& $installationStateScript -ExpectedGenerationPath $expectedGenerationPath -InstallRoot $installRoot -MarketplacePath $marketplace -Json | ConvertFrom-Json)
    Assert-True ([string]$beforeInstall.status -eq "needs_install") "Missing stable install must be classified as needs_install."

    & $installScript -SourcePlugin $pluginSource -ExpectedGenerationPath $expectedGenerationPath -InstallRoot $installRoot -MarketplacePath $marketplace -Apply
    if ($LASTEXITCODE -ne 0) { throw "Plugin-only installation failed." }
    Assert-True (Test-Path -LiteralPath (Join-Path $installRoot "skills\codex-praetor\SKILL.md") -PathType Leaf) "Installed plugin lacks bundled Skill."
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $profileRoot ".codex\skills\codex-praetor"))) "Installer must not create a global Skill copy."
    $cachePath = Join-Path $profileRoot ('.' + 'codex\plugins\cache')
    Assert-True (-not (Test-Path -LiteralPath $cachePath)) "Installer must not write the Codex-managed cache."
    $receipt = Get-Content -LiteralPath (Join-Path $profileRoot "plugins\codex-praetor-installation.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ([string]$receipt.source_kind -eq "release_bundle") "Release install receipt must not claim a development source."
    Assert-True ([string]$receipt.generation.generation_id -eq [string]$topGeneration.generation_id) "Install receipt must retain the installed generation identity."

    $afterInstall = (& $installationStateScript -ExpectedGenerationPath $expectedGenerationPath -InstallRoot $installRoot -MarketplacePath $marketplace -Json | ConvertFrom-Json)
    Assert-True ([string]$afterInstall.status -eq "needs_host_restart") "Installed target generation without host proof must require host restart."
    $oldHostPath = Join-Path $testRoot "old-host-runtime.json"
    [ordered]@{ runtime_contract = [ordered]@{ version = "0.0.0" }; contract_path = "C:\\old\\runtime-contract.json"; runtime_identity = [ordered]@{ runtime_contract_sha256 = "old"; project_root = "C:\\old"; process_id = 1 } } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $oldHostPath -Encoding UTF8
    $oldHostState = (& $installationStateScript -ExpectedGenerationPath $expectedGenerationPath -InstallRoot $installRoot -MarketplacePath $marketplace -HostRuntimeInfoPath $oldHostPath -Json | ConvertFrom-Json)
    Assert-True ([string]$oldHostState.status -eq "needs_host_restart") "Old host runtime must never enter canary."
    $currentHostPath = Join-Path $testRoot "current-host-runtime.json"
    [ordered]@{ runtime_contract = [ordered]@{ version = [string]$topGeneration.version }; contract_path = "C:\\cache\\runtime-contract.json"; runtime_identity = [ordered]@{ runtime_contract_sha256 = [string]$topGeneration.runtime_contract_sha256; project_root = "C:\\cache"; process_id = 1 } } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $currentHostPath -Encoding UTF8
    $currentHostState = (& $installationStateScript -ExpectedGenerationPath $expectedGenerationPath -InstallRoot $installRoot -MarketplacePath $marketplace -HostRuntimeInfoPath $currentHostPath -Json | ConvertFrom-Json)
    Assert-True ([string]$currentHostState.status -eq "needs_canary") "Matching installed and host identities must be the only route to canary."
    $newExpectedPath = Join-Path $testRoot "newer-release-generation.json"
    $newExpected = Get-Content -LiteralPath $expectedGenerationPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $newExpected.commit = "ffffffffffffffffffffffffffffffffffffffff"
    $newExpected.generation_id = "$($newExpected.version)--ffffffffffff--newer"
    $newExpected | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $newExpectedPath -Encoding UTF8
    $staleInstall = (& $installationStateScript -ExpectedGenerationPath $newExpectedPath -InstallRoot $installRoot -MarketplacePath $marketplace -Json | ConvertFrom-Json)
    Assert-True ([string]$staleInstall.status -eq "needs_install") "Old stable plugin must be classified as needs_install for a newer Release."
    Write-Host "[PASS] Plugin-only release boundary smoke passed."
} finally {
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
