param(
    [string]$SourcePlugin = (Join-Path (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)) "plugin"),
    [string]$InstallRoot = (Join-Path $env:USERPROFILE "plugins\codex-praetor"),
    [string]$MarketplacePath = (Join-Path $env:USERPROFILE ".agents\plugins\marketplace.json"),
    [switch]$Apply
)

$ErrorActionPreference = "Stop"

function Resolve-FullPath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Assert-RealDirectoryIfExists {
    param([string]$Path, [string]$Label)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $item = Get-Item -LiteralPath $Path -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "$Label must be a real directory, not a link: $Path"
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

function New-MarketplacePayload {
    return [ordered]@{
        name = "personal"
        interface = [ordered]@{ displayName = "Personal" }
        plugins = @()
    }
}

function Update-Marketplace {
    param([string]$Path)

    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $parent -Force | Out-Null

    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        $payload = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    } else {
        $payload = New-MarketplacePayload
    }

    if (-not $payload.name) {
        $payload | Add-Member -NotePropertyName name -NotePropertyValue "personal"
    }
    if (-not $payload.interface) {
        $payload | Add-Member -NotePropertyName interface -NotePropertyValue ([pscustomobject]@{ displayName = "Personal" })
    }
    if (-not $payload.plugins) {
        $payload | Add-Member -NotePropertyName plugins -NotePropertyValue @()
    }

    $plugins = @($payload.plugins | Where-Object { $_.name -ne "codex-praetor" })
    $plugins += [pscustomobject]@{
        name = "codex-praetor"
        source = [pscustomobject]@{
            source = "local"
            path = "./plugins/codex-praetor"
        }
        policy = [pscustomobject]@{
            installation = "AVAILABLE"
            authentication = "ON_INSTALL"
        }
        category = "Productivity"
    }
    $payload.plugins = @($plugins)

    $json = ($payload | ConvertTo-Json -Depth 20) + [Environment]::NewLine
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $json, $utf8NoBom)
}

$sourcePath = Resolve-FullPath $SourcePlugin
$installPath = Resolve-FullPath $InstallRoot
$marketplacePath = Resolve-FullPath $MarketplacePath
$installParent = Split-Path -Parent $installPath

if (-not (Test-Path -LiteralPath $sourcePath -PathType Container)) {
    throw "Source plugin missing: $sourcePath"
}
if (-not (Test-Path -LiteralPath (Join-Path $sourcePath ".codex-plugin\plugin.json") -PathType Leaf)) {
    throw "Source plugin manifest missing under: $sourcePath"
}

Assert-RealDirectoryIfExists -Path $installPath -Label "Existing install"

Write-Host "Codex Praetor user install plan"
Write-Host "Source plugin: $sourcePath"
Write-Host "Install path:   $installPath"
Write-Host "Marketplace:    $marketplacePath"
Write-Host "Mode:           $(if ($Apply) { 'apply' } else { 'dry-run' })"

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Write-Host "[WARN] Node.js was not found on PATH. Codex Praetor MCP needs node to start."
}

if (-not $Apply) {
    Write-Host ""
    Write-Host "Dry run only. Re-run with -Apply to install."
    exit 0
}

$sourceMap = Get-RelativeHashMap $sourcePath
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$tempPath = Join-Path $installParent ".codex-praetor.install-$stamp.tmp"
$backupRoot = Join-Path $installParent ".codex-praetor-backups"
$backupPath = Join-Path $backupRoot "codex-praetor-$stamp"

if (Test-Path -LiteralPath $tempPath) {
    throw "Temporary install path already exists: $tempPath"
}

try {
    New-Item -ItemType Directory -Path $installParent -Force | Out-Null
    New-Item -ItemType Directory -Path $tempPath -Force | Out-Null
    Copy-Item -Path (Join-Path $sourcePath "*") -Destination $tempPath -Recurse -Force

    $tempDiffs = Compare-HashMaps -Expected $sourceMap -Actual (Get-RelativeHashMap $tempPath)
    if ($tempDiffs.Count -gt 0) {
        throw "Temporary install copy differs from source: $($tempDiffs -join '; ')"
    }

    if (Test-Path -LiteralPath $installPath) {
        New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
        Move-Item -LiteralPath $installPath -Destination $backupPath
    }

    Move-Item -LiteralPath $tempPath -Destination $installPath
    Update-Marketplace -Path $marketplacePath

    $installedDiffs = Compare-HashMaps -Expected $sourceMap -Actual (Get-RelativeHashMap $installPath)
    if ($installedDiffs.Count -gt 0) {
        throw "Installed copy differs from source: $($installedDiffs -join '; ')"
    }

    Write-Host "[PASS] Codex Praetor plugin copied to a real local directory."
    Write-Host "[PASS] Personal marketplace entry is present."
    Write-Host "Next: restart Codex or open a new task once so the plugin can be discovered."
    Write-Host "After that, ask Codex to split a task for external agents in dry-run mode."
} catch {
    if (Test-Path -LiteralPath $tempPath) {
        Remove-Item -LiteralPath $tempPath -Recurse -Force
    }
    throw
}
