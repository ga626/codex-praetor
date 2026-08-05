param(
    [Parameter(Mandatory = $true)][ValidateSet("read_only_diagnosis", "bounded_code_change", "fixed_test_execution", "failure_recovery")][string]$TaskFamily,
    [Parameter(Mandatory = $true)][string]$Provider,
    [Parameter(Mandatory = $true)][string]$CliPath,
    [Parameter(Mandatory = $true)][string]$CliHash,
    [Parameter(Mandatory = $true)][string]$Model,
    [Parameter(Mandatory = $true)][string]$PermissionProfile,
    [Parameter(Mandatory = $true)][string]$TaskKind,
    [Parameter(Mandatory = $true)][string]$Distribution,
    [string]$ConnectionMode = "",
    [string]$RunnerIdentity = "",
    [string]$EvidenceRoot = "$env:USERPROFILE\.codex\codex-praetor-capability-evidence",
    [ValidateRange(1, 365)][int]$MaximumAgeDays = 30
)
$ErrorActionPreference = "Stop"
function Get-StringProperty { param([object]$Object, [string]$Name) if ($null -eq $Object) { return "" }; $property = $Object.PSObject.Properties[$Name]; if ($null -eq $property -or $null -eq $property.Value) { return "" }; return [string]$property.Value }
$expected = [ordered]@{ provider = $Provider; distribution = $Distribution; cli_path = $CliPath; cli_hash = $CliHash; model = $Model; permission_profile = $PermissionProfile; task_kind = $TaskKind; connection_mode = $ConnectionMode; runner_identity = $RunnerIdentity }
$acceptedIds = New-Object System.Collections.Generic.List[string]
$cutoff = (Get-Date).ToUniversalTime().AddDays(-$MaximumAgeDays)
if (Test-Path -LiteralPath $EvidenceRoot -PathType Container) {
    foreach ($file in Get-ChildItem -LiteralPath $EvidenceRoot -Filter "*.json" -File -ErrorAction SilentlyContinue) {
        try {
            $receipt = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            if ((Get-StringProperty $receipt "schema") -ne "codex-praetor-capability-evidence/v1" -or (Get-StringProperty $receipt "supervisor_verdict") -ne "accepted" -or (Get-StringProperty $receipt "task_family") -ne $TaskFamily) { continue }
            $evidenceId = Get-StringProperty $receipt "evidence_id"; if ([string]::IsNullOrWhiteSpace($evidenceId) -or $acceptedIds.Contains($evidenceId)) { continue }
            $acceptedAt = [DateTime]::MinValue; if (-not [DateTime]::TryParse((Get-StringProperty $receipt "accepted_at"), [ref]$acceptedAt) -or $acceptedAt.ToUniversalTime() -lt $cutoff) { continue }
            $sameTuple = $true; foreach ($name in $expected.Keys) { if ((Get-StringProperty $receipt.provider_tuple $name) -ne [string]$expected[$name]) { $sameTuple = $false; break } }
            if ($sameTuple) { [void]$acceptedIds.Add($evidenceId) }
        } catch { }
    }
}
$wellObserved = $acceptedIds.Count -ge 3
[ordered]@{ schema = "codex-praetor-capability-gate/v2"; allowed = $true; reason = if ($wellObserved) { "Worker identity is well observed; normal dispatch remains subject to current safety and acceptance contracts." } else { "No warm-up task is required. This real task may establish worker evidence after Codex accepts it." }; task_family = $TaskFamily; well_observed = $wellObserved; well_observed_minimum_accepted = 3; maximum_age_days = $MaximumAgeDays; accepted_evidence_ids = @($acceptedIds); accepted_count = $acceptedIds.Count; controller_validation_is_separate = $true } | ConvertTo-Json -Depth 5 -Compress
