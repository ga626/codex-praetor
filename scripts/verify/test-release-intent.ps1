param(
    [string]$ProjectRoot = "",
    [string]$BaseRef = "",
    [switch]$CheckRemote,
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

if (-not [string]::IsNullOrWhiteSpace($BaseRef) -and $BaseRef -notmatch '^0+$') {
    $changed = @(& git -C $root diff --name-only "$BaseRef...HEAD")
    if ($LASTEXITCODE -ne 0) { throw "Unable to inspect changed files against base ref $BaseRef." }
    $impactPatterns = @(
        '^plugin/', '^skill/', '^mcp/', '^scripts/(dispatch|install|maintenance|release|verify)/',
        '^setup\.(ps1|cmd)$', '^config/runtime-contract\.json$', '^README(\.en)?\.md$',
        '^docs/user/', '^docs/release/', '^docs/roadmap\.md$', '^SECURITY\.md$', '^CHANGELOG\.md$'
    )
    $impact = @($changed | Where-Object { $path = [string]$_; @($impactPatterns | Where-Object { $path -match $_ }).Count -gt 0 })
    $intentChanged = @($changed | Where-Object { [string]$_ -eq "config/release-intent.json" }).Count -gt 0
    if ($RequireReleaseImpact -and $impact.Count -gt 0 -and -not $intentChanged) {
        throw "Release-impacting files changed without config/release-intent.json; merge is not allowed."
    }
    if ($RequireReleaseImpact -and $intentChanged -and $impact.Count -eq 0) {
        throw "Release intent changed without a release-impacting file; classify the PR as non-release or add the intended product change."
    }
}

if ($CheckRemote) {
    $remoteTag = @(& git -C $root ls-remote --tags origin "refs/tags/$($intent.tag)")
    if ($LASTEXITCODE -ne 0) { throw "Unable to inspect remote tag $($intent.tag)." }
    if (@($remoteTag | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count -gt 0) {
        throw "Remote tag $($intent.tag) already exists. Bump release-intent version in this PR; immutable tags cannot be reused."
    }
}

Write-Host "[PASS] Release intent is valid: $($intent.version) / $($intent.tag) / auto_on_main"
