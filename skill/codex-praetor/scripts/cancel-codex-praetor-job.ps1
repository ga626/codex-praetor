param(
    [Parameter(Mandatory = $true)]
    [string]$JobDir
)

$ErrorActionPreference = "Stop"
$metaPath = Join-Path $JobDir "job.json"
$completionPath = Join-Path $JobDir "completion.json"
if (-not (Test-Path -LiteralPath $metaPath -PathType Leaf)) {
    throw "Missing job metadata: $metaPath"
}

$meta = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8 | ConvertFrom-Json
$existingCompletion = $null
if (Test-Path -LiteralPath $completionPath -PathType Leaf) {
    try { $existingCompletion = Get-Content -LiteralPath $completionPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $existingCompletion = $null }
}
if ($null -ne $existingCompletion -and [string]$existingCompletion.status -in @("completed", "failed", "timed_out", "cancelled", "watcher_failed")) {
    throw "Job $($meta.job_id) is already terminal ($($existingCompletion.status)); refusing to rewrite its completion record."
}

function Stop-ProcessTree {
    param([int]$RootProcessId)
    $children = @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$RootProcessId" -ErrorAction SilentlyContinue)
    foreach ($child in $children) {
        Stop-ProcessTree -RootProcessId ([int]$child.ProcessId)
    }
    try {
        $target = [System.Diagnostics.Process]::GetProcessById($RootProcessId)
        $target.Kill()
        $target.WaitForExit(15000) | Out-Null
    } catch {
        if ($_.Exception.Message -notmatch "exited|no longer running|找不到") { throw }
    }
}
$workerProcessId = [int]$meta.pid
if ($workerProcessId -le 0) {
    throw "Job has no worker pid yet: $($meta.job_id)"
}

$proc = $null
try {
    $proc = [System.Diagnostics.Process]::GetProcessById($workerProcessId)
} catch {
    throw "Worker process is no longer running: $workerProcessId"
}

if ($meta.worker_started_at) {
    $expected = [DateTime]::Parse([string]$meta.worker_started_at).ToUniversalTime()
    if ([Math]::Abs(($proc.StartTime.ToUniversalTime() - $expected).TotalSeconds) -gt 2) {
        throw "PID identity check failed for job $($meta.job_id); refusing to kill a reused process id."
    }
}

# Publish the cancellation intent before terminating the worker so the watcher cannot win the terminal-state race.
$meta.status = "cancelled"
$meta | Add-Member -NotePropertyName "cancelled_at" -NotePropertyValue (Get-Date).ToString("o") -Force
$meta.status_note = "Worker cancellation was requested through the durable job identity."
$meta | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $metaPath -Encoding UTF8

try {
    Stop-ProcessTree -RootProcessId $proc.Id
} catch {
    throw "Could not terminate worker process tree for job $($meta.job_id): $($_.Exception.Message)"
}

$meta.status_note = "Worker process tree was cancelled through the durable job identity."
$meta | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $metaPath -Encoding UTF8

$completion = [ordered]@{
    schema = "codex-praetor-job-completion/v2"
    job_id = $meta.job_id
    provider = $meta.provider
    tier = $meta.tier
    model = $meta.model
    task_kind = $meta.task_kind
    contract_hash = $meta.contract_hash
    task_contract_schema = $meta.task_contract_schema
    generation_id = $meta.generation_id
    runtime_contract_sha256 = $meta.runtime_contract_sha256
    wrapper_protocol = $meta.wrapper_protocol
    terminal_state = "cancelled"
    status = "cancelled"
    exit_code = $null
    cancelled_at = (Get-Date).ToString("o")
    stdout = $meta.stdout
    stderr = $meta.stderr
    worktree = $meta.execution_repo
}
$completion | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $completionPath -Encoding UTF8
Write-Output "job_id=$($meta.job_id)"
Write-Output "status=cancelled"
