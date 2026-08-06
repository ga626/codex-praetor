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
    $repo = Join-Path $root 'repo'
    New-Item -ItemType Directory -Path $repo -Force | Out-Null
    & git -C $repo init -q
    & git -C $repo config user.email 'evaluation-suite@example.invalid'
    & git -C $repo config user.name 'Codex Praetor evaluation'
    Set-Content -LiteralPath (Join-Path $repo 'README.md') -Value 'fixture' -Encoding ascii
    & git -C $repo add README.md
    & git -C $repo commit --no-verify -qm fixture
    Assert-True ($LASTEXITCODE -eq 0) 'Evaluation fixture initial commit failed.'
    $planRoot = Join-Path $repo '.codex-praetor\plans'
    $prepared = & $script -ProjectRoot $repo -SuitePath (Join-Path $ProjectRoot 'config\evaluation-suite.json') -TemplateRoot (Join-Path $ProjectRoot 'config\evaluation-task-templates') -PlanScript (Join-Path $ProjectRoot 'scripts\dispatch\manage-codex-praetor-plan.ps1') -PlanRoot $planRoot -PlanId fixture -Action Prepare -Apply | ConvertFrom-Json
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
        if ([string]$task.task_kind -eq 'code_change') {
            Assert-True ([string]$task.base_commit -match '^[0-9a-f]{40}$') "Prepared code-change task $($task.task_id) lacks a frozen baseline commit."
            Assert-True ([string]$task.task_material.baseline_ref -match '^refs/codex-praetor/evaluation/') "Prepared code-change task $($task.task_id) lacks its retained baseline ref."
            foreach ($immutablePath in @($task.immutable_paths)) {
                & git -C $repo rev-parse --verify ("$($task.base_commit):$immutablePath") | Out-Null
                Assert-True ($LASTEXITCODE -eq 0) "Prepared code-change task $($task.task_id) did not track immutable path $immutablePath at its frozen baseline."
            }
        }
    }
    Write-Host "[PASS] Evaluation suite contract preserves the complete bounded dispatch contract in a project-local plan without dispatching a worker."
} finally { if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force } }
