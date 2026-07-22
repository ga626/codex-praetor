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
    $Value | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding UTF8
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

function Read-MiMoJsonEventSummary {
    param([string]$Path)
    $summary = [ordered]@{
        text = ""
        cost = $null
        input_tokens = $null
        output_tokens = $null
        reasoning_tokens = $null
        cache_read = $null
        cache_write = $null
        tool_use_count = 0
        parse_errors = 0
        provider_error = $null
    }

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        return $summary
    }

    $texts = New-Object System.Collections.Generic.List[string]
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart()[0] -ne "{") {
            continue
        }
        try {
            $event = $line | ConvertFrom-Json
        } catch {
            $summary.parse_errors = [int]$summary.parse_errors + 1
            continue
        }

        if ($event.type -eq "text" -and $null -ne $event.part.text) {
            $texts.Add([string]$event.part.text) | Out-Null
        }

        if ($event.type -eq "tool_use") {
            $summary.tool_use_count = [int]$summary.tool_use_count + 1
        }

        if ($event.type -eq "error" -and $null -ne $event.error) {
            $error = $event.error
            $data = $error.data
            $responseError = $null
            if ($null -ne $data -and -not [string]::IsNullOrWhiteSpace([string]$data.responseBody)) {
                try {
                    $responseError = (($data.responseBody | ConvertFrom-Json).error)
                } catch {
                    # Keep the provider's top-level error when its response body is not JSON.
                }
            }
            $summary.provider_error = [ordered]@{
                name = [string]$error.name
                message = if ($null -ne $responseError) { [string]$responseError.message } elseif ($null -ne $data) { [string]$data.message } else { "" }
                status_code = if ($null -ne $data) { $data.statusCode } else { $null }
                code = if ($null -ne $responseError) { [string]$responseError.code } else { "" }
                type = if ($null -ne $responseError) { [string]$responseError.type } else { "" }
                retryable = if ($null -ne $data) { $data.isRetryable } else { $null }
            }
        }

        if ($event.type -eq "step_finish" -and $null -ne $event.part) {
            if ($null -ne $event.part.cost) { $summary.cost = $event.part.cost }
            if ($null -ne $event.part.tokens) {
                $tokens = $event.part.tokens
                if ($null -ne $tokens.input) { $summary.input_tokens = $tokens.input }
                if ($null -ne $tokens.output) { $summary.output_tokens = $tokens.output }
                if ($null -ne $tokens.reasoning) { $summary.reasoning_tokens = $tokens.reasoning }
                if ($null -ne $tokens.cache) {
                    if ($null -ne $tokens.cache.read) { $summary.cache_read = $tokens.cache.read }
                    if ($null -ne $tokens.cache.write) { $summary.cache_write = $tokens.cache.write }
                }
            }
        }
    }

    $summary.text = ($texts -join "`n")
    return $summary
}

$metaPath = Join-Path $JobDir "job.json"
$completionPath = Join-Path $JobDir "completion.json"
$watcherLog = Join-Path $JobDir "watcher.log"

try {
    if (-not (Test-Path -LiteralPath $metaPath)) {
        throw "Missing job metadata: $metaPath"
    }

    $meta = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $exitCode = $null
    $waitError = $null
    $alreadyWaited = $false
    $timedOut = $false

    try {
        if ($StartWorker) {
            if ([string]::IsNullOrWhiteSpace($Exe) -or [string]::IsNullOrWhiteSpace($ArgumentListPath)) {
                throw "StartWorker requires -Exe and -ArgumentListPath."
            }
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
            $proc = Start-Process -FilePath $Exe -ArgumentList $argumentLine -WorkingDirectory $WorkingDirectory -RedirectStandardOutput $StdoutPath -RedirectStandardError $StderrPath -WindowStyle Hidden -PassThru
            $WorkerPid = $proc.Id
            Set-JsonProperty -Object $meta -Name "pid" -Value $WorkerPid
            Set-JsonProperty -Object $meta -Name "worker_started_at" -Value $proc.StartTime.ToUniversalTime().ToString("o")
            Write-JsonFile -Path $metaPath -Value $meta
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
        $proc.Refresh()
        try {
            $exitCode = [int]$proc.ExitCode
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
    $cancelledExternally = ($null -ne $latestMeta -and [string]$latestMeta.status -in @("cancel_requested", "cancelled")) -or ($null -ne $latestCompletion -and [string]$latestCompletion.status -eq "cancelled")
    # A worker exit is execution evidence, not a logical-task acceptance.
    $status = "process_exited"
    $semanticFailure = ""
    $mimoSummary = $null
    $combinedOutput = ""
    foreach ($outputPath in @([string]$meta.stdout, [string]$meta.stderr)) {
        if (Test-Path -LiteralPath $outputPath -PathType Leaf) {
            $combinedOutput += [Environment]::NewLine + (Get-Content -LiteralPath $outputPath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue)
        }
    }
    if ([string]$meta.provider -eq "mimo") {
        $mimoSummary = Read-MiMoJsonEventSummary -Path ([string]$meta.stdout)
        if ($null -ne $mimoSummary.provider_error) {
            if ([string]$mimoSummary.provider_error.type -eq "risk_control" -or [string]$mimoSummary.provider_error.code -eq "441") {
                $semanticFailure = "provider_risk_control"
            } else {
                $semanticFailure = "provider_rejected"
            }
        } elseif ([int]$mimoSummary.parse_errors -gt 0 -and [string]::IsNullOrWhiteSpace([string]$mimoSummary.text)) {
            $semanticFailure = "provider_output_unparseable"
        }
    }
    if ([string]::IsNullOrWhiteSpace($semanticFailure) -and $combinedOutput -match "(?is)max(?:imum)?\s+turns?.*(?:exceeded|limit)|turns?\s+exceeded") {
        $semanticFailure = "max_turns_exceeded"
    } elseif ([string]::IsNullOrWhiteSpace($semanticFailure) -and $combinedOutput -match "(?is)tool.+not found.+agent|not found in agent|tool_contract_mismatch") {
        $semanticFailure = "tool_contract_mismatch"
    } elseif ([string]::IsNullOrWhiteSpace($semanticFailure) -and $combinedOutput -match "(?is)permission denied|permission_denied") {
        $semanticFailure = "permission_denied"
    }
    if ($cancelledExternally) {
        $status = "cancelled"
        $semanticFailure = "cancelled_by_operator"
    } elseif ($timedOut) {
        $status = "timed_out"
    } elseif (-not [string]::IsNullOrWhiteSpace($semanticFailure)) {
        $status = "process_exited"
    } elseif ($null -ne $exitCode -and $exitCode -ne 0) {
        $status = "process_exited"
    } elseif ($waitError) {
        $status = "unknown"
    }

    $stdoutHasText = -not [string]::IsNullOrWhiteSpace([string]$meta.stdout) -and (Test-Path -LiteralPath ([string]$meta.stdout) -PathType Leaf) -and ((Get-Item -LiteralPath ([string]$meta.stdout)).Length -gt 0)
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
        observed_at = (Get-Date).ToString("o")
    }

    $now = Get-Date
    Set-JsonProperty -Object $meta -Name "status" -Value $status
    Set-JsonProperty -Object $meta -Name "process_state" -Value $status
    Set-JsonProperty -Object $meta -Name "evidence_state" -Value $evidenceState
    Set-JsonProperty -Object $meta -Name "artifact_state" -Value $artifactState
    Set-JsonProperty -Object $meta -Name "evidence_observation" -Value $evidenceObservation
    $governanceState = if ([string]::IsNullOrWhiteSpace($semanticFailure)) { "awaiting_supervisor" } else { "rejected" }
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
        exited_at = $now.ToString("o")
        stdout = $meta.stdout
        stderr = $meta.stderr
        stderr_nonempty = (-not [string]::IsNullOrWhiteSpace([string]$meta.stderr) -and (Test-Path -LiteralPath ([string]$meta.stderr)) -and ((Get-Item -LiteralPath ([string]$meta.stderr)).Length -gt 0))
        worktree = $meta.execution_repo
        task_kind = $meta.task_kind
        contract_hash = $meta.contract_hash
        task_contract_schema = $meta.task_contract_schema
        generation_id = $meta.generation_id
        runtime_contract_sha256 = $meta.runtime_contract_sha256
        wrapper_protocol = $meta.wrapper_protocol
        provider_tuple = $meta.provider_tuple
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

    if ($null -ne $mimoSummary) {
        $completion.provider_cost = $mimoSummary.cost
        $completion.input_tokens = $mimoSummary.input_tokens
        $completion.output_tokens = $mimoSummary.output_tokens
        $completion.reasoning_tokens = $mimoSummary.reasoning_tokens
        $completion.cache_read = $mimoSummary.cache_read
        $completion.cache_write = $mimoSummary.cache_write
        $completion.tool_use_count = $mimoSummary.tool_use_count
        $completion.parser = "mimo_json_event_summary"
        $completion.parser_errors = $mimoSummary.parse_errors
        $completion.summary_text = $mimoSummary.text
        $completion.provider_error = $mimoSummary.provider_error
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
