param([string]$ProjectRoot = "")

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$planScript = Join-Path $ProjectRoot "scripts\dispatch\manage-codex-praetor-plan.ps1"
$root = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-praetor-real-evidence-" + [Guid]::NewGuid().ToString("N"))

function Assert-True { param([bool]$Condition, [string]$Message) if (-not $Condition) { throw $Message } }

try {
    $planRoot = Join-Path $root "plans"
    $evidenceRoot = Join-Path $root "evidence"
    $jobDir = Join-Path $root "job"
    $executionRepo = Join-Path $root "execution"
    New-Item -ItemType Directory -Path $jobDir -Force | Out-Null
    New-Item -ItemType Directory -Path $executionRepo -Force | Out-Null
    'fixture' | Set-Content -LiteralPath (Join-Path $executionRepo "README.md") -Encoding ASCII
    & git -C $executionRepo init -q
    & git -C $executionRepo config user.email "evidence@example.invalid"
    & git -C $executionRepo config user.name "Codex Praetor test"
    & git -C $executionRepo add README.md
    & git -C $executionRepo commit -qm fixture
    $contractPath = Join-Path $jobDir "task-contract.json"
    $stdoutPath = Join-Path $jobDir "stdout.log"
    $jobPath = Join-Path $jobDir "job.json"
    $completionPath = Join-Path $jobDir "completion.json"
    '{"required_checks":["powershell -File verify.ps1"]}' | Set-Content -LiteralPath $contractPath -Encoding UTF8
    'CODEX_PRAETOR_REQUIRED_CHECKS_OK' | Set-Content -LiteralPath $stdoutPath -Encoding UTF8
    [ordered]@{ created_at = "2026-07-25T00:00:00Z"; worker_started_at = "2026-07-25T00:00:02Z"; execution_repo = $executionRepo; task_contract = $contractPath; stdout = $stdoutPath } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jobPath -Encoding UTF8
    $tuple = [ordered]@{ provider = "codebuddy"; cli_path = "codebuddy"; cli_hash = "cli-sha"; model = "test-model"; permission_profile = "readonly"; task_kind = "test_execution"; generation_id = "generation"; runtime_contract_sha256 = "runtime-sha"; task_contract_schema = "task-contract/v1" }
    [ordered]@{ job_id = "real-evidence-attempt"; base_commit = "base"; contract_sha256 = "contract-sha"; status = "process_exited"; process_state = "process_exited"; failure_class = ""; evidence_state = "tests_passed"; provider = "codebuddy"; tier = "fixture"; model = "test-model"; mode = "readonly"; acceptance = "independent"; exit_code = 0; task_kind = "test_execution"; write_set = @(); provider_tuple = $tuple; exited_at = "2026-07-25T00:00:12Z" } | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $completionPath -Encoding UTF8

    & $planScript -Action Init -PlanId evidence -PlanRoot $planRoot -Title evidence -Repo $ProjectRoot | Out-Null
    & $planScript -Action UpsertTask -PlanId evidence -PlanRoot $planRoot -TaskId task -TaskTitle task -TaskFamily fixed_test_execution -TaskKind test_execution -Mode readonly -Status pending -Acceptance independent -RequiredCheck "powershell -File verify.ps1" | Out-Null
    $context = '{"source_category":"real_historical_issue","source_ref":"issue-42","source_commit":"base","input_sha256":"input-sha","connection_mode":"supervised_cli_text","verifier_id":"independent-verifier","verifier_version":"1","verifier_sha256":"verifier-sha"}'
    & $planScript -Action SetEvidenceContext -PlanId evidence -PlanRoot $planRoot -TaskId task -EvidenceContextJson $context | Out-Null
    & $planScript -Action RecordIntervention -PlanId evidence -PlanRoot $planRoot -TaskId task -InterventionKind clarification -InterventionSummary "Clarified the frozen test command." | Out-Null
    & $planScript -Action RecordJob -PlanId evidence -PlanRoot $planRoot -TaskId task -JobDir $jobDir -CompletionPath $completionPath | Out-Null
    & $planScript -Action VerifyTask -PlanId evidence -PlanRoot $planRoot -CapabilityEvidenceRoot $evidenceRoot -TaskId task -VerificationVerdict accepted -VerificationSummary accepted | Out-Null

    $plan = Get-Content -LiteralPath (Join-Path $planRoot "evidence\plan.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    $task = @($plan.tasks | Where-Object { $_.task_id -eq "task" } | Select-Object -First 1)
    Assert-True ($task.Count -eq 1) "Task was not retained."
    Assert-True ([string]$task[0].evidence_context.source_category -eq "real_historical_issue") "Real task source was not recorded."
    Assert-True ([int]$task[0].human_intervention_count -eq 1) "Human intervention was not counted."
    Assert-True ([string]$task[0].attempts[-1].timeline.worker_started_at -eq "2026-07-25T00:00:02Z") "Worker start time was not retained."
    Assert-True ([double]$task[0].attempts[-1].timeline.worker_elapsed_ms -eq 10000) "Worker elapsed time was not calculated."
    Assert-True ([double]$task[0].attempts[-1].timeline.end_to_end_ms -ge 0) "End-to-end time was not calculated."
    $receipt = Get-Content -LiteralPath (Join-Path $evidenceRoot "real-evidence-attempt.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ([string]$receipt.evidence_context.connection_mode -eq "supervised_cli_text") "Connection mode was not written to the receipt."
    Assert-True ([string]$receipt.evidence_context.verifier_sha256 -eq "verifier-sha") "Verifier identity was not written to the receipt."
    Assert-True ([int]$receipt.human_intervention_count -eq 1) "Receipt lacks intervention count."

    $fixtureJobDir = Join-Path $root "fixture-job"
    New-Item -ItemType Directory -Path $fixtureJobDir -Force | Out-Null
    [ordered]@{ created_at = "2026-07-25T00:00:00Z"; worker_started_at = "2026-07-25T00:00:02Z"; execution_repo = $executionRepo; task_contract = $contractPath; stdout = $stdoutPath } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $fixtureJobDir "job.json") -Encoding UTF8
    [ordered]@{ job_id = "fixture-attempt"; base_commit = "base"; contract_sha256 = "contract-sha"; status = "process_exited"; process_state = "process_exited"; failure_class = ""; evidence_state = "tests_passed"; provider = "codebuddy"; tier = "fixture"; model = "test-model"; mode = "readonly"; acceptance = "independent"; exit_code = 0; task_kind = "test_execution"; write_set = @(); provider_tuple = $tuple; exited_at = "2026-07-25T00:00:12Z" } | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $fixtureJobDir "completion.json") -Encoding UTF8
    & $planScript -Action UpsertTask -PlanId evidence -PlanRoot $planRoot -TaskId fixture -TaskTitle fixture -TaskFamily fixed_test_execution -TaskKind test_execution -Mode readonly -Status pending -Acceptance independent -RequiredCheck "powershell -File verify.ps1" | Out-Null
    $fixtureContext = '{"source_category":"contract_regression","source_ref":"bounded-fixture","source_commit":"base","input_sha256":"input-sha","connection_mode":"supervised_cli_text","verifier_id":"independent-verifier","verifier_version":"1","verifier_sha256":"verifier-sha"}'
    & $planScript -Action SetEvidenceContext -PlanId evidence -PlanRoot $planRoot -TaskId fixture -EvidenceContextJson $fixtureContext | Out-Null
    & $planScript -Action RecordJob -PlanId evidence -PlanRoot $planRoot -TaskId fixture -JobDir $fixtureJobDir | Out-Null
    & $planScript -Action VerifyTask -PlanId evidence -PlanRoot $planRoot -CapabilityEvidenceRoot $evidenceRoot -TaskId fixture -VerificationVerdict accepted -VerificationSummary accepted | Out-Null
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $evidenceRoot "fixture-attempt.json"))) "Contract regressions must not create capability evidence."
    Write-Host "[PASS] Real task evidence contract regression passed."
} finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
