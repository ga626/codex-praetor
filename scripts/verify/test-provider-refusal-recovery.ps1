param([string]$ProjectRoot = "")

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$root = [IO.Path]::GetFullPath($ProjectRoot)
$manager = Join-Path $root "scripts\dispatch\manage-codex-praetor-plan.ps1"
$watcher = Join-Path $root "scripts\dispatch\watch-codex-praetor-job.ps1"
$scratch = Join-Path ([IO.Path]::GetTempPath()) ("codex-praetor-refusal-" + [Guid]::NewGuid().ToString("N"))

function Assert-True([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Invoke-Manager([string[]]$Arguments) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $manager @Arguments | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Plan manager failed: $($Arguments -join ' ')" }
}

try {
    New-Item -ItemType Directory -Path $scratch -Force | Out-Null
    $repo = Join-Path $scratch "repo"
    New-Item -ItemType Directory -Path $repo -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $repo "README.md") -Value "fixture" -Encoding ASCII
    & git -C $repo init -q
    & git -C $repo config user.email "refusal-test@example.invalid"
    & git -C $repo config user.name "Codex Praetor test"
    & git -C $repo add README.md
    & git -C $repo commit -qm "fixture"
    if ($LASTEXITCODE -ne 0) { throw "Unable to create refusal fixture repository." }
    $planRoot = Join-Path $scratch "plans"
    $planId = "provider-refusal"
    $jobDir = Join-Path $scratch "job"
    New-Item -ItemType Directory -Path $jobDir -Force | Out-Null
    $contractPath = Join-Path $jobDir "contract.json"
    @{ required_checks = @("git status --short") } | ConvertTo-Json | Set-Content -LiteralPath $contractPath -Encoding UTF8
    @{ job_id = "refusal-job"; created_at = "2026-08-09T00:00:00Z"; worker_started_at = "2026-08-09T00:00:01Z"; execution_repo = $repo; task_contract = $contractPath; stdout = (Join-Path $jobDir "stdout.log") } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $jobDir "job.json") -Encoding UTF8
    @{ job_id = "refusal-job"; provider = "codebuddy"; task_id = "task"; status = "process_exited"; process_state = "process_exited"; exit_code = 0; failure_class = "provider_rejected"; failure_subclass = "provider_refusal_before_tool_use"; safe_provider_fallback = $true; evidence_observation = @{ worktree_changed = $false; acp_terminal_stop_reason = "refusal" }; exited_at = "2026-08-09T00:00:02Z"; task_kind = "local_audit"; provider_tuple = @{ provider = "codebuddy"; cli_path = "fixture"; cli_hash = ("a" * 64); model = "hy3"; permission_profile = "readonly"; task_kind = "local_audit"; generation_id = "fixture"; runtime_contract_sha256 = ("b" * 64); task_contract_schema = "fixture/v1" } } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $jobDir "completion.json") -Encoding UTF8
    Invoke-Manager @("-Action","Init","-PlanId",$planId,"-PlanRoot",$planRoot,"-Repo",$repo)
    Invoke-Manager @("-Action","UpsertTask","-PlanId",$planId,"-PlanRoot",$planRoot,"-TaskId","task","-TaskTitle","label only","-TaskFamily","read_only_diagnosis","-TaskKind","local_audit","-Mode","readonly","-Status","pending","-Acceptance","read status","-AllowedPath","README.md","-ForbiddenPath",".git","-RequiredCheck","git status --short","-BudgetJson",'{"max_wall_seconds":300}')
    Invoke-Manager @("-Action","RecordJob","-PlanId",$planId,"-PlanRoot",$planRoot,"-TaskId","task","-JobDir",$jobDir,"-CompletionPath",(Join-Path $jobDir "completion.json"))
    $planPath = Join-Path (Join-Path $planRoot $planId) "plan.json"
    $plan = Get-Content -LiteralPath $planPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($plan.tasks[0].status -eq "retryable" -and $plan.tasks[0].governance_state -eq "retryable") "No-diff ACP refusal was not recorded as a controlled retryable provider failure."
    Assert-True ([bool]$plan.tasks[0].attempts[0].safe_provider_fallback) "Attempt ledger lost the safe fallback flag."
    Invoke-Manager @("-Action","PrepareProviderFallback","-PlanId",$planId,"-PlanRoot",$planRoot,"-TaskId","task")
    $prepared = Get-Content -LiteralPath $planPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($prepared.tasks[0].status -eq "pending" -and $prepared.tasks[0].dispatch_state -eq "provider_fallback_prepared") "Controlled fallback did not return the same durable task to pending."
    $watcherText = Get-Content -LiteralPath $watcher -Raw -Encoding UTF8
    Assert-True ($watcherText -match 'terminal_stop_reason -eq "refusal"' -and $watcherText -match 'safeProviderFallback') "Watcher lacks the ACP refusal normalization and no-diff recovery gate."
    Write-Output "[PASS] ACP refusal is ledgered as a single controlled alternate-provider handoff only when no diff exists."
} finally {
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}
