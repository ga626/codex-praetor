param(
    [Parameter(Mandatory = $true)]
    [string]$JobDir,

    [Parameter(Mandatory = $true)]
    [int]$WorkerPid,

    [switch]$StartWorker,

    [string]$Exe = "",

    [string]$ArgumentListPath = "",

    [string]$WorkingDirectory = "",

    [string]$StdoutPath = "",

    [string]$StderrPath = "",

    [string]$LockPath = "",

    [string]$NotifyThreadId = "",

    [string]$NotifyWorkspace = "",

    [switch]$NoNotify,

    [ValidateRange(30, 86400)]
    [int]$TimeoutSeconds = 1200
)

$ErrorActionPreference = "Stop"

function Write-JsonFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [object]$Value
    )
    $tmp = "$Path.$([Guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllText($tmp, ($Value | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding($false)))
        [IO.File]::Copy($tmp, $Path, $true)
    } finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
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

function Set-JsonProperty {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Object,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [object]$Value
    )
    if ($Object.PSObject.Properties[$Name]) {
        $Object.$Name = $Value
    } else {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
}

function Test-CancellationRequested {
    param([object]$Metadata, [string]$RequestPath = "")
    return ($null -ne $Metadata -and [string]$Metadata.status -in @("cancel_requested", "cancelled")) -or (-not [string]::IsNullOrWhiteSpace($RequestPath) -and (Test-Path -LiteralPath $RequestPath -PathType Leaf))
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

function Quote-Arg {
    param([string]$Value)
    if ($null -eq $Value) { return '""' }
    if ($Value -notmatch '[\s&|<>]' -and -not $Value.Contains('"')) { return $Value }
    return '"' + ($Value -replace '"', '\"') + '"'
}

function Update-LockForWorker {
    param(
        [string]$Path,
        [string]$JobId,
        [int]$WorkerProcessId
    )
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        return
    }
    $lock = $null
    try {
        $lock = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        $lock = [pscustomobject]@{}
    }
    $updated = [ordered]@{}
    if ($null -ne $lock) {
        foreach ($property in $lock.PSObject.Properties) {
            $updated[$property.Name] = $property.Value
        }
    }
    $updated["pid"] = $PID
    $updated["watcher_pid"] = $PID
    $updated["worker_pid"] = $WorkerProcessId
    $updated["job_id"] = $JobId
    $updated["updated_at"] = (Get-Date).ToString("o")
    $updated["note"] = "Repo edit lock is held by the detached worker process and will be released by watch-codex-praetor-job.ps1 when that process exits."
    $updated | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Get-StreamJsonObservation {
    param([string]$Path)

    $result = [ordered]@{ total_lines = 0; parsed_events = 0; invalid_lines = 0; event_types = @() }
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject]$result
    }
    $types = New-Object System.Collections.Generic.List[string]
    foreach ($line in @(Get-Content -LiteralPath $Path -Encoding UTF8)) {
        if ([string]::IsNullOrWhiteSpace([string]$line)) { continue }
        $result.total_lines += 1
        try {
            $event = [string]$line | ConvertFrom-Json
            if ($null -eq $event -or $event -isnot [object]) { throw "not an event object" }
            $result.parsed_events += 1
            $type = if ($event.PSObject.Properties["type"]) { [string]$event.type } elseif ($event.PSObject.Properties["event"]) { [string]$event.event } else { "untyped" }
            if (-not [string]::IsNullOrWhiteSpace($type) -and -not $types.Contains($type)) { $types.Add($type) }
        } catch {
            $result.invalid_lines += 1
        }
    }
    $result.event_types = @($types)
    return [pscustomobject]$result
}

$metaPath = Join-Path $JobDir "job.json"
$completionPath = Join-Path $JobDir "completion.json"
$cancelRequestPath = Join-Path $JobDir "cancel-request.json"
$watcherLog = Join-Path $JobDir "watcher.log"

try {
    if (-not (Test-Path -LiteralPath $metaPath)) {
        throw "Missing job metadata: $metaPath"
    }

    $meta = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $exitCode = $null
    $waitError = $null
    $alreadyWaited = $false
    $stdoutReadTask = $null
    $stderrReadTask = $null
    $timedOut = $false

    try {
        if ($StartWorker) {
            if ([string]::IsNullOrWhiteSpace($Exe) -or [string]::IsNullOrWhiteSpace($ArgumentListPath)) {
                throw "StartWorker requires -Exe and -ArgumentListPath."
            }
            $latestBeforeStart = Read-JsonWithRetry -Path $metaPath
            if (Test-CancellationRequested -Metadata $latestBeforeStart -RequestPath $cancelRequestPath) {
                $meta = $latestBeforeStart
                $alreadyWaited = $true
            } else {
            if ([string]::IsNullOrWhiteSpace($WorkingDirectory)) {
                $WorkingDirectory = $meta.execution_repo
            }
            if ([string]::IsNullOrWhiteSpace($StdoutPath)) {
                $StdoutPath = $meta.stdout
            }
            if ([string]::IsNullOrWhiteSpace($StderrPath)) {
                $StderrPath = $meta.stderr
            }
            $jobScratch = [string]$meta.job_scratch
            if (-not [string]::IsNullOrWhiteSpace($jobScratch)) {
                New-Item -ItemType Directory -Path $jobScratch -Force | Out-Null
                $env:TEMP = $jobScratch
                $env:TMP = $jobScratch
                Set-JsonProperty -Object $meta -Name "worker_temp" -Value $jobScratch
            }
            $argumentList = @()
            $loadedArgs = Get-Content -LiteralPath $ArgumentListPath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($arg in @($loadedArgs)) {
                $argumentList += [string]$arg
            }
            $argumentLine = ($argumentList | ForEach-Object { Quote-Arg ([string]$_) }) -join " "
            Set-JsonProperty -Object $meta -Name "started_exe" -Value $Exe
            Set-JsonProperty -Object $meta -Name "started_argument_line" -Value $argumentLine
            Set-JsonProperty -Object $meta -Name "watcher_pid" -Value $PID
            Set-JsonProperty -Object $meta -Name "status" -Value "running"
            Set-JsonProperty -Object $meta -Name "started_at" -Value (Get-Date).ToString("o")
            Set-JsonProperty -Object $meta -Name "status_note" -Value "Worker was started and is being waited by the watcher process."
            Write-JsonFile -Path $metaPath -Value $meta
            Update-LockForWorker -Path $LockPath -JobId $meta.job_id -WorkerProcessId 0
            $startInfo = New-Object System.Diagnostics.ProcessStartInfo
            $startInfo.FileName = $Exe
            $startInfo.Arguments = $argumentLine
            $startInfo.WorkingDirectory = $WorkingDirectory
            $startInfo.UseShellExecute = $false
            $startInfo.CreateNoWindow = $true
            $startInfo.RedirectStandardOutput = $true
            $startInfo.RedirectStandardError = $true
            $startInfo.StandardOutputEncoding = New-Object System.Text.UTF8Encoding($false)
            $startInfo.StandardErrorEncoding = New-Object System.Text.UTF8Encoding($false)
            $proc = New-Object System.Diagnostics.Process
            $proc.StartInfo = $startInfo
            if (-not $proc.Start()) { throw "Worker process did not start." }
            $stdoutReadTask = $proc.StandardOutput.ReadToEndAsync()
            $stderrReadTask = $proc.StandardError.ReadToEndAsync()
            $WorkerPid = $proc.Id
            Set-JsonProperty -Object $meta -Name "pid" -Value $WorkerPid
            Set-JsonProperty -Object $meta -Name "worker_started_at" -Value $proc.StartTime.ToUniversalTime().ToString("o")
            Write-JsonFile -Path $metaPath -Value $meta
            $latestAfterStart = Read-JsonWithRetry -Path $metaPath
            if (Test-CancellationRequested -Metadata $latestAfterStart -RequestPath $cancelRequestPath) {
                Stop-ProcessTree -RootProcessId $WorkerPid
                $alreadyWaited = $true
            }
            }
        } else {
            $proc = [System.Diagnostics.Process]::GetProcessById($WorkerPid)
        }
        if (-not $alreadyWaited) {
            $waitMs = [Math]::Min([int64]$TimeoutSeconds * 1000, [int64]2147483647)
            if (-not $proc.WaitForExit([int]$waitMs)) {
                $timedOut = $true
                try {
                    Stop-ProcessTree -RootProcessId $proc.Id
                } catch {
                    $waitError = "Worker timed out and process tree termination failed: $($_.Exception.Message)"
                }
            }
        }
        if ($null -ne $stdoutReadTask -and $null -ne $stderrReadTask) {
            [System.IO.File]::WriteAllText($StdoutPath, [string]$stdoutReadTask.GetAwaiter().GetResult(), (New-Object System.Text.UTF8Encoding($false)))
            [System.IO.File]::WriteAllText($StderrPath, [string]$stderrReadTask.GetAwaiter().GetResult(), (New-Object System.Text.UTF8Encoding($false)))
        }
        $proc.Refresh()
        try {
            $rawExitCode = $proc.ExitCode
            if ($null -ne $rawExitCode) { $exitCode = [int]$rawExitCode }
        } catch {
            $exitCode = $null
        }
    } catch {
        $waitError = $_.Exception.Message
    }

    $latestMeta = $null
    try { $latestMeta = Read-JsonWithRetry -Path $metaPath } catch { $waitError = "Could not read job metadata after retries: $($_.Exception.Message)" }
    $latestCompletion = $null
    try { $latestCompletion = Read-JsonWithRetry -Path $completionPath } catch { $waitError = "Could not read existing completion after retries: $($_.Exception.Message)" }
    $cancelledExternally = (Test-CancellationRequested -Metadata $latestMeta -RequestPath $cancelRequestPath) -or ($null -ne $latestCompletion -and [string]$latestCompletion.status -eq "cancelled")
    $sdkSession = $null
    $sdkSessionPath = if ($null -ne $latestMeta) { [string]$latestMeta.qoder_sdk_session } else { "" }
    if (-not [string]::IsNullOrWhiteSpace($sdkSessionPath)) {
        try { $sdkSession = Read-JsonWithRetry -Path $sdkSessionPath } catch { $sdkSession = $null }
    }
    $streamJsonSession = $null
    $streamJsonSessionPath = if ($null -ne $latestMeta) { [string]$latestMeta.qoder_stream_json_session } else { "" }
    if (-not [string]::IsNullOrWhiteSpace($streamJsonSessionPath)) {
        try { $streamJsonSession = Read-JsonWithRetry -Path $streamJsonSessionPath } catch { $streamJsonSession = $null }
    }
    $acpSession = $null
    $acpSessionPath = if ($null -ne $latestMeta) { [string]$latestMeta.codebuddy_acp_session } else { "" }
    if (-not [string]::IsNullOrWhiteSpace($acpSessionPath)) {
        try { $acpSession = Read-JsonWithRetry -Path $acpSessionPath } catch { $acpSession = $null }
    }
    $completedAcpBoundaryObservation = [string]$latestMeta.connection_mode -eq "codebuddy_acp" -and $null -ne $acpSession -and [string]$acpSession.state -eq "completed" -and [int]$acpSession.boundary_denials -gt 0 -and $null -ne $exitCode -and $exitCode -eq 0
    # A worker exit is execution evidence, not a logical-task acceptance.
    $status = "process_exited"
    $semanticFailure = ""
    $failureSubClass = ""
    # stdout is the worker's untrusted natural-language report. It can describe
    # a failure class as an example while the actual task succeeded, so it must
    # never drive terminal classification. Provider process diagnostics belong
    # on stderr; a non-zero process exit is handled below as well.
    $providerDiagnostics = ""
    $stderrPath = [string]$meta.stderr
    if (-not [string]::IsNullOrWhiteSpace($stderrPath) -and (Test-Path -LiteralPath $stderrPath -PathType Leaf)) {
        $providerDiagnostics = Get-Content -LiteralPath $stderrPath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
    }
    if ($providerDiagnostics -match "(?is)provider[_ -]?(?:rejected|risk[_ -]?control)|request blocked|status(?:Code)?\s*[:=]?\s*4\d\d") {
        $semanticFailure = "provider_rejected"
    } elseif ($providerDiagnostics -match "(?is)max(?:imum)?\s+turns?.*(?:exceeded|limit)|turns?\s+exceeded") {
        $semanticFailure = "max_turns_exceeded"
    } elseif ([string]::IsNullOrWhiteSpace($semanticFailure) -and $providerDiagnostics -match "(?is)tool.+not found.+agent|not found in agent|tool_contract_mismatch") {
        $semanticFailure = "tool_contract_mismatch"
    } elseif ([string]::IsNullOrWhiteSpace($semanticFailure) -and -not $completedAcpBoundaryObservation -and $providerDiagnostics -match "(?is)permission denied|permission_denied") {
        $semanticFailure = "permission_denied"
    }
    if ($cancelledExternally) {
        $status = "cancelled"
        if ([string]$latestMeta.connection_mode -eq "qoder_agent_sdk" -and $null -ne $sdkSession -and [string]$sdkSession.state -eq "cancelled_session_terminated" -and [bool]$sdkSession.abort_requested -and [bool]$sdkSession.iteration_ended) {
            $semanticFailure = "cancelled_session_terminated"
        } elseif ([string]$latestMeta.connection_mode -eq "codebuddy_acp" -and $null -ne $acpSession -and [string]$acpSession.state -eq "cancelled_session_terminated" -and [bool]$acpSession.cancel_requested -and [bool]$acpSession.cancel_acknowledged -and [string]$acpSession.terminal_stop_reason -eq "cancelled") {
            $semanticFailure = "cancelled_session_terminated"
        } else {
            $semanticFailure = "cancelled_by_operator"
        }
    } elseif ([string]$latestMeta.connection_mode -eq "qoder_agent_sdk" -and $null -ne $sdkSession -and [string]$sdkSession.state -eq "progress_saturated" -and [string]$sdkSession.stop_reason -eq "progress_saturated") {
        $status = "process_exited"
        $semanticFailure = "progress_saturated"
    } elseif ([string]$latestMeta.connection_mode -eq "supervised_cli_stream_json" -and $null -ne $streamJsonSession -and [string]$streamJsonSession.state -eq "provider_queue_timeout" -and [bool]$streamJsonSession.queue_observed) {
        # Qoder emits queue heartbeats before a model begins meaningful work.
        # They prove upstream admission, but are not task progress; terminate at
        # the declared queue bound and preserve the provider-side queue facts.
        $status = "timed_out"
        $semanticFailure = "provider_queue_timeout"
        $failureSubClass = "model_queue_saturated"
    } elseif ([string]$latestMeta.connection_mode -eq "codebuddy_acp" -and $null -ne $acpSession -and [string]$acpSession.state -eq "progress_saturated" -and [string]$acpSession.stop_reason -eq "progress_saturated") {
        $status = "process_exited"
        $semanticFailure = "progress_saturated"
    } elseif ([string]$latestMeta.connection_mode -eq "codebuddy_acp" -and $null -ne $acpSession -and [string]$acpSession.terminal_stop_reason -eq "cancelled") {
        $status = "process_exited"
        $semanticFailure = "provider_cancelled_unexpected"
    } elseif ([string]$latestMeta.connection_mode -eq "codebuddy_acp" -and $null -ne $acpSession -and [string]$acpSession.terminal_stop_reason -eq "refusal") {
        # ACP can complete its JSON-RPC process cleanly while refusing the task.
        # Never expose it as a successful worker exit merely because Node exits 0.
        $status = "process_exited"
        $semanticFailure = "provider_rejected"
        $failureSubClass = "provider_refusal_before_tool_use"
    } elseif ($timedOut) {
        $status = "timed_out"
    } elseif (-not [string]::IsNullOrWhiteSpace($semanticFailure)) {
        $status = "process_exited"
    } elseif ($null -ne $exitCode -and $exitCode -ne 0) {
        $status = "process_exited"
        $semanticFailure = "worker_process_failed"
    } elseif ($null -eq $exitCode) {
        $status = "unknown"
        $semanticFailure = "worker_exit_code_unavailable"
    } elseif ($waitError) {
        $status = "unknown"
    }

    $stdoutHasText = -not [string]::IsNullOrWhiteSpace([string]$meta.stdout) -and (Test-Path -LiteralPath ([string]$meta.stdout) -PathType Leaf) -and ((Get-Item -LiteralPath ([string]$meta.stdout)).Length -gt 0)
    $streamJsonObservation = $null
    if ([string]$latestMeta.connection_mode -eq "supervised_cli_stream_json") {
        $streamJsonObservation = Get-StreamJsonObservation -Path ([string]$meta.stdout)
        if ([string]::IsNullOrWhiteSpace($semanticFailure) -and $null -ne $exitCode -and $exitCode -eq 0 -and $streamJsonObservation.parsed_events -eq 0) {
            $semanticFailure = "provider_output_unparseable"
        }
    }
    $worktreeStatus = ""
    $worktreeChanged = $false
    if ($status -eq "process_exited" -and [string]$meta.task_kind -eq "code_change" -and -not [string]::IsNullOrWhiteSpace([string]$meta.execution_repo)) {
        try {
            $worktreeStatus = (& git -C ([string]$meta.execution_repo) status --short 2>$null | Out-String).Trim()
            $worktreeChanged = -not [string]::IsNullOrWhiteSpace($worktreeStatus)
        } catch {
            $worktreeStatus = "worktree_status_unavailable: $($_.Exception.Message)"
        }
    }
    $evidenceState = "evidence_missing"
    $artifactState = "none"
    if ([string]::IsNullOrWhiteSpace($semanticFailure) -and $null -ne $exitCode -and $exitCode -eq 0 -and $status -eq "process_exited") {
        if ([string]$meta.task_kind -eq "code_change" -and $worktreeChanged) {
            $evidenceState = "artifact_valid"
            $artifactState = "worktree_diff_observed"
        } elseif ($stdoutHasText) {
            $evidenceState = "report_valid"
            $artifactState = "report_observed"
        }
    } elseif ($worktreeChanged) {
        $artifactState = "partial_worktree_diff"
    }
    $evidenceObservation = [ordered]@{
        stdout_nonempty = $stdoutHasText
        worktree_changed = $worktreeChanged
        worktree_status = $worktreeStatus
        boundary_denials_observed = if ($null -ne $acpSession) { [int]$acpSession.boundary_denials } else { 0 }
        acp_terminal_stop_reason = if ($null -ne $acpSession) { [string]$acpSession.terminal_stop_reason } else { "" }
        acp_terminal_diagnostic = if ($null -ne $acpSession) { $acpSession.terminal_diagnostic } else { $null }
        stream_json = $streamJsonObservation
        qoder_stream_json_session = $streamJsonSession
        observed_at = (Get-Date).ToString("o")
    }
    # A provider handoff is safe only for an explicit refusal before a material
    # change.  Timeouts, cancellations, failures with a diff, and unknown
    # transport states stay with Codex; they must never be silently replayed.
    $safeProviderFallback = $semanticFailure -eq "provider_rejected" -and $failureSubClass -eq "provider_refusal_before_tool_use" -and -not $worktreeChanged -and [string]$meta.task_kind -ne "external_research"
    $evidenceObservation.safe_provider_fallback = $safeProviderFallback

    $now = Get-Date
    Set-JsonProperty -Object $meta -Name "status" -Value $status
    Set-JsonProperty -Object $meta -Name "process_state" -Value $status
    Set-JsonProperty -Object $meta -Name "evidence_state" -Value $evidenceState
    Set-JsonProperty -Object $meta -Name "artifact_state" -Value $artifactState
    Set-JsonProperty -Object $meta -Name "evidence_observation" -Value $evidenceObservation
    $governanceState = if ([string]::IsNullOrWhiteSpace($semanticFailure) -and $null -ne $exitCode -and $exitCode -eq 0) { "awaiting_supervisor" } else { "rejected" }
    Set-JsonProperty -Object $meta -Name "governance_state" -Value $governanceState
    Set-JsonProperty -Object $meta -Name "exit_code" -Value $exitCode
    Set-JsonProperty -Object $meta -Name "exited_at" -Value $now.ToString("o")
    Set-JsonProperty -Object $meta -Name "wait_error" -Value $waitError
    Set-JsonProperty -Object $meta -Name "completion" -Value $completionPath
    Set-JsonProperty -Object $meta -Name "status_note" -Value "Worker process reached a durable terminal state."
    Write-JsonFile -Path $metaPath -Value $meta

    $completion = [ordered]@{
        schema = "codex-praetor-job-completion/v2"
        job_id = $meta.job_id
        provider = $meta.provider
        tier = $meta.tier
        model = $meta.model
        plan_id = $meta.plan_id
        task_id = $meta.task_id
        depends_on = $meta.depends_on
        acceptance = $meta.acceptance
        repo = $meta.repo
        mode = $meta.mode
        status = $status
        exit_code = $exitCode
        failure_class = $semanticFailure
        failure_subclass = $failureSubClass
        safe_provider_fallback = $safeProviderFallback
        exited_at = $now.ToString("o")
        stdout = $meta.stdout
        stderr = $meta.stderr
        stderr_nonempty = (-not [string]::IsNullOrWhiteSpace([string]$meta.stderr) -and (Test-Path -LiteralPath ([string]$meta.stderr)) -and ((Get-Item -LiteralPath ([string]$meta.stderr)).Length -gt 0))
        worktree = $meta.execution_repo
        base_commit = $meta.base_commit
        worktree_head = $meta.worktree_head
        task_kind = $meta.task_kind
        contract_hash = $meta.contract_hash
        task_contract_schema = $meta.task_contract_schema
        generation_id = $meta.generation_id
        runtime_contract_sha256 = $meta.runtime_contract_sha256
        wrapper_protocol = $meta.wrapper_protocol
        provider_tuple = $meta.provider_tuple
        connection_mode = $meta.connection_mode
        qoder_sdk_session = $sdkSession
        qoder_stream_json_session = $streamJsonSession
        codebuddy_acp_session = $acpSession
        recovery_mode = if ([string]$meta.connection_mode -in @("qoder_agent_sdk", "codebuddy_acp") -and $semanticFailure -eq "cancelled_session_terminated") { "cold_resume_from_codex_ledger" } else { "" }
        terminal_state = $status
        process_state = $status
        evidence_state = $evidenceState
        artifact_state = $artifactState
        evidence_observation = $evidenceObservation
        governance_state = $governanceState
        lock_released = $false
        notify_attempted = $false
        notify_ok = $false
        notify_error = ""
    }

    if (-not [string]::IsNullOrWhiteSpace($LockPath) -and (Test-Path -LiteralPath $LockPath)) {
        $removeLock = $true
        try {
            $lock = Get-Content -LiteralPath $LockPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($null -ne $lock.job_id -and $lock.job_id -ne $meta.job_id) {
                $removeLock = $false
            }
        } catch {
            $removeLock = $true
        }
        if ($removeLock) {
            Remove-Item -LiteralPath $LockPath -Force
            $completion.lock_released = $true
        }
    }

    Write-JsonFile -Path $completionPath -Value $completion

    if ([bool]$latestMeta.evidence_bootstrap -and -not [string]::IsNullOrWhiteSpace([string]$latestMeta.readiness_path)) {
        $readinessRecorder = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "record-codex-praetor-readiness.ps1"
        if (Test-Path -LiteralPath $readinessRecorder -PathType Leaf) {
            try {
                $bootstrapOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $readinessRecorder -JobDir $JobDir -ReadinessPath ([string]$latestMeta.readiness_path) 2>&1
                $completion.readiness_bootstrap = ($bootstrapOutput -join "`n")
                $completion.readiness_bootstrap_status = if ($LASTEXITCODE -eq 0) { "recorded" } else { "failed" }
            } catch {
                $completion.readiness_bootstrap_status = "failed"
                $completion.readiness_bootstrap_error = $_.Exception.Message
            }
            Write-JsonFile -Path $completionPath -Value $completion
        }
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$meta.plan_id) -and -not [string]::IsNullOrWhiteSpace([string]$meta.task_id)) {
        $planScript = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "manage-codex-praetor-plan.ps1"
        $planRoot = [string]$meta.plan_root
        if ([string]::IsNullOrWhiteSpace($planRoot)) {
            $planRoot = "$env:USERPROFILE\.codex\codex-praetor-plans"
        }
        if (Test-Path -LiteralPath $planScript) {
            try {
                $null = & powershell -NoProfile -ExecutionPolicy Bypass -File $planScript -Action RecordJob -PlanId ([string]$meta.plan_id) -PlanRoot $planRoot -TaskId ([string]$meta.task_id) -JobDir $JobDir -CompletionPath $completionPath 2>&1
            } catch {
                $completion.plan_record_error = $_.Exception.Message
            }
        }
    }

    if (-not $NoNotify -and -not [string]::IsNullOrWhiteSpace($NotifyThreadId)) {
        $completion.notify_attempted = $true
        if ([string]::IsNullOrWhiteSpace($NotifyWorkspace)) {
            $NotifyWorkspace = $meta.repo
        }

        $notifyScript = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "notify-codex-praetor-completion.ps1"
        try {
            $result = & powershell -NoProfile -ExecutionPolicy Bypass -File $notifyScript -ThreadId $NotifyThreadId -Workspace $NotifyWorkspace -CompletionPath $completionPath -JobDir $JobDir 2>&1
            $completion.notify_result = ($result -join "`n")
            if ($LASTEXITCODE -eq 0) {
                $completion.notify_ok = $true
            }
        } catch {
            $completion.notify_error = $_.Exception.Message
        }
    }

    Write-JsonFile -Path $completionPath -Value $completion
    "completed $(Get-Date -Format o) status=$status exit_code=$exitCode" | Add-Content -LiteralPath $watcherLog -Encoding UTF8
} catch {
    $failure = [ordered]@{
        schema = "codex-praetor-job-completion/v2"
        status = "watcher_failed"
        job_dir = $JobDir
        worker_pid = $WorkerPid
        job_id = if ($null -ne $meta) { [string]$meta.job_id } else { "" }
        generation_id = if ($null -ne $meta) { [string]$meta.generation_id } else { "" }
        task_contract_schema = if ($null -ne $meta) { [string]$meta.task_contract_schema } else { "" }
        error = $_.Exception.Message
        at = (Get-Date).ToString("o")
    }
    Write-JsonFile -Path $completionPath -Value $failure
    "watcher_failed $(Get-Date -Format o) $($_.Exception.Message)" | Add-Content -LiteralPath $watcherLog -Encoding UTF8
    exit 1
}
