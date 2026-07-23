param(
    [string]$SourcePlugin = (Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))) "plugin"),
    [string]$InstallRoot = (Join-Path $env:USERPROFILE "plugins\codex-praetor"),
    [string]$MarketplacePath = (Join-Path $env:USERPROFILE ".agents\plugins\marketplace.json"),
    [string]$ExpectedGenerationPath = "",
    [switch]$Apply
)

$ErrorActionPreference = "Stop"
. (Join-Path (Split-Path -Parent $PSScriptRoot) "shared\ensure-file-hash.ps1")

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
    return [pscustomobject]@{
        name = "personal"
        interface = [pscustomobject]@{ displayName = "Personal" }
        plugins = @()
    }
}

function Test-ObjectProperty {
    param([object]$Object, [string]$Name)
    if ($null -eq $Object) { return $false }
    return ($Object.PSObject.Properties.Name -contains $Name)
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

    if (-not (Test-ObjectProperty -Object $payload -Name "name") -or [string]::IsNullOrWhiteSpace([string]$payload.name)) {
        $payload | Add-Member -NotePropertyName name -NotePropertyValue "personal"
    }
    if (-not (Test-ObjectProperty -Object $payload -Name "interface") -or $null -eq $payload.interface) {
        $payload | Add-Member -NotePropertyName interface -NotePropertyValue ([pscustomobject]@{ displayName = "Personal" })
    }
    if (-not (Test-ObjectProperty -Object $payload -Name "plugins") -or $null -eq $payload.plugins) {
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

    $written = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    $entry = @($written.plugins | Where-Object { $_.name -eq "codex-praetor" } | Select-Object -First 1)
    if ($entry.Count -eq 0) {
        throw "Marketplace write verification failed: codex-praetor entry is missing from $Path"
    }
    if ([string]$entry[0].source.path -ne "./plugins/codex-praetor") {
        throw "Marketplace write verification failed: unexpected plugin path $($entry[0].source.path)"
    }
}

function Read-GenerationIfPresent {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try {
        $generation = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($name in @("product", "version", "generation_id", "commit", "runtime_contract_sha256")) {
            if ([string]::IsNullOrWhiteSpace([string]$generation.$name)) { throw "missing $name" }
        }
        if ([string]$generation.product -ne "codex-praetor") { throw "unexpected product" }
        return $generation
    } catch { throw "Release generation manifest is invalid: $Path ($($_.Exception.Message))" }
}

function Test-GenerationEqual {
    param($Left, $Right)
    return $null -ne $Left -and $null -ne $Right -and
        [string]$Left.version -eq [string]$Right.version -and
        [string]$Left.generation_id -eq [string]$Right.generation_id -and
        [string]$Left.commit -eq [string]$Right.commit -and
        [string]$Left.runtime_contract_sha256 -eq [string]$Right.runtime_contract_sha256
}

function Write-InstallationReceipt {
    param([string]$Path, [string]$InstallPath, [string]$MarketplacePath, $Generation)
    $receipt = [ordered]@{
        schema = "codex-praetor-installation-receipt/v1"
        installed_at = [DateTime]::UtcNow.ToString("o")
        source_kind = if ($null -eq $Generation) { "development_source" } else { "release_bundle" }
        install_path = $InstallPath
        marketplace_path = $MarketplacePath
        generation = $Generation
    }
    $temp = "$Path.tmp-$([Guid]::NewGuid().ToString('N'))"
    [IO.File]::WriteAllText($temp, (($receipt | ConvertTo-Json -Depth 10) + [Environment]::NewLine), (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $temp -Destination $Path -Force
}

$sourcePath = Resolve-FullPath $SourcePlugin
$installPath = Resolve-FullPath $InstallRoot
$marketplacePath = Resolve-FullPath $MarketplacePath
$installParent = Split-Path -Parent $installPath
$sourceGeneration = Read-GenerationIfPresent -Path (Join-Path $sourcePath "release-generation.json")
if (-not [string]::IsNullOrWhiteSpace($ExpectedGenerationPath)) {
    $expectedGeneration = Read-GenerationIfPresent -Path (Resolve-FullPath $ExpectedGenerationPath)
    if ($null -eq $expectedGeneration -or -not (Test-GenerationEqual $sourceGeneration $expectedGeneration)) {
        throw "Source plugin generation does not equal the expected Release generation."
    }
}

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
    $installedGeneration = Read-GenerationIfPresent -Path (Join-Path $installPath "release-generation.json")
    if ($null -ne $sourceGeneration -and -not (Test-GenerationEqual $sourceGeneration $installedGeneration)) {
        throw "Installed plugin generation differs from the source Release generation."
    }
    Write-InstallationReceipt -Path (Join-Path $installParent "codex-praetor-installation.json") -InstallPath $installPath -MarketplacePath $marketplacePath -Generation $installedGeneration

    Write-Host "[PASS] Codex Praetor plugin copied to a real local directory."
    Write-Host "[PASS] Personal marketplace entry is present."
    if ($null -eq $installedGeneration) {
        Write-Host "[WARN] Development source installed; it is not evidence of a public Release."
    } else {
        Write-Host "[PASS] Installed Release generation: $($installedGeneration.generation_id)"
    }
    Write-Host "Next: verify the installed identity against the target Release, then refresh the running Codex Desktop host. A new task alone does not refresh host plugin discovery."
} catch {
    if (Test-Path -LiteralPath $tempPath) {
        Remove-Item -LiteralPath $tempPath -Recurse -Force
    }
    throw
}
