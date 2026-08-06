param(
    [Parameter(Mandatory = $true)][string]$ReceiptPath,
    [Parameter(Mandatory = $true)][string]$ArtifactManifestPath,
    [string]$PromotionMainCommit = "",
    [string]$ProjectRoot = ""
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
function Require([bool]$Condition, [string]$Message) { if (-not $Condition) { throw "Candidate host receipt gate failed: $Message" } }
foreach ($path in @($ReceiptPath, $ArtifactManifestPath)) { Require (Test-Path -LiteralPath $path -PathType Leaf) "missing file: $path" }
$receipt = Get-Content -LiteralPath $ReceiptPath -Raw -Encoding UTF8 | ConvertFrom-Json
$artifact = Get-Content -LiteralPath $ArtifactManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$intent = Get-Content -LiteralPath (Join-Path $ProjectRoot "config\release-intent.json") -Raw -Encoding UTF8 | ConvertFrom-Json
Require ([string]$receipt.schema -eq "codex-praetor-candidate-host-receipt/v2") "wrong schema"
Require ([string]$receipt.status -eq "accepted") "host receipt is not accepted"
Require ([string]$artifact.status -eq "artifact_verified") "artifact is not verified"
Require (([string]$receipt.artifact.zip_sha256).ToLowerInvariant() -eq ([string]$artifact.artifact.sha256).ToLowerInvariant()) "ZIP SHA differs from the verified candidate"
Require ([string]$receipt.candidate.version -eq [string]$intent.version) "version differs from release intent"
Require ([string]$receipt.candidate.generation_id -eq [string]$artifact.generation.id) "generation differs from artifact generation"
Require (([string]$receipt.candidate.runtime_contract_sha256).ToLowerInvariant() -eq ([string]$artifact.generation.runtime_contract_sha256).ToLowerInvariant()) "runtime contract differs from artifact generation"
Require ([string]$receipt.host_runtime.version -eq [string]$receipt.candidate.version) "host version differs from candidate"
Require ([string]$receipt.host_runtime.generation_id -eq [string]$receipt.candidate.generation_id) "host generation differs from candidate"
Require (([string]$receipt.host_runtime.runtime_contract_sha256).ToLowerInvariant() -eq ([string]$receipt.candidate.runtime_contract_sha256).ToLowerInvariant()) "host runtime contract differs from candidate"
Require ([string]$receipt.user_path.evidence_sha256 -match '^[0-9a-f]{64}$') "user-path evidence hash is missing or malformed"
Require ([string]$receipt.user_path.entry.kind -eq "new_task_execution_mode") "candidate host receipt does not prove the execution-mode entry"
Require ([string]$receipt.user_path.route.result -eq "delegated_code_change") "candidate host receipt does not prove code-change routing"
Require ([string]$receipt.user_path.preflight.kind -eq "real_code_change" -and $receipt.user_path.preflight.worker_started -eq $false) "candidate host receipt does not prove the non-starting code-change preflight"
Require (-not [string]::IsNullOrWhiteSpace([string]$receipt.user_path.dispatch.job_id) -and $receipt.user_path.dispatch.worker_started -eq $true) "candidate host receipt does not prove worker startup"
Require ([string]$receipt.user_path.completion.status -eq "process_exited" -and [int]$receipt.user_path.completion.exit_code -eq 0) "candidate host receipt does not prove worker completion"
Require ([string]$receipt.user_path.acceptance.verdict -eq "accepted" -and $receipt.user_path.acceptance.required_checks_passed -eq $true) "candidate host receipt does not prove Codex acceptance"
if (-not [string]::IsNullOrWhiteSpace($PromotionMainCommit)) {
    $tree = ((& git -C $ProjectRoot rev-parse ($PromotionMainCommit + "^{tree}") 2>$null | Out-String).Trim()).ToLowerInvariant()
    Require ($tree -match '^[0-9a-f]{40}$') "promotion main tree is unavailable"
    Require (([string]$receipt.candidate.content_tree).ToLowerInvariant() -eq $tree) "candidate host receipt tree differs from promoted main"
}
Write-Host "[PASS] Candidate host receipt gate: PR #$($receipt.pull_request.number), generation=$($receipt.candidate.generation_id)."
