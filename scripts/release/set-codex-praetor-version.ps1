param(
    [Parameter(Mandatory = $true)]
    [string]$Version,
    [string]$ProjectRoot = "",
    [switch]$Apply
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $ProjectRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
}
$root = [System.IO.Path]::GetFullPath($ProjectRoot)
if ($Version -notmatch '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$') { throw "Invalid semantic version: $Version" }

$jsonFiles = @(
    "config\runtime-contract.json",
    "plugin\runtime-contract.json",
    "plugin\skills\codex-praetor\scripts\runtime-contract.json",
    "skill\codex-praetor\scripts\runtime-contract.json",
    "plugin\.codex-plugin\plugin.json",
    "mcp\package.json",
    "plugin\mcp\package.json"
)
$textFiles = @(
    "setup.ps1",
    "mcp\src\server.ts",
    "mcp\package-lock.json",
    "README.md",
    "README.en.md",
    "docs\user\installation.zh.md",
    "docs\user\troubleshooting.zh.md",
    "docs\README.md",
    "docs\user\user-acceptance-checklist.zh.md",
    "docs\roadmap.md",
    "SECURITY.md",
    "scripts\release\build-codex-praetor-release.ps1",
    "scripts\release\publish-github-release-asset.ps1",
    "scripts\release\verify-github-release-asset.ps1",
    "scripts\verify\test-public-entry-consistency.ps1",
    "scripts\verify\test-release-package-determinism.ps1",
    "scripts\verify\test-supply-chain-controls.ps1",
    "docs\release\github-publish-runbook.md",
    "docs\release\release-gate-checklist.md"
)

function Read-Json([string]$relative) {
    $path = Join-Path $root $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Version source is missing: $relative" }
    return [pscustomobject]@{ path = $path; value = (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json) }
}

function Write-Json([string]$path, [object]$value) {
    $json = ($value | ConvertTo-Json -Depth 30) + [Environment]::NewLine
    [IO.File]::WriteAllText($path, $json, (New-Object Text.UTF8Encoding($false)))
}

foreach ($relative in $jsonFiles) {
    $item = Read-Json $relative
    $item.value.version = $Version
    if ($Apply) { Write-Json $item.path $item.value } else { Write-Host "would-update $relative" }
}

foreach ($relative in $textFiles) {
    $path = Join-Path $root $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Version text source is missing: $relative" }
    $text = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    $updated = $text -replace '0\.5\.0-alpha', $Version
    if ($Apply) {
        [IO.File]::WriteAllText($path, $updated, (New-Object Text.UTF8Encoding($false)))
    } else {
        Write-Host "would-update $relative"
    }
}

Write-Host "[PASS] Version surface plan prepared for $Version. Apply: $Apply"
