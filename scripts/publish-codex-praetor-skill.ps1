param(
    [string]$SourceSkill = "",
    [string]$InstalledSkill = (Join-Path $env:USERPROFILE ".codex\skills\codex-praetor"),
    [string]$BackupRoot = (Join-Path $env:USERPROFILE ".codex\codex-praetor-backups\skills"),
    [switch]$Apply
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
if ([string]::IsNullOrWhiteSpace($SourceSkill)) {
    $SourceSkill = Join-Path $projectRoot "skill\codex-praetor"
}

function Resolve-FullPath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Assert-RealDirectory {
    param([string]$Path, [string]$Label)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "$Label is not a directory: $Path"
    }
    $item = Get-Item -LiteralPath $Path -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "$Label must be a real directory, not a link or reparse point: $Path"
    }
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
    param(
        [hashtable]$Expected,
        [hashtable]$Actual
    )

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

$sourcePath = Resolve-FullPath $SourceSkill
$installedPath = Resolve-FullPath $InstalledSkill
$backupRootPath = Resolve-FullPath $BackupRoot
$installedParent = Split-Path -Parent $installedPath

Assert-RealDirectory $sourcePath "Source skill"
if (-not (Test-Path -LiteralPath $installedParent -PathType Container)) {
    throw "Installed skill parent does not exist: $installedParent"
}
if ($sourcePath -eq $installedPath) {
    throw "Source and installed skill paths must be different."
}
if ($sourcePath.StartsWith($installedPath + "\", [System.StringComparison]::OrdinalIgnoreCase) -or
    $installedPath.StartsWith($sourcePath + "\", [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Source and installed skill paths must not be nested."
}

$sourceSkillMd = Join-Path $sourcePath "SKILL.md"
if (-not (Test-Path -LiteralPath $sourceSkillMd -PathType Leaf)) {
    throw "Source SKILL.md missing: $sourceSkillMd"
}
$skillText = Get-Content -LiteralPath $sourceSkillMd -Raw
if ($skillText -notmatch "(?m)^name:\s*codex-praetor\s*$") {
    throw "Source SKILL.md frontmatter name is not codex-praetor."
}

if (Test-Path -LiteralPath $installedPath) {
    Assert-RealDirectory $installedPath "Installed skill"
}

$sourceMap = Get-RelativeHashMap $sourcePath
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$tempPath = Join-Path $installedParent ".codex-praetor.publish-$stamp.tmp"
$backupPath = Join-Path $backupRootPath "codex-praetor-$stamp"

Write-Host "Codex Praetor skill publish plan"
Write-Host "Source:    $sourcePath"
Write-Host "Installed: $installedPath"
Write-Host "Temp:      $tempPath"
Write-Host "Backup:    $backupPath"
Write-Host "Files:     $($sourceMap.Count)"

if (-not $Apply) {
    Write-Host ""
    Write-Host "Dry run only. Re-run with -Apply to replace the installed skill."
    exit 0
}

if (Test-Path -LiteralPath $tempPath) {
    throw "Temporary publish path already exists: $tempPath"
}
if (Test-Path -LiteralPath $backupPath) {
    throw "Backup path already exists: $backupPath"
}

$backupMade = $false
$failedPath = Join-Path $installedParent "codex-praetor.failed-$stamp"

try {
    New-Item -ItemType Directory -Path $tempPath -Force | Out-Null
    Copy-Item -Path (Join-Path $sourcePath "*") -Destination $tempPath -Recurse -Force

    $tempMap = Get-RelativeHashMap $tempPath
    $tempDiffs = Compare-HashMaps -Expected $sourceMap -Actual $tempMap
    if ($tempDiffs.Count -gt 0) {
        throw "Temporary copy differs from source: $($tempDiffs -join '; ')"
    }

    New-Item -ItemType Directory -Path $backupRootPath -Force | Out-Null
    if (Test-Path -LiteralPath $installedPath) {
        Move-Item -LiteralPath $installedPath -Destination $backupPath
        $backupMade = $true
    }

    Move-Item -LiteralPath $tempPath -Destination $installedPath

    $installedMap = Get-RelativeHashMap $installedPath
    $installedDiffs = Compare-HashMaps -Expected $sourceMap -Actual $installedMap
    if ($installedDiffs.Count -gt 0) {
        throw "Installed skill differs from source after publish: $($installedDiffs -join '; ')"
    }

    Write-Host "[PASS] Installed skill replaced with source skill."
    if ($backupMade) {
        Write-Host "[PASS] Previous installed skill moved to backup: $backupPath"
    } else {
        Write-Host "[PASS] No previous installed skill existed."
    }
} catch {
    Write-Host "[FAIL] Publish failed: $($_.Exception.Message)"

    if ((Test-Path -LiteralPath $installedPath) -and $backupMade) {
        Move-Item -LiteralPath $installedPath -Destination $failedPath
        Write-Host "[ROLLBACK] Failed installed copy moved to: $failedPath"
    }
    if ($backupMade -and -not (Test-Path -LiteralPath $installedPath) -and (Test-Path -LiteralPath $backupPath)) {
        Move-Item -LiteralPath $backupPath -Destination $installedPath
        Write-Host "[ROLLBACK] Previous installed skill restored."
    }

    throw
}
