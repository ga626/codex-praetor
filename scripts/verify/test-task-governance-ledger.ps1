param([string]$ProjectRoot = "")

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$planScript = Join-Path $ProjectRoot "scripts\dispatch\manage-codex-praetor-plan.ps1"
$root = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-praetor-ledger-" + [Guid]::NewGuid().ToString("N"))

function Assert-True { param([bool]$Condition, [string]$Message) if (-not $Condition) { throw $Message } }

try {
    & $planScript -Action Init -PlanId ledger -PlanRoot $root -Title ledger -Repo $ProjectRoot | Out-Null
    & $planScript -Action UpsertTask -PlanId ledger -PlanRoot $root -TaskId producer -TaskTitle producer -Status pending | Out-Null
    & $planScript -Action UpsertTask -PlanId ledger -PlanRoot $root -TaskId consumer -TaskTitle consumer -DependsOn producer -Status pending | Out-Null
    $path = Join-Path $root "ledger\plan.json"
    $plan = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ([string]$plan.schema -eq "codex-praetor-task-ledger/v2") "Ledger schema was not written."
    Assert-True ([int]$plan.revision -ge 3) "Ledger revision was not incremented."
    Assert-True (@($plan.events | Select-Object -ExpandProperty event_id -Unique).Count -eq @($plan.events).Count) "Ledger event ids are not unique."

    & $planScript -Action UpsertTask -PlanId ledger -PlanRoot $root -TaskId producer -Status completed | Out-Null
    $ready = & $planScript -Action NextReady -PlanId ledger -PlanRoot $root -OutputJson
    Assert-True ([string]$ready -notmatch 'consumer') "Process completion without a supervisor verdict unlocked a dependency."

    & $planScript -Action VerifyTask -PlanId ledger -PlanRoot $root -TaskId producer -VerificationVerdict accepted -VerificationSummary accepted | Out-Null
    $ready = & $planScript -Action NextReady -PlanId ledger -PlanRoot $root -OutputJson
    Assert-True ([string]$ready -match 'consumer') "Accepted task did not unlock its dependency."
    $selection = '{"selection_id":"sel-1","provider":"codebuddy","model":"hy3","reason":"fixed model and readonly tuple","expires_at":"2099-01-01T00:00:00Z"}'
    & $planScript -Action RecordSelection -PlanId ledger -PlanRoot $root -TaskId producer -SelectionJson $selection | Out-Null
    $outcome = '{"outcome_id":"out-1","verdict":"accepted","summary":"verified"}'
    & $planScript -Action RecordOutcome -PlanId ledger -PlanRoot $root -TaskId producer -OutcomeJson $outcome | Out-Null
    $summary = & $planScript -Action Summary -PlanId ledger -PlanRoot $root
    Assert-True ([string]$summary -match 'outcomes.*1') "Outcome was not included in compact summary."
    Write-Host "[PASS] Task governance ledger smoke passed."
} finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
