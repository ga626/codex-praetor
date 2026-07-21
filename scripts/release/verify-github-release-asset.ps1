param(
    [string]$Version = "0.8.1-alpha",
    [string]$Tag = "",
    [string]$Repository = "ga626/codex-praetor",
    [string]$OutputRoot = ".codex-praetor\releases",
    [string]$ArtifactManifestPath = "",
    [ValidateSet("same-artifact", "published-artifact")][string]$VerificationMode = "same-artifact",
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
if ([string]::IsNullOrWhiteSpace($ArtifactManifestPath)) { $ArtifactManifestPath = Join-Path $outputRootPath "$releaseName.artifact.json" }
$ArtifactManifestPath = [IO.Path]::GetFullPath($ArtifactManifestPath)

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

function Resolve-GitHubTagCommit {
    param([string]$Repository, [string]$Tag)
    $refJson = & gh api "repos/$Repository/git/ref/tags/$Tag"
    if ($LASTEXITCODE -ne 0) { throw "Unable to resolve GitHub tag $Repository@$Tag." }
    $ref = $refJson | ConvertFrom-Json
    $object = $ref.object
    if ([string]$object.type -eq "tag") {
        $tagJson = & gh api "repos/$Repository/git/tags/$($object.sha)"
        if ($LASTEXITCODE -ne 0) { throw "Unable to resolve annotated GitHub tag $Repository@$Tag." }
        $object = ($tagJson | ConvertFrom-Json).object
    }
    if ([string]$object.type -ne "commit" -or [string]$object.sha -notmatch "^[0-9a-f]{40}$") {
        throw "GitHub tag $Repository@$Tag does not resolve to a commit."
    }
    return ([string]$object.sha).ToLowerInvariant()
}

Assert-Command -Name "gh"

if ($VerificationMode -eq "same-artifact" -and -not $SkipBuild) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptDir "build-codex-praetor-release.ps1") -Version $Version -OutputRoot $OutputRoot -Apply
    if ($LASTEXITCODE -ne 0) {
        throw "Local release package build failed."
    }
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path (Split-Path -Parent $scriptDir) "verify\test-release-artifact-runtime.ps1") -Version $Version -OutputRoot $OutputRoot -ArtifactManifestPath $ArtifactManifestPath -MarkVerified
    if ($LASTEXITCODE -ne 0) {
        throw "Local final artifact runtime acceptance failed."
    }
}

$artifactManifest = $null
if ($VerificationMode -eq "same-artifact") {
    if (-not (Test-Path -LiteralPath $localZip -PathType Leaf)) { throw "Local release zip missing: $localZip" }
    if (-not (Test-Path -LiteralPath $localSha -PathType Leaf)) { throw "Local release SHA256 file missing: $localSha" }
    if (-not (Test-Path -LiteralPath $localNotes -PathType Leaf)) { throw "Local release notes missing: $localNotes" }
    if (-not (Test-Path -LiteralPath $ArtifactManifestPath -PathType Leaf)) { throw "Artifact manifest is missing: $ArtifactManifestPath" }
    $artifactManifest = Get-Content -LiteralPath $ArtifactManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$artifactManifest.status -ne "artifact_verified" -or [string]$artifactManifest.verification.status -ne "passed") { throw "Same-artifact verification requires an artifact_verified manifest." }
}

$releaseJson = & gh release view $Tag --repo $Repository --json tagName,isDraft,isPrerelease,assets,body
if ($LASTEXITCODE -ne 0) {
    throw "Unable to read GitHub Release $Repository@$Tag. Output: $releaseJson"
}
$release = $releaseJson | ConvertFrom-Json
if ([bool]$release.isDraft) {
    throw "GitHub Release $Tag is still a draft; public release verification cannot pass."
}
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
    $remoteZipHash = Get-FileSha256Lower -Path $remoteZip
    $remoteShaText = Read-TextNormalized -Path $remoteSha
    if ($remoteShaText -notlike "$remoteZipHash*") {
        throw "Remote SHA256 file does not match the downloaded zip hash."
    }
    if ($VerificationMode -eq "same-artifact") {
        $localZipHash = Get-FileSha256Lower -Path $localZip
        if ($localZipHash -ne $remoteZipHash) {
            throw "Remote release zip differs from the verified local artifact. Local=$localZipHash Remote=$remoteZipHash"
        }
        if ($remoteZipHash -ne [string]$artifactManifest.artifact.sha256) { throw "Remote release zip is not the verified artifact. Remote=$remoteZipHash Verified=$($artifactManifest.artifact.sha256)" }
        $localNotesText = Read-TextNormalized -Path $localNotes
        $remoteNotesText = ([string]$release.body -replace "`r`n", "`n").Trim()
        if ($localNotesText -ne $remoteNotesText) { throw "GitHub Release notes differ from local release notes: $localNotes" }
    }

    $unzip = Join-Path $tmp "unzip"
    Expand-Archive -LiteralPath $remoteZip -DestinationPath $unzip -Force
    $remoteGenerationPath = Join-Path $unzip "codex-praetor-release-generation.json"
    if (-not (Test-Path -LiteralPath $remoteGenerationPath -PathType Leaf)) { throw "Remote release zip is missing its generation manifest." }
    $remoteGeneration = Get-Content -LiteralPath $remoteGenerationPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $tagCommit = Resolve-GitHubTagCommit -Repository $Repository -Tag $Tag
    if ([string]$remoteGeneration.version -ne $Version -or [string]$remoteGeneration.commit -ne $tagCommit) {
        throw "Remote release generation does not match version/tag commit. Version=$($remoteGeneration.version) Commit=$($remoteGeneration.commit) TagCommit=$tagCommit"
    }
    if ($VerificationMode -eq "same-artifact" -and [string]$remoteGeneration.commit -ne [string]$artifactManifest.generation.commit) {
        throw "Remote release generation commit differs from the verified local artifact manifest."
    }
    if ($VerificationMode -eq "published-artifact" -and (Test-Path -LiteralPath $ArtifactManifestPath -PathType Leaf)) {
        try {
            $localCandidate = Get-Content -LiteralPath $ArtifactManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ([string]$localCandidate.generation.commit -ne $tagCommit) {
                Write-Host "[INFO] local_candidate_stale: local candidate commit $($localCandidate.generation.commit) differs from published tag commit $tagCommit."
            }
        } catch {
            Write-Host "[INFO] local_candidate_unreadable: published-artifact verification ignores the local candidate manifest."
        }
    }
    $setupPath = Join-Path $unzip "setup.ps1"
    if (-not (Test-Path -LiteralPath $setupPath -PathType Leaf)) {
        throw "Remote release zip is missing setup.ps1."
    }
    Assert-CmdFileUsesCrlf -Path (Join-Path $unzip "setup.cmd") -Label "Remote setup.cmd"
    $runtimeSmoke = Join-Path $projectRoot "mcp\scripts\smoke-plugin-mcp.js"
    $remoteRuntime = Join-Path $unzip "plugin\mcp\dist\server.js"
    & node $runtimeSmoke $remoteRuntime $unzip --skip-dry-run --expected-version $Version --expected-contract (Join-Path $unzip "config\runtime-contract.json") --expected-generation (Join-Path $unzip "codex-praetor-release-generation.json")
    if ($LASTEXITCODE -ne 0) {
        throw "Downloaded GitHub Release MCP runtime acceptance failed."
    }
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

    Write-Host "[PASS] Downloaded GitHub Release zip verified: $remoteZipHash"
    Write-Host "[PASS] GitHub Release SHA256 file matches."
    if ($VerificationMode -eq "same-artifact") { Write-Host "[PASS] GitHub Release notes match local release notes." }
    Write-Host "[PASS] Downloaded Release generation matches tag commit: $tagCommit"
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
