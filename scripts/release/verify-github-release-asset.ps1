param(
    [string]$Version = "0.5.0-alpha",
    [string]$Tag = "",
    [string]$Repository = "ga626/codex-praetor",
    [string]$OutputRoot = ".codex-praetor\releases",
    [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) {
    $global:PSNativeCommandUseErrorActionPreference = $false
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
if ([string]::IsNullOrWhiteSpace($Tag)) {
    $Tag = "v$Version"
}

$releaseName = "codex-praetor-setup-$Version"
$outputRootPath = [System.IO.Path]::GetFullPath((Join-Path $projectRoot $OutputRoot))
$localZip = Join-Path $outputRootPath "$releaseName.zip"
$localSha = Join-Path $outputRootPath "$releaseName.zip.sha256"
$localNotes = Join-Path $projectRoot "docs\release\release-notes-$Version.md"

function Assert-Command {
    param([string]$Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command is missing: $Name"
    }
}

function Get-FileSha256Lower {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Read-TextNormalized {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return "" }
    return ((Get-Content -LiteralPath $Path -Raw -Encoding UTF8) -replace "`r`n", "`n").Trim()
}

function Assert-Contains {
    param([string]$Text, [string]$Needle, [string]$Label)
    if ($Text -notlike "*$Needle*") {
        throw "Remote release zip does not contain expected setup marker '$Label'."
    }
}

function Assert-CmdFileUsesCrlf {
    param([string]$Path, [string]$Label)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Label is missing: $Path"
    }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $lfCount = 0
    $crlfCount = 0
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        if ($bytes[$i] -eq 10) {
            $lfCount += 1
            if ($i -gt 0 -and $bytes[$i - 1] -eq 13) {
                $crlfCount += 1
            }
        }
    }
    if ($lfCount -eq 0 -or $lfCount -ne $crlfCount) {
        throw "$Label must use CRLF line endings so cmd.exe can run it after download."
    }
}

Assert-Command -Name "gh"

if (-not $SkipBuild) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptDir "build-codex-praetor-release.ps1") -Version $Version -OutputRoot $OutputRoot -Apply
    if ($LASTEXITCODE -ne 0) {
        throw "Local release package build failed."
    }
}

if (-not (Test-Path -LiteralPath $localZip -PathType Leaf)) {
    throw "Local release zip missing: $localZip"
}
if (-not (Test-Path -LiteralPath $localSha -PathType Leaf)) {
    throw "Local release SHA256 file missing: $localSha"
}
if (-not (Test-Path -LiteralPath $localNotes -PathType Leaf)) {
    throw "Local release notes missing: $localNotes"
}

$releaseJson = & gh release view $Tag --repo $Repository --json tagName,isDraft,isPrerelease,assets,body 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "Unable to read GitHub Release $Repository@$Tag. Output: $releaseJson"
}
$release = $releaseJson | ConvertFrom-Json
$assetNames = @($release.assets | ForEach-Object { $_.name })
if ($assetNames -notcontains "$releaseName.zip") {
    throw "GitHub Release is missing asset: $releaseName.zip"
}
if ($assetNames -notcontains "$releaseName.zip.sha256") {
    throw "GitHub Release is missing asset: $releaseName.zip.sha256"
}

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-praetor-release-verify-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
try {
    & gh release download $Tag --repo $Repository --pattern "$releaseName.zip" --dir $tmp
    if ($LASTEXITCODE -ne 0) { throw "Failed to download remote release zip." }
    & gh release download $Tag --repo $Repository --pattern "$releaseName.zip.sha256" --dir $tmp
    if ($LASTEXITCODE -ne 0) { throw "Failed to download remote release SHA256 file." }

    $remoteZip = Join-Path $tmp "$releaseName.zip"
    $remoteSha = Join-Path $tmp "$releaseName.zip.sha256"
    $localZipHash = Get-FileSha256Lower -Path $localZip
    $remoteZipHash = Get-FileSha256Lower -Path $remoteZip
    if ($localZipHash -ne $remoteZipHash) {
        throw "Remote release zip is stale or different. Local=$localZipHash Remote=$remoteZipHash"
    }

    $remoteShaText = Read-TextNormalized -Path $remoteSha
    if ($remoteShaText -notlike "$localZipHash*") {
        throw "Remote SHA256 file does not match the remote/local zip hash."
    }

    $localNotesText = Read-TextNormalized -Path $localNotes
    $remoteNotesText = ([string]$release.body -replace "`r`n", "`n").Trim()
    if ($localNotesText -ne $remoteNotesText) {
        throw "GitHub Release notes differ from local release notes: $localNotes"
    }

    $unzip = Join-Path $tmp "unzip"
    Expand-Archive -LiteralPath $remoteZip -DestinationPath $unzip -Force
    $setupPath = Join-Path $unzip "setup.ps1"
    if (-not (Test-Path -LiteralPath $setupPath -PathType Leaf)) {
        throw "Remote release zip is missing setup.ps1."
    }
    Assert-CmdFileUsesCrlf -Path (Join-Path $unzip "setup.cmd") -Label "Remote setup.cmd"
    $setupText = Get-Content -LiteralPath $setupPath -Raw -Encoding UTF8
    Assert-Contains -Text $setupText -Needle "Get-ProviderDefinitions" -Label "provider definitions"
    Assert-Contains -Text $setupText -Needle "Invoke-OfficialInstallCommand" -Label "official installer execution"
    Assert-Contains -Text $setupText -Needle 'Shell = "cmd"' -Label "Qoder CMD shell"
    Assert-Contains -Text $setupText -Needle "Save-OnboardingState" -Label "onboarding state"
    Assert-Contains -Text $setupText -Needle "codex-praetor.onboarding-state.json" -Label "state file path"
    Assert-Contains -Text $setupText -Needle 'Write-Host "  1.' -Label "all providers choice"
    Assert-Contains -Text $setupText -Needle 'Write-Host "  2.' -Label "skip providers choice"
    Assert-Contains -Text $setupText -Needle "Qoder" -Label "Qoder choice"
    Assert-Contains -Text $setupText -Needle "CodeBuddy" -Label "CodeBuddy choice"
    Assert-Contains -Text $setupText -Needle "MiMo" -Label "MiMo choice"

    Write-Host "[PASS] GitHub Release zip matches the local build: $remoteZipHash"
    Write-Host "[PASS] GitHub Release SHA256 file matches."
    Write-Host "[PASS] GitHub Release notes match local release notes."
    Write-Host "[PASS] Downloaded remote setup.cmd uses CRLF line endings."
    Write-Host "[PASS] Downloaded remote zip contains the current onboarding wizard."

    $publicEntryCheck = Join-Path (Split-Path -Parent $scriptDir) "verify\test-public-entry-consistency.ps1"
    if (Test-Path -LiteralPath $publicEntryCheck -PathType Leaf) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $publicEntryCheck -Version $Version -Repository $Repository -SkipRemoteRelease
        if ($LASTEXITCODE -ne 0) {
            throw "Public entry consistency check failed."
        }
    }
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
