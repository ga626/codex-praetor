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
    param([string]$Name, [string[]]$WorkerArguments, [int]$TimeoutSeconds)
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
    [ordered]@{ schema = "codex-praetor-job/v2"; job_id = "lifecycle-$Name"; repo = $projectPath; execution_repo = $projectPath; provider = "test"; tier = "test"; model = "test"; task_kind = "local_audit"; mode = "readonly"; pid = 0; stdout = $stdoutPath; stderr = $stderrPath; completion = $completionPath; status = "starting" } | ConvertTo-Json | Set-Content -LiteralPath $metaPath -Encoding UTF8
    $watcherArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $watcherScript, "-JobDir", $jobDir, "-WorkerPid", "0", "-StartWorker", "-Exe", "powershell.exe", "-ArgumentListPath", $argumentPath, "-WorkingDirectory", $projectPath, "-StdoutPath", $stdoutPath, "-StderrPath", $stderrPath, "-TimeoutSeconds", "$TimeoutSeconds", "-NoNotify")
    $watcher = Start-Process -FilePath "powershell.exe" -ArgumentList (($watcherArgs | ForEach-Object { Quote-Arg ([string]$_) }) -join " ") -WindowStyle Hidden -RedirectStandardOutput $watcherStdoutPath -RedirectStandardError $watcherStderrPath -PassThru
    if (-not $watcher.WaitForExit(([Math]::Min(($TimeoutSeconds + 20) * 1000, 2147483647)))) { try { $watcher.Kill() } catch { }; throw "Watcher did not finish for case $Name." }
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
    Assert-True ([string]$semantic.governance_state -eq "awaiting_supervisor") "Worker exit must await a supervisor verdict."
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
    Write-Host "[PASS] Job lifecycle smoke passed: semantic failure, timeout, and durable cancellation."
} finally {
    if ($succeeded -and (Test-Path -LiteralPath $testRoot)) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
    if (-not $succeeded) { Write-Host "[DIAGNOSTIC] Lifecycle test artifacts retained at $testRoot" }
}
