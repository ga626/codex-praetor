param([string]$ProjectRoot = "")

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}
$root = [IO.Path]::GetFullPath($ProjectRoot)
$scratch = Join-Path ([IO.Path]::GetTempPath()) ("codex-praetor-version-updater-" + [guid]::NewGuid().ToString("N"))
$sourceIntent = Get-Content -LiteralPath (Join-Path $root "config\release-intent.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$sourceVersion = [string]$sourceIntent.version
if ($sourceVersion -notmatch '^(?<major>[0-9]+)\.(?<minor>[0-9]+)\.(?<patch>[0-9]+)(?:-[0-9A-Za-z.-]+)?$') {
    throw "Fixture source version is not semantic: $sourceVersion"
}
$targetVersion = "$($Matches.major).$($Matches.minor).$([int]$Matches.patch + 1)-alpha"

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Copy-RelativeFile([string]$Relative) {
    $source = Join-Path $root $Relative
    $destination = Join-Path $scratch $Relative
    if (-not (Test-Path -LiteralPath $source)) { throw "Fixture source is missing: $Relative" }
    if (Test-Path -LiteralPath $source -PathType Leaf) {
        $parent = Split-Path -Parent $destination
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
        Copy-Item -LiteralPath $source -Destination $destination -Force
    } else {
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
        Copy-Item -Path (Join-Path $source '*') -Destination $destination -Recurse -Force
    }
}

try {
    New-Item -ItemType Directory -Path $scratch -Force | Out-Null
    $fixtures = @(& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "scripts\release\set-codex-praetor-version.ps1") -ProjectRoot $root -Version $sourceVersion -ListSourcePaths)
    if ($LASTEXITCODE -ne 0 -or $fixtures.Count -eq 0) { throw "Version surface updater did not provide its fixture source list." }
    foreach ($fixture in $fixtures) { Copy-RelativeFile $fixture }

    $sourceNotes = Join-Path $scratch "docs\release\release-notes-$sourceVersion.md"
    $targetNotes = Join-Path $scratch "docs\release\release-notes-$targetVersion.md"
    Copy-Item -LiteralPath $sourceNotes -Destination $targetNotes -Force

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scratch "scripts\release\set-codex-praetor-version.ps1") -ProjectRoot $scratch -Version $targetVersion -Apply
    if ($LASTEXITCODE -ne 0) { throw "Version surface updater failed in its isolated fixture." }

    $setupPath = Join-Path $scratch "setup.ps1"
    $setupBytes = [IO.File]::ReadAllBytes($setupPath)
    Assert-True ($setupBytes.Length -ge 3 -and $setupBytes[0] -eq 0xEF -and $setupBytes[1] -eq 0xBB -and $setupBytes[2] -eq 0xBF) "Version updater removed the UTF-8 BOM required by Windows PowerShell setup.ps1."
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($setupPath, [ref]$tokens, [ref]$errors) | Out-Null
    Assert-True ($errors.Count -eq 0) "Version updater produced a setup.ps1 that Windows PowerShell cannot parse."

    $intent = Get-Content -LiteralPath (Join-Path $scratch "config\release-intent.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    $contract = Get-Content -LiteralPath (Join-Path $scratch "config\runtime-contract.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($intent.version -eq $targetVersion -and $intent.previous_version -eq $sourceVersion) "Version updater did not advance the release intent correctly."
    Assert-True ($intent.tag -eq "v$targetVersion" -and $intent.artifact -eq "codex-praetor-setup-$targetVersion.zip") "Version updater did not synchronize tag and artifact."
    Assert-True ($contract.version -eq $targetVersion) "Version updater did not synchronize the runtime contract."
    $derivedContract = Get-Content -LiteralPath (Join-Path $scratch "plugin\runtime-contract.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($derivedContract.version -eq $targetVersion -and @($derivedContract.requiredMcpTools).Count -eq @($contract.requiredMcpTools).Count) "Version updater did not regenerate derived runtime contracts from the canonical source."
    Write-Host "[PASS] Version surface updater preserves encoding and advances the release contract in an isolated fixture."
} finally {
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}
