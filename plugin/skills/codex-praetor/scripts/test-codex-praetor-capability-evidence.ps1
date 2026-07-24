param(
    [Parameter(Mandatory = $true)][ValidateSet("read_only_diagnosis", "bounded_code_change", "fixed_test_execution", "failure_recovery")][string]$TaskFamily,
    [Parameter(Mandatory = $true)][string]$Provider,
    [Parameter(Mandatory = $true)][string]$CliPath,
    [Parameter(Mandatory = $true)][string]$CliHash,
    [Parameter(Mandatory = $true)][string]$Model,
    [Parameter(Mandatory = $true)][string]$PermissionProfile,
    [Parameter(Mandatory = $true)][string]$TaskKind,
    [Parameter(Mandatory = $true)][string]$GenerationId,
    [Parameter(Mandatory = $true)][string]$RuntimeContractSha256,
    [Parameter(Mandatory = $true)][string]$TaskContractSchema,
    [string]$EvidenceRoot = "$env:USERPROFILE\.codex\codex-praetor-capability-evidence",
    [ValidateRange(1, 100)][int]$MinimumAccepted = 3,
    [ValidateRange(1, 365)][int]$MaximumAgeDays = 30
)
$ErrorActionPreference = "Stop"
function Get-StringProperty { param([object]$Object, [string]$Name) if ($null -eq $Object) { return "" }; $property = $Object.PSObject.Properties[$Name]; if ($null -eq $property -or $null -eq $property.Value) { return "" }; return [string]$property.Value }
$expected = [ordered]@{ provider = $Provider; cli_path = $CliPath; cli_hash = $CliHash; model = $Model; permission_profile = $PermissionProfile; task_kind = $TaskKind; generation_id = $GenerationId; runtime_contract_sha256 = $RuntimeContractSha256; task_contract_schema = $TaskContractSchema }
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
$allowed = $acceptedIds.Count -ge $MinimumAccepted
[ordered]@{ schema = "codex-praetor-capability-gate/v1"; allowed = $allowed; reason = if ($allowed) { "Fresh accepted evidence satisfies the exact provider tuple and task family." } else { "Normal dispatch requires $MinimumAccepted fresh accepted receipts for this exact provider tuple and task family." }; task_family = $TaskFamily; minimum_accepted = $MinimumAccepted; maximum_age_days = $MaximumAgeDays; accepted_evidence_ids = @($acceptedIds); accepted_count = $acceptedIds.Count } | ConvertTo-Json -Depth 5 -Compress
