param(
    [string]$ProjectRoot = "",
    [string]$BaseRef = "origin/main",
    [string]$ReceiptPath = "",
    [switch]$CheckRemote,
    [switch]$AllowDraftMetadataPlaceholders
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$root = [IO.Path]::GetFullPath($ProjectRoot)
if ([string]::IsNullOrWhiteSpace($ReceiptPath)) { $ReceiptPath = Join-Path $root ".codex-praetor\receipts\candidate-preflight.json" }
$ReceiptPath = [IO.Path]::GetFullPath($ReceiptPath)

function Invoke-Check {
    param([string]$Name, [string]$File, [string[]]$Arguments = @())
    Write-Host "[RUN] $Name"
    & powershell -NoProfile -ExecutionPolicy Bypass -File $File @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Candidate preflight failed: $Name (exit $LASTEXITCODE)." }
}

Push-Location $root
try {
    & git diff --check
    if ($LASTEXITCODE -ne 0) { throw "Candidate preflight requires a whitespace-clean worktree." }
    $dirty = (& git status --porcelain | Out-String).Trim()
    if (-not [string]::IsNullOrWhiteSpace($dirty)) { throw "Candidate preflight requires a clean committed candidate worktree. Create an isolated worktree at the candidate HEAD, then rerun." }
    $head = ((& git rev-parse HEAD | Out-String).Trim().ToLowerInvariant())
    if ($head -notmatch '^[0-9a-f]{40}$') { throw "Candidate preflight could not resolve HEAD." }

    $verify = Join-Path $root "scripts\verify"
    $release = Join-Path $root "scripts\release"
    $intentArgs = @("-BaseRef", $BaseRef, "-RequireReleaseImpact")
    if ($CheckRemote) { $intentArgs += "-CheckRemote" }
    Invoke-Check "release intent" (Join-Path $verify "test-release-intent.ps1") $intentArgs
    Invoke-Check "release workflow readiness" (Join-Path $verify "test-release-workflow-readiness.ps1") $(if ($CheckRemote) { @("-CheckRemoteActionPins") } else { @() })
    Invoke-Check "release-impact classification" (Join-Path $verify "test-release-intent-classification.ps1")
    Invoke-Check "version surface updater" (Join-Path $verify "test-version-surface-updater.ps1")

    Write-Host "[RUN] MCP dependencies and tests"
    & npm --prefix (Join-Path $root "mcp") ci
    if ($LASTEXITCODE -ne 0) { throw "Candidate preflight failed: MCP dependency installation." }
    & npm --prefix (Join-Path $root "mcp") test
    if ($LASTEXITCODE -ne 0) { throw "Candidate preflight failed: MCP tests." }

    $doctorArgs = @("-RequireHead", "-PublicRelease", "-ConfigPath", (Join-Path $root "config\codex-praetor-tiers.example.json"))
    if ($AllowDraftMetadataPlaceholders) { $doctorArgs += "-AllowDraftMetadataPlaceholders" }
    Invoke-Check "public doctor" (Join-Path $verify "doctor-codex-praetor.ps1") $doctorArgs
    foreach ($script in @(
        "test-codex-praetor.ps1",
        "test-codex-praetor-native.ps1",
        "test-provider-canary-evidence.ps1",
        "test-job-lifecycle.ps1",
        "test-capability-profile-contract.ps1",
        "test-evaluation-suite-contract.ps1",
        "test-public-capability-contract.ps1"
    )) { Invoke-Check $script (Join-Path $verify $script) }
    Invoke-Check "public entry consistency" (Join-Path $verify "test-public-entry-consistency.ps1") @("-SkipRemoteRelease")

    $intent = Get-Content -LiteralPath (Join-Path $root "config\release-intent.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    $buildArgs = @("-Version", [string]$intent.version, "-Apply")
    if ($AllowDraftMetadataPlaceholders) { $buildArgs += "-AllowDraftMetadataPlaceholders" }
    Invoke-Check "release package build" (Join-Path $release "build-codex-praetor-release.ps1") $buildArgs
    Invoke-Check "release package determinism" (Join-Path $verify "test-release-package-determinism.ps1") @("-Version", [string]$intent.version)
    Invoke-Check "final artifact runtime" (Join-Path $verify "test-release-artifact-runtime.ps1") @("-Version", [string]$intent.version, "-MarkVerified")
    Invoke-Check "historical release mutations" (Join-Path $verify "test-runtime-contract-mutations.ps1")
    Invoke-Check "isolated release closeout" (Join-Path $verify "test-release-closeout.ps1")

    $artifactPath = Join-Path $root (".codex-praetor\releases\codex-praetor-setup-" + [string]$intent.version + ".artifact.json")
    $artifact = Get-Content -LiteralPath $artifactPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$artifact.status -ne "artifact_verified") { throw "Candidate artifact is not verified: $artifactPath" }
    $receiptParent = Split-Path -Parent $ReceiptPath
    New-Item -ItemType Directory -Path $receiptParent -Force | Out-Null
    $receipt = [ordered]@{
        schema = "codex-praetor-candidate-preflight/v1"
        status = "passed"
        head = $head
        base_ref = $BaseRef
        verified_at = [DateTime]::UtcNow.ToString("o")
        artifact = [ordered]@{ path = [string]$artifact.artifact.path; sha256 = [string]$artifact.artifact.sha256; manifest = $artifactPath }
    }
    [IO.File]::WriteAllText($ReceiptPath, (($receipt | ConvertTo-Json -Depth 10) + [Environment]::NewLine), (New-Object Text.UTF8Encoding($false)))
    Write-Host "[PASS] Candidate preflight receipt: $ReceiptPath"
} finally { Pop-Location }
