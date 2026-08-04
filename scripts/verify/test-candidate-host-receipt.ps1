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
Require ([string]$receipt.schema -eq "codex-praetor-candidate-host-receipt/v1") "wrong schema"
Require ([string]$receipt.status -eq "accepted") "host receipt is not accepted"
Require ([string]$artifact.status -eq "artifact_verified") "artifact is not verified"
Require (([string]$receipt.artifact.zip_sha256).ToLowerInvariant() -eq ([string]$artifact.artifact.sha256).ToLowerInvariant()) "ZIP SHA differs from the verified candidate"
Require ([string]$receipt.candidate.version -eq [string]$intent.version) "version differs from release intent"
Require ([string]$receipt.candidate.generation_id -eq [string]$artifact.generation.id) "generation differs from artifact generation"
Require (([string]$receipt.candidate.runtime_contract_sha256).ToLowerInvariant() -eq ([string]$artifact.generation.runtime_contract_sha256).ToLowerInvariant()) "runtime contract differs from artifact generation"
Require ([string]$receipt.host_runtime.version -eq [string]$receipt.candidate.version) "host version differs from candidate"
Require ([string]$receipt.host_runtime.generation_id -eq [string]$receipt.candidate.generation_id) "host generation differs from candidate"
Require (([string]$receipt.host_runtime.runtime_contract_sha256).ToLowerInvariant() -eq ([string]$receipt.candidate.runtime_contract_sha256).ToLowerInvariant()) "host runtime contract differs from candidate"
if (-not [string]::IsNullOrWhiteSpace($PromotionMainCommit)) {
    $tree = ((& git -C $ProjectRoot rev-parse ($PromotionMainCommit + "^{tree}") 2>$null | Out-String).Trim()).ToLowerInvariant()
    Require ($tree -match '^[0-9a-f]{40}$') "promotion main tree is unavailable"
    Require (([string]$receipt.candidate.content_tree).ToLowerInvariant() -eq $tree) "candidate host receipt tree differs from promoted main"
}
Write-Host "[PASS] Candidate host receipt gate: PR #$($receipt.pull_request.number), generation=$($receipt.candidate.generation_id)."
