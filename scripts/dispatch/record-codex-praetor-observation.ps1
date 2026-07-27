param(
    [Parameter(Mandatory = $true)][string]$PlanId,
    [Parameter(Mandatory = $true)][string]$TaskId,
    [Parameter(Mandatory = $true)]
    [ValidateSet("codex_direct_started", "codex_direct_evidence", "route_completed", "plan_completed", "dry_run_completed", "dispatch_submitted", "worker_started", "worker_terminal", "verification_finished", "recovery_started", "recovery_finished")]
    [string]$Phase,
    [string]$PlanRoot = "$env:USERPROFILE\.codex\codex-praetor-plans",
    [string]$PairId = "",
    [ValidateSet("", "codex_direct", "supervised_cli_text", "supervised_cli_json", "supervised_cli_stream_json", "qoder_acp", "qoder_sdk", "codebuddy_daemon")]
    [string]$TransportMode = "",
    [string]$EvidenceJson = "",
    [string]$ObservedAt = ""
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ObservedAt)) { $ObservedAt = (Get-Date).ToUniversalTime().ToString("o") }
try { [DateTime]::Parse($ObservedAt) | Out-Null } catch { throw "ObservedAt must be an ISO-8601 timestamp." }
$evidence = if ([string]::IsNullOrWhiteSpace($EvidenceJson)) { $null } else { $EvidenceJson | ConvertFrom-Json }
$data = [ordered]@{ task_id = $TaskId; pair_id = $PairId; transport_mode = $TransportMode; observed_at = $ObservedAt; evidence = $evidence }
$manager = Join-Path $PSScriptRoot "manage-codex-praetor-plan.ps1"
& $manager -Action AppendEvent -PlanId $PlanId -PlanRoot $PlanRoot -EventType $Phase -EventMessage "$Phase observed for task $TaskId." -EventActor codex -EventDataJson ($data | ConvertTo-Json -Depth 20 -Compress)
if (-not $?) { throw "Could not append observation to plan $PlanId." }
