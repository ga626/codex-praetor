param([string]$ProjectRoot = "")

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$projectPath = [IO.Path]::GetFullPath($ProjectRoot)
$retired = @(
    "scripts\release\complete-codex-praetor-release.ps1",
    "scripts\release\publish-codex-praetor-skill.ps1",
    "scripts\release\publish-codex-praetor-personal-cache.ps1"
)
foreach ($relative in $retired) {
    if (Test-Path -LiteralPath (Join-Path $projectPath $relative)) { throw "Retired multi-surface release command remains callable: $relative" }
}
Write-Host "[PASS] Retired multi-surface release commands are absent."
