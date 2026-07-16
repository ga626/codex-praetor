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
$pid = [int]$meta.pid
if ($pid -le 0) {
    throw "Job has no worker pid yet: $($meta.job_id)"
}

$proc = $null
try {
    $proc = [System.Diagnostics.Process]::GetProcessById($pid)
} catch {
    throw "Worker process is no longer running: $pid"
}

if ($meta.worker_started_at) {
    $expected = [DateTime]::Parse([string]$meta.worker_started_at).ToUniversalTime()
    if ([Math]::Abs(($proc.StartTime.ToUniversalTime() - $expected).TotalSeconds) -gt 2) {
        throw "PID identity check failed for job $($meta.job_id); refusing to kill a reused process id."
    }
}

try {
    $proc.Kill($true)
    $proc.WaitForExit(15000) | Out-Null
} catch {
    throw "Could not terminate worker process tree for job $($meta.job_id): $($_.Exception.Message)"
}

$meta.status = "cancelled"
$meta.cancelled_at = (Get-Date).ToString("o")
$meta.status_note = "Worker process tree was cancelled through the durable job identity."
$meta | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $metaPath -Encoding UTF8

$completion = [ordered]@{
    job_id = $meta.job_id
    provider = $meta.provider
    tier = $meta.tier
    model = $meta.model
    task_kind = $meta.task_kind
    contract_hash = $meta.contract_hash
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
