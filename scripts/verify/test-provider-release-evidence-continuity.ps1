param([string]$ProjectRoot = "")

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$root = [System.IO.Path]::GetFullPath($ProjectRoot)
. (Join-Path $root "scripts\shared\get-provider-compatibility-impact.ps1")
$fixture = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-praetor-provider-impact-" + [Guid]::NewGuid().ToString("N"))

function Assert-True([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Invoke-Git([string[]]$Arguments) {
    & git -C $fixture @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Fixture git command failed: git -C $fixture $($Arguments -join ' ')" }
}

try {
    foreach ($name in @('GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE', 'GIT_PREFIX', 'GIT_COMMON_DIR')) { Remove-Item -LiteralPath ("Env:" + $name) -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Path (Join-Path $fixture "docs") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $fixture "config") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $fixture "scripts\dispatch") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $fixture "mcp\src") -Force | Out-Null
    Invoke-Git @("init", "-q")
    Invoke-Git @("config", "user.email", "fixture@example.invalid")
    Invoke-Git @("config", "user.name", "Codex Praetor Fixture")
    [IO.File]::WriteAllText((Join-Path $fixture "scripts\dispatch\invoke-codex-praetor.ps1"), "# fixture`n", (New-Object Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText((Join-Path $fixture "mcp\src\tools.ts"), "export function runtimeInfoTool() { return 'baseline'; }`nexport function capabilityProfilesTool() { return 'provider-sensitive'; }`n", (New-Object Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText((Join-Path $fixture "config\runtime-contract.json"), '{"product":"codex-praetor","version":"0.16.24-alpha","taskContractSchema":"fixture/v1"}' + "`n", (New-Object Text.UTF8Encoding($false)))
    Invoke-Git @("add", ".")
    Invoke-Git @("commit", "-qm", "provider source")
    $source = ((& git -C $fixture rev-parse HEAD | Out-String).Trim())
    $sourceSurface = Get-CodexPraetorProviderCompatibilitySurfaceHash -Repo $fixture -Revision $source

    [IO.File]::WriteAllText((Join-Path $fixture "docs\release-notes.md"), "documentation-only amend`n", (New-Object Text.UTF8Encoding($false)))
    Invoke-Git @("add", ".")
    Invoke-Git @("commit", "-qm", "docs")
    $docsTarget = ((& git -C $fixture rev-parse HEAD | Out-String).Trim())
    $docsImpact = @(Get-CodexPraetorProviderCompatibilityImpact -Repo $fixture -ComparisonBase $source -TargetRef $docsTarget)
    Assert-True ($docsImpact.Count -eq 0) "Documentation-only amend must preserve provider evidence continuity."
    Assert-True ($sourceSurface -eq (Get-CodexPraetorProviderCompatibilitySurfaceHash -Repo $fixture -Revision $docsTarget)) "Documentation-only amend must preserve the portable provider surface hash."

    [IO.File]::WriteAllText((Join-Path $fixture "config\runtime-contract.json"), '{"product":"codex-praetor","version":"0.16.25-alpha","taskContractSchema":"fixture/v1"}' + "`n", (New-Object Text.UTF8Encoding($false)))
    Invoke-Git @("add", ".")
    Invoke-Git @("commit", "-qm", "release version only")
    $versionTarget = ((& git -C $fixture rev-parse HEAD | Out-String).Trim())
    $versionImpact = @(Get-CodexPraetorProviderCompatibilityImpact -Repo $fixture -ComparisonBase $docsTarget -TargetRef $versionTarget)
    Assert-True ($versionImpact.Count -eq 0) "A runtime-contract version-only release change must not demand new provider evidence."
    Assert-True ($sourceSurface -eq (Get-CodexPraetorProviderCompatibilitySurfaceHash -Repo $fixture -Revision $versionTarget)) "A runtime-contract version-only release change must preserve the provider surface hash."

    $toolsPath = Join-Path $fixture "mcp\src\tools.ts"
    [IO.File]::WriteAllText($toolsPath, ((Get-Content -LiteralPath $toolsPath -Raw -Encoding UTF8).Replace("baseline", "observed")), (New-Object Text.UTF8Encoding($false)))
    Invoke-Git @("add", "mcp/src/tools.ts")
    Invoke-Git @("commit", "-qm", "runtime observability")
    $observabilityTarget = ((& git -C $fixture rev-parse HEAD | Out-String).Trim())
    $observabilityImpact = @(Get-CodexPraetorProviderCompatibilityImpact -Repo $fixture -ComparisonBase $versionTarget -TargetRef $observabilityTarget)
    Assert-True ($observabilityImpact.Count -eq 0) "runtime_info-only changes must not demand provider evidence."
    Assert-True ($sourceSurface -eq (Get-CodexPraetorProviderCompatibilitySurfaceHash -Repo $fixture -Revision $observabilityTarget)) "runtime_info-only changes must preserve the provider compatibility surface hash."

    [IO.File]::AppendAllText((Join-Path $fixture "scripts\dispatch\invoke-codex-praetor.ps1"), "# provider behavior changed`n", (New-Object Text.UTF8Encoding($false)))
    Invoke-Git @("add", ".")
    Invoke-Git @("commit", "-qm", "provider behavior")
    $providerTarget = ((& git -C $fixture rev-parse HEAD | Out-String).Trim())
    $providerImpact = @(Get-CodexPraetorProviderCompatibilityImpact -Repo $fixture -ComparisonBase $observabilityTarget -TargetRef $providerTarget)
    Assert-True (($providerImpact -join ",") -eq "codebuddy,qoder") "Provider behavior change must invalidate both provider evidence tuples."
    Assert-True ($sourceSurface -ne (Get-CodexPraetorProviderCompatibilitySurfaceHash -Repo $fixture -Revision $providerTarget)) "Provider behavior change must invalidate the portable provider surface hash."
    Write-Output "[PASS] Provider evidence continuity permits documentation/version-only releases and rejects provider behavior changes."
} finally {
    if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue }
}
