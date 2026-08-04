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
. (Join-Path $root "scripts\shared\get-provider-compatibility-impact.ps1")

function Require([bool]$Condition, [string]$Message) { if (-not $Condition) { throw "Provider release evidence binding failed: $Message" } }
function Read-Json([string]$Path) {
    Require (Test-Path -LiteralPath $Path -PathType Leaf) "Missing JSON file: $Path"
    try { return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json } catch { throw "Provider release evidence binding failed: Invalid JSON: $Path :: $($_.Exception.Message)" }
}

$evidence = Read-Json $EvidencePath
$artifact = Read-Json $ArtifactManifestPath
$artifactCommit = ([string]$artifact.generation.commit).ToLowerInvariant()
$artifactSha = ([string]$artifact.artifact.sha256).ToLowerInvariant()
$surfaceHash = ([string]$evidence.provider_surface_sha256).ToLowerInvariant()
Require ($artifact.status -eq "artifact_verified") "artifact manifest is not artifact_verified"
Require ($artifactCommit -match '^[0-9a-f]{40}$') "artifact generation commit is missing or malformed"
Require ($artifactSha -match '^[0-9a-f]{64}$') "artifact SHA is missing or malformed"
Require ($surfaceHash -match '^[0-9a-f]{64}$') "evidence provider_surface_sha256 is missing or malformed"
$currentSurfaceHash = Get-CodexPraetorProviderCompatibilitySurfaceHash -Repo $root
Require ($surfaceHash -eq $currentSurfaceHash) "provider compatibility surface differs from the accepted evidence"

$evidence.head = $artifactCommit
$evidence.artifact_sha256 = $artifactSha
if ($evidence.PSObject.Properties.Name -contains "bound_at") { $evidence.bound_at = [DateTime]::UtcNow.ToString("o") } else { $evidence | Add-Member -NotePropertyName "bound_at" -NotePropertyValue ([DateTime]::UtcNow.ToString("o")) }
[IO.File]::WriteAllText($EvidencePath, (($evidence | ConvertTo-Json -Depth 20) + [Environment]::NewLine), (New-Object Text.UTF8Encoding($false)))
Write-Output "[PASS] Provider evidence rebound to immutable artifact: provider_surface_sha256=$surfaceHash artifact_commit=$artifactCommit artifact_sha256=$artifactSha"
