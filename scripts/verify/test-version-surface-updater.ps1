param([string]$ProjectRoot = "")

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}
$root = [IO.Path]::GetFullPath($ProjectRoot)
$scratch = Join-Path ([IO.Path]::GetTempPath()) ("codex-praetor-version-updater-" + [guid]::NewGuid().ToString("N"))

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Copy-RelativeFile([string]$Relative) {
    $source = Join-Path $root $Relative
    $destination = Join-Path $scratch $Relative
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Fixture source is missing: $Relative" }
    $parent = Split-Path -Parent $destination
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination -Force
}

try {
    New-Item -ItemType Directory -Path $scratch -Force | Out-Null
    $fixtures = @(
        "config\release-intent.json", "config\runtime-contract.json",
        "plugin\runtime-contract.json", "plugin\skills\codex-praetor\scripts\runtime-contract.json",
        "skill\codex-praetor\scripts\runtime-contract.json", "plugin\.codex-plugin\plugin.json",
        "mcp\package.json", "plugin\mcp\package.json", "setup.ps1", "mcp\src\server.ts",
        "mcp\package-lock.json", "README.md", "README.en.md", "docs\user\installation.zh.md",
        "docs\user\troubleshooting.zh.md", "docs\README.md", "docs\user\user-acceptance-checklist.zh.md",
        "docs\roadmap.md", "SECURITY.md", "scripts\release\build-codex-praetor-release.ps1",
        "scripts\release\publish-github-release-asset.ps1", "scripts\release\verify-github-release-asset.ps1",
        "scripts\verify\test-public-entry-consistency.ps1", "scripts\verify\test-release-package-determinism.ps1",
        "scripts\verify\test-supply-chain-controls.ps1", "docs\release\github-publish-runbook.md",
        "docs\release\release-gate-checklist.md", "scripts\release\set-codex-praetor-version.ps1"
    )
    foreach ($fixture in $fixtures) { Copy-RelativeFile $fixture }

    $sourceNotes = Join-Path $root "docs\release\release-notes-0.6.1-alpha.md"
    $targetNotes = Join-Path $scratch "docs\release\release-notes-0.6.2-alpha.md"
    Copy-Item -LiteralPath $sourceNotes -Destination $targetNotes -Force

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scratch "scripts\release\set-codex-praetor-version.ps1") -ProjectRoot $scratch -Version "0.6.2-alpha" -Apply
    if ($LASTEXITCODE -ne 0) { throw "Version surface updater failed in its isolated fixture." }

    $setupPath = Join-Path $scratch "setup.ps1"
    $setupBytes = [IO.File]::ReadAllBytes($setupPath)
    Assert-True ($setupBytes.Length -ge 3 -and $setupBytes[0] -eq 0xEF -and $setupBytes[1] -eq 0xBB -and $setupBytes[2] -eq 0xBF) "Version updater removed the UTF-8 BOM required by Windows PowerShell setup.ps1."
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($setupPath, [ref]$tokens, [ref]$errors) | Out-Null
    Assert-True ($errors.Count -eq 0) "Version updater produced a setup.ps1 that Windows PowerShell cannot parse."

    $intent = Get-Content -LiteralPath (Join-Path $scratch "config\release-intent.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    $contract = Get-Content -LiteralPath (Join-Path $scratch "config\runtime-contract.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($intent.version -eq "0.6.2-alpha" -and $intent.previous_version -eq "0.6.1-alpha") "Version updater did not advance the release intent correctly."
    Assert-True ($intent.tag -eq "v0.6.2-alpha" -and $intent.artifact -eq "codex-praetor-setup-0.6.2-alpha.zip") "Version updater did not synchronize tag and artifact."
    Assert-True ($contract.version -eq "0.6.2-alpha") "Version updater did not synchronize the runtime contract."
    Write-Host "[PASS] Version surface updater preserves encoding and advances the release contract in an isolated fixture."
} finally {
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}
