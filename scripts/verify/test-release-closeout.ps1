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
    & $installScript -SourcePlugin $pluginSource -InstallRoot $installRoot -MarketplacePath $marketplace -Apply
    if ($LASTEXITCODE -ne 0) { throw "Plugin-only installation failed." }
    Assert-True (Test-Path -LiteralPath (Join-Path $installRoot "skills\codex-praetor\SKILL.md") -PathType Leaf) "Installed plugin lacks bundled Skill."
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $profileRoot ".codex\skills\codex-praetor"))) "Installer must not create a global Skill copy."
    $cachePath = Join-Path $profileRoot ('.' + 'codex\plugins\cache')
    Assert-True (-not (Test-Path -LiteralPath $cachePath)) "Installer must not write the Codex-managed cache."
    Write-Host "[PASS] Plugin-only release boundary smoke passed."
} finally {
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
