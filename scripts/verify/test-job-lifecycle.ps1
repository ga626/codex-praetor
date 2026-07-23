param(
    [string]$ProjectRoot = ""
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $ProjectRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
}
$projectPath = [System.IO.Path]::GetFullPath($ProjectRoot)
$testRoot = Join-Path $projectPath (".codex-praetor\job-lifecycle-smoke-" + [Guid]::NewGuid().ToString("N"))
$watcherScript = Join-Path $projectPath "scripts\dispatch\watch-codex-praetor-job.ps1"
$cancelScript = Join-Path $projectPath "scripts\dispatch\cancel-codex-praetor-job.ps1"

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Quote-Arg {
    param([string]$Value)
    if ($Value -notmatch '[\s&|<>]' -and -not $Value.Contains('"')) { return $Value }
    return '"' + ($Value -replace '"', '\"') + '"'
}

function Invoke-WatchedCase {
    param(
        [string]$Name,
        [string[]]$WorkerArguments,
        [int]$TimeoutSeconds,
        [string]$Provider = "test",
        [string]$TaskKind = "local_audit",
        [string]$ExecutionRepo = ""
    )
    if ([string]::IsNullOrWhiteSpace($ExecutionRepo)) { $ExecutionRepo = $projectPath }
    $jobDir = Join-Path $testRoot $Name
    New-Item -ItemType Directory -Path $jobDir -Force | Out-Null
    $argumentPath = Join-Path $jobDir "arguments.json"
    $stdoutPath = Join-Path $jobDir "stdout.log"
    $stderrPath = Join-Path $jobDir "stderr.log"
    $watcherStdoutPath = Join-Path $jobDir "watcher.stdout.log"
    $watcherStderrPath = Join-Path $jobDir "watcher.stderr.log"
    $metaPath = Join-Path $jobDir "job.json"
    $completionPath = Join-Path $jobDir "completion.json"
    $WorkerArguments | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $argumentPath -Encoding UTF8
    [ordered]@{ schema = "codex-praetor-job/v2"; job_id = "lifecycle-$Name"; repo = $projectPath; execution_repo = $ExecutionRepo; provider = $Provider; tier = "test"; model = "test"; task_kind = $TaskKind; mode = if ($TaskKind -eq "code_change") { "edit" } else { "readonly" }; pid = 0; stdout = $stdoutPath; stderr = $stderrPath; completion = $completionPath; status = "starting" } | ConvertTo-Json | Set-Content -LiteralPath $metaPath -Encoding UTF8
    $watcherArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $watcherScript, "-JobDir", $jobDir, "-WorkerPid", "0", "-StartWorker", "-Exe", "powershell.exe", "-ArgumentListPath", $argumentPath, "-WorkingDirectory", $ExecutionRepo, "-StdoutPath", $stdoutPath, "-StderrPath", $stderrPath, "-TimeoutSeconds", "$TimeoutSeconds", "-NoNotify")
    $watcher = Start-Process -FilePath "powershell.exe" -ArgumentList (($watcherArgs | ForEach-Object { Quote-Arg ([string]$_) }) -join " ") -WindowStyle Hidden -RedirectStandardOutput $watcherStdoutPath -RedirectStandardError $watcherStderrPath -PassThru
    # The watcher is allowed to spend up to 15 seconds terminating a process
    # tree after its own timeout. Keep the test wait bounded, but leave enough
    # room for that cleanup and durable completion write on loaded Windows hosts.
    if (-not $watcher.WaitForExit(([Math]::Min(($TimeoutSeconds + 45) * 1000, 2147483647)))) { try { $watcher.Kill() } catch { }; throw "Watcher did not finish for case $Name." }
    if (-not (Test-Path -LiteralPath $completionPath -PathType Leaf)) {
        $diagnostic = if (Test-Path -LiteralPath $watcherStderrPath) { Get-Content -LiteralPath $watcherStderrPath -Raw -Encoding UTF8 } else { "" }
        throw "Completion is missing for case $Name. Watcher stderr: $diagnostic"
    }
    return (Get-Content -LiteralPath $completionPath -Raw -Encoding UTF8 | ConvertFrom-Json)
}

try {
    $succeeded = $false
    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
    $semantic = Invoke-WatchedCase -Name "semantic-exit-zero" -WorkerArguments @("-NoProfile", "-Command", "Write-Error permission denied; exit 0") -TimeoutSeconds 30
    Assert-True ([string]$semantic.status -eq "process_exited") "A worker exit must be recorded as process_exited, not a logical outcome."
    Assert-True ([string]$semantic.failure_class -eq "permission_denied") "Semantic permission failure was not classified."
    Assert-True ([string]$semantic.governance_state -eq "rejected") "Semantic worker failure must be recorded as rejected, not awaiting supervisor acceptance."
    $report = Invoke-WatchedCase -Name "report-evidence" -WorkerArguments @("-NoProfile", "-Command", "Write-Output 'worker report'; exit 0") -TimeoutSeconds 30
    Assert-True ([string]$report.evidence_state -eq "report_valid") "A successful worker report must be recorded as report evidence while awaiting supervisor verification."
    $nonzeroScript = Join-Path $testRoot "nonzero-worker.ps1"
    Set-Content -LiteralPath $nonzeroScript -Value "Write-Output 'unclassified failure'; exit 7" -Encoding ASCII
    $nonzero = Invoke-WatchedCase -Name "nonzero-exit" -WorkerArguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $nonzeroScript) -TimeoutSeconds 30
    Assert-True ([string]$nonzero.failure_class -eq "worker_process_failed") "A nonzero worker exit without a keyword must have a structured failure class."
    Assert-True ([string]$nonzero.governance_state -eq "rejected") "A nonzero worker exit must not be recorded as awaiting supervisor acceptance."
    $maxTurns = Invoke-WatchedCase -Name "max-turns" -WorkerArguments @("-NoProfile", "-Command", "Write-Error 'Max turns (8) exceeded'; exit 0") -TimeoutSeconds 30
    Assert-True ([string]$maxTurns.failure_class -eq "max_turns_exceeded") "Max turns must have a structured failure class."
    Assert-True ([string]$maxTurns.evidence_state -eq "evidence_missing") "Max turns output must not be labeled as valid report evidence."
    Assert-True ([string]$maxTurns.governance_state -eq "rejected") "Max turns must not be recorded as awaiting verification."
    $partialRepo = Join-Path $testRoot "partial-worktree"
    New-Item -ItemType Directory -Path $partialRepo -Force | Out-Null
    & git -C $partialRepo init -q
    if ($LASTEXITCODE -ne 0) { throw "Could not initialize partial-worktree fixture." }
    $partial = Invoke-WatchedCase -Name "partial-max-turns" -WorkerArguments @("-NoProfile", "-Command", "Set-Content -LiteralPath partial.txt -Value partial; Write-Error 'Max turns (16) exceeded'; exit 0") -TimeoutSeconds 30 -TaskKind "code_change" -ExecutionRepo $partialRepo
    Assert-True ([string]$partial.artifact_state -eq "partial_worktree_diff") "A max-turns worktree diff must be marked as partial, not accepted artifact evidence."
    $rejected = Invoke-WatchedCase -Name "provider-rejected" -WorkerArguments @("-NoProfile", "-Command", "Write-Error 'provider_rejected: request blocked statusCode 400'; exit 0") -TimeoutSeconds 30 -Provider "qoder" -TaskKind "code_change" -ExecutionRepo $partialRepo
    Assert-True ([string]$rejected.failure_class -eq "provider_rejected") "A provider rejection must be classified as provider_rejected."
    Assert-True ([string]$rejected.evidence_state -eq "evidence_missing") "A provider rejection must never be labeled as valid worker evidence."
    $timedOut = Invoke-WatchedCase -Name "timeout" -WorkerArguments @("-NoProfile", "-Command", "Start-Sleep -Seconds 35") -TimeoutSeconds 30
    Assert-True ([string]$timedOut.status -eq "timed_out") "Worker timeout was not classified."

    $cancelDir = Join-Path $testRoot "cancel"
    New-Item -ItemType Directory -Path $cancelDir -Force | Out-Null
    $cancelArgsPath = Join-Path $cancelDir "arguments.json"
    $cancelStdout = Join-Path $cancelDir "stdout.log"
    $cancelStderr = Join-Path $cancelDir "stderr.log"
    $cancelMetaPath = Join-Path $cancelDir "job.json"
    $cancelCompletionPath = Join-Path $cancelDir "completion.json"
    @("-NoProfile", "-Command", "Start-Sleep -Seconds 300") | ConvertTo-Json | Set-Content -LiteralPath $cancelArgsPath -Encoding UTF8
    [ordered]@{ schema = "codex-praetor-job/v2"; job_id = "lifecycle-cancel"; repo = $projectPath; execution_repo = $projectPath; provider = "test"; tier = "test"; model = "test"; task_kind = "local_audit"; mode = "readonly"; pid = 0; stdout = $cancelStdout; stderr = $cancelStderr; completion = $cancelCompletionPath; status = "starting" } | ConvertTo-Json | Set-Content -LiteralPath $cancelMetaPath -Encoding UTF8
    $cancelWatchArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $watcherScript, "-JobDir", $cancelDir, "-WorkerPid", "0", "-StartWorker", "-Exe", "powershell.exe", "-ArgumentListPath", $cancelArgsPath, "-WorkingDirectory", $projectPath, "-StdoutPath", $cancelStdout, "-StderrPath", $cancelStderr, "-TimeoutSeconds", "30", "-NoNotify")
    $cancelWatcher = Start-Process -FilePath "powershell.exe" -ArgumentList (($cancelWatchArgs | ForEach-Object { Quote-Arg ([string]$_) }) -join " ") -WindowStyle Hidden -PassThru
    $workerPid = 0
    for ($attempt = 0; $attempt -lt 50; $attempt++) { Start-Sleep -Milliseconds 100; $currentMeta = Get-Content -LiteralPath $cancelMetaPath -Raw -Encoding UTF8 | ConvertFrom-Json; if ([int]$currentMeta.pid -gt 0) { $workerPid = [int]$currentMeta.pid; break } }
    Assert-True ($workerPid -gt 0) "Cancellation case did not publish a worker identity."
    $cancelOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cancelScript -JobDir $cancelDir 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Cancellation command failed: $($cancelOutput -join "`n")" }
    if (-not $cancelWatcher.WaitForExit(15000)) { throw "Cancellation watcher did not finish." }
    $cancelCompletion = Get-Content -LiteralPath $cancelCompletionPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ([string]$cancelCompletion.status -eq "cancelled") "Cancellation was overwritten by watcher completion."
    $succeeded = $true
    Write-Host "[PASS] Job lifecycle smoke passed: semantic failures, provider rejection, partial artifacts, timeout, and durable cancellation."
} finally {
    if ($succeeded -and (Test-Path -LiteralPath $testRoot)) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
    if (-not $succeeded) { Write-Host "[DIAGNOSTIC] Lifecycle test artifacts retained at $testRoot" }
}
