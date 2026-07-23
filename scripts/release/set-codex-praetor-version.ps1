param(
    [string]$Version = "",
    [string]$ProjectRoot = "",
    [switch]$Apply,
    [switch]$ListSourcePaths
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $ProjectRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
}
$root = [System.IO.Path]::GetFullPath($ProjectRoot)

$intentPath = Join-Path $root "config\release-intent.json"
if (-not (Test-Path -LiteralPath $intentPath -PathType Leaf)) { throw "Release intent is missing: $intentPath" }
$intent = Get-Content -LiteralPath $intentPath -Raw -Encoding UTF8 | ConvertFrom-Json
$currentVersion = [string]$intent.version
if ([string]::IsNullOrWhiteSpace($currentVersion)) { throw "Release intent does not declare a current version." }

$jsonFiles = @(
    "config\runtime-contract.json",
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
    "scripts\release\activate-published-codex-praetor-release.ps1",
    "scripts\verify\test-public-entry-consistency.ps1",
    "scripts\verify\test-release-package-determinism.ps1",
    "scripts\verify\test-release-artifact-runtime.ps1",
    "scripts\release\sync-codex-praetor-runtime-contract.ps1",
    "scripts\verify\test-supply-chain-controls.ps1",
    "docs\release\github-publish-runbook.md",
    "docs\release\release-gate-checklist.md",
    "docs\release\release-notes-$Version.md"
)
$runtimeDataSources = @(
    "config\evaluation-suite.json",
    "config\provider-onboarding-checklist.json",
    "config\provider-adapters\qoder.json",
    "config\provider-adapters\codebuddy.json",
    "config\provider-adapters\mimo.json"
)

if ($ListSourcePaths) {
    @(
        "config\release-intent.json",
        $jsonFiles,
        $textFiles,
        $runtimeDataSources,
        "scripts\release\set-codex-praetor-version.ps1"
    ) | Select-Object -Unique | ForEach-Object { $_ }
    return
}

if ($Version -notmatch '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$') { throw "Invalid semantic version: $Version" }
if ($currentVersion -eq $Version) { throw "Target version must differ from the current release intent version: $Version" }

function Read-Json([string]$relative) {
    $path = Join-Path $root $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Version source is missing: $relative" }
    return [pscustomobject]@{ path = $path; value = (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json) }
}

function Get-Utf8EncodingForExistingFile([string]$path) {
    $bytes = [IO.File]::ReadAllBytes($path)
    $hasUtf8Bom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    return (New-Object Text.UTF8Encoding($hasUtf8Bom))
}

function Set-JsonStringProperty([string]$path, [string]$property, [string]$value) {
    $text = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    $pattern = '(?m)(?<prefix>"' + [regex]::Escape($property) + '"\s*:\s*")[^"]*(?<suffix>")'
    $updated = [regex]::Replace($text, $pattern, ('${prefix}' + $value + '${suffix}'), 1)
    if ($updated -eq $text) { throw "JSON property '$property' was not found in $path" }
    [IO.File]::WriteAllText($path, $updated, (Get-Utf8EncodingForExistingFile $path))
}

foreach ($relative in $jsonFiles) {
    $item = Read-Json $relative
    if ($Apply) { Set-JsonStringProperty -path $item.path -property "version" -value $Version } else { Write-Host "would-update $relative" }
}

if ($Apply) {
    Set-JsonStringProperty -path $intentPath -property "previous_version" -value $currentVersion
    Set-JsonStringProperty -path $intentPath -property "version" -value $Version
    Set-JsonStringProperty -path $intentPath -property "tag" -value "v$Version"
    Set-JsonStringProperty -path $intentPath -property "artifact" -value "codex-praetor-setup-$Version.zip"
    & (Join-Path $root "scripts\release\sync-codex-praetor-runtime-contract.ps1") -ProjectRoot $root -Apply
    if ($LASTEXITCODE -ne 0) { throw "Runtime contract surface generation failed after version update." }
} else { Write-Host "would-update config\\release-intent.json" }

foreach ($relative in $textFiles) {
    $path = Join-Path $root $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Version text source is missing: $relative" }
    $text = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    $updated = $text.Replace($currentVersion, $Version)
    if ($Apply) {
        [IO.File]::WriteAllText($path, $updated, (Get-Utf8EncodingForExistingFile $path))
    } else {
        Write-Host "would-update $relative"
    }
}

Write-Host "[PASS] Version surface plan prepared for $Version. Apply: $Apply"
