param([string]$ProjectRoot = "")

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$script = Join-Path $ProjectRoot "scripts\evaluation\initialize-codex-praetor-evaluation.ps1"
$root = Join-Path ([IO.Path]::GetTempPath()) ("codex-praetor-evaluation-" + [Guid]::NewGuid().ToString("N"))
function Assert-True { param([bool]$Condition, [string]$Message) if (-not $Condition) { throw $Message } }
try {
    $preview = & $script -ProjectRoot $ProjectRoot -Action Preview | ConvertFrom-Json
    Assert-True ($preview.tasks.Count -ge 4) "Evaluation preview did not expose the task suite."
    Assert-True ((@($preview.tasks.task_family | Select-Object -Unique)).Count -eq 4) "Evaluation suite does not cover every task family."
    $prepared = & $script -ProjectRoot $ProjectRoot -Action Prepare -PlanRoot $root -PlanId fixture -Apply | ConvertFrom-Json
    Assert-True (Test-Path -LiteralPath $prepared.plan_path -PathType Leaf) "Evaluation preparation did not create a local plan."
    $plan = Get-Content -LiteralPath $prepared.plan_path -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True (@($plan.tasks).Count -eq @($preview.tasks).Count) "Prepared plan task count drifted from the suite."
    Assert-True (@($plan.tasks | Where-Object { [string]$_.task_family -eq "unclassified" }).Count -eq 0) "Prepared evaluation task was left unclassified."
    $fixed = @($plan.tasks | Where-Object { [string]$_.task_family -eq "fixed_test_execution" })
    Assert-True ($fixed.Count -gt 0 -and @($fixed | Where-Object { [string]$_.task_kind -ne "test_execution" }).Count -eq 0) "Fixed test tasks lost their test_execution kind in the prepared plan."
    foreach ($task in @($plan.tasks)) {
        Assert-True (-not [string]::IsNullOrWhiteSpace([string]$task.task_kind)) "Prepared task $($task.task_id) lost task_kind."
        Assert-True (@($task.allowed_paths).Count -gt 0 -and @($task.forbidden_paths).Count -gt 0) "Prepared task $($task.task_id) lost path boundaries."
        Assert-True (@($task.completion_definition.required_checks).Count -gt 0) "Prepared task $($task.task_id) lost required checks."
        Assert-True ([int]$task.budget.max_turns -gt 0 -and [int]$task.budget.max_wall_seconds -gt 0) "Prepared task $($task.task_id) lost its budget."
    }
    Write-Host "[PASS] Evaluation suite contract preserves the complete bounded dispatch contract in a project-local plan without dispatching a worker."
} finally { if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force } }
