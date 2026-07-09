param(
    [string]$InstallRoot = (Join-Path $env:USERPROFILE "plugins\codex-praetor"),
    [string]$CacheRoot = (Join-Path $env:USERPROFILE ".codex\plugins\cache\personal\codex-praetor"),
    [switch]$Apply
)

$ErrorActionPreference = "Stop"

function Resolve-FullPath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Get-RelativeHashMap {
    param([string]$Root)
    $map = @{}
    Get-ChildItem -LiteralPath $Root -Recurse -File -Force |
        Sort-Object FullName |
        ForEach-Object {
            $relative = $_.FullName.Substring($Root.Length).TrimStart("\")
            $map[$relative] = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
        }
    return $map
}

function Compare-HashMaps {
    param([hashtable]$Expected, [hashtable]$Actual)
    $allKeys = @($Expected.Keys + $Actual.Keys | Sort-Object -Unique)
    $diffs = @()
    foreach ($key in $allKeys) {
        if (-not $Expected.ContainsKey($key)) {
            $diffs += "extra: $key"
        } elseif (-not $Actual.ContainsKey($key)) {
            $diffs += "missing: $key"
        } elseif ($Expected[$key] -ne $Actual[$key]) {
            $diffs += "changed: $key"
        }
    }
    return $diffs
}

$installPath = Resolve-FullPath $InstallRoot
$cacheRootPath = Resolve-FullPath $CacheRoot
$manifestPath = Join-Path $installPath ".codex-plugin\plugin.json"

if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Install manifest missing: $manifestPath"
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$version = [string]$manifest.version
if ([string]::IsNullOrWhiteSpace($version)) {
    throw "Install manifest version missing."
}

$sourceMap = Get-RelativeHashMap $installPath
$targetPath = Join-Path $cacheRootPath $version
$backupRoot = Join-Path $cacheRootPath ".backups"
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupPath = Join-Path $backupRoot $version
$tempPath = Join-Path $cacheRootPath ".publish-$stamp.tmp"

Write-Host "Codex Praetor personal cache publish plan"
Write-Host "Install: $installPath"
Write-Host "Cache:   $targetPath"

if (-not $Apply) {
    Write-Host ""
    Write-Host "Dry run only. Re-run with -Apply to populate the Codex personal cache."
    exit 0
}

if (Test-Path -LiteralPath $tempPath) {
    throw "Temporary path already exists: $tempPath"
}
if (Test-Path -LiteralPath $backupPath) {
    throw "Backup path already exists: $backupPath"
}

$backupMade = $false

try {
    New-Item -ItemType Directory -Path $tempPath -Force | Out-Null
    Copy-Item -Path (Join-Path $installPath "*") -Destination $tempPath -Recurse -Force

    $tempMap = Get-RelativeHashMap $tempPath
    $tempDiffs = Compare-HashMaps -Expected $sourceMap -Actual $tempMap
    if ($tempDiffs.Count -gt 0) {
        throw "Temporary cache copy differs from install root: $($tempDiffs -join '; ')"
    }

    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
    if (Test-Path -LiteralPath $targetPath) {
        Move-Item -LiteralPath $targetPath -Destination $backupPath
        $backupMade = $true
    }

    Move-Item -LiteralPath $tempPath -Destination $targetPath

    Write-Host "[PASS] Personal cache populated at $targetPath"
    if ($backupMade) {
        Write-Host "[PASS] Previous cache version backed up at $backupPath"
    }
    Write-Host "Next step: install with Codex from the personal marketplace or reload Codex and check whether codex-praetor tools appear."
} catch {
    Write-Host "[FAIL] Cache publish failed: $($_.Exception.Message)"
    if ((Test-Path -LiteralPath $targetPath) -and $backupMade) {
        Move-Item -LiteralPath $targetPath -Destination (Join-Path $cacheRootPath ".failed-$stamp")
    }
    if ($backupMade -and -not (Test-Path -LiteralPath $targetPath) -and (Test-Path -LiteralPath $backupPath)) {
        Move-Item -LiteralPath $backupPath -Destination $targetPath
        Write-Host "[ROLLBACK] Previous cache version restored."
    }
    throw
}
