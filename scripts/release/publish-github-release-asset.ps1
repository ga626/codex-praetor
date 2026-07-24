param(
    [string]$Version = "0.13.0-alpha",
    [string]$Tag = "",
    [string]$Repository = "ga626/codex-praetor",
    [string]$OutputRoot = ".codex-praetor\releases",
    [string]$ArtifactManifestPath = "",
    [switch]$ResumeExistingRelease,
    [switch]$AllowDetachedHead,
    [switch]$Apply
)

$ErrorActionPreference = "Stop"
. (Join-Path (Split-Path -Parent $PSScriptRoot) "shared\ensure-file-hash.ps1")
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
$defaultArtifactManifestPath = Join-Path $outputRootPath "$releaseName.artifact.json"
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
if ([string]::IsNullOrWhiteSpace($ArtifactManifestPath)) { $ArtifactManifestPath = $defaultArtifactManifestPath }
$ArtifactManifestPath = [IO.Path]::GetFullPath($ArtifactManifestPath)

if ($branch -ne "main" -and -not ($AllowDetachedHead -and $env:GITHUB_ACTIONS -eq "true")) {
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
    $releaseJson = & gh release view $Tag --repo $Repository --json tagName,isDraft,isPrerelease 2>&1
    $releaseExists = $LASTEXITCODE -eq 0
} finally {
    $ErrorActionPreference = $previousErrorActionPreference
}
$releaseIsDraft = $false
if ($releaseExists) {
    try {
        $releaseInfo = ($releaseJson | ConvertFrom-Json)
        $releaseIsDraft = [bool]$releaseInfo.isDraft
    } catch {
        throw "Existing GitHub Release $Tag is unreadable: $($_.Exception.Message)"
    }
}
if ($releaseExists -and -not $releaseIsDraft -and -not $ResumeExistingRelease) {
    throw "GitHub Release $Tag already exists. Published releases are verify-only; use a new version for a source or artifact defect."
}
if ($releaseExists -and (-not $tagExists -or -not $remoteTagExists)) {
    throw "GitHub Release $Tag exists, but its local or remote tag is missing."
}

Write-Host "Tag state:   $(if ($tagExists) { "local tag at $tagCommit" } else { 'new local tag' })"
Write-Host "Remote tag:  $(if ($remoteTagExists) { 'exists' } else { 'will be pushed' })"
Write-Host "Release:     $(if ($releaseExists -and $releaseIsDraft) { 'resume existing draft' } elseif ($releaseExists) { 'existing asset replacement' } else { 'new prerelease' })"

if (-not (Test-Path -LiteralPath $notesPath -PathType Leaf)) {
    throw "Release notes missing: $notesPath"
}
if (-not (Test-Path -LiteralPath $ArtifactManifestPath -PathType Leaf)) { throw "Verified artifact manifest is missing: $ArtifactManifestPath" }
$artifactManifest = Get-Content -LiteralPath $ArtifactManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$artifactManifest.status -ne "artifact_verified" -or [string]$artifactManifest.verification.status -ne "passed") {
    throw "Publisher only accepts an artifact_verified manifest; run final artifact runtime acceptance first."
}
if ([IO.Path]::GetFullPath([string]$artifactManifest.artifact.path) -ne [IO.Path]::GetFullPath($zipPath)) { throw "Artifact manifest zip path differs from the publisher zip path." }
if ((Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne [string]$artifactManifest.artifact.sha256) { throw "Artifact manifest SHA256 differs from the upload candidate." }

if (-not $Apply) {
    Write-Host ""
    Write-Host "Dry run only. Re-run with -Apply after the release preparation PR is merged."
    exit 0
}

if ($releaseExists -and -not $releaseIsDraft -and $ResumeExistingRelease) {
    Write-Host "[PASS] Published immutable Release already exists for this exact HEAD. Running remote verification only."
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptDir "verify-github-release-asset.ps1") -Version $Version -Tag $Tag -Repository $Repository -OutputRoot $OutputRoot -ArtifactManifestPath $ArtifactManifestPath -SkipBuild
    if ($LASTEXITCODE -ne 0) { throw "Existing immutable GitHub Release verification failed." }
    exit 0
}

if (-not (Test-Path -LiteralPath $zipPath -PathType Leaf)) { throw "Verified release zip is missing: $zipPath" }
if (-not (Test-Path -LiteralPath $shaPath -PathType Leaf)) { throw "Verified release SHA256 file is missing: $shaPath" }
if (-not (Test-Path -LiteralPath $notesPath -PathType Leaf)) { throw "Release notes missing: $notesPath" }

if ($releaseExists -and $releaseIsDraft) {
    & gh release upload $Tag $zipPath $shaPath --repo $Repository --clobber
    if ($LASTEXITCODE -ne 0) { throw "Failed to resume draft GitHub Release assets." }
    & gh release edit $Tag --repo $Repository --notes-file $notesPath --draft=false --prerelease
    if ($LASTEXITCODE -ne 0) { throw "Failed to publish the resumed draft GitHub Release." }
} elseif ($releaseExists) {
    throw "Published GitHub Releases are verify-only. Use a new version for recovery."
} else {
    if (-not $tagExists) {
        & git -C $projectRoot tag $Tag $head
        if ($LASTEXITCODE -ne 0) { throw "Failed to create local tag $Tag." }
    }
    if (-not $remoteTagExists) {
        & git -C $projectRoot push origin $Tag
        if ($LASTEXITCODE -ne 0) { throw "Failed to push tag $Tag." }
    }
    & gh release create $Tag --repo $Repository --title "Codex Praetor $Version" --notes-file $notesPath --draft --prerelease --verify-tag
    if ($LASTEXITCODE -ne 0) { throw "Failed to create draft GitHub Release $Tag." }
    & gh release upload $Tag $zipPath $shaPath --repo $Repository
    if ($LASTEXITCODE -ne 0) { throw "Failed to upload draft GitHub Release assets." }
    & gh release edit $Tag --repo $Repository --draft=false --prerelease
    if ($LASTEXITCODE -ne 0) { throw "Failed to publish GitHub Release $Tag." }
}

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptDir "verify-github-release-asset.ps1") -Version $Version -Tag $Tag -Repository $Repository -OutputRoot $OutputRoot -ArtifactManifestPath $ArtifactManifestPath -SkipBuild
if ($LASTEXITCODE -ne 0) { throw "Remote GitHub Release verification failed after upload." }
