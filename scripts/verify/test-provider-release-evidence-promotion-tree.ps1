param([string]$ProjectRoot = "")

$ErrorActionPreference = "Stop"
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) {
    $previousNativeErrorPreference = $global:PSNativeCommandUseErrorActionPreference
    $global:PSNativeCommandUseErrorActionPreference = $false
}
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$root = [System.IO.Path]::GetFullPath($ProjectRoot)
$validator = Join-Path $root "scripts\verify\test-provider-release-evidence.ps1"
$scratch = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-praetor-promotion-tree-" + [Guid]::NewGuid().ToString("N"))

function Assert-True([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Write-Utf8Json([string]$Path, $Value) { [IO.File]::WriteAllText($Path, (($Value | ConvertTo-Json -Depth 12) + [Environment]::NewLine), (New-Object Text.UTF8Encoding($false))) }

try {
    New-Item -ItemType Directory -Path $scratch -Force | Out-Null
    $head = ((& git -C $root rev-parse HEAD | Out-String).Trim()).ToLowerInvariant()
    $tree = ((& git -C $root rev-parse ("$head" + "^{tree}") | Out-String).Trim()).ToLowerInvariant()
    $candidate = ((& git -C $root -c user.name="Codex Praetor Fixture" -c user.email="fixture@example.invalid" commit-tree $tree -p $head -m "promotion candidate fixture" | Out-String).Trim()).ToLowerInvariant()
    Assert-True ($candidate -match '^[0-9a-f]{40}$' -and $candidate -ne $head) "Fixture must create a candidate commit distinct from promoted main HEAD."
    $intent = Get-Content -LiteralPath (Join-Path $root "config\release-intent.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    . (Join-Path $root "scripts\shared\get-provider-compatibility-impact.ps1")
    # Exercise only promotion identity. The validator computes the
    # compatibility surface from the checkout it receives, including an
    # intentionally dirty pre-commit test checkout, so this fixture must use
    # the same view rather than a historical revision.
    $surface = Get-CodexPraetorProviderCompatibilitySurfaceHash -Repo $root
    $artifactPath = Join-Path $scratch "artifact.json"
    $evidencePath = Join-Path $scratch "evidence.json"
    $artifact = [ordered]@{ status="artifact_verified"; generation=[ordered]@{ commit=$candidate; source_tree=$tree }; artifact=[ordered]@{ sha256=("a" * 64) } }
    $evidence = [ordered]@{ schema="codex-praetor-provider-release-evidence/v2"; status="accepted"; product="codex-praetor"; version=[string]$intent.version; head=$candidate; artifact_sha256=("a" * 64); provider_surface_sha256=$surface; compatibility_scope="unchanged"; providers=@() }
    Write-Utf8Json $artifactPath $artifact
    Write-Utf8Json $evidencePath $evidence
    & powershell -NoProfile -ExecutionPolicy Bypass -File $validator -ProjectRoot $root -EvidencePath $evidencePath -ArtifactManifestPath $artifactPath -BaseRef $head -PromotionMainCommit $head
    if ($LASTEXITCODE -ne 0) { throw "Same-tree promotion candidate was rejected." }
    $artifact.generation.source_tree = ("0" * 40)
    Write-Utf8Json $artifactPath $artifact
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    & powershell -NoProfile -ExecutionPolicy Bypass -File $validator -ProjectRoot $root -EvidencePath $evidencePath -ArtifactManifestPath $artifactPath -BaseRef $head -PromotionMainCommit $head 2>$null
    $rejectedExitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorActionPreference
    Assert-True ($rejectedExitCode -ne 0) "Promotion with a different source tree must be rejected."
    Write-Output "[PASS] Promotion accepts an immutable PR artifact only when its source tree equals the merged main tree."
} finally {
    if (Get-Variable -Name previousNativeErrorPreference -ErrorAction SilentlyContinue) { $global:PSNativeCommandUseErrorActionPreference = $previousNativeErrorPreference }
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}
