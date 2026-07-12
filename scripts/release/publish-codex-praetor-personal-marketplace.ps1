param(
    [string]$SourcePlugin = (Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))) "plugin"),
    [string]$InstallRoot = (Join-Path $env:USERPROFILE "plugins\codex-praetor"),
    [string]$MarketplacePath = (Join-Path $env:USERPROFILE ".agents\plugins\marketplace.json"),
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

function Get-DirectoryChildren {
    param([string]$Root)
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        return @()
    }
    return @(Get-ChildItem -LiteralPath $Root -Force | Where-Object { $_.PSIsContainer })
}

function Remove-DirectoryList {
    param(
        [System.Collections.IEnumerable]$Items,
        [string]$Label
    )

    $removed = @()
    foreach ($item in @($Items)) {
        if (-not $item) {
            continue
        }
        Remove-Item -LiteralPath $item.FullName -Recurse -Force
        $removed += $item.FullName
    }

    if ($removed.Count -gt 0) {
        Write-Host "[PASS] Removed ${Label}:"
        foreach ($path in $removed) {
            Write-Host "  - $path"
        }
    }
}

function Test-RealDirectory {
    param([string]$Path, [string]$Label)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "$Label missing: $Path"
    }
    $item = Get-Item -LiteralPath $Path -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "$Label must be a real directory, not a link: $Path"
    }
}

function Update-PluginCachebuster {
    param([string]$PluginRoot, [string]$Stamp)

    $manifestPath = Join-Path $PluginRoot ".codex-plugin\plugin.json"
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "Installed plugin manifest missing before cachebuster: $manifestPath"
    }

    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $baseVersion = [string]$manifest.version
    if ([string]::IsNullOrWhiteSpace($baseVersion)) {
        throw "Plugin manifest version missing before cachebuster."
    }
    $baseVersion = $baseVersion -replace "\+codex\.[0-9A-Za-z.-]+$", ""
    $cacheStamp = Get-Date -Format "yyyyMMddHHmmss"
    $manifest.version = "$baseVersion+codex.$cacheStamp"
    $manifestJson = ($manifest | ConvertTo-Json -Depth 20) + [Environment]::NewLine
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($manifestPath, $manifestJson, $utf8NoBom)

    $updated = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$updated.version -ne "$baseVersion+codex.$cacheStamp") {
        throw "Plugin cachebuster failed; version is $($updated.version)"
    }
    return [string]$updated.version
}

$sourcePath = Resolve-FullPath $SourcePlugin
$installPath = Resolve-FullPath $InstallRoot
$marketplacePath = Resolve-FullPath $MarketplacePath
$installParent = Split-Path -Parent $installPath
$backupRoot = Join-Path $installParent ".codex-praetor-backups"

Test-RealDirectory $sourcePath "Source plugin"
if (-not (Test-Path -LiteralPath $marketplacePath -PathType Leaf)) {
    throw "Marketplace missing: $marketplacePath"
}

$marketplace = Get-Content -LiteralPath $marketplacePath -Raw -Encoding UTF8 | ConvertFrom-Json
$entry = @($marketplace.plugins | Where-Object { $_.name -eq "codex-praetor" } | Select-Object -First 1)
if ($entry.Count -eq 0) {
    throw "Marketplace entry codex-praetor is missing from $marketplacePath"
}
if ($entry[0].source.path -ne "./plugins/codex-praetor") {
    throw "Marketplace entry source path is unexpected: $($entry[0].source.path)"
}

Write-Host "Codex Praetor personal marketplace publish plan"
Write-Host "Source:      $sourcePath"
Write-Host "Install:     $installPath"
Write-Host "Marketplace: $marketplacePath"

if (-not $Apply) {
    Write-Host ""
    Write-Host "Dry run only. Re-run with -Apply to publish the marketplace install copy."
    exit 0
}

$sourceMap = Get-RelativeHashMap $sourcePath
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$tempPath = Join-Path $installParent ".codex-praetor.publish-$stamp.tmp"
$backupBasePath = Join-Path $backupRoot "codex-praetor-$stamp"
$backupPath = $backupBasePath
$backupSuffix = 1
while (Test-Path -LiteralPath $backupPath) {
    $backupPath = "$backupBasePath-$backupSuffix"
    $backupSuffix++
}

if (Test-Path -LiteralPath $tempPath) {
    throw "Temporary publish path already exists: $tempPath"
}

$backupMade = $false

try {
    New-Item -ItemType Directory -Path $tempPath -Force | Out-Null
    Copy-Item -Path (Join-Path $sourcePath "*") -Destination $tempPath -Recurse -Force

    $tempMap = Get-RelativeHashMap $tempPath
    $tempDiffs = Compare-HashMaps -Expected $sourceMap -Actual $tempMap
    if ($tempDiffs.Count -gt 0) {
        throw "Temporary copy differs from source: $($tempDiffs -join '; ')"
    }

    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
    if (Test-Path -LiteralPath $installPath) {
        Move-Item -LiteralPath $installPath -Destination $backupPath
        $backupMade = $true
    }

    Move-Item -LiteralPath $tempPath -Destination $installPath

    $cachebustedVersion = Update-PluginCachebuster -PluginRoot $installPath -Stamp $stamp

    $installedMap = Get-RelativeHashMap $installPath
    if (-not $installedMap.ContainsKey(".codex-plugin\plugin.json")) {
        throw "Installed plugin manifest missing after publish."
    }

    $stalePublishDirs = @(Get-DirectoryChildren $installParent | Where-Object {
        $_.Name -like ".codex-praetor.publish-*.tmp" -or $_.Name -like "codex-praetor.failed-*"
    })
    $staleBackupDirs = @(Get-DirectoryChildren $backupRoot | Where-Object {
        $_.Name -like "codex-praetor-*"
    })

    Remove-DirectoryList -Items $stalePublishDirs -Label "stale marketplace scratch directories"
    Remove-DirectoryList -Items $staleBackupDirs -Label "stale marketplace backup directories"

    Write-Host "[PASS] Personal marketplace install copy published."
    Write-Host "[PASS] Plugin version was cachebusted in the install copy: $cachebustedVersion"
    if ($backupMade) {
        Write-Host "[PASS] Previous install copy was backed up for rollback during publish and pruned after success."
    }
    Write-Host "Next step: codex plugin add codex-praetor@personal"
} catch {
    Write-Host "[FAIL] Publish failed: $($_.Exception.Message)"
    if ((Test-Path -LiteralPath $installPath) -and $backupMade) {
        Move-Item -LiteralPath $installPath -Destination (Join-Path $installParent "codex-praetor.failed-$stamp")
    }
    if ($backupMade -and -not (Test-Path -LiteralPath $installPath) -and (Test-Path -LiteralPath $backupPath)) {
        Move-Item -LiteralPath $backupPath -Destination $installPath
        Write-Host "[ROLLBACK] Previous install copy restored."
    }
    throw
}
