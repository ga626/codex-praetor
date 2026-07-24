param([string]$ProjectRoot = "")

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
$initializer = Join-Path $ProjectRoot 'scripts\evaluation\initialize-codex-praetor-evaluation.ps1'
$invoker = Join-Path $ProjectRoot 'scripts\dispatch\invoke-codex-praetor.ps1'
$verifier = Join-Path $ProjectRoot 'scripts\evaluation\verify-codex-praetor-task-material.ps1'
$evidenceRoot = Join-Path ([IO.Path]::GetTempPath()) ('cp-eval-' + [Guid]::NewGuid().ToString('N').Substring(0, 12))
$gitEnvironmentNames = @('GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE', 'GIT_PREFIX', 'GIT_COMMON_DIR')
$gitEnvironmentBackup = @{}
foreach ($name in $gitEnvironmentNames) {
    $gitEnvironmentBackup[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
    Remove-Item -LiteralPath ("Env:" + $name) -ErrorAction SilentlyContinue
}

function Assert-True { param([bool]$Condition, [string]$Message) if (-not $Condition) { throw $Message } }
function New-FixtureRepo {
    param([string]$Name)
    $repo = Join-Path $evidenceRoot $Name
    New-Item -ItemType Directory -Path $repo -Force | Out-Null
    & git -C $repo init -q
    & git -C $repo config user.email 'evaluation@example.invalid'
    & git -C $repo config user.name 'Codex Praetor evaluation'
    Set-Content -LiteralPath (Join-Path $repo 'README.md') -Value 'fixture' -Encoding ascii
    & git -C $repo add README.md
    & git -C $repo commit -qm fixture
    return $repo
}
function Prepare-Task {
    param([string]$Repo, [string]$PlanId)
    $planRoot = Join-Path $Repo '.codex-praetor\plans'
    & $initializer -ProjectRoot $ProjectRoot -Action Prepare -PlanRoot $planRoot -PlanId $PlanId -Apply | Out-Null
    $plan = Get-Content -LiteralPath (Join-Path $planRoot "$PlanId\plan.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    return @($plan.tasks | Where-Object { $_.task_id -eq 'bounded-test-fix' })[0]
}
function Preflight-Task {
    param([string]$Repo, [object]$Task)
    $arguments = @{
        Provider = 'qoder'; Tier = 'qoder-day-cheap'; Repo = $Repo; Task = [string]$Task.title; Mode = 'edit'; TaskKind = 'code_change'; RunMode = 'blocking';
        AllowedPathsJson = ($Task.allowed_paths | ConvertTo-Json -Compress); ForbiddenPathsJson = ($Task.forbidden_paths | ConvertTo-Json -Compress);
        RequiredChecksJson = ($Task.completion_definition.required_checks | ConvertTo-Json -Compress); BudgetJson = ($Task.budget | ConvertTo-Json -Compress);
        TaskMaterialJson = ($Task.task_material | ConvertTo-Json -Compress -Depth 12); PreflightOnly = $true; NoNotify = $true
    }
    $lines = @(& $invoker @arguments)
    Assert-True ($LASTEXITCODE -eq 0) 'Preflight should not start a provider and must succeed with a failing baseline.'
    $worktreeLine = @($lines | Where-Object { $_ -like 'execution_worktree=*' })[0]
    Assert-True (-not [string]::IsNullOrWhiteSpace($worktreeLine)) 'Preflight did not report its isolated worktree.'
    return $worktreeLine.Substring('execution_worktree='.Length)
}
function Verify-Task {
    param([string]$Worktree, [object]$Task)
    $result = & $verifier -Worktree $Worktree -TaskMaterialJson ($Task.task_material | ConvertTo-Json -Compress -Depth 12) -RequiredChecksJson ($Task.completion_definition.required_checks | ConvertTo-Json -Compress)
    Assert-True ($LASTEXITCODE -eq 0) 'Independent verifier failed to return machine-readable evidence.'
    return ($result | ConvertFrom-Json)
}
function Repair-Fixture { param([string]$Worktree) $path = Join-Path $Worktree '.codex-praetor\evaluation\bounded-test-fix\compute.ps1'; (Get-Content -LiteralPath $path -Raw -Encoding UTF8).Replace('$Left - $Right', '$Left + $Right') | Set-Content -LiteralPath $path -Encoding UTF8 }

New-Item -ItemType Directory -Path $evidenceRoot -Force | Out-Null
$repo = New-FixtureRepo -Name 'baseline-and-verifier'
$task = Prepare-Task -Repo $repo -PlanId 'material-contract'
Assert-True (@($task.task_material.files).Count -eq 3) 'Prepared code-change task must preserve every supplied material file.'
$worktree = Preflight-Task -Repo $repo -Task $task
$beforeRepair = Verify-Task -Worktree $worktree -Task $task
Assert-True ($beforeRepair.verdict -eq 'rejected') 'A supplied baseline that still fails must never be accepted.'
Repair-Fixture -Worktree $worktree
$accepted = Verify-Task -Worktree $worktree -Task $task
Assert-True ($accepted.verdict -eq 'accepted_candidate') 'A repair limited to the declared write set and passing the supplied test should be an acceptance candidate.'

$immutableRepo = New-FixtureRepo -Name 'immutable-fault'
$immutableTask = Prepare-Task -Repo $immutableRepo -PlanId 'immutable-fault'
$immutableWorktree = Preflight-Task -Repo $immutableRepo -Task $immutableTask
Repair-Fixture -Worktree $immutableWorktree
Add-Content -LiteralPath (Join-Path $immutableWorktree '.codex-praetor\evaluation\bounded-test-fix\test.ps1') -Value '# tampered'
$immutableResult = Verify-Task -Worktree $immutableWorktree -Task $immutableTask
Assert-True ($immutableResult.verdict -eq 'rejected' -and (@($immutableResult.violations) -match 'immutable_file_changed').Count -gt 0) 'Changing a supplied immutable test must be rejected.'

$scopeRepo = New-FixtureRepo -Name 'scope-fault'
$scopeTask = Prepare-Task -Repo $scopeRepo -PlanId 'scope-fault'
$scopeWorktree = Preflight-Task -Repo $scopeRepo -Task $scopeTask
Repair-Fixture -Worktree $scopeWorktree
Add-Content -LiteralPath (Join-Path $scopeWorktree 'README.md') -Value 'outside write set'
$scopeResult = Verify-Task -Worktree $scopeWorktree -Task $scopeTask
Assert-True ($scopeResult.verdict -eq 'rejected' -and (@($scopeResult.violations) -match 'tracked_diff_outside_write_set').Count -gt 0) 'A tracked diff outside the declared write set must be rejected.'

try {
    Write-Host "[PASS] Evaluation task material requires a known failing baseline and independently rejects immutable-file and write-set faults. Evidence retained at $evidenceRoot"
} finally {
    foreach ($name in $gitEnvironmentNames) {
        $value = $gitEnvironmentBackup[$name]
        if ($null -eq $value) { Remove-Item -LiteralPath ("Env:" + $name) -ErrorAction SilentlyContinue }
        else { [Environment]::SetEnvironmentVariable($name, $value, 'Process') }
    }
}
