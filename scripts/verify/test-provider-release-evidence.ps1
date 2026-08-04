param(
    [string]$ProjectRoot = "",
    [string]$EvidencePath = "",
    [string]$ArtifactManifestPath = "",
    [string]$BaseRef = ""
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$root = [System.IO.Path]::GetFullPath($ProjectRoot)
if ([string]::IsNullOrWhiteSpace($EvidencePath)) { $EvidencePath = Join-Path $root ".codex-praetor\provider-release-evidence.json" }
if ([string]::IsNullOrWhiteSpace($ArtifactManifestPath)) {
    $intent = Get-Content -LiteralPath (Join-Path $root "config\release-intent.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    $ArtifactManifestPath = Join-Path $root (".codex-praetor\releases\codex-praetor-setup-" + [string]$intent.version + ".artifact.json")
}
. (Join-Path $root "scripts\shared\get-provider-compatibility-impact.ps1")

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

Require ([string]$evidence.schema -eq "codex-praetor-provider-release-evidence/v2") "schema is not provider-release-evidence/v2"
Require ([string]$evidence.status -eq "accepted") "overall status must be accepted"
Require ([string]$evidence.product -eq "codex-praetor") "product is not codex-praetor"
Require ([string]$evidence.version -eq [string]$intent.version) "evidence version does not match release intent"
Require ($artifactCommit -match '^[0-9a-f]{40}$') "artifact generation commit is missing or malformed"
$evidenceHead = ([string]$evidence.head).ToLowerInvariant()
$evidenceSurfaceHash = ([string]$evidence.provider_surface_sha256).ToLowerInvariant()
Require ($artifactCommit -eq $head) "artifact generation commit does not match candidate HEAD"
Require ($evidenceHead -eq $artifactCommit) "evidence binding head does not match the artifact generation commit"
Require ($evidenceSurfaceHash -match '^[0-9a-f]{64}$') "evidence provider_surface_sha256 is missing or malformed"
Require ($evidenceSurfaceHash -eq (Get-CodexPraetorProviderCompatibilitySurfaceHash -Repo $root)) "provider compatibility surface differs from the accepted evidence"
Require ($artifact.status -eq "artifact_verified") "artifact manifest is not artifact_verified"
Require ([string]$evidence.artifact_sha256.ToLowerInvariant() -eq $artifactSha) "evidence artifact SHA does not match the verified artifact"
Require ([string]$runtime.version -eq [string]$intent.version) "runtime contract version does not match release intent"
$compatibilityScope = [string]$evidence.compatibility_scope
Require ($compatibilityScope -in @("unchanged", "changed")) "compatibility_scope must be unchanged or changed"

$expectedProviders = Get-CodexPraetorProviderCompatibilityImpact -Repo $root -ComparisonBase $BaseRef -TargetRef $artifactCommit
if ($expectedProviders.Count -eq 0) {
    Require ($compatibilityScope -eq "unchanged") "non-provider changes must declare compatibility_scope=unchanged"
    Require (@($evidence.providers).Count -eq 0) "unchanged compatibility must not demand or claim provider-credit runs"
} else {
    Require ($compatibilityScope -eq "changed") "provider compatibility changes must declare compatibility_scope=changed"
    $providers = @($evidence.providers | ForEach-Object { [string]$_.provider } | Sort-Object)
    Require (($providers -join ",") -eq ($expectedProviders -join ",")) "provider evidence does not match the affected compatibility tuples: expected=$($expectedProviders -join ',') observed=$($providers -join ',')"
}
$seenJobs = @{}
foreach ($entry in @($evidence.providers)) {
    $provider = [string]$entry.provider
    $expectedConnection = if ($provider -eq "qoder") { "qoder_agent_sdk" } else { "codebuddy_acp" }
    Require ([string]$entry.evidence_kind -eq "real_task") "$provider evidence is not a real task"
    Require ([string]$entry.connection_mode -eq $expectedConnection) "$provider connection mode is not the approved adapter"
    Require (-not [string]::IsNullOrWhiteSpace([string]$entry.model)) "$provider model is missing"
    Require ([string]$entry.cli_hash -match '^[0-9a-fA-F]{64}$') "$provider CLI hash is missing or malformed"
    Require ([string]$entry.provider_compatibility_fingerprint -match '^[0-9a-fA-F]{64}$') "$provider compatibility fingerprint is missing or malformed"
    Require ([string]$entry.completion_status -eq "process_exited" -and [int]$entry.exit_code -eq 0) "$provider real task did not exit successfully"
    Require ([string]$entry.evidence_state -eq "report_valid") "$provider evidence is not report_valid"
    Require ([string]$entry.artifact_state -eq "report_observed") "$provider artifact observation is missing"
    Require ([string]$entry.governance_state -eq "accepted" -and $entry.accepted -eq $true) "$provider task was not accepted by Codex"
    Require ($entry.repository_clean -eq $true) "$provider task did not leave a clean repository"
    Require (-not [string]::IsNullOrWhiteSpace([string]$entry.job_id)) "$provider job_id is missing"
    Require (-not $seenJobs.ContainsKey([string]$entry.job_id)) "duplicate job_id: $($entry.job_id)"
    $seenJobs[[string]$entry.job_id] = $true
}

Write-Output "[PASS] Provider release evidence gate: compatibility_scope=$compatibilityScope affected=$($expectedProviders -join ',') real_provider_runs=$(@($evidence.providers).Count)."
Write-Output "current_head=$head"
Write-Output "artifact_generation_commit=$artifactCommit"
Write-Output "artifact_sha256=$artifactSha"
