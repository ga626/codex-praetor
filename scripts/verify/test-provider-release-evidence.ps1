param(
    [string]$ProjectRoot = "",
    [string]$EvidencePath = "",
    [string]$ArtifactManifestPath = ""
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$root = [System.IO.Path]::GetFullPath($ProjectRoot)
if ([string]::IsNullOrWhiteSpace($EvidencePath)) { $EvidencePath = Join-Path $root ".codex-praetor\provider-release-evidence.json" }
if ([string]::IsNullOrWhiteSpace($ArtifactManifestPath)) {
    $intent = Get-Content -LiteralPath (Join-Path $root "config\release-intent.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    $ArtifactManifestPath = Join-Path $root (".codex-praetor\releases\codex-praetor-setup-" + [string]$intent.version + ".artifact.json")
}

function Fail([string]$Message) { throw "Provider release evidence gate failed: $Message" }
function Require([bool]$Condition, [string]$Message) { if (-not $Condition) { Fail $Message } }
function Read-Json([string]$Path) {
    Require (Test-Path -LiteralPath $Path -PathType Leaf) "Missing JSON file: $Path"
    try { return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json } catch { Fail "Invalid JSON: $Path :: $($_.Exception.Message)" }
}

$evidence = Read-Json $EvidencePath
$artifact = Read-Json $ArtifactManifestPath
$intent = Read-Json (Join-Path $root "config\release-intent.json")
$runtime = Read-Json (Join-Path $root "config\runtime-contract.json")
$head = ((& git -C $root rev-parse HEAD | Out-String).Trim()).ToLowerInvariant()
$artifactSha = ([string]$artifact.artifact.sha256).ToLowerInvariant()
$artifactCommit = ([string]$artifact.generation.commit).ToLowerInvariant()
$sourceTree = ([string]$artifact.generation.source_tree).ToLowerInvariant()

Require ([string]$evidence.schema -eq "codex-praetor-provider-release-evidence/v1") "schema is not provider-release-evidence/v1"
Require ([string]$evidence.status -eq "accepted") "overall status must be accepted"
Require ([string]$evidence.product -eq "codex-praetor") "product is not codex-praetor"
Require ([string]$evidence.version -eq [string]$intent.version) "evidence version does not match release intent"
Require ($artifactCommit -match '^[0-9a-f]{40}$') "artifact generation commit is missing or malformed"
Require ($sourceTree -match '^[0-9a-f]{40}$') "artifact source tree is missing or malformed"
$evidenceHead = ([string]$evidence.head).ToLowerInvariant()
$evidenceSourceHead = ([string]$evidence.source_head).ToLowerInvariant()
$headMatches = $evidenceHead -eq $artifactCommit
if (-not $headMatches -and $evidenceSourceHead -match '^[0-9a-f]{40}$') {
    $observedTree = ((& git -C $root rev-parse "$evidenceSourceHead^{tree}" 2>$null | Out-String).Trim()).ToLowerInvariant()
    $headMatches = $observedTree -eq $sourceTree
}
Require $headMatches "evidence head/source_head does not match the artifact generation commit or source tree"
Require ($artifact.status -eq "artifact_verified") "artifact manifest is not artifact_verified"
Require ([string]$evidence.artifact_sha256.ToLowerInvariant() -eq $artifactSha) "evidence artifact SHA does not match the verified artifact"
Require ([string]$runtime.version -eq [string]$intent.version) "runtime contract version does not match release intent"
Require (@($evidence.providers).Count -eq 2) "exactly two provider evidence entries are required"

$providers = @($evidence.providers | ForEach-Object { [string]$_.provider } | Sort-Object)
Require (($providers -join ",") -eq "codebuddy,qoder") "provider evidence must contain exactly CodeBuddy and Qoder"
$seenJobs = @{}
foreach ($entry in @($evidence.providers)) {
    $provider = [string]$entry.provider
    $expectedConnection = if ($provider -eq "qoder") { "qoder_agent_sdk" } else { "codebuddy_acp" }
    Require ([string]$entry.evidence_kind -eq "real_task") "$provider evidence is not a real task"
    Require ([string]$entry.connection_mode -eq $expectedConnection) "$provider connection mode is not the approved adapter"
    Require (-not [string]::IsNullOrWhiteSpace([string]$entry.model)) "$provider model is missing"
    Require ([string]$entry.cli_hash -match '^[0-9a-fA-F]{64}$') "$provider CLI hash is missing or malformed"
    Require ([string]$entry.generation_id -eq [string]$artifact.generation.id) "$provider generation does not match the artifact"
    Require ([string]$entry.runtime_contract_sha256.ToLowerInvariant() -eq [string]$artifact.generation.runtime_contract_sha256.ToLowerInvariant()) "$provider runtime contract hash does not match the artifact"
    Require ([string]$entry.canary.status -eq "accepted" -and -not [string]::IsNullOrWhiteSpace([string]$entry.canary.job_id)) "$provider has no accepted canary evidence"
    Require ([string]$entry.completion_status -eq "process_exited" -and [int]$entry.exit_code -eq 0) "$provider real task did not exit successfully"
    Require ([string]$entry.evidence_state -eq "report_valid") "$provider evidence is not report_valid"
    Require ([string]$entry.artifact_state -eq "report_observed") "$provider artifact observation is missing"
    Require ([string]$entry.governance_state -eq "accepted" -and $entry.accepted -eq $true) "$provider task was not accepted by Codex"
    Require ($entry.repository_clean -eq $true) "$provider task did not leave a clean repository"
    Require (-not [string]::IsNullOrWhiteSpace([string]$entry.job_id)) "$provider job_id is missing"
    Require (-not $seenJobs.ContainsKey([string]$entry.job_id)) "duplicate job_id: $($entry.job_id)"
    $seenJobs[[string]$entry.job_id] = $true
}

Write-Output "[PASS] Provider release hard gate: Qoder and CodeBuddy each have an accepted real task on the same verified artifact."
Write-Output "current_head=$head"
Write-Output "artifact_generation_commit=$artifactCommit"
Write-Output "artifact_sha256=$artifactSha"
