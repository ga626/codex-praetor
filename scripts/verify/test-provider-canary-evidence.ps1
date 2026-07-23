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
    $workerRepo = Join-Path $scratch "worker-repo"
    $workerJobDir = Join-Path $scratch "worker-job"
    New-Item -ItemType Directory -Path $workerRepo -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $workerRepo "README.md") -Value "worker fixture" -Encoding UTF8
    & git -C $workerRepo init -q
    & git -C $workerRepo config user.email "canary-test@example.invalid"
    & git -C $workerRepo config user.name "Codex Praetor test"
    & git -C $workerRepo add README.md
    & git -C $workerRepo commit -qm "fixture"
    if ($LASTEXITCODE -ne 0) { throw "Unable to create the edit-canary worker fixture repository." }
    $wrapperPath = Join-Path $scratch "fake-wrapper.ps1"
    @'
$taskKind = ""
for ($index = 0; $index -lt $args.Count; $index++) {
    if ($args[$index] -eq "-TaskKind" -and $index + 1 -lt $args.Count) {
        $taskKind = [string]$args[$index + 1]
        break
    }
}
$workerRepo = $env:CODEX_PRAETOR_CANARY_WORKER_REPO
$jobDir = $env:CODEX_PRAETOR_CANARY_WORKER_JOB_DIR
New-Item -ItemType Directory -Path $jobDir -Force | Out-Null
$stdoutPath = Join-Path $jobDir "stdout.log"
$completionPath = Join-Path $jobDir "completion.json"
$failure = $env:CODEX_PRAETOR_CANARY_FAKE_FAILURE -eq "1"
$permission = if ($taskKind -eq "code_change") { "edit_worktree" } elseif ($taskKind -eq "test_execution") { "test-execution-v1" } else { "readonly_read_grep_glob" }
[ordered]@{ job_id = "fake-canary-$taskKind"; execution_repo = $workerRepo; stdout = $stdoutPath; completion = $completionPath; provider_tuple = [ordered]@{ model = "Qwen3.7-Plus"; permission_profile = $permission } } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $jobDir "job.json") -Encoding UTF8
if ($failure) {
    Set-Content -LiteralPath $stdoutPath -Value "Request blocked by risk control" -Encoding UTF8
    [ordered]@{ status = "process_exited"; exit_code = 0; failure_class = "provider_output_unparseable" } | ConvertTo-Json | Set-Content -LiteralPath $completionPath -Encoding UTF8
    Write-Output "command=TASK: CODEX_PRAETOR_CAPABILITY_CANARY_OK"
    Write-Output "job_dir=$jobDir"
    Write-Output "model=Qwen3.7-Plus"
    Write-Output "permission_profile=$permission"
    exit 0
}
Set-Content -LiteralPath $stdoutPath -Value "CODEX_PRAETOR_CAPABILITY_CANARY_OK" -Encoding UTF8
[ordered]@{ status = "process_exited"; exit_code = 0; failure_class = "" } | ConvertTo-Json | Set-Content -LiteralPath $completionPath -Encoding UTF8
if ($taskKind -eq "code_change") {
    Set-Content -LiteralPath (Join-Path $workerRepo "CODEX_PRAETOR_EDIT_CANARY.txt") -Value "CODEX_PRAETOR_CAPABILITY_CANARY_OK" -Encoding ASCII
} elseif ($taskKind -eq "test_execution") {
    Start-Sleep -Milliseconds 120
    Set-Content -LiteralPath $env:CODEX_PRAETOR_CANARY_DRIFT_PATH -Value "concurrent editor" -Encoding UTF8
} else {
    Start-Sleep -Milliseconds 120
    Set-Content -LiteralPath $env:CODEX_PRAETOR_CANARY_DRIFT_PATH -Value "concurrent editor" -Encoding UTF8
}
Write-Output "job_dir=$jobDir"
Write-Output "model=Qwen3.7-Plus"
Write-Output "permission_profile=$permission"
Write-Output "version=fake-provider"
Write-Output "CODEX_PRAETOR_CAPABILITY_CANARY_OK"
'@ | Set-Content -LiteralPath $wrapperPath -Encoding UTF8

    $env:CODEX_PRAETOR_CANARY_DRIFT_PATH = $driftPath
    $env:CODEX_PRAETOR_CANARY_WORKER_REPO = $workerRepo
    $env:CODEX_PRAETOR_CANARY_WORKER_JOB_DIR = $workerJobDir
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $canary -Repo $repo -Provider qoder -ConfigPath $configPath -ReadinessPath $readinessPath -WrapperPath $wrapperPath -Apply
    if ($LASTEXITCODE -ne 0) { throw "A successful worker plus concurrent checkout drift must retain readiness proof." }
    $state = Get-Content -LiteralPath $readinessPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ([string]$state.repo_observation.status -eq "external_repo_drift_observed") "Canary did not retain the concurrent repository-drift observation."
    Assert-True (@($state.entries).Count -eq 1) "Canary did not write exactly one readiness tuple."
    Assert-True ([string]$state.entries[0].repo_observation.status -eq "external_repo_drift_observed") "Readiness tuple did not retain its repository observation."

    Remove-Item -LiteralPath $driftPath -Force
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $canary -Repo $repo -Provider qoder -ConfigPath $configPath -ReadinessPath $readinessPath -WrapperPath $wrapperPath -TaskKind code_change -Apply
    if ($LASTEXITCODE -ne 0) { throw "A code-change canary with a worker worktree diff must pass." }
    $state = Get-Content -LiteralPath $readinessPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $editEntry = @($state.entries | Where-Object { [string]$_.task_kind -eq "code_change" }) | Select-Object -First 1
    Assert-True ($null -ne $editEntry) "Edit capability canary did not write a code-change readiness tuple."
    Assert-True (Test-Path -LiteralPath (Join-Path $workerRepo "CODEX_PRAETOR_EDIT_CANARY.txt") -PathType Leaf) "Edit capability canary did not require a worker-worktree artifact."
    Assert-True (-not [string]::IsNullOrWhiteSpace((& git -C $workerRepo status --short | Out-String).Trim())) "Edit capability canary did not require a worker-worktree diff."

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $canary -Repo $repo -Provider qoder -ConfigPath $configPath -ReadinessPath $readinessPath -WrapperPath $wrapperPath -TaskKind test_execution -Apply
    if ($LASTEXITCODE -ne 0) { throw "A test-execution canary must record a distinct readonly-with-Bash capability tuple." }
    $state = Get-Content -LiteralPath $readinessPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $testEntry = @($state.entries | Where-Object { [string]$_.task_kind -eq "test_execution" }) | Select-Object -First 1
    Assert-True ($null -ne $testEntry) "Test-execution capability canary did not write its readiness tuple."
    Assert-True ([string]$testEntry.permission_profile -eq "test-execution-v1") "Test-execution canary did not record its distinct permission profile."
    Assert-True ([string]$testEntry.evidence.schema -eq "codex-praetor-canary-evidence/v1") "Readiness tuple did not retain authenticated worker evidence."

    Remove-Item -LiteralPath $driftPath -Force
    $beforeFailureEntries = @($state.entries).Count
    $env:CODEX_PRAETOR_CANARY_FAKE_FAILURE = "1"
    $failureStdoutPath = Join-Path $scratch "failure-stdout.txt"
    $failureStderrPath = Join-Path $scratch "failure-stderr.txt"
    $previousFailureErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $canary -Repo $repo -Provider qoder -ConfigPath $configPath -ReadinessPath $readinessPath -WrapperPath $wrapperPath -Apply 1>$failureStdoutPath 2>$failureStderrPath
        $failureExitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousFailureErrorAction
    }
    Remove-Item Env:CODEX_PRAETOR_CANARY_FAKE_FAILURE -ErrorAction SilentlyContinue
    Assert-True ($failureExitCode -ne 0) "A wrapper echo must not turn a rejected worker into readiness."
    $afterFailureState = Get-Content -LiteralPath $readinessPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True (@($afterFailureState.entries).Count -eq $beforeFailureEntries) "Rejected worker output must not mutate readiness."

    Set-Content -LiteralPath (Join-Path $repo "dirty-before.txt") -Value "dirty" -Encoding UTF8
    $dirtyStdoutPath = Join-Path $scratch "dirty-stdout.txt"
    $dirtyStderrPath = Join-Path $scratch "dirty-stderr.txt"
    $previousErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $canary -Repo $repo -Provider qoder -ConfigPath $configPath -ReadinessPath $readinessPath -WrapperPath $wrapperPath -Apply 1>$dirtyStdoutPath 2>$dirtyStderrPath
        $dirtyExitCode = $LASTEXITCODE
        $dirtyOutput = @(
            (Get-Content -LiteralPath $dirtyStdoutPath -Raw -Encoding UTF8),
            (Get-Content -LiteralPath $dirtyStderrPath -Raw -Encoding UTF8)
        )
    } finally {
        $ErrorActionPreference = $previousErrorAction
    }
    Assert-True ($dirtyExitCode -ne 0) "A dirty repository before a capability canary must be rejected."
    Assert-True (($dirtyOutput -join "`n") -match "requires a clean repository") "Dirty-before rejection did not explain the safe next action."

    Write-Host "[PASS] Capability canary separates clean-before safety from concurrent repository-drift observation."
} finally {
    Remove-Item Env:CODEX_PRAETOR_CANARY_DRIFT_PATH -ErrorAction SilentlyContinue
    Remove-Item Env:CODEX_PRAETOR_CANARY_WORKER_REPO -ErrorAction SilentlyContinue
    Remove-Item Env:CODEX_PRAETOR_CANARY_WORKER_JOB_DIR -ErrorAction SilentlyContinue
    Remove-Item Env:CODEX_PRAETOR_CANARY_FAKE_FAILURE -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}

# The last native call intentionally exercises a rejected dirty checkout.  Do not
# leak that expected non-zero exit code after all assertions have passed.
exit 0
