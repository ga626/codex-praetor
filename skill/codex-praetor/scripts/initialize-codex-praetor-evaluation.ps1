param(
    [ValidateSet("Preview", "Prepare")]
    [string]$Action = "Preview",
    [string]$ProjectRoot = "",
    [string]$SuitePath = "",
    [string]$PlanRoot = "",
    [string]$PlanId = "",
    [string]$PlanScript = "",
    [string]$TemplateRoot = "",
    [switch]$Apply
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
if ([string]::IsNullOrWhiteSpace($SuitePath)) { $SuitePath = Join-Path $ProjectRoot "config\evaluation-suite.json" }
if ([string]::IsNullOrWhiteSpace($PlanRoot)) { $PlanRoot = Join-Path $ProjectRoot ".codex-praetor\plans" }
if ([string]::IsNullOrWhiteSpace($PlanScript)) { $PlanScript = Join-Path $ProjectRoot "scripts\dispatch\manage-codex-praetor-plan.ps1" }
if ([string]::IsNullOrWhiteSpace($TemplateRoot)) { $TemplateRoot = Join-Path $ProjectRoot "config\evaluation-task-templates" }
$PlanScript = [IO.Path]::GetFullPath($PlanScript)

function Assert-True { param([bool]$Condition, [string]$Message) if (-not $Condition) { throw $Message } }
function Get-TextSha256 { param([string]$Path) $bytes = [IO.File]::ReadAllBytes($Path); $sha = [Security.Cryptography.SHA256]::Create(); try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant() } finally { $sha.Dispose() } }
function New-TaskMaterial { param([object]$Task, [string]$PlanDirectory)
    if ([string]$Task.task_kind -ne 'code_change') { return $null }
    Assert-True ($Task.PSObject.Properties.Name -contains 'task_material') "Code-change task $($Task.task_id) lacks task material."
    $spec = $Task.task_material; foreach($name in @('template','destination','write_set','baseline_command','baseline_exit_code','immutable_paths','files')) { Assert-True ($spec.PSObject.Properties.Name -contains $name) "Task material for $($Task.task_id) lacks $name." }
    $template = Join-Path $TemplateRoot ([string]$spec.template); Assert-True (Test-Path -LiteralPath $template -PathType Container) "Task material template is missing: $($spec.template)"
    $instance = Join-Path (Join-Path $PlanDirectory 'instances') ([string]$Task.task_id)
    Assert-True (-not (Test-Path -LiteralPath $instance)) "Task material instance already exists: $instance. Use a new plan id; do not overwrite prior evidence."
    New-Item -ItemType Directory -Path $instance -Force | Out-Null
    Copy-Item -Path (Join-Path $template '*') -Destination $instance -Recurse -Force
    $files = @()
    foreach ($relativePath in @($spec.files)) {
        Assert-True (-not [IO.Path]::IsPathRooted([string]$relativePath) -and [string]$relativePath -notmatch '(^|[\\/])\.\.([\\/]|$)') "Task material file path is unsafe: $relativePath"
        $sourcePath = Join-Path $instance ([string]$relativePath)
        Assert-True (Test-Path -LiteralPath $sourcePath -PathType Leaf) "Task material file is missing from template: $relativePath"
        $files += [ordered]@{
            path = ([string]$relativePath).Replace('\', '/')
            sha256 = Get-TextSha256 -Path $sourcePath
        }
    }
    $material = [ordered]@{ schema='codex-praetor-task-material-instance/v1'; source_root=$instance; destination=[string]$spec.destination; write_set=@($spec.write_set); immutable_paths=@($spec.immutable_paths); baseline_command=[string]$spec.baseline_command; baseline_exit_code=[int]$spec.baseline_exit_code; files=$files }
    $materialPath = Join-Path $instance 'material-manifest.json'; $material | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $materialPath -Encoding UTF8
    $material.manifest_sha256 = Get-TextSha256 $materialPath
    # Dispatch reads this durable contract by path.  Passing the full JSON through
    # a Windows command line can alter backslash-containing payloads before the
    # wrapper validates them.
    $contractPath = Join-Path $instance 'task-material.json'; $material | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $contractPath -Encoding UTF8
    return $material
}
function Get-SafeRefSegment {
    param([Parameter(Mandatory = $true)][string]$Value)
    $safe = $Value -replace '[^A-Za-z0-9._-]', '_'
    Assert-True (-not [string]::IsNullOrWhiteSpace($safe)) 'Evaluation ref segment is empty after normalization.'
    return $safe
}
function New-EvaluationBaselineCommit {
    param(
        [Parameter(Mandatory = $true)][object]$Task,
        [Parameter(Mandatory = $true)][object]$Material,
        [Parameter(Mandatory = $true)][string]$SourceCommit
    )
    # A real code-change worker may only start from tracked, immutable files.
    # The suite's intentionally failing fixture is therefore committed in a
    # disposable staging worktree, never copied into the worker after launch.
    $stageName = 'evaluation-stage-' + (Get-SafeRefSegment $resolvedPlanId) + '-' + (Get-SafeRefSegment ([string]$Task.task_id)) + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
    $stageRoot = Join-Path (Join-Path $ProjectRoot '.codex\worktrees') $stageName
    $baseRef = 'refs/codex-praetor/evaluation/' + (Get-SafeRefSegment $resolvedPlanId) + '/' + (Get-SafeRefSegment ([string]$Task.task_id))
    $created = $false
    try {
        $priorErrorAction = $ErrorActionPreference
        try {
            # Git writes its normal "Preparing worktree" progress to stderr.
            # Keep that text and the native exit code together instead of
            # letting PowerShell mistake a successful native progress line for
            # a terminating exception.
            $ErrorActionPreference = 'Continue'
            $stageOutput = (& git -C $ProjectRoot worktree add --detach $stageRoot $SourceCommit 2>&1 | Out-String).Trim()
            $stageExitCode = $LASTEXITCODE
        } finally { $ErrorActionPreference = $priorErrorAction }
        Assert-True ($stageExitCode -eq 0 -and (Test-Path -LiteralPath $stageRoot -PathType Container)) "Could not create disposable evaluation staging worktree. $stageOutput"
        $created = $true
        $destination = ([string]$Material.destination).Replace('/', '\\')
        $destinationRoot = Join-Path $stageRoot $destination
        Assert-True (-not (Test-Path -LiteralPath $destinationRoot)) "Evaluation fixture destination already exists at the frozen source commit: $destination"
        New-Item -ItemType Directory -Path $destinationRoot -Force | Out-Null
        foreach ($entry in @($Material.files)) {
            $relative = ([string]$entry.path).Replace('/', '\\')
            $source = Join-Path ([string]$Material.source_root) $relative
            $target = Join-Path $destinationRoot $relative
            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
            Copy-Item -LiteralPath $source -Destination $target -Force
            Assert-True ((Get-TextSha256 -Path $target) -eq [string]$entry.sha256) "Evaluation fixture copy hash mismatch: $relative"
        }
        $priorErrorAction = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $gitAddOutput = (& git -C $stageRoot add -- $destination 2>&1 | Out-String).Trim()
            $gitAddExitCode = $LASTEXITCODE
        } finally { $ErrorActionPreference = $priorErrorAction }
        Assert-True ($gitAddExitCode -eq 0) "Could not stage the evaluation fixture baseline. $gitAddOutput"
        & git -C $stageRoot -c user.name='Codex Praetor evaluation' -c user.email='codex-praetor-evaluation@localhost' -c commit.gpgSign=false commit --no-verify -m ('codex-praetor evaluation baseline ' + [string]$Task.task_id) | Out-Null
        Assert-True ($LASTEXITCODE -eq 0) 'Could not commit the disposable evaluation fixture baseline.'
        $baselineCommit = (& git -C $stageRoot rev-parse --verify 'HEAD^{commit}' | Out-String).Trim().ToLowerInvariant()
        Assert-True ($LASTEXITCODE -eq 0 -and $baselineCommit -match '^[0-9a-f]{40}$') 'Could not resolve the evaluation fixture baseline commit.'
        & git -C $ProjectRoot update-ref $baseRef $baselineCommit | Out-Null
        Assert-True ($LASTEXITCODE -eq 0) 'Could not retain the evaluation fixture baseline ref.'
        $Material | Add-Member -NotePropertyName baseline_commit -NotePropertyValue $baselineCommit -Force
        $Material | Add-Member -NotePropertyName baseline_ref -NotePropertyValue $baseRef -Force
        # The MCP verifier deliberately reads this file by path so native
        # PowerShell argument parsing cannot alter the contract. Persist the
        # resolved baseline fields after the fixture commit is known.
        $contractPath = Join-Path ([string]$Material.source_root) 'task-material.json'
        $Material | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $contractPath -Encoding UTF8
        return $baselineCommit
    } finally {
        if ($created -and (Test-Path -LiteralPath $stageRoot -PathType Container)) {
            $priorErrorAction = $ErrorActionPreference
            try {
                $ErrorActionPreference = 'Continue'
                $removeOutput = (& git -C $ProjectRoot worktree remove --force $stageRoot 2>&1 | Out-String).Trim()
                $removeExitCode = $LASTEXITCODE
            } finally { $ErrorActionPreference = $priorErrorAction }
            if ($removeExitCode -ne 0) { throw "Could not retire disposable evaluation staging worktree: $stageRoot :: $removeOutput" }
        }
    }
}
function Assert-Task { param([object]$Task)
    foreach ($name in @("task_id", "task_family", "goal", "mode", "task_kind", "provider_candidates", "allowed_paths", "forbidden_paths", "acceptance", "required_checks", "budget", "failure_injection")) {
        Assert-True ($Task.PSObject.Properties.Name -contains $name) "Evaluation task is missing $name."
    }
    Assert-True ([string]$Task.task_family -in @("read_only_diagnosis", "bounded_code_change", "fixed_test_execution", "failure_recovery")) "Unsupported task family: $($Task.task_family)"
    Assert-True ([string]$Task.mode -in @("readonly", "edit")) "Unsupported task mode: $($Task.mode)"
    Assert-True ([string]$Task.task_kind -in @("local_audit", "test_execution", "code_change")) "Unsupported task kind: $($Task.task_kind)"
    if ([string]$Task.task_family -eq "fixed_test_execution") { Assert-True ([string]$Task.task_kind -eq "test_execution") "Fixed test execution task $($Task.task_id) must use test_execution." }
    if ([string]$Task.task_kind -eq "test_execution") { Assert-True ([string]$Task.mode -eq "readonly") "test_execution task $($Task.task_id) must be readonly." }
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
        Assert-True (Test-Path -LiteralPath $PlanScript -PathType Leaf) "Evaluation plan script is missing: $PlanScript"
        $sourceCommit = (& git -C $ProjectRoot rev-parse --verify "HEAD^{commit}" | Out-String).Trim().ToLowerInvariant()
        Assert-True ($LASTEXITCODE -eq 0 -and $sourceCommit -match '^[0-9a-f]{40}$') "Evaluation plan cannot freeze the repository source commit."
        & $PlanScript -Action Init -PlanId $resolvedPlanId -PlanRoot $PlanRoot -Title "Evaluation $($suite.suite_id)" -Repo $ProjectRoot | Out-Null
        foreach ($task in $tasks) {
            $budgetJson = $task.budget | ConvertTo-Json -Compress
            $planDir = Join-Path $PlanRoot $resolvedPlanId; $material = New-TaskMaterial -Task $task -PlanDirectory $planDir
            $taskBaseCommit = $sourceCommit
            if ($null -ne $material) { $taskBaseCommit = New-EvaluationBaselineCommit -Task $task -Material $material -SourceCommit $sourceCommit }
            $planArgs = @{ Action='UpsertTask'; PlanId=$resolvedPlanId; PlanRoot=$PlanRoot; TaskId=[string]$task.task_id; TaskTitle=[string]$task.goal; TaskFamily=[string]$task.task_family; TaskKind=[string]$task.task_kind; Status='pending'; Mode=[string]$task.mode; AllowedPath=@($task.allowed_paths); ForbiddenPath=@($task.forbidden_paths); RequiredCheck=@($task.required_checks); BudgetJson=$budgetJson; FailureInjection=[string]$task.failure_injection; Sensitivity=[string]$task.sensitivity; Acceptance=[string]$task.acceptance; Summary=('required_checks=' + (@($task.required_checks) -join ' | ')); BaseCommit=$taskBaseCommit }
            if ($null -ne $material) { $planArgs.ImmutablePath = @($material.immutable_paths) }
            if ($null -ne $material) { $planArgs.TaskMaterialJson = ($material | ConvertTo-Json -Compress -Depth 8) }; & $PlanScript @planArgs | Out-Null
        }
        $summary.plan_path = Join-Path (Join-Path $PlanRoot $resolvedPlanId) "plan.json"
        $summary.next_action = "Dispatch a single prepared task through the normal worker contract; do not mass-dispatch the suite."
    }
}
$summary | ConvertTo-Json -Depth 20
