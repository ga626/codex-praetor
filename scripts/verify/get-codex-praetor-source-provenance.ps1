param(
    [Parameter(Mandatory = $true)][string]$Repo,
    [string]$ExpectedCommit = "",
    [switch]$Json
)

$ErrorActionPreference = "Stop"
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) {
    $global:PSNativeCommandUseErrorActionPreference = $false
}

function Invoke-GitText {
    param([string[]]$Arguments)
    $oldPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $value = (& git.exe -C $script:repoRoot @Arguments 2>$null | Out-String).Trim()
        return [pscustomobject]@{ value = $value; exit_code = [int]$LASTEXITCODE }
    } finally { $ErrorActionPreference = $oldPreference }
}

$script:repoRoot = [System.IO.Path]::GetFullPath($Repo)
$oldPreference = $ErrorActionPreference
try { $ErrorActionPreference = "Continue"; $resolvedRoot = (& git.exe -C $script:repoRoot rev-parse --show-toplevel 2>$null | Out-String).Trim() } finally { $ErrorActionPreference = $oldPreference }
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($resolvedRoot)) {
    $payload = [ordered]@{
        schema = "codex-praetor-source-provenance/v1"
        repo = $script:repoRoot
        classification = "invalid_repo"
        read_only = $true
        reason = "path_is_not_a_git_checkout"
    }
    if ($Json) { $payload | ConvertTo-Json -Depth 12 } else { Write-Output "Source provenance: invalid_repo ($($payload.reason))" }
    exit 2
}
$script:repoRoot = [System.IO.Path]::GetFullPath($resolvedRoot)

$headResult = Invoke-GitText @("rev-parse", "HEAD")
$head = $headResult.value
$branchResult = Invoke-GitText @("symbolic-ref", "--quiet", "--short", "HEAD")
$branch = if ($branchResult.exit_code -eq 0) { $branchResult.value } else { "(detached)" }
$originResult = Invoke-GitText @("rev-parse", "--verify", "refs/remotes/origin/main")
$originMain = if ($originResult.exit_code -eq 0) { $originResult.value } else { "" }
$oldPreference = $ErrorActionPreference
try { $ErrorActionPreference = "Continue"; $statusText = (& git.exe -C $script:repoRoot status --porcelain 2>$null | Out-String).Trim() } finally { $ErrorActionPreference = $oldPreference }
$dirty = -not [string]::IsNullOrWhiteSpace($statusText)
$expected = if ([string]::IsNullOrWhiteSpace($ExpectedCommit)) { "" } else { $ExpectedCommit.Trim() }

$headEqualsOrigin = -not [string]::IsNullOrWhiteSpace($originMain) -and $head -eq $originMain
$headEqualsExpected = -not [string]::IsNullOrWhiteSpace($expected) -and $head -eq $expected
$behind = $false
$ahead = $false
$diverged = $false
if (-not [string]::IsNullOrWhiteSpace($originMain)) {
    & git.exe -C $script:repoRoot merge-base --is-ancestor HEAD refs/remotes/origin/main 2>$null
    $headIsAncestor = ($LASTEXITCODE -eq 0)
    & git.exe -C $script:repoRoot merge-base --is-ancestor refs/remotes/origin/main HEAD 2>$null
    $originIsAncestor = ($LASTEXITCODE -eq 0)
    $behind = $headIsAncestor -and -not $headEqualsOrigin
    $ahead = $originIsAncestor -and -not $headEqualsOrigin
    $diverged = -not $headIsAncestor -and -not $originIsAncestor
}

$tracked = @("plugin/.codex-plugin/plugin.json", "mcp/package.json", "config/runtime-contract.json")
$sourceFiles = @()
foreach ($relative in $tracked) {
    $path = Join-Path $script:repoRoot ($relative -replace "/", "\")
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        $sourceFiles += [ordered]@{ path = $relative; sha256 = $hash }
    }
}
$version = ""
$manifestPath = Join-Path $script:repoRoot "plugin\.codex-plugin\plugin.json"
if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
    try { $version = [string](Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json).version } catch { $version = "" }
}

$classification = "unknown"
$reason = "origin_main_ref_unavailable"
if ($dirty) {
    $classification = "dirty_checkout"
    $reason = "working_tree_has_uncommitted_changes"
} elseif ($headEqualsOrigin) {
    $classification = "product_baseline"
    $reason = "clean_HEAD_matches_origin_main"
} elseif ($headEqualsExpected) {
    $classification = "candidate_checkout"
    $reason = "clean_HEAD_matches_expected_commit"
} elseif ($behind) {
    $classification = "stale_checkout"
    $reason = "clean_HEAD_is_behind_origin_main"
} elseif ($ahead) {
    $classification = "ahead_checkout"
    $reason = "clean_HEAD_is_ahead_of_origin_main"
} elseif ($diverged) {
    $classification = "diverged_checkout"
    $reason = "clean_HEAD_and_origin_main_have_diverged"
}

$payload = [ordered]@{
    schema = "codex-praetor-source-provenance/v1"
    read_only = $true
    repo = $script:repoRoot
    head = $head
    branch = $branch
    origin_main = $originMain
    expected_commit = $expected
    dirty = $dirty
    classification = $classification
    reason = $reason
    product_version = $version
    source_files = $sourceFiles
    checked_at = (Get-Date).ToString("o")
    policy = "This probe reads local Git refs and source metadata only; it never fetches, pulls, resets, writes, or scans other worktrees."
}
if ($Json) {
    $payload | ConvertTo-Json -Depth 12
} else {
    Write-Output "Source provenance: $($payload.classification); reason=$($payload.reason); HEAD=$($payload.head); origin/main=$($payload.origin_main)"
}
