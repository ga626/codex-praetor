param([string]$ProjectRoot = "")

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$root = [System.IO.Path]::GetFullPath($ProjectRoot)
$scratch = Join-Path $root (".codex-praetor\published-activation-" + [Guid]::NewGuid().ToString("N"))
$build = Join-Path $root "scripts\release\build-codex-praetor-release.ps1"
$generation = Join-Path $root "scripts\release\get-codex-praetor-generation.ps1"
$activation = Join-Path $root "scripts\release\activate-published-codex-praetor-release.ps1"

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

try {
    New-Item -ItemType Directory -Path $scratch -Force | Out-Null
    $current = (& $generation -ProjectRoot $root -Json | ConvertFrom-Json)
    $version = [string]$current.version
    $releaseRoot = Join-Path $scratch "release"
    $releaseRootRelative = $releaseRoot.Substring($root.Length).TrimStart("\\")
    & powershell -NoProfile -ExecutionPolicy Bypass -File $build -Version $version -OutputRoot $releaseRootRelative -Apply
    if ($LASTEXITCODE -ne 0) { throw "Fixture release build failed." }
    $zip = Join-Path $releaseRoot "codex-praetor-setup-$version.zip"
    $sha = "$zip.sha256"
    $fakeCodex = Join-Path $scratch "fake-codex.cmd"
    @"
@echo off
if "%1"=="plugin" if "%2"=="add" exit /b 0
if "%1"=="plugin" if "%2"=="list" echo codex-praetor@personal $version
exit /b 0
"@ | Set-Content -LiteralPath $fakeCodex -Encoding ASCII
    $profile = Join-Path $scratch "profile"
    $result = (& powershell -NoProfile -ExecutionPolicy Bypass -File $activation -Version $version -ReleaseZip $zip -ReleaseSha256 $sha -UserProfileRoot $profile -CodexCommand $fakeCodex -SkipMaintenance -Json | Out-String | ConvertFrom-Json)
    Assert-True ([string]$result.source_kind -eq "explicit_release_fixture") "Fixture activation must be labeled as a fixture, never as a published delivery proof."
    Assert-True ([string]$result.status -eq "needs_host_restart") "Verified installation must stop at the explicit host refresh boundary."
    Assert-True ([string]$result.generation.generation_id -eq [string]$current.generation_id) "Activated plugin must retain the exact bundled generation."
    Assert-True (Test-Path -LiteralPath (Join-Path $profile "plugins\codex-praetor\release-generation.json") -PathType Leaf) "Activation did not install the bundled plugin generation."
    Write-Host "[PASS] Published Release activation installs the verified bundle, uses the official plugin command, and stops at host refresh."
} finally {
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}
