param(
    [string]$ProjectRoot = ""
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
$dispatcher = Join-Path $ProjectRoot "scripts\dispatch\invoke-codex-praetor.ps1"
$manager = Join-Path $ProjectRoot "scripts\dispatch\manage-codex-praetor-plan.ps1"
$scratch = Join-Path ([IO.Path]::GetTempPath()) ("codex-praetor-evidence-bootstrap-" + [Guid]::NewGuid().ToString("N"))
$planRoot = Join-Path $scratch "plans"
$planId = "bootstrap"
$taskId = "task-01"
$taskTitle = "Read the frozen release-intent verifier and report its contract without writing files."

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$dispatcherText = Get-Content -LiteralPath $dispatcher -Raw -Encoding UTF8
Assert-True ($dispatcherText -match 'if \(-not \$DryRun -and -not \$CapabilityCanary -and -not \$PreflightOnly -and -not \$EvidenceBootstrap\)') "A real evidence bootstrap must bypass only the duplicate readiness gate after its own strict contract check."

try {
    New-Item -ItemType Directory -Path $planRoot -Force | Out-Null
    & $manager -Action Init -PlanId $planId -PlanRoot $planRoot -Title "bootstrap" -Repo $ProjectRoot | Out-Null
    & $manager -Action UpsertTask -PlanId $planId -PlanRoot $planRoot -TaskId $taskId -TaskTitle $taskTitle -TaskFamily read_only_diagnosis -TaskKind local_audit -Mode readonly -Status pending -Acceptance "Codex independently checks the report." -AllowedPath "scripts/verify/test-release-intent.ps1" -ForbiddenPath ".git" -RequiredCheck "powershell -NoProfile -ExecutionPolicy Bypass -File scripts/verify/test-release-intent.ps1" | Out-Null
    $realContext = '{"source_category":"real_historical_issue","source_ref":"release-intent historical fix","source_commit":"62d8ef5","input_sha256":"input-sha","connection_mode":"supervised_cli_text","verifier_id":"test-release-intent","verifier_version":"1","verifier_sha256":"verifier-sha"}'
    & $manager -Action SetEvidenceContext -PlanId $planId -PlanRoot $planRoot -TaskId $taskId -EvidenceContextJson $realContext | Out-Null
    $common = @{ Provider = "qoder"; Tier = "qoder-day-cheap"; Repo = $ProjectRoot; Task = $taskTitle; Mode = "readonly"; TaskKind = "local_audit"; RunMode = "background"; PlanId = $planId; TaskId = $taskId; TaskFamily = "read_only_diagnosis"; Acceptance = "Codex independently checks the report."; PlanRoot = $planRoot; AllowedPathsJson = '["scripts/verify/test-release-intent.ps1"]'; ForbiddenPathsJson = '[".git"]'; RequiredChecksJson = '["powershell -NoProfile -ExecutionPolicy Bypass -File scripts/verify/test-release-intent.ps1"]'; DryRun = $true; NoNotify = $true }
    & $dispatcher @common -EvidenceBootstrap | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) "Frozen real-task bootstrap was unexpectedly rejected."

    $fixtureContext = $realContext.Replace("real_historical_issue", "contract_regression")
    & $manager -Action SetEvidenceContext -PlanId $planId -PlanRoot $planRoot -TaskId $taskId -EvidenceContextJson $fixtureContext | Out-Null
    $rejected = $false
    try { & $dispatcher @common -EvidenceBootstrap | Out-Null } catch { $rejected = $true }
    Assert-True $rejected "A contract regression was incorrectly allowed to bootstrap real-task evidence."
    Write-Host "[PASS] Real-task evidence bootstrap accepts only a frozen real-source plan and rejects contract regressions."
} finally {
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force }
}
