param(
    [ValidateSet("Preview", "Prepare")]
    [string]$Action = "Preview",
    [string]$ProjectRoot = "",
    [string]$SuitePath = "",
    [string]$PlanRoot = "",
    [string]$PlanId = "",
    [switch]$Apply
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
if ([string]::IsNullOrWhiteSpace($SuitePath)) { $SuitePath = Join-Path $ProjectRoot "config\evaluation-suite.json" }
if ([string]::IsNullOrWhiteSpace($PlanRoot)) { $PlanRoot = Join-Path $ProjectRoot ".codex-praetor\plans" }

function Assert-True { param([bool]$Condition, [string]$Message) if (-not $Condition) { throw $Message } }
function Assert-Task { param([object]$Task)
    foreach ($name in @("task_id", "task_family", "goal", "mode", "task_kind", "provider_candidates", "allowed_paths", "forbidden_paths", "acceptance", "required_checks", "budget", "failure_injection")) {
        Assert-True ($Task.PSObject.Properties.Name -contains $name) "Evaluation task is missing $name."
    }
    Assert-True ([string]$Task.task_family -in @("read_only_diagnosis", "bounded_code_change", "fixed_test_execution", "failure_recovery")) "Unsupported task family: $($Task.task_family)"
    Assert-True ([string]$Task.mode -in @("readonly", "edit")) "Unsupported task mode: $($Task.mode)"
    Assert-True (@($Task.provider_candidates).Count -gt 0) "Evaluation task $($Task.task_id) has no provider candidates."
    Assert-True (@($Task.allowed_paths).Count -gt 0 -and @($Task.forbidden_paths).Count -gt 0) "Evaluation task $($Task.task_id) lacks path boundaries."
    Assert-True ([int]$Task.budget.max_turns -gt 0 -and [int]$Task.budget.max_wall_seconds -ge 60) "Evaluation task $($Task.task_id) has an invalid budget."
}

if (-not (Test-Path -LiteralPath $SuitePath -PathType Leaf)) { throw "Evaluation suite is missing: $SuitePath" }
$suite = Get-Content -LiteralPath $SuitePath -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-True ([string]$suite.schema -eq "codex-praetor-evaluation-suite/v1") "Evaluation suite schema is invalid."
$tasks = @($suite.tasks)
Assert-True ($tasks.Count -ge 4) "Evaluation suite needs at least four tasks."
Assert-True (@($tasks.task_id | Select-Object -Unique).Count -eq $tasks.Count) "Evaluation task ids must be unique."
foreach ($task in $tasks) { Assert-Task -Task $task }
$families = @($tasks.task_family | Select-Object -Unique)
foreach ($family in @("read_only_diagnosis", "bounded_code_change", "fixed_test_execution", "failure_recovery")) { Assert-True ($family -in $families) "Evaluation suite does not cover $family." }

$resolvedPlanId = if ([string]::IsNullOrWhiteSpace($PlanId)) { "evaluation-$($suite.suite_id)" } else { $PlanId }
$summary = [ordered]@{ schema = "codex-praetor-evaluation-preparation/v1"; suite_id = [string]$suite.suite_id; plan_id = $resolvedPlanId; action = $Action; apply = [bool]$Apply; tasks = @($tasks | ForEach-Object { [ordered]@{ task_id = [string]$_.task_id; task_family = [string]$_.task_family; mode = [string]$_.mode; candidates = @($_.provider_candidates); acceptance = [string]$_.acceptance } }); next_action = "Review the prepared contracts, then dispatch one task at a time in an isolated worktree. A prepared plan is not capability evidence." }

if ($Action -eq "Prepare") {
    if (-not $Apply) { $summary.next_action = "Re-run with -Action Prepare -Apply to create the project-local plan ledger." }
    else {
        $planScript = Join-Path $ProjectRoot "scripts\dispatch\manage-codex-praetor-plan.ps1"
        & $planScript -Action Init -PlanId $resolvedPlanId -PlanRoot $PlanRoot -Title "Evaluation $($suite.suite_id)" -Repo $ProjectRoot | Out-Null
        foreach ($task in $tasks) {
            & $planScript -Action UpsertTask -PlanId $resolvedPlanId -PlanRoot $PlanRoot -TaskId ([string]$task.task_id) -TaskTitle ([string]$task.goal) -TaskFamily ([string]$task.task_family) -Status pending -Mode ([string]$task.mode) -Acceptance ([string]$task.acceptance) -Summary ("required_checks=" + (@($task.required_checks) -join " | ")) | Out-Null
        }
        $summary.plan_path = Join-Path (Join-Path $PlanRoot $resolvedPlanId) "plan.json"
        $summary.next_action = "Dispatch a single prepared task through the normal worker contract; do not mass-dispatch the suite."
    }
}
$summary | ConvertTo-Json -Depth 20
