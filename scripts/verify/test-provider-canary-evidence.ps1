param(
    [string]$ProjectRoot = ""
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}
$root = [System.IO.Path]::GetFullPath($ProjectRoot)
$canary = Join-Path $root "scripts\verify\test-provider-capability-canary.ps1"
if (-not (Test-Path -LiteralPath $canary -PathType Leaf)) { throw "Capability canary is missing: $canary" }

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$scratch = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-praetor-canary-evidence-" + [guid]::NewGuid().ToString("N"))
try {
    New-Item -ItemType Directory -Path $scratch -Force | Out-Null
    $repo = Join-Path $scratch "repo"
    New-Item -ItemType Directory -Path $repo -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $repo "README.md") -Value "fixture" -Encoding UTF8
    & git -C $repo init -q
    & git -C $repo config user.email "canary-test@example.invalid"
    & git -C $repo config user.name "Codex Praetor test"
    & git -C $repo add README.md
    & git -C $repo commit -qm "fixture"
    if ($LASTEXITCODE -ne 0) { throw "Unable to create the canary fixture repository." }

    $powershellPath = (Get-Command powershell.exe -ErrorAction Stop).Source
    $configPath = Join-Path $scratch "providers.json"
    [ordered]@{ providers = [ordered]@{ qoder = [ordered]@{ cliPath = $powershellPath } } } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $configPath -Encoding UTF8
    $readinessPath = Join-Path $scratch "readiness.json"
    $driftPath = Join-Path $repo "external-drift.txt"
    $wrapperPath = Join-Path $scratch "fake-wrapper.ps1"
    @'
Start-Sleep -Milliseconds 120
Set-Content -LiteralPath $env:CODEX_PRAETOR_CANARY_DRIFT_PATH -Value "concurrent editor" -Encoding UTF8
Write-Output "model=Qwen3.7-Plus"
Write-Output "permission_profile=readonly_read_grep_glob"
Write-Output "version=fake-provider"
Write-Output "CODEX_PRAETOR_CAPABILITY_CANARY_OK"
'@ | Set-Content -LiteralPath $wrapperPath -Encoding UTF8

    $env:CODEX_PRAETOR_CANARY_DRIFT_PATH = $driftPath
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $canary -Repo $repo -Provider qoder -ConfigPath $configPath -ReadinessPath $readinessPath -WrapperPath $wrapperPath -Apply
    if ($LASTEXITCODE -ne 0) { throw "A successful worker plus concurrent checkout drift must retain readiness proof." }
    $state = Get-Content -LiteralPath $readinessPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ([string]$state.repo_observation.status -eq "external_repo_drift_observed") "Canary did not retain the concurrent repository-drift observation."
    Assert-True (@($state.entries).Count -eq 1) "Canary did not write exactly one readiness tuple."
    Assert-True ([string]$state.entries[0].repo_observation.status -eq "external_repo_drift_observed") "Readiness tuple did not retain its repository observation."

    Remove-Item -LiteralPath $driftPath -Force
    Set-Content -LiteralPath (Join-Path $repo "dirty-before.txt") -Value "dirty" -Encoding UTF8
    $previousErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $dirtyOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $canary -Repo $repo -Provider qoder -ConfigPath $configPath -ReadinessPath $readinessPath -WrapperPath $wrapperPath -Apply 2>&1
        $dirtyExitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorAction
    }
    Assert-True ($dirtyExitCode -ne 0) "A dirty repository before a capability canary must be rejected."
    Assert-True (($dirtyOutput -join "`n") -match "requires a clean repository") "Dirty-before rejection did not explain the safe next action."

    Write-Host "[PASS] Capability canary separates clean-before safety from concurrent repository-drift observation."
} finally {
    Remove-Item Env:CODEX_PRAETOR_CANARY_DRIFT_PATH -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}
