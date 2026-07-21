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
    & git -C $scratch add config mcp/package.json
    & git -C $scratch commit -qm "fixture"
    if ($LASTEXITCODE -ne 0) { throw "Unable to create the release-intent fixture repository." }

    $packagePath = Join-Path $scratch "mcp\package.json"
    $packageText = Get-Content -LiteralPath $packagePath -Raw -Encoding UTF8
    $updated = $packageText -replace '"typescript"\s*:\s*"\^5\.9\.3"', '"typescript": "^5.9.4"'
    Assert-True ($updated -ne $packageText) "Fixture no longer contains the expected development dependency."
    Set-Content -LiteralPath $packagePath -Value $updated -Encoding UTF8
    & git -C $scratch add mcp/package.json
    & git -C $scratch commit -qm "update dev dependency"
    if ($LASTEXITCODE -ne 0) { throw "Unable to commit the dependency-only fixture change." }

    # There is deliberately no origin remote. A non-release candidate must not
    # reach ls-remote or demand a new immutable product tag.
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $gate -ProjectRoot $scratch -BaseRef HEAD~1 -RequireReleaseImpact -CheckRemote 2>&1
    Assert-True ($LASTEXITCODE -eq 0) "Dependency-only candidate was incorrectly sent to a remote immutable-tag gate: $($output -join "`n")"
    Assert-True (($output -join "`n") -match "Pipeline classification: non_release") "Dependency-only candidate did not emit the shared non-release classification."
    Write-Host "[PASS] Dependency-only candidate bypasses remote immutable-tag checks while retaining release-intent validation."
} finally {
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}
