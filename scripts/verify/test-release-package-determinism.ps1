param(
    [string]$Version = "0.9.0-alpha"
)

$ErrorActionPreference = "Stop"
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) {
    $global:PSNativeCommandUseErrorActionPreference = $false
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
$buildScript = Join-Path $projectRoot "scripts\release\build-codex-praetor-release.ps1"
$runtimeRoot = Join-Path $projectRoot ".codex-praetor"
$outputA = ".codex-praetor\determinism-check\a"
$outputB = ".codex-praetor\determinism-check\b"
$outputRootA = Join-Path $projectRoot $outputA
$outputRootB = Join-Path $projectRoot $outputB
$releaseName = "codex-praetor-setup-$Version"
$zipA = Join-Path $outputRootA "$releaseName.zip"
$zipB = Join-Path $outputRootB "$releaseName.zip"
$shaA = Join-Path $outputRootA "$releaseName.zip.sha256"
$shaB = Join-Path $outputRootB "$releaseName.zip.sha256"
$expectedTimestamp = [System.DateTimeOffset]::new(2024, 1, 1, 0, 0, 0, [System.TimeSpan]::Zero)
$expectedZipWallClock = $expectedTimestamp.ToString("yyyy-MM-ddTHH:mm:ss")

function Get-FileSha256Lower {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Assert-ZipEntryMetadata {
    param([string]$ZipPath)

    Add-Type -AssemblyName System.IO.Compression
    $stream = [System.IO.File]::OpenRead($ZipPath)
    try {
        $archive = New-Object System.IO.Compression.ZipArchive -ArgumentList $stream, ([System.IO.Compression.ZipArchiveMode]::Read)
        try {
            $entries = @($archive.Entries)
            if ($entries.Count -eq 0) {
                throw "Release zip has no entries: $ZipPath"
            }

            $names = @($entries | ForEach-Object { $_.FullName })
            $sortedNames = @($names | Sort-Object)
            for ($i = 0; $i -lt $names.Count; $i++) {
                if ($names[$i] -ne $sortedNames[$i]) {
                    throw "Release zip entries are not sorted. First mismatch: $($names[$i]) != $($sortedNames[$i])"
                }
            }

            foreach ($entry in $entries) {
                $entryZipWallClock = $entry.LastWriteTime.ToString("yyyy-MM-ddTHH:mm:ss")
                if ($entryZipWallClock -ne $expectedZipWallClock) {
                    throw "Release zip entry timestamp is not deterministic: $($entry.FullName) :: $($entry.LastWriteTime.ToString("o"))"
                }
            }
        } finally {
            $archive.Dispose()
        }
    } finally {
        $stream.Dispose()
    }
}

Remove-Item -LiteralPath (Join-Path $runtimeRoot "determinism-check") -Recurse -Force -ErrorAction SilentlyContinue

& powershell -NoProfile -ExecutionPolicy Bypass -File $buildScript -Version $Version -OutputRoot $outputA -Apply -AllowDraftMetadataPlaceholders
if ($LASTEXITCODE -ne 0) {
    throw "First deterministic release build failed."
}

& powershell -NoProfile -ExecutionPolicy Bypass -File $buildScript -Version $Version -OutputRoot $outputB -Apply -AllowDraftMetadataPlaceholders
if ($LASTEXITCODE -ne 0) {
    throw "Second deterministic release build failed."
}

foreach ($path in @($zipA, $zipB, $shaA, $shaB)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Expected release output missing: $path"
    }
}

$zipHashA = Get-FileSha256Lower -Path $zipA
$zipHashB = Get-FileSha256Lower -Path $zipB
$shaTextA = (Get-Content -LiteralPath $shaA -Raw -Encoding UTF8).Trim()
$shaTextB = (Get-Content -LiteralPath $shaB -Raw -Encoding UTF8).Trim()

if ($zipHashA -ne $zipHashB) {
    throw "Release package is not deterministic. First=$zipHashA Second=$zipHashB"
}
if ($shaTextA -ne $shaTextB) {
    throw "Release SHA256 files differ. First='$shaTextA' Second='$shaTextB'"
}
if ($shaTextA -notlike "$zipHashA*") {
    throw "Release SHA256 file does not match zip hash. SHA='$shaTextA' Zip=$zipHashA"
}

Assert-ZipEntryMetadata -ZipPath $zipA

Write-Host "[PASS] Release package builds deterministically: $zipHashA"
Write-Host "[PASS] Release SHA256 file is reproducible."
Write-Host "[PASS] Release zip entries are sorted and use fixed timestamps."
