param(
    [string]$ProjectRoot = ""
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}
$root = [System.IO.Path]::GetFullPath($ProjectRoot)
$gate = Join-Path $root "scripts\verify\test-release-intent.ps1"
if (-not (Test-Path -LiteralPath $gate -PathType Leaf)) { throw "Release intent gate is missing: $gate" }

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$scratch = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-praetor-release-intent-" + [guid]::NewGuid().ToString("N"))
try {
    New-Item -ItemType Directory -Path $scratch -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $root "config") -Destination (Join-Path $scratch "config") -Recurse -Force
    New-Item -ItemType Directory -Path (Join-Path $scratch "mcp") -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $root "mcp\package.json") -Destination (Join-Path $scratch "mcp\package.json") -Force
    & git -C $scratch init -q
    & git -C $scratch config user.email "release-intent-test@example.invalid"
    & git -C $scratch config user.name "Codex Praetor test"
    # The fixture must be independent of the maintainer's global Git line-ending
    # preference. Otherwise core.autocrlf=true emits a warning that the strict
    # candidate-preflight wrapper correctly treats as a failed child command.
    & git -C $scratch config core.autocrlf false
    & git -C $scratch add config mcp/package.json
    & git -C $scratch commit -qm "fixture"
    if ($LASTEXITCODE -ne 0) { throw "Unable to create the release-intent fixture repository." }

    $packagePath = Join-Path $scratch "mcp\package.json"
    $packageText = Get-Content -LiteralPath $packagePath -Raw -Encoding UTF8
    $runtimeDependencyVersion = [regex]::Match($packageText, '"@qoder-ai/qoder-agent-sdk"\s*:\s*"(?<version>[^"]+)"')
    Assert-True $runtimeDependencyVersion.Success "Fixture no longer contains the Qoder SDK production dependency."
    $replacementVersion = $runtimeDependencyVersion.Groups["version"].Value + "-fixture.0"
    $updated = $packageText.Substring(0, $runtimeDependencyVersion.Groups["version"].Index) + $replacementVersion + $packageText.Substring($runtimeDependencyVersion.Groups["version"].Index + $runtimeDependencyVersion.Groups["version"].Length)
    Set-Content -LiteralPath $packagePath -Value $updated -Encoding UTF8
    & git -C $scratch add mcp/package.json
    & git -C $scratch commit -qm "update production dependency"
    if ($LASTEXITCODE -ne 0) { throw "Unable to commit the dependency-only fixture change." }

    # There is deliberately no origin remote. A non-release candidate must not
    # reach ls-remote or demand a new immutable product tag.
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $gate -ProjectRoot $scratch -BaseRef HEAD~1 -RequireReleaseImpact -CheckRemote 2>&1
    Assert-True ($LASTEXITCODE -eq 0) "Dependency-only candidate was incorrectly sent to a remote immutable-tag gate: $($output -join "`n")"
    Assert-True (($output -join "`n") -match "Pipeline classification: non_release") "Dependency-only candidate did not emit the shared non-release classification."

    $verifyDirectory = Join-Path $scratch "scripts\verify"
    New-Item -ItemType Directory -Path $verifyDirectory -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $verifyDirectory "internal-fixture.ps1") -Value "# internal verification fixture" -Encoding utf8
    & git -C $scratch add scripts/verify/internal-fixture.ps1
    & git -C $scratch commit -qm "update internal verification fixture"
    if ($LASTEXITCODE -ne 0) { throw "Unable to commit the verification-only fixture change." }

    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $gate -ProjectRoot $scratch -BaseRef HEAD~1 -RequireReleaseImpact -CheckRemote 2>&1
    Assert-True ($LASTEXITCODE -eq 0) "Verification-only candidate was incorrectly treated as release-impacting: $($output -join "`n")"
    Assert-True (($output -join "`n") -match "Pipeline classification: non_release") "Verification-only candidate did not emit the shared non-release classification."
    Write-Host "[PASS] Dependency-only candidate bypasses remote immutable-tag checks while retaining release-intent validation."
} finally {
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}
