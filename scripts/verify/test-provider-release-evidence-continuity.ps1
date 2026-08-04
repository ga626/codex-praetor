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
    New-Item -ItemType Directory -Path (Join-Path $fixture "scripts\dispatch") -Force | Out-Null
    Invoke-Git @("init", "-q")
    Invoke-Git @("config", "user.email", "fixture@example.invalid")
    Invoke-Git @("config", "user.name", "Codex Praetor Fixture")
    [IO.File]::WriteAllText((Join-Path $fixture "scripts\dispatch\invoke-codex-praetor.ps1"), "# fixture`n", (New-Object Text.UTF8Encoding($false)))
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

    [IO.File]::AppendAllText((Join-Path $fixture "scripts\dispatch\invoke-codex-praetor.ps1"), "# provider behavior changed`n", (New-Object Text.UTF8Encoding($false)))
    Invoke-Git @("add", ".")
    Invoke-Git @("commit", "-qm", "provider behavior")
    $providerTarget = ((& git -C $fixture rev-parse HEAD | Out-String).Trim())
    $providerImpact = @(Get-CodexPraetorProviderCompatibilityImpact -Repo $fixture -ComparisonBase $source -TargetRef $providerTarget)
    Assert-True (($providerImpact -join ",") -eq "codebuddy,qoder") "Provider behavior change must invalidate both provider evidence tuples."
    Assert-True ($sourceSurface -ne (Get-CodexPraetorProviderCompatibilitySurfaceHash -Repo $fixture -Revision $providerTarget)) "Provider behavior change must invalidate the portable provider surface hash."
    Write-Output "[PASS] Provider evidence continuity allows documentation-only amend and rejects provider behavior changes."
} finally {
    if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue }
}
