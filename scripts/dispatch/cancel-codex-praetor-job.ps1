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
if ($null -ne $existingCompletion -and [string]$existingCompletion.status -in @("process_exited", "failed", "timed_out", "cancelled", "watcher_failed")) {
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
$meta.status = "cancel_requested"
$meta | Add-Member -NotePropertyName "cancel_requested_at" -NotePropertyValue (Get-Date).ToString("o") -Force
$meta.status_note = "Cancellation was requested; the watcher is the only terminal-state writer."
$meta | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $metaPath -Encoding UTF8

if ($workerProcessId -gt 0) {
    try {
        $proc = [System.Diagnostics.Process]::GetProcessById($workerProcessId)
        if ($meta.worker_started_at) {
            $expected = [DateTime]::Parse([string]$meta.worker_started_at).ToUniversalTime()
            if ([Math]::Abs(($proc.StartTime.ToUniversalTime() - $expected).TotalSeconds) -gt 2) {
                throw "PID identity check failed for job $($meta.job_id); refusing to kill a reused process id."
            }
        }
        Stop-ProcessTree -RootProcessId $proc.Id
    } catch [System.ArgumentException] {
        # The process can exit after the request is persisted; watcher will project the terminal state.
    } catch {
        throw "Could not terminate worker process tree for job $($meta.job_id): $($_.Exception.Message)"
    }
}

$meta.status_note = "Cancellation request persisted; waiting for watcher terminal projection."
$meta | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $metaPath -Encoding UTF8
Write-Output "job_id=$($meta.job_id)"
Write-Output "status=cancel_requested"
