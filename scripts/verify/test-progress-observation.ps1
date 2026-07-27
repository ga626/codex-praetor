param([string]$ProjectRoot = "")
$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$manager = Join-Path $ProjectRoot "scripts\dispatch\manage-codex-praetor-plan.ps1"
$observer = Join-Path $ProjectRoot "scripts\dispatch\record-codex-praetor-observation.ps1"
$root = Join-Path ([IO.Path]::GetTempPath()) ("codex-praetor-observation-" + [Guid]::NewGuid().ToString("N"))
try {
    & $manager -Action Init -PlanId observation -PlanRoot $root -Title observation -Repo $ProjectRoot | Out-Null
    & $manager -Action UpsertTask -PlanId observation -PlanRoot $root -TaskId task -TaskTitle task -Status pending | Out-Null
    & $observer -PlanId observation -PlanRoot $root -TaskId task -Phase codex_direct_started -PairId pair-1 -TransportMode codex_direct -ObservedAt 2026-07-27T00:00:00Z | Out-Null
    & $observer -PlanId observation -PlanRoot $root -TaskId task -Phase route_completed -PairId pair-1 -TransportMode supervised_cli_text -EvidenceJson '{"route":"qoder"}' -ObservedAt 2026-07-27T00:00:02Z | Out-Null
    $plan = Get-Content -LiteralPath (Join-Path $root "observation\plan.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    $events = @($plan.events | Where-Object { $_.type -in @("codex_direct_started", "route_completed") })
    if ($events.Count -ne 2) { throw "Expected two observation events." }
    if ([string]$events[1].data.pair_id -ne "pair-1" -or [string]$events[1].data.transport_mode -ne "supervised_cli_text") { throw "Observation did not preserve pairing or transport mode." }
    Write-Output "[PASS] Progress observation records paired timing phases without dispatching a worker."
} finally { if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue } }
