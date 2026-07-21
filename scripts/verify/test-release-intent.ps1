param(
    [string]$ProjectRoot = "",
    [string]$BaseRef = "",
    [switch]$CheckRemote,
    [switch]$AllowExistingTagAtHead,
    [switch]$RequireReleaseImpact
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $ProjectRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
}
$root = [System.IO.Path]::GetFullPath($ProjectRoot)
$intentPath = Join-Path $root "config\release-intent.json"
$schemaPath = Join-Path $root "config\release-intent.schema.json"
$contractPath = Join-Path $root "config\runtime-contract.json"
foreach ($path in @($intentPath, $schemaPath, $contractPath)) { if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Release intent input is missing: $path" } }

$intent = Get-Content -LiteralPath $intentPath -Raw -Encoding UTF8 | ConvertFrom-Json
$schema = Get-Content -LiteralPath $schemaPath -Raw -Encoding UTF8 | ConvertFrom-Json
$contract = Get-Content -LiteralPath $contractPath -Raw -Encoding UTF8 | ConvertFrom-Json
function Assert-True([bool]$condition, [string]$message) { if (-not $condition) { throw $message } }

Assert-True ([string]$schema.properties.schema.const -eq "codex-praetor-release-intent/v1") "Release intent schema contract is invalid."
Assert-True ([string]$intent.schema -eq "codex-praetor-release-intent/v1") "Release intent schema is invalid."
Assert-True ([string]$intent.product -eq "codex-praetor") "Release intent product is invalid."
Assert-True ([string]$intent.release_mode -eq "auto_on_main") "Release intent must use auto_on_main."
Assert-True ([bool]$intent.release_required) "Release intent must require a release."
Assert-True ([string]$intent.version -eq [string]$contract.version) "Release intent version does not match runtime contract."
Assert-True ([string]$intent.tag -eq "v$($intent.version)") "Release intent tag does not match version."
Assert-True ([string]$intent.previous_version -ne [string]$intent.version) "Release intent previous_version must differ from version."
Assert-True ([string]$intent.artifact -eq "codex-praetor-setup-$($intent.version).zip") "Release intent artifact does not match version."

function ConvertTo-VersionTuple([string]$Value) {
    if ($Value -notmatch '^(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)(?:-[0-9A-Za-z.-]+)?$') { throw "Invalid semantic version: $Value" }
    return @([int]$Matches.major, [int]$Matches.minor, [int]$Matches.patch)
}

function Test-VersionGreater([string]$Candidate, [string]$Baseline) {
    $candidateTuple = ConvertTo-VersionTuple $Candidate
    $baselineTuple = ConvertTo-VersionTuple $Baseline
    for ($index = 0; $index -lt 3; $index++) {
        if ($candidateTuple[$index] -gt $baselineTuple[$index]) { return $true }
        if ($candidateTuple[$index] -lt $baselineTuple[$index]) { return $false }
    }
    return $false
}

$releaseImpact = $true
if (-not [string]::IsNullOrWhiteSpace($BaseRef) -and $BaseRef -notmatch '^0+$') {
    $changed = @(& git -C $root diff --name-only "$BaseRef...HEAD")
    if ($LASTEXITCODE -ne 0) { throw "Unable to inspect changed files against base ref $BaseRef." }
    # Dependabot's TypeScript/tooling bumps change the lockfile but do not
    # change the bundled runtime. They must still run CI, but must not force a
    # fake product version/tag release.
    $nonReleaseDependencyOnly = $false
    $dependencyFiles = @("mcp/package.json", "mcp/package-lock.json")
    if ($changed.Count -gt 0 -and @($changed | Where-Object { $_ -notin $dependencyFiles }).Count -eq 0 -and @($changed | Where-Object { $_ -eq "mcp/package.json" }).Count -eq 1) {
        $basePackageText = & git -C $root show "$BaseRef`:mcp/package.json"
        if ($LASTEXITCODE -eq 0) {
            $basePackage = ($basePackageText -join [Environment]::NewLine) | ConvertFrom-Json
            $currentPackage = Get-Content -LiteralPath (Join-Path $root "mcp\package.json") -Raw -Encoding UTF8 | ConvertFrom-Json
            $baseRuntime = ($basePackage.dependencies | ConvertTo-Json -Compress)
            $currentRuntime = ($currentPackage.dependencies | ConvertTo-Json -Compress)
            $nonReleaseDependencyOnly = $baseRuntime -eq $currentRuntime
        }
    }
    $impactPatterns = @(
        '^plugin/', '^skill/', '^mcp/', '^scripts/(dispatch|install|maintenance|release|verify)/',
        '^setup\.(ps1|cmd)$', '^config/runtime-contract\.json$', '^README(\.en)?\.md$',
        '^docs/user/', '^docs/release/', '^docs/roadmap\.md$', '^SECURITY\.md$', '^CHANGELOG\.md$'
    )
    $impact = if ($nonReleaseDependencyOnly) { @() } else { @($changed | Where-Object { $path = [string]$_; @($impactPatterns | Where-Object { $path -match $_ }).Count -gt 0 }) }
    $releaseImpact = $impact.Count -gt 0
    $intentChanged = @($changed | Where-Object { [string]$_ -eq "config/release-intent.json" }).Count -gt 0
    if ($RequireReleaseImpact -and $impact.Count -gt 0 -and -not $intentChanged) {
        throw "Release-impacting files changed without config/release-intent.json; merge is not allowed."
    }
    if ($RequireReleaseImpact -and $intentChanged -and $impact.Count -eq 0) {
        throw "Release intent changed without a release-impacting file; classify the PR as non-release or add the intended product change."
    }
    if ($RequireReleaseImpact -and $impact.Count -gt 0) {
        $baseIntentText = & git -C $root show "$BaseRef`:config/release-intent.json"
        if ($LASTEXITCODE -ne 0) { throw "Unable to read the base release intent from $BaseRef." }
        $baseIntent = ($baseIntentText -join [Environment]::NewLine) | ConvertFrom-Json
        Assert-True ([string]$intent.previous_version -eq [string]$baseIntent.version) "Release intent previous_version must equal the target branch version ($($baseIntent.version))."
        Assert-True (Test-VersionGreater -Candidate ([string]$intent.version) -Baseline ([string]$baseIntent.version)) "Release intent version must be greater than the target branch version ($($baseIntent.version))."
    }
    if ($nonReleaseDependencyOnly) { Write-Host "[PASS] Development-only MCP dependency update does not require a product release." }
}

# The candidate classification is computed once above and owns every
# release-only gate below. Non-release dependency PRs still build and test in
# the shared pipeline, but never pretend they need a new immutable product tag.
if ($releaseImpact) {
    Write-Host "[PASS] Pipeline classification: release_impact"
} else {
    Write-Host "[PASS] Pipeline classification: non_release"
}

if ($CheckRemote -and $releaseImpact) {
    $remoteTag = @(& git -C $root ls-remote --tags origin "refs/tags/$($intent.tag)")
    if ($LASTEXITCODE -ne 0) { throw "Unable to inspect remote tag $($intent.tag)." }
    if (@($remoteTag | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count -gt 0) {
        if (-not $AllowExistingTagAtHead) {
            throw "Remote tag $($intent.tag) already exists. Bump release-intent version in this PR; immutable tags cannot be reused."
        }
        & git -C $root fetch origin --tags
        if ($LASTEXITCODE -ne 0) { throw "Unable to fetch existing remote tag $($intent.tag)." }
        $tagCommit = (& git -C $root rev-parse "$($intent.tag)^{commit}").Trim()
        if ($LASTEXITCODE -ne 0) { throw "Unable to resolve existing tag $($intent.tag) to a commit." }
        $headCommit = (& git -C $root rev-parse HEAD).Trim()
        if ($LASTEXITCODE -ne 0) { throw "Unable to resolve HEAD for release intent retry." }
        Assert-True ($tagCommit -eq $headCommit) "Remote tag $($intent.tag) belongs to $tagCommit, not current HEAD $headCommit. A release retry must never reuse another commit's tag."
        Write-Host "[PASS] Existing remote tag matches current HEAD and may be resumed: $($intent.tag)"
    }
}

Write-Host "[PASS] Release intent is valid: $($intent.version) / $($intent.tag) / auto_on_main"
