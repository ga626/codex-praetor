param(
    [Parameter(Mandatory = $true)]
    [string]$JobDir
)

$ErrorActionPreference = "Stop"
$metaPath = Join-Path $JobDir "job.json"
$completionPath = Join-Path $JobDir "completion.json"
$cancelRequestPath = Join-Path $JobDir "cancel-request.json"
if (-not (Test-Path -LiteralPath $metaPath -PathType Leaf)) {
    throw "Missing job metadata: $metaPath"
}

function Read-JsonWithRetry {
    param([string]$Path, [int]$Attempts = 50)
    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        try {
            if (Test-Path -LiteralPath $Path -PathType Leaf) {
                return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
            }
            return $null
        } catch {
            if ($attempt -eq $Attempts) { throw }
            Start-Sleep -Milliseconds 100
        }
    }
}

function Write-JsonFile {
    param([string]$Path, [object]$Value)
    $tmp = "$Path.$([Guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllText($tmp, ($Value | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $tmp -Destination $Path -Force
    } finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
}

function Set-JsonProperty {
    param([object]$Object, [string]$Name, [object]$Value)
    if ($Object.PSObject.Properties[$Name]) {
        $Object.$Name = $Value
    } else {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
}

$meta = Read-JsonWithRetry -Path $metaPath
$existingCompletion = $null
if (Test-Path -LiteralPath $completionPath -PathType Leaf) {
    try { $existingCompletion = Read-JsonWithRetry -Path $completionPath } catch { $existingCompletion = $null }
}
if ($null -ne $existingCompletion -and [string]$existingCompletion.status -in @("process_exited", "failed", "timed_out", "cancelled", "watcher_failed")) {
    throw "Job $($meta.job_id) is already terminal ($($existingCompletion.status)); refusing to rewrite its completion record."
}

Write-JsonFile -Path $cancelRequestPath -Value ([ordered]@{
    schema = "codex-praetor-cancel-request/v1"
    job_id = $meta.job_id
    requested_at = (Get-Date).ToString("o")
    requested_by = "operator"
})

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
Set-JsonProperty -Object $meta -Name "status" -Value "cancel_requested"
Set-JsonProperty -Object $meta -Name "cancel_requested_at" -Value (Get-Date).ToString("o")
Set-JsonProperty -Object $meta -Name "status_note" -Value "Cancellation was requested; the watcher is the only terminal-state writer."
Write-JsonFile -Path $metaPath -Value $meta

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

Set-JsonProperty -Object $meta -Name "status_note" -Value "Cancellation request persisted; waiting for watcher terminal projection."
Write-JsonFile -Path $metaPath -Value $meta
Write-Output "job_id=$($meta.job_id)"
Write-Output "status=cancel_requested"
