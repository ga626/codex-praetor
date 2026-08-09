param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Init", "UpsertTask", "SetEvidenceContext", "SetDecisionReceipt", "SetDispatchState", "PrepareProviderFallback", "RecordIntervention", "RecordJob", "VerifyTask", "RecordSelection", "RecordOutcome", "NextReady", "Summary", "Get", "AppendEvent")]
    [string]$Action,

    [Parameter(Mandatory = $true)]
    [string]$PlanId,

    [string]$PlanRoot = "$env:USERPROFILE\.codex\codex-praetor-plans",
    [string]$CapabilityEvidenceRoot = "$env:USERPROFILE\.codex\codex-praetor-capability-evidence",
    [string]$Title = "",
    [string]$Repo = "",
    [string]$TaskId = "",
    [string]$TaskTitle = "",
    [ValidateSet("", "read_only_diagnosis", "bounded_code_change", "fixed_test_execution", "failure_recovery", "unclassified")]
    [string]$TaskFamily = "",
    [ValidateSet("", "local_audit", "test_execution", "code_change", "external_research")]
    [string]$TaskKind = "",
    [string]$DependsOn = "",
    [string]$DependsOnJson = "",
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
    [string]$AllowedPathsJson = "",
    [string]$ForbiddenPathsJson = "",
    [string]$RequiredChecksJson = "",
    [string]$BudgetJson = "",
    [string]$FailureInjection = "",
    [string]$Sensitivity = "",
    [string]$TaskMaterialJson = "",
    [string]$BaseCommit = "",
    [string[]]$ImmutablePath = @(),
    [string]$ImmutablePathsJson = "",
    [string]$EvidenceContextJson = "",
    [string]$EvidenceContextPath = "",
    [string]$DecisionReceiptJson = "",
    [ValidateSet("", "preflight_ready", "bootstrap_eligible", "bootstrap_started", "worker_started", "dispatch_blocked", "awaiting_codex_verification")]
    [string]$DispatchState = "",
    [switch]$ValidationOnly,
    [string]$ValidationReason = "",
    [string]$InterventionKind = "",
    [string]$InterventionSummary = "",
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
$hasImmutablePathsJson = -not [string]::IsNullOrWhiteSpace($ImmutablePathsJson)
if ($hasImmutablePathsJson) { try { [string[]]$ImmutablePath = ($ImmutablePathsJson | ConvertFrom-Json) } catch { throw "ImmutablePathsJson is not valid JSON." } }
$hasExplicitImmutablePaths = $hasImmutablePathsJson -or $ImmutablePath.Count -gt 0
if (-not [string]::IsNullOrWhiteSpace($AllowedPathsJson)) { try { [string[]]$AllowedPath = ($AllowedPathsJson | ConvertFrom-Json) } catch { throw "AllowedPathsJson is not valid JSON." } }
if (-not [string]::IsNullOrWhiteSpace($ForbiddenPathsJson)) { try { [string[]]$ForbiddenPath = ($ForbiddenPathsJson | ConvertFrom-Json) } catch { throw "ForbiddenPathsJson is not valid JSON." } }
if (-not [string]::IsNullOrWhiteSpace($RequiredChecksJson)) { try { [string[]]$RequiredCheck = ($RequiredChecksJson | ConvertFrom-Json) } catch { throw "RequiredChecksJson is not valid JSON." } }
$hasDependsOnJson = -not [string]::IsNullOrWhiteSpace($DependsOnJson)
if ($hasDependsOnJson) { try { [string[]]$DependsOnValues = ($DependsOnJson | ConvertFrom-Json) } catch { throw "DependsOnJson is not valid JSON." } }

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
    $backup = "$Path.$([Guid]::NewGuid().ToString('N')).bak"
    try {
        $Value | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $tmp -Encoding UTF8
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            [IO.File]::Replace($tmp, $Path, $backup, $true)
        } else {
            [IO.File]::Move($tmp, $Path)
        }
    } finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $backup) { Remove-Item -LiteralPath $backup -Force -ErrorAction SilentlyContinue }
    }
}

function Get-PlanMutexName {
    param([Parameter(Mandatory = $true)][string]$Id)
    $identity = ([IO.Path]::GetFullPath((Get-PlanPath -Id $Id))).ToLowerInvariant()
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($identity))
        return 'Local\CodexPraetorPlan_' + (($hash | ForEach-Object { $_.ToString('x2') }) -join '')
    } finally {
        $sha.Dispose()
    }
}

function Get-ChangedWorktreePaths {
    param([Parameter(Mandatory = $true)][string]$WorktreePath, [Parameter(Mandatory = $true)][string]$BaseCommitValue)
    $tracked = @((& git -C $WorktreePath diff --name-only $BaseCommitValue 2>$null | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }))
    if ($LASTEXITCODE -ne 0) { throw "Could not inspect Git diff against base commit: $BaseCommitValue" }
    $untracked = @((& git -C $WorktreePath ls-files --others --exclude-standard 2>$null | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }))
    if ($LASTEXITCODE -ne 0) { throw "Could not inspect untracked paths in worker worktree." }
    return @($tracked + $untracked | ForEach-Object { ([string]$_).Replace('\\', '/') } | Sort-Object -Unique)
}
function Test-PathMatchesContractPatterns {
    param([Parameter(Mandatory = $true)][string]$PathValue, [string[]]$Patterns)
    $normal = $PathValue.Replace('\\', '/')
    foreach ($pattern in @($Patterns)) {
        $normalizedPattern = ([string]$pattern).Replace('\\', '/').TrimEnd('/')
        if ([string]::IsNullOrWhiteSpace($normalizedPattern)) { continue }
        if ($normalizedPattern -notmatch '[*?]') {
            if ($normal -eq $normalizedPattern -or $normal.StartsWith($normalizedPattern + '/', [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
        } elseif ($normal -like $normalizedPattern) {
            return $true
        }
    }
    return $false
}
function Assert-RealWorktreeAcceptance {
    param([Parameter(Mandatory = $true)][object]$Contract, [Parameter(Mandatory = $true)][string]$WorktreePath)
    if ([string]$Contract.base_commit -notmatch '^[0-9a-f]{40}$') { throw "Real worktree contract lacks a resolved base_commit." }
    if (@($Contract.allowed_paths).Count -eq 0 -or @($Contract.immutable_manifest).Count -eq 0) { throw "Real worktree contract lacks allowlist or immutable manifest." }
    $changed = @(Get-ChangedWorktreePaths -WorktreePath $WorktreePath -BaseCommitValue ([string]$Contract.base_commit))
    if ($changed.Count -eq 0) { throw "Accepted real code_change requires a non-empty Git diff." }
    $outside = @($changed | Where-Object { -not (Test-PathMatchesContractPatterns -PathValue $_ -Patterns @($Contract.allowed_paths)) })
    if ($outside.Count -gt 0) { throw "Accepted real code_change changed paths outside the allowlist: $($outside -join ', ')" }
    $forbidden = @($changed | Where-Object { Test-PathMatchesContractPatterns -PathValue $_ -Patterns @($Contract.forbidden_paths) })
    if ($forbidden.Count -gt 0) { throw "Accepted real code_change changed forbidden paths: $($forbidden -join ', ')" }
    foreach ($entry in @($Contract.immutable_manifest)) {
        $actual = (& git -C $WorktreePath rev-parse --verify "HEAD:$([string]$entry.path)" 2>$null | Out-String).Trim()
        if ($LASTEXITCODE -ne 0 -or $actual.ToLowerInvariant() -ne [string]$entry.git_blob_sha1) { throw "Accepted real code_change changed immutable path: $([string]$entry.path)" }
    }
    return $changed
}

function Assert-BaseCommitEvidence {
    param(
        [Parameter(Mandatory = $true)][object]$Task,
        [Parameter(Mandatory = $true)][object]$Completion,
        [Parameter(Mandatory = $true)][string]$JobDir
    )

    $declared = ([string]$Task.base_commit).Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($declared)) { return }
    if ($declared -notmatch '^[0-9a-f]{40}$') { throw "Task declares an unresolved base_commit: $declared" }

    $jobPath = Join-Path $JobDir "job.json"
    $contractPath = Join-Path $JobDir "task-contract.json"
    if (-not (Test-Path -LiteralPath $jobPath -PathType Leaf)) { throw "Base commit integrity failure: job metadata is missing: $jobPath" }
    if (-not (Test-Path -LiteralPath $contractPath -PathType Leaf)) { throw "Base commit integrity failure: task contract is missing: $contractPath" }
    $job = Get-Content -LiteralPath $jobPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $contract = Get-Content -LiteralPath $contractPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $reported = @(
        [string]$contract.base_commit,
        [string]$contract.worktree_head,
        [string]$job.base_commit,
        [string]$job.worktree_head,
        [string]$Completion.base_commit,
        [string]$Completion.worktree_head
    ) | ForEach-Object { $_.Trim().ToLowerInvariant() }
    if (@($reported | Where-Object { $_ -ne $declared }).Count -gt 0) {
        throw "Base commit integrity failure: task, contract, job, or completion does not match declared base_commit $declared."
    }

    $worktree = [string]$Completion.worktree
    if ([string]::IsNullOrWhiteSpace($worktree) -or -not (Test-Path -LiteralPath $worktree -PathType Container)) {
        throw "Base commit integrity failure: completion worktree is unavailable for verification."
    }
    $actual = (& git -C $worktree rev-parse --verify "HEAD^{commit}" 2>$null | Out-String).Trim().ToLowerInvariant()
    if ($LASTEXITCODE -ne 0 -or $actual -ne $declared) {
        throw "Base commit integrity failure: actual worktree HEAD $actual does not match declared base_commit $declared."
    }
}

function Get-RequiredEvidenceContext {
    param([object]$Task)
    $context = $Task.evidence_context
    if ($null -eq $context) { return $null }
    $required = @("source_category", "source_ref", "source_commit", "input_sha256", "connection_mode", "verifier_id", "verifier_version", "verifier_sha256")
    if (@($required | Where-Object { [string]::IsNullOrWhiteSpace([string]$context.$_) }).Count -gt 0) { return $null }
    return $context
}

function Get-ElapsedMilliseconds {
    param([string]$StartedAt, [string]$FinishedAt)
    $start = [DateTime]::MinValue
    $finish = [DateTime]::MinValue
    if (-not [DateTime]::TryParse($StartedAt, [ref]$start) -or -not [DateTime]::TryParse($FinishedAt, [ref]$finish)) { return $null }
    $elapsed = ($finish.ToUniversalTime() - $start.ToUniversalTime()).TotalMilliseconds
    if ($elapsed -lt 0) { return $null }
    return [Math]::Round($elapsed, 0)
}

function Get-CompletionContractSha256 {
    param([object]$Completion)
    $canonical = [string]$Completion.contract_sha256
    if (-not [string]::IsNullOrWhiteSpace($canonical)) { return $canonical }
    return [string]$Completion.contract_hash
}

function Write-CapabilityEvidence {
    param([object]$Task, [object]$Job, [object]$Completion)
    $family = [string]$Task.task_family
    $tuple = $Completion.provider_tuple
    $requiredTupleFields = @("provider", "cli_path", "cli_hash", "model", "permission_profile", "task_kind", "generation_id", "runtime_contract_sha256", "task_contract_schema")
    $hasCompleteTuple = $null -ne $tuple -and @($requiredTupleFields | Where-Object { [string]::IsNullOrWhiteSpace([string]$tuple.$_) }).Count -eq 0
    $evidenceContext = Get-RequiredEvidenceContext -Task $Task
    $isRealSource = $null -ne $evidenceContext -and [string]$evidenceContext.source_category -in @("real_historical_issue", "real_user_request")
    if ([string]::IsNullOrWhiteSpace($family) -or $family -eq "unclassified" -or -not $hasCompleteTuple -or -not $isRealSource) { return }
    New-Item -ItemType Directory -Path $CapabilityEvidenceRoot -Force | Out-Null
    $jobPath = Join-Path ([string]$Task.job_dir) "job.json"
    $completionPath = [string]$Task.completion
    if ([string]::IsNullOrWhiteSpace($completionPath)) { $completionPath = Join-Path ([string]$Task.job_dir) "completion.json" }
    $attempt = @($Task.attempts | Where-Object { [string]$_.attempt_id -eq [string]$Completion.job_id } | Select-Object -Last 1)
    $receipt = [ordered]@{ schema = "codex-praetor-capability-evidence/v1"; evidence_id = [string]$Completion.job_id; accepted_at = (Get-Date).ToUniversalTime().ToString("o"); task_family = $family; provider_tuple = $tuple; task_kind = [string]$Task.task_kind; supervisor_verdict = "accepted"; contract_sha256 = Get-CompletionContractSha256 -Completion $Completion; job_sha256 = (Get-FileHash -LiteralPath $jobPath -Algorithm SHA256).Hash.ToLowerInvariant(); completion_sha256 = (Get-FileHash -LiteralPath $completionPath -Algorithm SHA256).Hash.ToLowerInvariant(); required_checks = @($Task.completion_definition.required_checks); evidence_context = $evidenceContext; timeline = if ($attempt.Count -eq 1) { $attempt[0].timeline } else { $null }; human_intervention_count = [int]$Task.human_intervention_count }
    Write-JsonFile -Path (Join-Path $CapabilityEvidenceRoot ((Get-SafeName ([string]$Completion.job_id)) + ".json")) -Value $receipt
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
                if (-not ($task.PSObject.Properties.Name -contains "budget")) { $task | Add-Member -NotePropertyName budget -NotePropertyValue ([pscustomobject]@{ max_attempts = 1; max_stall_seconds = 300; max_wall_seconds = 1200 }) }
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
        [object]$Data = $null,
        [string]$Actor = "controller"
    )
    $events = @($Plan.events)
    $events += [ordered]@{
        event_id = [Guid]::NewGuid().ToString("N")
        at = (Get-Date).ToString("o")
        type = $Type
        actor = $Actor
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
            budget = [pscustomobject]@{ max_attempts = 1; max_stall_seconds = 300; max_wall_seconds = 1200 }
            stop_loss = [pscustomobject]@{ on_tool_denied = "needs_decision"; on_write_set_overlap = "needs_decision"; on_missing_evidence = "needs_decision" }
            selection_id = ""
            outcome_ids = @()
            progress = [pscustomobject]@{ completed = 0; total = 1; summary = "" }
            attempts = @()
            write_set = @()
            task_material = $null
            base_commit = ""
            immutable_paths = @()
            evidence_context = $null
            validation_only = $false
            validation_reason = ""
            human_intervention_count = 0
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
    if (-not [string]::IsNullOrWhiteSpace($BaseCommit)) { Set-DynamicProperty -Target $existing -Name "base_commit" -Value $BaseCommit }
    # An explicit [] is a contract update: clear a previous code-change
    # baseline when the same durable task is corrected to a readonly task.
    # Checking Count alone preserves stale paths and makes the next dispatch
    # fail before a worker can start.
    if ($hasExplicitImmutablePaths) { Set-DynamicProperty -Target $existing -Name "immutable_paths" -Value @($ImmutablePath) }
    if ($ValidationOnly) { Set-DynamicProperty -Target $existing -Name "validation_only" -Value $true; Set-DynamicProperty -Target $existing -Name "validation_reason" -Value $ValidationReason }
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

    if ($Verdict -eq "accepted") {
        $jobDir = [string]$target.job_dir
        if ([string]::IsNullOrWhiteSpace($jobDir) -or -not (Test-Path -LiteralPath $jobDir -PathType Container)) {
            throw "Accepted verification requires a recorded job directory."
        }
        $jobPath = Join-Path $jobDir "job.json"
        $completionPath = [string]$target.completion
        if ([string]::IsNullOrWhiteSpace($completionPath)) { $completionPath = Join-Path $jobDir "completion.json" }
        if (-not (Test-Path -LiteralPath $jobPath -PathType Leaf) -or -not (Test-Path -LiteralPath $completionPath -PathType Leaf)) {
            throw "Accepted verification requires job.json and completion.json."
        }
        $job = Get-Content -LiteralPath $jobPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $completion = Get-Content -LiteralPath $completionPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([string]$completion.status -ne "process_exited" -or [int]$completion.exit_code -ne 0 -or -not [string]::IsNullOrWhiteSpace([string]$completion.failure_class)) {
            throw "Accepted verification requires a clean process_exited/0 completion."
        }
        if ([string]$target.mode -eq "readonly") {
            $executionRepo = [string]$job.execution_repo
            if ([string]::IsNullOrWhiteSpace($executionRepo) -or -not (Test-Path -LiteralPath $executionRepo -PathType Container)) {
                throw "Readonly accepted verification requires the recorded execution worktree."
            }
            $status = (& git -C $executionRepo status --short 2>$null | Out-String).Trim()
            if ($LASTEXITCODE -ne 0) { throw "Could not inspect readonly worker worktree status." }
            if (-not [string]::IsNullOrWhiteSpace($status)) {
                throw "Readonly worker changed its execution worktree; it cannot be accepted."
            }
        }
        if ([string]$target.task_kind -eq "code_change") {
            $contractPath = [string]$job.task_contract
            if ([string]::IsNullOrWhiteSpace($contractPath) -or -not (Test-Path -LiteralPath $contractPath -PathType Leaf)) { throw "Accepted code_change verification requires its task contract." }
            $contract = Get-Content -LiteralPath $contractPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if (-not [bool]$contract.real_worktree) { throw "Copied-material code_change cannot be accepted as real source editing." }
            $executionRepo = [string]$job.execution_repo
            if ([string]::IsNullOrWhiteSpace($executionRepo) -or -not (Test-Path -LiteralPath $executionRepo -PathType Container)) { throw "Accepted real code_change requires its recorded execution worktree." }
            $null = Assert-RealWorktreeAcceptance -Contract $contract -WorktreePath $executionRepo
            foreach ($evidenceName in @("stdout", "stderr")) {
                $evidencePath = [string]$job.$evidenceName
                if ([string]::IsNullOrWhiteSpace($evidencePath) -or -not (Test-Path -LiteralPath $evidencePath -PathType Leaf)) { throw "Accepted real code_change requires recorded $evidenceName evidence." }
            }
        }
        if ([string]$target.task_kind -eq "test_execution") {
            $contractPath = [string]$job.task_contract
            if ([string]::IsNullOrWhiteSpace($contractPath) -or -not (Test-Path -LiteralPath $contractPath -PathType Leaf)) {
                throw "Accepted test_execution verification requires its task contract."
            }
            $contract = Get-Content -LiteralPath $contractPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if (@($contract.required_checks | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count -eq 0) {
                throw "Accepted test_execution verification requires declared required_checks."
            }
            $stdoutPath = [string]$job.stdout
            if ([string]::IsNullOrWhiteSpace($stdoutPath)) { $stdoutPath = Join-Path $jobDir "stdout.log" }
            if (-not (Test-Path -LiteralPath $stdoutPath -PathType Leaf)) { throw "Accepted test_execution verification requires worker stdout." }
            $stdout = Get-Content -LiteralPath $stdoutPath -Raw -Encoding UTF8
            if ($stdout -notmatch [regex]::Escape("CODEX_PRAETOR_REQUIRED_CHECKS_OK")) {
                throw "Accepted test_execution verification requires the worker success marker."
            }
        }
    }

    Set-DynamicProperty -Target $target -Name "verification_verdict" -Value $Verdict
    Set-DynamicProperty -Target $target -Name "verification_summary" -Value $SummaryValue
    Set-DynamicProperty -Target $target -Name "verified_at" -Value (Get-Date).ToString("o")
    Set-DynamicProperty -Target $target -Name "next_action" -Value $NextActionValue
    Set-DynamicProperty -Target $target -Name "summary" -Value $SummaryValue
    Set-DynamicProperty -Target $target -Name "updated_at" -Value (Get-Date).ToString("o")
    $attempts = @($target.attempts)
    if ($attempts.Count -gt 0) {
        $verifiedAttempt = @($attempts | Where-Object { [string]$_.attempt_id -eq [string]$target.job_id })
        if ($verifiedAttempt.Count -ne 1) {
            throw "Supervisor verification requires exactly one immutable attempt for job $([string]$target.job_id)."
        }
        Set-DynamicProperty -Target $verifiedAttempt[0] -Name "supervisor_verdict" -Value $Verdict
        Set-DynamicProperty -Target $verifiedAttempt[0] -Name "accepted_at" -Value (Get-Date).ToUniversalTime().ToString("o")
        $timeline = $verifiedAttempt[0].timeline
        if ($null -ne $timeline) {
            Set-DynamicProperty -Target $timeline -Name "verified_at" -Value (Get-Date).ToUniversalTime().ToString("o")
            $elapsed = Get-ElapsedMilliseconds -StartedAt ([string]$timeline.submitted_at) -FinishedAt ([string]$timeline.verified_at)
            if ($null -ne $elapsed) { Set-DynamicProperty -Target $timeline -Name "end_to_end_ms" -Value $elapsed }
        }
    }

    if ($Verdict -eq "accepted") {
        Set-DynamicProperty -Target $target -Name "status" -Value "completed"
        Set-DynamicProperty -Target $target -Name "governance_state" -Value "accepted"
        Write-CapabilityEvidence -Task $target -Job $job -Completion $completion
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

function Set-TaskEvidenceContext {
    param([object]$Plan, [string]$Id, [string]$ContextJson)
    if ([string]::IsNullOrWhiteSpace($Id) -or [string]::IsNullOrWhiteSpace($ContextJson)) { throw "TaskId and EvidenceContextJson are required." }
    try { $context = $ContextJson | ConvertFrom-Json } catch { throw "EvidenceContextJson is not valid JSON." }
    $required = @("source_category", "source_ref", "source_commit", "input_sha256", "connection_mode", "verifier_id", "verifier_version", "verifier_sha256")
    if (@($required | Where-Object { [string]::IsNullOrWhiteSpace([string]$context.$_) }).Count -gt 0) { throw "EvidenceContextJson lacks a required field." }
    if ([string]$context.source_category -notin @("contract_regression", "real_historical_issue", "real_user_request", "untrusted_or_unknown")) { throw "EvidenceContextJson source_category is not recognized." }
    if ([string]$context.connection_mode -notin @("supervised_cli_text", "supervised_cli_json", "supervised_cli_stream_json", "qoder_acp", "qoder_sdk", "qoder_agent_sdk", "codebuddy_acp", "codebuddy_daemon")) { throw "EvidenceContextJson connection_mode is not recognized." }
    $target = @($Plan.tasks | Where-Object { $_.task_id -eq $Id } | Select-Object -First 1)
    if ($target.Count -ne 1) { throw "Task not found for evidence context: $Id" }
    Set-DynamicProperty -Target $target[0] -Name "evidence_context" -Value $context
}

function Set-TaskDecisionReceipt {
    param([object]$Plan, [string]$Id, [string]$ReceiptJson)
    if ([string]::IsNullOrWhiteSpace($Id) -or [string]::IsNullOrWhiteSpace($ReceiptJson)) { throw "TaskId and DecisionReceiptJson are required." }
    try { $receipt = $ReceiptJson | ConvertFrom-Json } catch { throw "DecisionReceiptJson is not valid JSON." }
    if ([string]$receipt.schema -ne "codex-praetor-decision-receipt/v1") { throw "DecisionReceiptJson has an unsupported schema." }
    if ([string]::IsNullOrWhiteSpace([string]$receipt.decision_receipt_id)) { throw "DecisionReceiptJson lacks decision_receipt_id." }
    if ([string]$receipt.executive_mode -notin @("active", "inactive")) { throw "DecisionReceiptJson has an invalid executive_mode." }
    $target = @($Plan.tasks | Where-Object { $_.task_id -eq $Id } | Select-Object -First 1)
    if ($target.Count -ne 1) { throw "Task not found for decision receipt: $Id" }
    Set-DynamicProperty -Target $target[0] -Name "decision_receipt" -Value $receipt
}

function Record-TaskIntervention {
    param([object]$Plan, [string]$Id, [string]$Kind, [string]$SummaryValue)
    if ([string]::IsNullOrWhiteSpace($Id) -or [string]::IsNullOrWhiteSpace($Kind)) { throw "TaskId and InterventionKind are required." }
    $target = @($Plan.tasks | Where-Object { $_.task_id -eq $Id } | Select-Object -First 1)
    if ($target.Count -ne 1) { throw "Task not found for intervention: $Id" }
    $count = [int]$target[0].human_intervention_count + 1
    Set-DynamicProperty -Target $target[0] -Name "human_intervention_count" -Value $count
    Add-PlanEvent -Plan $Plan -Type "human_intervention" -Actor "codex" -Message "Intervention $Kind recorded for task $Id." -Data @{ task_id = $Id; intervention_kind = $Kind; summary = $SummaryValue; count = $count }
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

$planMutex = New-Object Threading.Mutex($false, (Get-PlanMutexName -Id $PlanId))
$planLockTaken = $false
try {
    try {
        $planLockTaken = $planMutex.WaitOne([TimeSpan]::FromSeconds(30))
    } catch [Threading.AbandonedMutexException] {
        $planLockTaken = $true
    }
    if (-not $planLockTaken) { throw "Timed out waiting for exclusive plan lock: $PlanId" }

    $plan = Read-Plan -Id $PlanId

if ($Action -eq "Init") {
    if (-not [string]::IsNullOrWhiteSpace($Title)) { $plan.title = $Title }
    if (-not [string]::IsNullOrWhiteSpace($Repo)) { $plan.repo = $Repo }
    Add-PlanEvent -Plan $plan -Type "plan_initialized" -Message "Plan initialized or refreshed."
    Save-Plan -Plan $plan
} elseif ($Action -eq "UpsertTask") {
    Upsert-Task -Plan $plan -Id $TaskId -TitleValue $TaskTitle -DependsValue $DependsOn -StatusValue $Status -AcceptanceValue $Acceptance -JobIdValue $JobId -JobDirValue $JobDir -ProviderValue $Provider -TierValue $Tier -ModelValue $Model -ModeValue $Mode -CompletionValue $CompletionPath -SummaryValue $Summary
    if ($hasDependsOnJson) {
        $target = @($plan.tasks | Where-Object { $_.task_id -eq $TaskId } | Select-Object -First 1)
        if ($target.Count -eq 1) { Set-DynamicProperty -Target $target[0] -Name "depends_on" -Value ([string[]]$DependsOnValues) }
    }
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
    $recordStatus = if ($completion.status -eq "process_exited" -and [string]::IsNullOrWhiteSpace([string]$completion.failure_class) -and $null -ne $completion.exit_code -and [int]$completion.exit_code -eq 0) { "awaiting_verification" } elseif ($completion.status -eq "cancelled") { "blocked" } elseif ([string]$completion.failure_class -eq "provider_rejected" -and [bool]$completion.safe_provider_fallback) { "retryable" } else { "failed" }
    $existingAttempts = @($plan.tasks | ForEach-Object { @($_.attempts) } | Where-Object { [string]$_.attempt_id -eq [string]$completion.job_id })
    if ($existingAttempts.Count -gt 1) {
        throw "Ledger integrity failure: job $([string]$completion.job_id) has multiple immutable attempts."
    }
    if ($existingAttempts.Count -eq 0) {
        $summaryText = "process_state=$($completion.process_state); failure_class=$($completion.failure_class); exit_code=$($completion.exit_code)"
        Upsert-Task -Plan $plan -Id $recordTaskId -TitleValue "" -DependsValue "" -StatusValue $recordStatus -AcceptanceValue ([string]$completion.acceptance) -JobIdValue ([string]$completion.job_id) -JobDirValue $JobDir -ProviderValue ([string]$completion.provider) -TierValue ([string]$completion.tier) -ModelValue ([string]$completion.model) -ModeValue ([string]$completion.mode) -CompletionValue $completionFile -SummaryValue $summaryText
        $recordTask = @($plan.tasks | Where-Object { $_.task_id -eq $recordTaskId } | Select-Object -First 1)
        if ($recordTask.Count -ne 1) { throw "Task missing after recording job: $recordTaskId" }
        Assert-BaseCommitEvidence -Task $recordTask[0] -Completion $completion -JobDir $JobDir
        $jobPath = Join-Path $JobDir "job.json"
        $job = if (Test-Path -LiteralPath $jobPath -PathType Leaf) { Get-Content -LiteralPath $jobPath -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
        $submittedAt = if ($null -ne $job) { [string]$job.created_at } else { "" }
        $workerStartedAt = if ($null -ne $job) { [string]$job.worker_started_at } else { "" }
        $workerFinishedAt = [string]$completion.exited_at
        $attemptWriteSet = [object[]]@()
        if ($null -ne $completion.write_set) { $attemptWriteSet = @($completion.write_set) }
        $attempt = [ordered]@{ attempt_id = [string]$completion.job_id; base_commit = [string]$completion.base_commit; worktree_head = [string]$completion.worktree_head; contract_sha256 = Get-CompletionContractSha256 -Completion $completion; task_family = [string]$recordTask[0].task_family; provider_tuple = $completion.provider_tuple; provider = [string]$completion.provider; model = [string]$completion.model; task_kind = [string]$completion.task_kind; write_set = $attemptWriteSet; execution_state = [string]$completion.process_state; evidence_state = [string]$completion.evidence_state; evidence_observation = $completion.evidence_observation; artifacts = @(); completion = $completionFile; exit_code = $completion.exit_code; failure_class = [string]$completion.failure_class; failure_subclass = [string]$completion.failure_subclass; safe_provider_fallback = [bool]$completion.safe_provider_fallback; supervisor_verdict = if ($recordStatus -eq "awaiting_verification") { "" } elseif ($recordStatus -eq "blocked") { "blocked" } elseif ($recordStatus -eq "retryable") { "retryable" } else { "rejected" }; timeline = [ordered]@{ submitted_at = $submittedAt; worker_started_at = $workerStartedAt; worker_finished_at = $workerFinishedAt; worker_elapsed_ms = Get-ElapsedMilliseconds -StartedAt $workerStartedAt -FinishedAt $workerFinishedAt }; created_at = $submittedAt; finished_at = $workerFinishedAt }
        $recordTask[0].attempts = @($recordTask[0].attempts) + $attempt
        $recordTask[0].governance_state = if ($recordStatus -eq "awaiting_verification") { "awaiting_supervisor" } elseif ($recordStatus -eq "blocked") { "blocked" } elseif ($recordStatus -eq "retryable") { "retryable" } else { "rejected" }
        Add-PlanEvent -Plan $plan -Type "job_recorded" -Message "Job $($completion.job_id) recorded for task $recordTaskId as $recordStatus." -Data @{ task_id = $recordTaskId; job_id = $completion.job_id; status = $completion.status; exit_code = $completion.exit_code }
    }
    Save-Plan -Plan $plan
} elseif ($Action -eq "VerifyTask") {
    Set-TaskVerification -Plan $plan -Id $TaskId -Verdict $VerificationVerdict -SummaryValue $VerificationSummary -NextActionValue $NextAction
    Add-PlanEvent -Plan $plan -Type "task_verified" -Message "Task $TaskId verification verdict: $VerificationVerdict." -Data @{ task_id = $TaskId; verdict = $VerificationVerdict; next_action = $NextAction }
    Save-Plan -Plan $plan
} elseif ($Action -eq "SetEvidenceContext") {
    if (-not [string]::IsNullOrWhiteSpace($EvidenceContextJson) -and -not [string]::IsNullOrWhiteSpace($EvidenceContextPath)) { throw "Specify only one evidence context transport." }
    $contextJson = $EvidenceContextJson
    if (-not [string]::IsNullOrWhiteSpace($EvidenceContextPath)) {
        if (-not (Test-Path -LiteralPath $EvidenceContextPath -PathType Leaf)) { throw "EvidenceContextPath does not exist: $EvidenceContextPath" }
        $contextJson = Get-Content -LiteralPath $EvidenceContextPath -Raw -Encoding UTF8
    }
    Set-TaskEvidenceContext -Plan $plan -Id $TaskId -ContextJson $contextJson
    Add-PlanEvent -Plan $plan -Type "evidence_context_set" -Actor "codex" -Message "Evidence context recorded for task $TaskId." -Data @{ task_id = $TaskId; source_category = ($plan.tasks | Where-Object { $_.task_id -eq $TaskId } | Select-Object -First 1).evidence_context.source_category }
    Save-Plan -Plan $plan
} elseif ($Action -eq "SetDecisionReceipt") {
    Set-TaskDecisionReceipt -Plan $plan -Id $TaskId -ReceiptJson $DecisionReceiptJson
    Add-PlanEvent -Plan $plan -Type "decision_receipt_set" -Actor "codex" -Message "Decision receipt recorded for task $TaskId." -Data @{ task_id = $TaskId; decision_receipt_id = ($plan.tasks | Where-Object { $_.task_id -eq $TaskId } | Select-Object -First 1).decision_receipt.decision_receipt_id }
    Save-Plan -Plan $plan
} elseif ($Action -eq "RecordIntervention") {
    Record-TaskIntervention -Plan $plan -Id $TaskId -Kind $InterventionKind -SummaryValue $InterventionSummary
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
} elseif ($Action -eq "SetDispatchState") {
    if ([string]::IsNullOrWhiteSpace($TaskId) -or [string]::IsNullOrWhiteSpace($DispatchState)) { throw "TaskId and DispatchState are required." }
    $target = @($plan.tasks | Where-Object { $_.task_id -eq $TaskId } | Select-Object -First 1)
    if ($target.Count -ne 1) { throw "Task not found: $TaskId" }
    Set-DynamicProperty -Target $target[0] -Name "dispatch_state" -Value $DispatchState
    if (-not [string]::IsNullOrWhiteSpace($NextAction)) { Set-DynamicProperty -Target $target[0] -Name "next_action" -Value $NextAction }
    Add-PlanEvent -Plan $plan -Type "dispatch_state" -Message "Task $TaskId dispatch state: $DispatchState." -Data @{ task_id = $TaskId; dispatch_state = $DispatchState; next_action = $NextAction }
    Save-Plan -Plan $plan
} elseif ($Action -eq "PrepareProviderFallback") {
    if ([string]::IsNullOrWhiteSpace($TaskId)) { throw "TaskId is required for PrepareProviderFallback." }
    $target = @($plan.tasks | Where-Object { $_.task_id -eq $TaskId } | Select-Object -First 1)
    if ($target.Count -ne 1) { throw "Task not found: $TaskId" }
    if ([string]$target[0].status -ne "retryable" -or [string]$target[0].governance_state -ne "retryable") {
        throw "Provider fallback is only allowed from an explicitly retryable task."
    }
    $attempts = @($target[0].attempts)
    if ($attempts.Count -ne 1 -or -not [bool]$attempts[0].safe_provider_fallback) {
        throw "Provider fallback requires exactly one recorded no-diff provider refusal."
    }
    Set-DynamicProperty -Target $target[0] -Name "status" -Value "pending"
    Set-DynamicProperty -Target $target[0] -Name "governance_state" -Value "awaiting_supervisor"
    Set-DynamicProperty -Target $target[0] -Name "dispatch_state" -Value "provider_fallback_prepared"
    Set-DynamicProperty -Target $target[0] -Name "next_action" -Value "Dispatch the one recorded alternate provider; do not replay the original provider."
    Add-PlanEvent -Plan $plan -Type "provider_fallback_prepared" -Actor "codex" -Message "Task $TaskId was reset for one controlled alternate-provider attempt." -Data @{ task_id = $TaskId; previous_provider = [string]$attempts[0].provider; failure_class = [string]$attempts[0].failure_class; failure_subclass = [string]$attempts[0].failure_subclass }
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
} finally {
    if ($planLockTaken) { $planMutex.ReleaseMutex() }
    $planMutex.Dispose()
}
