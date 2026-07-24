param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Init", "UpsertTask", "RecordJob", "VerifyTask", "RecordSelection", "RecordOutcome", "NextReady", "Summary", "Get", "AppendEvent")]
    [string]$Action,

    [Parameter(Mandatory = $true)]
    [string]$PlanId,

    [string]$PlanRoot = "$env:USERPROFILE\.codex\codex-praetor-plans",
    [string]$Title = "",
    [string]$Repo = "",
    [string]$TaskId = "",
    [string]$TaskTitle = "",
    [ValidateSet("", "read_only_diagnosis", "bounded_code_change", "fixed_test_execution", "failure_recovery", "unclassified")]
    [string]$TaskFamily = "",
    [ValidateSet("", "local_audit", "test_execution", "code_change", "external_research")]
    [string]$TaskKind = "",
    [string]$DependsOn = "",
    [ValidateSet("pending", "running", "awaiting_verification", "completed", "failed", "blocked", "new_problem", "skipped", "retryable", "needs_decision")]
    [string]$Status = "pending",
    [string]$Acceptance = "",
    [string]$JobId = "",
    [string]$JobDir = "",
    [string]$Provider = "",
    [string]$Tier = "",
    [string]$Model = "",
    [string]$Mode = "",
    [string]$CompletionPath = "",
    [string]$Summary = "",
    [string[]]$AllowedPath = @(),
    [string[]]$ForbiddenPath = @(),
    [string[]]$RequiredCheck = @(),
    [string]$BudgetJson = "",
    [string]$FailureInjection = "",
    [string]$Sensitivity = "",
    [string]$TaskMaterialJson = "",
    [ValidateSet("", "accepted", "rejected", "retry", "human_required", "skipped")]
    [string]$VerificationVerdict = "",
    [string]$VerificationSummary = "",
    [string]$NextAction = "",
    [string]$SelectionId = "",
    [string]$SelectionJson = "",
    [string]$OutcomeJson = "",
    [string]$EventType = "",
    [string]$EventMessage = "",
    [switch]$OutputJson
)

$ErrorActionPreference = "Stop"

function Get-SafeName {
    param([string]$Value)
    return ($Value -replace '[^A-Za-z0-9_.-]', '_')
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [object]$Value
    )
    $tmp = "$Path.$([Guid]::NewGuid().ToString('N')).tmp"
    try {
        $Value | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $tmp -Encoding UTF8
        Move-Item -LiteralPath $tmp -Destination $Path -Force
    } finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
}

function ConvertTo-StringArray {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return @()
    }
    return @($Value -split "," | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function New-EmptyPlan {
    param([string]$Id)
    return [ordered]@{
        schema = "codex-praetor-task-ledger/v2"
        plan_id = $Id
        revision = 0
        contexts = @()
        title = ""
        repo = ""
        status = "active"
        created_at = (Get-Date).ToString("o")
        updated_at = (Get-Date).ToString("o")
        tasks = @()
        events = @()
        selections = @()
        outcomes = @()
        release_state = "draft"
    }
}

function Get-PlanPath {
    param([string]$Id)
    $dir = Join-Path $PlanRoot (Get-SafeName $Id)
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    return (Join-Path $dir "plan.json")
}

function Read-Plan {
    param([string]$Id)
    $path = Get-PlanPath -Id $Id
    if (Test-Path -LiteralPath $path) {
        $plan = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([string]$plan.schema -in @("codex-praetor-plan/v1", "codex-praetor-task-ledger/v1")) {
            # Legacy plans retain their historical projection but do not imply accepted outcomes.
            $plan | Add-Member -NotePropertyName schema -NotePropertyValue "codex-praetor-task-ledger/v2" -Force
            if (-not ($plan.PSObject.Properties.Name -contains "revision")) { $plan | Add-Member -NotePropertyName revision -NotePropertyValue 0 -Force }
            if (-not ($plan.PSObject.Properties.Name -contains "contexts")) { $plan | Add-Member -NotePropertyName contexts -NotePropertyValue @() -Force }
            foreach ($task in @($plan.tasks)) {
                if (-not ($task.PSObject.Properties.Name -contains "governance_state")) {
                    $state = if ([string]$task.status -eq "completed" -and [string]$task.verification_verdict -eq "accepted") { "accepted" } elseif ([string]$task.status -eq "completed") { "awaiting_supervisor" } elseif ([string]$task.status -eq "failed") { "rejected" } elseif ([string]$task.status -eq "blocked") { "blocked" } else { "awaiting_supervisor" }
                    $task | Add-Member -NotePropertyName governance_state -NotePropertyValue $state
                }
                if (-not ($task.PSObject.Properties.Name -contains "attempts")) { $task | Add-Member -NotePropertyName attempts -NotePropertyValue @() }
                if (-not ($task.PSObject.Properties.Name -contains "write_set")) { $task | Add-Member -NotePropertyName write_set -NotePropertyValue @() }
                if (-not ($task.PSObject.Properties.Name -contains "task_kind")) { $task | Add-Member -NotePropertyName task_kind -NotePropertyValue "" }
                if (-not ($task.PSObject.Properties.Name -contains "allowed_paths")) { $task | Add-Member -NotePropertyName allowed_paths -NotePropertyValue @() }
                if (-not ($task.PSObject.Properties.Name -contains "forbidden_paths")) { $task | Add-Member -NotePropertyName forbidden_paths -NotePropertyValue @() }
                if (-not ($task.PSObject.Properties.Name -contains "completion_definition")) { $task | Add-Member -NotePropertyName completion_definition -NotePropertyValue ([pscustomobject]@{ required_evidence = @(); required_checks = @(); success_predicate = "" }) }
                if (-not ($task.PSObject.Properties.Name -contains "budget")) { $task | Add-Member -NotePropertyName budget -NotePropertyValue ([pscustomobject]@{ max_attempts = 1; max_turns = 8; max_wall_seconds = 1200 }) }
                if (-not ($task.PSObject.Properties.Name -contains "stop_loss")) { $task | Add-Member -NotePropertyName stop_loss -NotePropertyValue ([pscustomobject]@{ on_tool_denied = "needs_decision"; on_write_set_overlap = "needs_decision"; on_missing_evidence = "needs_decision" }) }
                if (-not ($task.PSObject.Properties.Name -contains "outcome_ids")) { $task | Add-Member -NotePropertyName outcome_ids -NotePropertyValue @() }
                if (-not ($task.PSObject.Properties.Name -contains "progress")) { $task | Add-Member -NotePropertyName progress -NotePropertyValue ([pscustomobject]@{ completed = 0; total = 1; summary = "" }) }
            }
        }
        if (-not ($plan.PSObject.Properties.Name -contains "selections")) { $plan | Add-Member -NotePropertyName selections -NotePropertyValue @() }
        if (-not ($plan.PSObject.Properties.Name -contains "outcomes")) { $plan | Add-Member -NotePropertyName outcomes -NotePropertyValue @() }
        if (-not ($plan.PSObject.Properties.Name -contains "release_state")) { $plan | Add-Member -NotePropertyName release_state -NotePropertyValue "draft" }
        return $plan
    }
    return [pscustomobject](New-EmptyPlan -Id $Id)
}

function Save-Plan {
    param([object]$Plan)
    $Plan.updated_at = (Get-Date).ToString("o")
    $Plan.revision = [int]$Plan.revision + 1
    Write-JsonFile -Path (Get-PlanPath -Id $Plan.plan_id) -Value $Plan
}

function Add-PlanEvent {
    param(
        [object]$Plan,
        [string]$Type,
        [string]$Message,
        [object]$Data = $null
    )
    $events = @($Plan.events)
    $events += [ordered]@{
        event_id = [Guid]::NewGuid().ToString("N")
        at = (Get-Date).ToString("o")
        type = $Type
        message = $Message
        data = $Data
    }
    $Plan.events = $events
}

function Upsert-Task {
    param(
        [object]$Plan,
        [string]$Id,
        [string]$TitleValue,
        [string]$DependsValue,
        [string]$StatusValue,
        [string]$AcceptanceValue,
        [string]$JobIdValue,
        [string]$JobDirValue,
        [string]$ProviderValue,
        [string]$TierValue,
        [string]$ModelValue,
        [string]$ModeValue,
        [string]$CompletionValue,
        [string]$SummaryValue
    )
    if ([string]::IsNullOrWhiteSpace($Id)) {
        throw "TaskId is required for $Action."
    }

    $tasks = @($Plan.tasks)
    $existing = $null
    foreach ($task in $tasks) {
        if ($task.task_id -eq $Id) {
            $existing = $task
            break
        }
    }

    if ($null -eq $existing) {
        $existing = [pscustomobject]@{
            task_id = $Id
            title = ""
            task_family = "unclassified"
            task_kind = ""
            depends_on = @()
            status = "pending"
            acceptance = ""
            job_id = ""
            job_dir = ""
            provider = ""
            tier = ""
            model = ""
            mode = ""
            allowed_paths = @()
            forbidden_paths = @()
            completion = ""
            summary = ""
            verification_verdict = ""
            verification_summary = ""
            verified_at = ""
            next_action = ""
            governance_state = "awaiting_supervisor"
            completion_definition = [pscustomobject]@{ required_evidence = @(); required_checks = @(); success_predicate = "" }
            budget = [pscustomobject]@{ max_attempts = 1; max_turns = 8; max_wall_seconds = 1200 }
            stop_loss = [pscustomobject]@{ on_tool_denied = "needs_decision"; on_write_set_overlap = "needs_decision"; on_missing_evidence = "needs_decision" }
            selection_id = ""
            outcome_ids = @()
            progress = [pscustomobject]@{ completed = 0; total = 1; summary = "" }
            attempts = @()
            write_set = @()
            task_material = $null
            created_at = (Get-Date).ToString("o")
            updated_at = (Get-Date).ToString("o")
        }
        $tasks += $existing
    }

    if (-not [string]::IsNullOrWhiteSpace($TitleValue)) { $existing.title = $TitleValue }
    if (-not [string]::IsNullOrWhiteSpace($DependsValue)) { $existing.depends_on = @(ConvertTo-StringArray -Value $DependsValue) }
    if (-not [string]::IsNullOrWhiteSpace($StatusValue)) { $existing.status = $StatusValue }
    if (-not [string]::IsNullOrWhiteSpace($AcceptanceValue)) { $existing.acceptance = $AcceptanceValue }
    if (-not [string]::IsNullOrWhiteSpace($JobIdValue)) { $existing.job_id = $JobIdValue }
    if (-not [string]::IsNullOrWhiteSpace($JobDirValue)) { $existing.job_dir = $JobDirValue }
    if (-not [string]::IsNullOrWhiteSpace($ProviderValue)) { $existing.provider = $ProviderValue }
    if (-not [string]::IsNullOrWhiteSpace($TierValue)) { $existing.tier = $TierValue }
    if (-not [string]::IsNullOrWhiteSpace($ModelValue)) { $existing.model = $ModelValue }
    if (-not [string]::IsNullOrWhiteSpace($ModeValue)) { $existing.mode = $ModeValue }
    if (-not [string]::IsNullOrWhiteSpace($TaskKind)) { $existing.task_kind = $TaskKind }
    if ($AllowedPath.Count -gt 0) { $existing.allowed_paths = @($AllowedPath) }
    if ($ForbiddenPath.Count -gt 0) { $existing.forbidden_paths = @($ForbiddenPath) }
    if ($RequiredCheck.Count -gt 0) { $existing.completion_definition.required_checks = @($RequiredCheck) }
    if (-not [string]::IsNullOrWhiteSpace($BudgetJson)) { try { $existing.budget = $BudgetJson | ConvertFrom-Json } catch { throw "BudgetJson is not valid JSON." } }
    if (-not [string]::IsNullOrWhiteSpace($FailureInjection)) { Set-DynamicProperty -Target $existing -Name "failure_injection" -Value $FailureInjection }
    if (-not [string]::IsNullOrWhiteSpace($Sensitivity)) { Set-DynamicProperty -Target $existing -Name "sensitivity" -Value $Sensitivity }
    if (-not [string]::IsNullOrWhiteSpace($TaskMaterialJson)) { try { Set-DynamicProperty -Target $existing -Name "task_material" -Value ($TaskMaterialJson | ConvertFrom-Json) } catch { throw "TaskMaterialJson is not valid JSON." } }
    if (-not [string]::IsNullOrWhiteSpace($CompletionValue)) { $existing.completion = $CompletionValue }
    if (-not [string]::IsNullOrWhiteSpace($SummaryValue)) { $existing.summary = $SummaryValue }
    $existing.updated_at = (Get-Date).ToString("o")

    $Plan.tasks = @($tasks | Sort-Object task_id)
}

function Set-DynamicProperty {
    param(
        [object]$Target,
        [string]$Name,
        [object]$Value
    )
    if ($Target.PSObject.Properties.Name -contains $Name) {
        $Target.$Name = $Value
    } else {
        $Target | Add-Member -MemberType NoteProperty -Name $Name -Value $Value
    }
}

function Set-TaskVerification {
    param(
        [object]$Plan,
        [string]$Id,
        [string]$Verdict,
        [string]$SummaryValue,
        [string]$NextActionValue
    )
    if ([string]::IsNullOrWhiteSpace($Id)) {
        throw "TaskId is required for VerifyTask."
    }
    if ([string]::IsNullOrWhiteSpace($Verdict)) {
        throw "VerificationVerdict is required for VerifyTask."
    }

    $target = $null
    foreach ($task in @($Plan.tasks)) {
        if ($task.task_id -eq $Id) {
            $target = $task
            break
        }
    }
    if ($null -eq $target) {
        throw "Task not found for verification: $Id"
    }

    Set-DynamicProperty -Target $target -Name "verification_verdict" -Value $Verdict
    Set-DynamicProperty -Target $target -Name "verification_summary" -Value $SummaryValue
    Set-DynamicProperty -Target $target -Name "verified_at" -Value (Get-Date).ToString("o")
    Set-DynamicProperty -Target $target -Name "next_action" -Value $NextActionValue
    Set-DynamicProperty -Target $target -Name "summary" -Value $SummaryValue
    Set-DynamicProperty -Target $target -Name "updated_at" -Value (Get-Date).ToString("o")
    $attempts = @($target.attempts)
    if ($attempts.Count -gt 0) {
        Set-DynamicProperty -Target $attempts[$attempts.Count - 1] -Name "supervisor_verdict" -Value $Verdict
    }

    if ($Verdict -eq "accepted") {
        Set-DynamicProperty -Target $target -Name "status" -Value "completed"
        Set-DynamicProperty -Target $target -Name "governance_state" -Value "accepted"
    } elseif ($Verdict -eq "retry") {
        Set-DynamicProperty -Target $target -Name "status" -Value "new_problem"
        Set-DynamicProperty -Target $target -Name "governance_state" -Value "retryable"
    } elseif ($Verdict -eq "human_required") {
        Set-DynamicProperty -Target $target -Name "status" -Value "blocked"
        Set-DynamicProperty -Target $target -Name "governance_state" -Value "needs_decision"
    } elseif ($Verdict -eq "skipped") {
        Set-DynamicProperty -Target $target -Name "status" -Value "skipped"
        Set-DynamicProperty -Target $target -Name "governance_state" -Value "rejected"
    } else {
        Set-DynamicProperty -Target $target -Name "status" -Value "failed"
        Set-DynamicProperty -Target $target -Name "governance_state" -Value "rejected"
    }
}

function Get-ReadyTasks {
    param([object]$Plan)
    $done = @{}
    foreach ($task in @($Plan.tasks)) {
        if ([string]$task.governance_state -eq "accepted") {
            $done[$task.task_id] = $true
        }
    }

    $ready = @()
    foreach ($task in @($Plan.tasks)) {
        if ($task.status -ne "pending") {
            continue
        }
        $deps = @($task.depends_on)
        $ok = $true
        foreach ($dep in $deps) {
            if (-not $done.ContainsKey($dep)) {
                $ok = $false
                break
            }
        }
        if ($ok) {
            $ready += $task
        }
    }
    return $ready
}

$plan = Read-Plan -Id $PlanId

if ($Action -eq "Init") {
    if (-not [string]::IsNullOrWhiteSpace($Title)) { $plan.title = $Title }
    if (-not [string]::IsNullOrWhiteSpace($Repo)) { $plan.repo = $Repo }
    Add-PlanEvent -Plan $plan -Type "plan_initialized" -Message "Plan initialized or refreshed."
    Save-Plan -Plan $plan
} elseif ($Action -eq "UpsertTask") {
    Upsert-Task -Plan $plan -Id $TaskId -TitleValue $TaskTitle -DependsValue $DependsOn -StatusValue $Status -AcceptanceValue $Acceptance -JobIdValue $JobId -JobDirValue $JobDir -ProviderValue $Provider -TierValue $Tier -ModelValue $Model -ModeValue $Mode -CompletionValue $CompletionPath -SummaryValue $Summary
    if (-not [string]::IsNullOrWhiteSpace($TaskFamily)) {
        $target = @($plan.tasks | Where-Object { $_.task_id -eq $TaskId } | Select-Object -First 1)
        if ($target.Count -eq 1) { Set-DynamicProperty -Target $target[0] -Name "task_family" -Value $TaskFamily }
    }
    Add-PlanEvent -Plan $plan -Type "task_upserted" -Message "Task $TaskId is $Status." -Data @{ task_id = $TaskId; status = $Status; job_id = $JobId }
    Save-Plan -Plan $plan
} elseif ($Action -eq "RecordJob") {
    if ([string]::IsNullOrWhiteSpace($JobDir)) {
        throw "JobDir is required for RecordJob."
    }
    $completionFile = $CompletionPath
    if ([string]::IsNullOrWhiteSpace($completionFile)) {
        $completionFile = Join-Path $JobDir "completion.json"
    }
    if (-not (Test-Path -LiteralPath $completionFile)) {
        throw "Completion file not found: $completionFile"
    }
    $completion = Get-Content -LiteralPath $completionFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $recordTaskId = if (-not [string]::IsNullOrWhiteSpace($TaskId)) { $TaskId } else { [string]$completion.task_id }
    $recordStatus = if ($completion.status -eq "process_exited" -and [string]::IsNullOrWhiteSpace([string]$completion.failure_class) -and $null -ne $completion.exit_code -and [int]$completion.exit_code -eq 0) { "awaiting_verification" } elseif ($completion.status -eq "cancelled") { "blocked" } else { "failed" }
    $summaryText = "process_state=$($completion.process_state); failure_class=$($completion.failure_class); exit_code=$($completion.exit_code)"
    Upsert-Task -Plan $plan -Id $recordTaskId -TitleValue "" -DependsValue "" -StatusValue $recordStatus -AcceptanceValue ([string]$completion.acceptance) -JobIdValue ([string]$completion.job_id) -JobDirValue $JobDir -ProviderValue ([string]$completion.provider) -TierValue ([string]$completion.tier) -ModelValue ([string]$completion.model) -ModeValue ([string]$completion.mode) -CompletionValue $completionFile -SummaryValue $summaryText
    $recordTask = @($plan.tasks | Where-Object { $_.task_id -eq $recordTaskId } | Select-Object -First 1)
    if ($recordTask.Count -eq 1) {
        $attempt = [ordered]@{ attempt_id = [string]$completion.job_id; base_commit = [string]$completion.base_commit; contract_sha256 = [string]$completion.contract_sha256; task_family = [string]$recordTask[0].task_family; provider_tuple = $completion.provider_tuple; provider = [string]$completion.provider; model = [string]$completion.model; task_kind = [string]$completion.task_kind; write_set = @($completion.write_set); execution_state = [string]$completion.process_state; evidence_state = [string]$completion.evidence_state; artifacts = @(); completion = $completionFile; exit_code = $completion.exit_code; failure_class = [string]$completion.failure_class; supervisor_verdict = if ($recordStatus -eq "awaiting_verification") { "" } elseif ($recordStatus -eq "blocked") { "blocked" } else { "rejected" }; created_at = (Get-Date).ToString("o"); finished_at = (Get-Date).ToString("o") }
        $recordTask[0].attempts = @($recordTask[0].attempts) + $attempt
        $recordTask[0].governance_state = if ($recordStatus -eq "awaiting_verification") { "awaiting_supervisor" } elseif ($recordStatus -eq "blocked") { "blocked" } else { "rejected" }
    }
    Add-PlanEvent -Plan $plan -Type "job_recorded" -Message "Job $($completion.job_id) recorded for task $recordTaskId as $recordStatus." -Data @{ task_id = $recordTaskId; job_id = $completion.job_id; status = $completion.status; exit_code = $completion.exit_code }
    Save-Plan -Plan $plan
} elseif ($Action -eq "VerifyTask") {
    Set-TaskVerification -Plan $plan -Id $TaskId -Verdict $VerificationVerdict -SummaryValue $VerificationSummary -NextActionValue $NextAction
    Add-PlanEvent -Plan $plan -Type "task_verified" -Message "Task $TaskId verification verdict: $VerificationVerdict." -Data @{ task_id = $TaskId; verdict = $VerificationVerdict; next_action = $NextAction }
    Save-Plan -Plan $plan
} elseif ($Action -eq "RecordSelection") {
    if ([string]::IsNullOrWhiteSpace($SelectionJson)) { throw "SelectionJson is required for RecordSelection." }
    $selection = $SelectionJson | ConvertFrom-Json
    if ([string]::IsNullOrWhiteSpace([string]$selection.selection_id)) { throw "selection_id is required." }
    $plan.selections = @($plan.selections | Where-Object { $_.selection_id -ne $selection.selection_id }) + $selection
    if (-not [string]::IsNullOrWhiteSpace($TaskId)) {
        $target = @($plan.tasks | Where-Object { $_.task_id -eq $TaskId } | Select-Object -First 1)
        if ($target.Count -eq 1) { Set-DynamicProperty -Target $target[0] -Name "selection_id" -Value ([string]$selection.selection_id) }
    }
    Add-PlanEvent -Plan $plan -Type "selection_recorded" -Message "Selection $($selection.selection_id) recorded." -Data @{ task_id = $TaskId; selection_id = $selection.selection_id }
    Save-Plan -Plan $plan
} elseif ($Action -eq "RecordOutcome") {
    if ([string]::IsNullOrWhiteSpace($OutcomeJson)) { throw "OutcomeJson is required for RecordOutcome." }
    $outcome = $OutcomeJson | ConvertFrom-Json
    if ([string]::IsNullOrWhiteSpace([string]$outcome.outcome_id)) { throw "outcome_id is required." }
    $plan.outcomes = @($plan.outcomes | Where-Object { $_.outcome_id -ne $outcome.outcome_id }) + $outcome
    if (-not [string]::IsNullOrWhiteSpace($TaskId)) {
        $target = @($plan.tasks | Where-Object { $_.task_id -eq $TaskId } | Select-Object -First 1)
        if ($target.Count -eq 1) {
            Set-DynamicProperty -Target $target[0] -Name "outcome_ids" -Value (@($target[0].outcome_ids) + [string]$outcome.outcome_id)
            Set-DynamicProperty -Target $target[0] -Name "progress" -Value ([pscustomobject]@{ completed = if ([string]$outcome.verdict -eq "accepted") { 1 } else { 0 }; total = 1; last_outcome_id = [string]$outcome.outcome_id; summary = [string]$outcome.summary })
        }
    }
    Add-PlanEvent -Plan $plan -Type "outcome_recorded" -Message "Outcome $($outcome.outcome_id) recorded." -Data @{ task_id = $TaskId; outcome_id = $outcome.outcome_id; verdict = $outcome.verdict }
    Save-Plan -Plan $plan
} elseif ($Action -eq "AppendEvent") {
    Add-PlanEvent -Plan $plan -Type $EventType -Message $EventMessage
    Save-Plan -Plan $plan
} elseif ($Action -eq "NextReady") {
    $ready = @(Get-ReadyTasks -Plan $plan)
    if ($OutputJson) {
        $ready | ConvertTo-Json -Depth 20
    } else {
        foreach ($task in $ready) {
            Write-Output "$($task.task_id) $($task.title)"
        }
    }
    return
} elseif ($Action -eq "Get") {
    if ($OutputJson) {
        $plan | ConvertTo-Json -Depth 30
    } else {
        Write-Output "plan_id=$($plan.plan_id)"
        Write-Output "title=$($plan.title)"
        Write-Output "repo=$($plan.repo)"
        foreach ($task in @($plan.tasks)) {
            $deps = (@($task.depends_on) -join ",")
            Write-Output "$($task.task_id) status=$($task.status) depends_on=$deps job=$($task.job_id)"
        }
    }
    return
} elseif ($Action -eq "Summary") {
    $summaryPayload = [pscustomobject]@{
        plan_id = [string]$plan.plan_id; revision = [int]$plan.revision; release_state = [string]$plan.release_state
        tasks = @($plan.tasks | ForEach-Object { [pscustomobject]@{ task_id = $_.task_id; status = $_.status; governance_state = $_.governance_state; progress = $_.progress; next_action = $_.next_action } })
        counts = [pscustomobject]@{ total = @($plan.tasks).Count; accepted = @($plan.tasks | Where-Object { $_.governance_state -eq "accepted" }).Count; needs_decision = @($plan.tasks | Where-Object { $_.governance_state -eq "needs_decision" }).Count; outcomes = @($plan.outcomes).Count }
    }
    if ($OutputJson) { $summaryPayload | ConvertTo-Json -Depth 20 } else { Write-Output "plan=$($summaryPayload.plan_id) revision=$($summaryPayload.revision) release_state=$($summaryPayload.release_state) tasks=$($summaryPayload.counts.total) accepted=$($summaryPayload.counts.accepted) needs_decision=$($summaryPayload.counts.needs_decision) outcomes=$($summaryPayload.counts.outcomes)" }
    return
}

if ($OutputJson) {
    $plan | ConvertTo-Json -Depth 30
} else {
    Write-Output (Get-PlanPath -Id $PlanId)
}
