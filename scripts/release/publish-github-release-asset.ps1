param(
    [string]$Version = "0.4.2-alpha",
    [string]$Tag = "",
    [string]$Repository = "ga626/codex-praetor",
    [string]$OutputRoot = ".codex-praetor\releases",
    [switch]$ReplaceExistingAsset,
    [switch]$Apply
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
$zipPath = Join-Path $outputRootPath "$releaseName.zip"
$shaPath = Join-Path $outputRootPath "$releaseName.zip.sha256"
$notesPath = Join-Path $projectRoot "docs\release\release-notes-$Version.md"

function Assert-Command {
    param([string]$Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command is missing: $Name"
    }
}

Assert-Command -Name "git"
Assert-Command -Name "gh"

$branch = (& git -C $projectRoot branch --show-current).Trim()
$status = (& git -C $projectRoot status --short)
Write-Host "Codex Praetor GitHub Release publish plan"
Write-Host "Repository: $Repository"
Write-Host "Tag:        $Tag"
Write-Host "Branch:     $branch"
Write-Host "Zip:        $zipPath"
Write-Host "SHA256:     $shaPath"
Write-Host "Notes:      $notesPath"
Write-Host "Mode:       $(if ($Apply) { 'apply' } else { 'dry-run' })"

if ($branch -ne "main") {
    throw "Release assets must be published from main. Current branch: $branch"
}
if (-not [string]::IsNullOrWhiteSpace(($status -join "`n"))) {
    throw "Working tree must be clean before publishing release assets."
}

& git -C $projectRoot fetch origin --tags
if ($LASTEXITCODE -ne 0) { throw "Failed to fetch origin and release tags." }
$head = (& git -C $projectRoot rev-parse HEAD).Trim()
$originMain = (& git -C $projectRoot rev-parse origin/main).Trim()
if ($head -ne $originMain) {
    throw "Local main is not equal to origin/main. HEAD=$head origin/main=$originMain"
}

$tagCommit = ""
& git -C $projectRoot rev-parse --verify --quiet "refs/tags/$Tag" *> $null
$tagExists = $LASTEXITCODE -eq 0
if ($tagExists) {
    $tagCommit = (& git -C $projectRoot rev-list -n 1 $Tag).Trim()
    if ($tagCommit -ne $head) {
        throw "Refusing to reuse $Tag for newer source. Tag=$tagCommit HEAD=$head"
    }
}

$remoteTagRows = @(& git -C $projectRoot ls-remote --tags origin "refs/tags/$Tag")
if ($LASTEXITCODE -ne 0) { throw "Failed to inspect remote tag $Tag." }
$remoteTagExists = @($remoteTagRows | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count -gt 0

$previousErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = "Continue"
try {
    $releaseJson = & gh release view $Tag --repo $Repository --json tagName 2>&1
    $releaseExists = $LASTEXITCODE -eq 0
} finally {
    $ErrorActionPreference = $previousErrorActionPreference
}
if ($releaseExists -and -not $ReplaceExistingAsset) {
    throw "GitHub Release $Tag already exists. Use a new version, or explicitly approve -ReplaceExistingAsset for a broken asset from the same tagged commit."
}
if ($ReplaceExistingAsset -and -not $releaseExists) {
    throw "-ReplaceExistingAsset was requested, but GitHub Release $Tag does not exist."
}
if ($releaseExists -and (-not $tagExists -or -not $remoteTagExists)) {
    throw "GitHub Release $Tag exists, but its local or remote tag is missing."
}

Write-Host "Tag state:   $(if ($tagExists) { "local tag at $tagCommit" } else { 'new local tag' })"
Write-Host "Remote tag:  $(if ($remoteTagExists) { 'exists' } else { 'will be pushed' })"
Write-Host "Release:     $(if ($releaseExists) { 'existing asset replacement' } else { 'new prerelease' })"

if (-not (Test-Path -LiteralPath $notesPath -PathType Leaf)) {
    throw "Release notes missing: $notesPath"
}

if (-not $Apply) {
    Write-Host ""
    Write-Host "Dry run only. Re-run with -Apply after the release preparation PR is merged."
    exit 0
}

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptDir "build-codex-praetor-release.ps1") -Version $Version -OutputRoot $OutputRoot -Apply
if ($LASTEXITCODE -ne 0) { throw "Release package build failed." }
if (-not (Test-Path -LiteralPath $zipPath -PathType Leaf)) { throw "Release zip missing after build: $zipPath" }
if (-not (Test-Path -LiteralPath $shaPath -PathType Leaf)) { throw "Release SHA256 file missing after build: $shaPath" }
if (-not (Test-Path -LiteralPath $notesPath -PathType Leaf)) { throw "Release notes missing: $notesPath" }

if ($releaseExists) {
    & gh release upload $Tag $zipPath $shaPath --repo $Repository --clobber
    if ($LASTEXITCODE -ne 0) { throw "Failed to replace GitHub Release assets." }
    & gh release edit $Tag --repo $Repository --notes-file $notesPath
    if ($LASTEXITCODE -ne 0) { throw "Failed to update GitHub Release notes." }
} else {
    if (-not $tagExists) {
        & git -C $projectRoot tag $Tag $head
        if ($LASTEXITCODE -ne 0) { throw "Failed to create local tag $Tag." }
    }
    if (-not $remoteTagExists) {
        & git -C $projectRoot push origin $Tag
        if ($LASTEXITCODE -ne 0) { throw "Failed to push tag $Tag." }
    }
    & gh release create $Tag $zipPath $shaPath --repo $Repository --title "Codex Praetor $Version" --notes-file $notesPath --prerelease --verify-tag
    if ($LASTEXITCODE -ne 0) { throw "Failed to create GitHub Release $Tag." }
}

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptDir "verify-github-release-asset.ps1") -Version $Version -Tag $Tag -Repository $Repository -OutputRoot $OutputRoot -SkipBuild
if ($LASTEXITCODE -ne 0) { throw "Remote GitHub Release verification failed after upload." }
