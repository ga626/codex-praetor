param([string]$ProjectRoot = "")
$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$manager = Join-Path $ProjectRoot "scripts\dispatch\manage-codex-praetor-plan.ps1"
$watcher = Join-Path $ProjectRoot "scripts\dispatch\watch-codex-praetor-job.ps1"
$scratch = Join-Path ([IO.Path]::GetTempPath()) ("codex-praetor-observed-lifecycle-" + [Guid]::NewGuid().ToString("N"))
try {
    $planRoot = Join-Path $scratch "plans"
    $jobDir = Join-Path $scratch "job"
    New-Item -ItemType Directory -Path $jobDir -Force | Out-Null
    & $manager -Action Init -PlanId observed -PlanRoot $planRoot -Title observed -Repo $ProjectRoot | Out-Null
    & $manager -Action UpsertTask -PlanId observed -PlanRoot $planRoot -TaskId task -TaskTitle task -Status running | Out-Null
    $argsPath = Join-Path $jobDir "args.json"
    @("-NoProfile", "-Command", "Write-Output worker-report; exit 0") | ConvertTo-Json | Set-Content -LiteralPath $argsPath -Encoding UTF8
    $stdout = Join-Path $jobDir "stdout.log"
    $stderr = Join-Path $jobDir "stderr.log"
    $completion = Join-Path $jobDir "completion.json"
    [ordered]@{
        job_id = "observed-job"; provider = "qoder"; tier = "fixture"; model = "fixture"; output_format = "text"
        plan_id = "observed"; task_id = "task"; plan_root = $planRoot; repo = $ProjectRoot; execution_repo = $ProjectRoot
        task_kind = "local_audit"; mode = "readonly"; stdout = $stdout; stderr = $stderr; completion = $completion
        created_at = (Get-Date).ToUniversalTime().ToString("o"); status = "starting"
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $jobDir "job.json") -Encoding UTF8
    & powershell -NoProfile -ExecutionPolicy Bypass -File $watcher -JobDir $jobDir -WorkerPid 0 -StartWorker -Exe powershell.exe -ArgumentListPath $argsPath -WorkingDirectory $ProjectRoot -StdoutPath $stdout -StderrPath $stderr -TimeoutSeconds 30 -NoNotify | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Observed lifecycle watcher did not complete." }
    $plan = Get-Content -LiteralPath (Join-Path $planRoot "observed\plan.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    $events = @($plan.events | Where-Object { $_.type -in @("worker_started", "worker_terminal") })
    if ($events.Count -ne 2) { throw "Expected worker_started and worker_terminal observations." }
    if ([string]$events[0].data.transport_mode -ne "supervised_cli_text") { throw "Worker observation did not retain text CLI transport." }
    if ([string]$events[1].data.evidence.status -ne "process_exited") { throw "Worker terminal observation did not retain the terminal state." }
    Write-Output "[PASS] Watcher records low-frequency worker lifecycle observations into the durable plan."
} finally {
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}
