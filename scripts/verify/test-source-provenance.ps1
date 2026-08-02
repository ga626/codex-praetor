param([string]$ProjectRoot = "")

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$helper = Join-Path $ProjectRoot "scripts\verify\get-codex-praetor-source-provenance.ps1"
$scratch = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-praetor-source-provenance-" + [Guid]::NewGuid().ToString("N"))

function Assert-True([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Invoke-TestGit([string]$Path, [string[]]$GitArgs) { & git.exe -C $Path @GitArgs 2>$null | Out-Null; if ($LASTEXITCODE -ne 0) { throw "git failed: $($GitArgs -join ' ')" } }
function Probe([string]$Path, [string]$Expected = "") {
    $args = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $helper, "-Repo", $Path, "-Json")
    if (-not [string]::IsNullOrWhiteSpace($Expected)) { $args += @("-ExpectedCommit", $Expected) }
    return ((& powershell @args | Out-String) | ConvertFrom-Json)
}

try {
    New-Item -ItemType Directory -Path $scratch -Force | Out-Null
    $repo = Join-Path $scratch "repo"
    New-Item -ItemType Directory -Path $repo -Force | Out-Null
    Invoke-TestGit $repo @("init", "-q")
    Invoke-TestGit $repo @("config", "user.email", "provenance-test@example.invalid")
    Invoke-TestGit $repo @("config", "user.name", "Codex Praetor provenance test")
    Set-Content -LiteralPath (Join-Path $repo "README.md") -Value "one" -Encoding ASCII
    Invoke-TestGit $repo @("add", "README.md"); Invoke-TestGit $repo @("commit", "-qm", "one")
    $first = (& git -C $repo rev-parse HEAD).Trim()
    Invoke-TestGit $repo @("update-ref", "refs/remotes/origin/main", $first)
    $baseline = Probe $repo
    Assert-True ([string]$baseline.classification -eq "product_baseline") "Clean origin/main checkout must be product_baseline."
    Assert-True ([bool]$baseline.read_only) "Probe must declare read_only."

    Set-Content -LiteralPath (Join-Path $repo "README.md") -Value "two" -Encoding ASCII
    Invoke-TestGit $repo @("commit", "-qam", "two")
    $second = (& git -C $repo rev-parse HEAD).Trim()
    Invoke-TestGit $repo @("update-ref", "refs/remotes/origin/main", $second)
    Set-Content -LiteralPath (Join-Path $repo "README.md") -Value "dirty" -Encoding ASCII
    $dirty = Probe $repo
    Assert-True ([string]$dirty.classification -eq "dirty_checkout") "Dirty checkout must be dirty_checkout."
    Invoke-TestGit $repo @("restore", "README.md")
    Invoke-TestGit $repo @("checkout", "-q", $first)
    $stale = Probe $repo
    Assert-True ([string]$stale.classification -eq "stale_checkout") "Clean checkout behind origin/main must be stale_checkout."
    $candidate = Probe $repo $first
    Assert-True ([string]$candidate.classification -eq "candidate_checkout") "Expected commit must classify as candidate_checkout."

    $missing = Join-Path $scratch "missing-origin"
    New-Item -ItemType Directory -Path $missing -Force | Out-Null
    Invoke-TestGit $missing @("init", "-q")
    Invoke-TestGit $missing @("config", "user.email", "provenance-test@example.invalid")
    Invoke-TestGit $missing @("config", "user.name", "Codex Praetor provenance test")
    Set-Content -LiteralPath (Join-Path $missing "README.md") -Value "missing" -Encoding ASCII
    Invoke-TestGit $missing @("add", "README.md"); Invoke-TestGit $missing @("commit", "-qm", "missing")
    $unknown = Probe $missing
    Assert-True ([string]$unknown.classification -eq "unknown") "Without origin/main the clean checkout must be unknown."
    Write-Output "[PASS] Source provenance distinguishes product baseline, candidate, stale, dirty, and unknown checkouts without fetching or writing."
} finally {
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}
