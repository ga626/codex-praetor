param([string]$ProjectRoot = "")

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$root = [System.IO.Path]::GetFullPath($ProjectRoot)
$manager = Join-Path $root "scripts\dispatch\manage-codex-praetor-plan.ps1"
$scratch = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-praetor-acceptance-" + [Guid]::NewGuid().ToString("N"))

function Assert-True([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Invoke-Manager([string[]]$Arguments, [switch]$SuppressErrors) {
    if ($SuppressErrors) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $manager @Arguments 2>$null | Out-Null
    } else {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $manager @Arguments | Out-Null
    }
    if ($LASTEXITCODE -ne 0) { throw "Plan manager failed: $($Arguments -join ' ')" }
}

try {
    New-Item -ItemType Directory -Path $scratch -Force | Out-Null
    $repo = Join-Path $scratch "repo"
    New-Item -ItemType Directory -Path $repo -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $repo "README.md") -Value "fixture" -Encoding ASCII
    & git -C $repo init -q
    & git -C $repo config user.email "acceptance-test@example.invalid"
    & git -C $repo config user.name "Codex Praetor test"
    & git -C $repo add README.md
    & git -C $repo commit -qm "fixture"
    if ($LASTEXITCODE -ne 0) { throw "Unable to create acceptance fixture repository." }
    $planRoot = Join-Path $scratch "plans"
    $planId = "acceptance-gate"
    $jobDir = Join-Path $scratch "job"
    New-Item -ItemType Directory -Path $jobDir -Force | Out-Null
    $contractPath = Join-Path $jobDir "contract.json"
    [ordered]@{ required_checks = @("Test-Path README.md") } | ConvertTo-Json | Set-Content -LiteralPath $contractPath -Encoding UTF8
    [ordered]@{ execution_repo = $repo; task_contract = $contractPath; stdout = (Join-Path $jobDir "stdout.log") } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $jobDir "job.json") -Encoding UTF8
    [ordered]@{ job_id = "acceptance-gate"; status = "process_exited"; exit_code = 0; failure_class = "" } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $jobDir "completion.json") -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $jobDir "stdout.log") -Value "CODEX_PRAETOR_REQUIRED_CHECKS_OK" -Encoding ASCII
    Invoke-Manager @("-Action","Init","-PlanId",$planId,"-PlanRoot",$planRoot,"-Repo",$repo)
    Invoke-Manager @("-Action","UpsertTask","-PlanId",$planId,"-PlanRoot",$planRoot,"-TaskId","test","-TaskKind","test_execution","-Mode","readonly","-Status","awaiting_verification")
    Invoke-Manager @("-Action","RecordJob","-PlanId",$planId,"-PlanRoot",$planRoot,"-TaskId","test","-JobDir",$jobDir,"-CompletionPath",(Join-Path $jobDir "completion.json"))
    Invoke-Manager @("-Action","VerifyTask","-PlanId",$planId,"-PlanRoot",$planRoot,"-TaskId","test","-VerificationVerdict","accepted")
    Set-Content -LiteralPath (Join-Path $repo "drift.txt") -Value "drift" -Encoding ASCII
    $rejected = $false
    try { Invoke-Manager @("-Action","VerifyTask","-PlanId",$planId,"-PlanRoot",$planRoot,"-TaskId","test","-VerificationVerdict","accepted") -SuppressErrors } catch { $rejected = $true }
    Assert-True $rejected "Readonly worktree drift was accepted."
    Write-Output "[PASS] Plan acceptance gate requires a clean completion, readonly worktree, declared check and worker success marker."
} finally {
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}
