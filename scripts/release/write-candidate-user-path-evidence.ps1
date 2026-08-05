param(
    [Parameter(Mandatory = $true)][string]$CandidateReceiptPath,
    [Parameter(Mandatory = $true)][string]$HostRuntimeInfoPath,
    [Parameter(Mandatory = $true)][string]$PlanPath,
    [Parameter(Mandatory = $true)][string]$TaskId,
    [Parameter(Mandatory = $true)][string]$SkillPath,
    [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"

function Require([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "Candidate user-path evidence failed: $Message" }
}

function Read-Json([string]$Path) {
    Require (Test-Path -LiteralPath $Path -PathType Leaf) "missing JSON file: $Path"
    try { return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json } catch { throw "Candidate user-path evidence failed: invalid JSON $Path :: $($_.Exception.Message)" }
}

foreach ($path in @($CandidateReceiptPath, $HostRuntimeInfoPath, $PlanPath, $SkillPath)) {
    Require (Test-Path -LiteralPath $path -PathType Leaf) "required evidence is missing: $path"
}

$candidate = Read-Json $CandidateReceiptPath
$runtimeEnvelope = Read-Json $HostRuntimeInfoPath
$runtime = if ($null -ne $runtimeEnvelope.runtime_identity) { $runtimeEnvelope.runtime_identity } elseif ($null -ne $runtimeEnvelope.result -and $null -ne $runtimeEnvelope.result.runtime_identity) { $runtimeEnvelope.result.runtime_identity } else { throw "Candidate user-path evidence failed: runtime_info evidence has no runtime_identity." }
$plan = Read-Json $PlanPath

Require ([string]$candidate.schema -eq "codex-praetor-release-candidate/v1" -and [string]$candidate.status -eq "artifact_verified") "candidate receipt is not an artifact-verified candidate"
Require ([string]$runtime.version -eq [string]$candidate.candidate.version) "host runtime version differs from candidate"
Require ([string]$runtime.generation_id -eq [string]$candidate.generation.id) "host runtime generation differs from candidate"
Require (([string]$runtime.runtime_contract_sha256).ToLowerInvariant() -eq ([string]$candidate.generation.runtime_contract_sha256).ToLowerInvariant()) "host runtime contract differs from candidate"

$task = @($plan.tasks | Where-Object { [string]$_.task_id -eq $TaskId })
Require ($task.Count -eq 1) "plan does not contain exactly one task named $TaskId"
$task = $task[0]
Require ([string]$task.task_kind -eq "code_change") "user-path evidence must use a real code_change task"
Require ([string]$task.mode -eq "edit") "user-path evidence must use edit mode"
Require ([string]$task.status -eq "completed" -and [string]$task.governance_state -eq "accepted" -and [string]$task.verification_verdict -eq "accepted") "plan task is not accepted by Codex"
Require ([string]$task.base_commit -match "^[0-9a-fA-F]{40}$") "accepted task lacks a frozen base_commit"
Require (@($task.immutable_paths | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count -gt 0) "accepted task lacks immutable_paths"
Require (@($task.completion_definition.required_checks | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count -gt 0) "accepted task lacks required_checks"

$jobDir = [string]$task.job_dir
Require (-not [string]::IsNullOrWhiteSpace($jobDir) -and (Test-Path -LiteralPath $jobDir -PathType Container)) "accepted task lacks a recorded job directory"
$jobPath = Join-Path $jobDir "job.json"
$completionPath = [string]$task.completion
if ([string]::IsNullOrWhiteSpace($completionPath)) { $completionPath = Join-Path $jobDir "completion.json" }
$job = Read-Json $jobPath
$completion = Read-Json $completionPath
$baseCommit = ([string]$task.base_commit).ToLowerInvariant()
foreach ($value in @([string]$job.job_id, [string]$completion.job_id, [string]$task.job_id)) { Require (-not [string]::IsNullOrWhiteSpace($value)) "job identity is incomplete" }
Require ([string]$job.job_id -eq [string]$completion.job_id -and [string]$job.job_id -eq [string]$task.job_id) "plan, job and completion job IDs do not agree"
Require ([string]$job.task_kind -eq "code_change" -and [string]$completion.task_kind -eq "code_change") "job or completion is not a code_change"
Require ([string]$completion.status -eq "process_exited" -and [int]$completion.exit_code -eq 0 -and [string]::IsNullOrWhiteSpace([string]$completion.failure_class)) "worker did not complete successfully"
foreach ($observed in @([string]$job.base_commit, [string]$completion.base_commit, [string]$completion.worktree_head)) {
    Require ($observed.ToLowerInvariant() -eq $baseCommit) "job, completion and plan must retain the same frozen base_commit"
}
$worktree = [string]$job.execution_repo
Require (-not [string]::IsNullOrWhiteSpace($worktree) -and (Test-Path -LiteralPath $worktree -PathType Container)) "job does not retain its execution worktree"
$worktreeHead = ((& git -C $worktree rev-parse HEAD 2>$null | Out-String).Trim()).ToLowerInvariant()
Require ($worktreeHead -eq $baseCommit) "execution worktree HEAD differs from the frozen base_commit"
foreach ($value in @([string]$job.provider, [string]$job.model, [string]$job.connection_mode)) { Require (-not [string]::IsNullOrWhiteSpace($value)) "worker provider identity is incomplete" }

$evidence = [ordered]@{
    schema = "codex-praetor-candidate-user-path-evidence/v1"
    status = "accepted"
    candidate = [ordered]@{
        version = [string]$candidate.candidate.version
        pull_request_head = ([string]$candidate.pull_request.head_sha).ToLowerInvariant()
        artifact_sha256 = ([string]$candidate.artifact.zip_sha256).ToLowerInvariant()
        generation_id = [string]$candidate.generation.id
        runtime_contract_sha256 = ([string]$candidate.generation.runtime_contract_sha256).ToLowerInvariant()
    }
    host_runtime = [ordered]@{
        version = [string]$runtime.version
        generation_id = [string]$runtime.generation_id
        runtime_contract_sha256 = ([string]$runtime.runtime_contract_sha256).ToLowerInvariant()
    }
    entry = [ordered]@{
        kind = "new_task_execution_mode"
        skill_path = [IO.Path]::GetFullPath($SkillPath)
        skill_sha256 = (Get-FileHash -LiteralPath $SkillPath -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    route = [ordered]@{ result = "delegated_code_change"; task_family = [string]$task.task_family }
    preflight = [ordered]@{
        kind = "real_code_change"
        base_commit = $baseCommit
        immutable_paths = @($task.immutable_paths)
        required_checks = @($task.completion_definition.required_checks)
        worker_started = $false
    }
    dispatch = [ordered]@{
        job_id = [string]$job.job_id
        execution_worktree = $worktree
        provider = [string]$job.provider
        model = [string]$job.model
        connection_mode = [string]$job.connection_mode
        worker_started = $true
    }
    completion = [ordered]@{ status = [string]$completion.status; exit_code = [int]$completion.exit_code; worktree_head = ([string]$completion.worktree_head).ToLowerInvariant() }
    acceptance = [ordered]@{ verdict = [string]$task.verification_verdict; governance_state = [string]$task.governance_state; required_checks_passed = $true }
    created_at = [DateTime]::UtcNow.ToString("o")
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) { $OutputPath = Join-Path (Split-Path -Parent $PlanPath) ("candidate-user-path-" + [string]$job.job_id + ".json") }
$OutputPath = [IO.Path]::GetFullPath($OutputPath)
New-Item -ItemType Directory -Path (Split-Path -Parent $OutputPath) -Force | Out-Null
[IO.File]::WriteAllText($OutputPath, (($evidence | ConvertTo-Json -Depth 16) + [Environment]::NewLine), (New-Object Text.UTF8Encoding($false)))
Write-Host "[PASS] Candidate user-path evidence created: $OutputPath"
