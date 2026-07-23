param([string]$ProjectRoot = "")

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
function Assert-True { param([bool]$Condition, [string]$Message) if (-not $Condition) { throw $Message } }
$workflowRoot = Join-Path $ProjectRoot ".github\workflows"
$workflows = @(Get-ChildItem -LiteralPath $workflowRoot -Filter "*.yml" -File -ErrorAction SilentlyContinue) + @(Get-ChildItem -LiteralPath $workflowRoot -Filter "*.yaml" -File -ErrorAction SilentlyContinue)
Assert-True ($workflows.Count -gt 0) "No GitHub Actions workflow exists."
foreach ($workflow in $workflows) {
    $text = Get-Content -LiteralPath $workflow.FullName -Raw -Encoding UTF8
    $uses = [regex]::Matches($text, '(?m)^\s*uses:\s*([^\s#]+)')
    foreach ($match in $uses) {
        $reference = $match.Groups[1].Value
        if ($reference.StartsWith("./")) { continue }
        Assert-True ($reference -match '@[0-9a-f]{40}$') "Action is not pinned to a full SHA: $reference"
    }
    if ($workflow.Name -eq "release-on-main.yml") {
        Assert-True ($text -match '(?ms)permissions:\s*\r?\n\s+contents:\s*write') "Release workflow must explicitly request contents: write for immutable publication."
        Assert-True ($text -notmatch '(?m)^\s+id-token:\s*write') "Release workflow must not request unused id-token: write."
    } elseif ($workflow.Name -eq "release-pipeline.yml") {
        Assert-True ($text -match '(?ms)on:\s*\r?\n\s+workflow_call:') "Shared release pipeline must use workflow_call."
        Assert-True ($text -notmatch '(?m)^\s*permissions:') "Shared release pipeline must inherit, not elevate, caller permissions."
    } else {
        Assert-True ($text -match '(?ms)permissions:\s*\r?\n\s+contents:\s*read') "Workflow lacks explicit least-privilege contents: read: $($workflow.Name)"
    }
}
$dependabot = Join-Path $ProjectRoot ".github\dependabot.yml"
Assert-True (Test-Path -LiteralPath $dependabot -PathType Leaf) "Dependabot configuration is missing."
$dependabotText = Get-Content -LiteralPath $dependabot -Raw -Encoding UTF8
Assert-True ($dependabotText -match 'package-ecosystem: github-actions') "Dependabot does not monitor GitHub Actions."
Assert-True ($dependabotText -match 'package-ecosystem: npm') "Dependabot does not monitor npm dependencies."
$mcpPackagePath = Join-Path $ProjectRoot "mcp\package.json"
$mcpLockPath = Join-Path $ProjectRoot "mcp\package-lock.json"
Assert-True (Test-Path -LiteralPath $mcpPackagePath -PathType Leaf) "MCP package manifest is missing."
Assert-True (Test-Path -LiteralPath $mcpLockPath -PathType Leaf) "MCP package lock is missing."
$mcpPackage = Get-Content -LiteralPath $mcpPackagePath -Raw -Encoding UTF8 | ConvertFrom-Json
$mcpLockText = Get-Content -LiteralPath $mcpLockPath -Raw -Encoding UTF8
function Get-LockPackageVersion {
    param([string]$LockText, [string]$PackagePath)
    $match = [regex]::Match($LockText, '(?s)"' + [regex]::Escape($PackagePath) + '"\s*:\s*\{\s*"version"\s*:\s*"(?<version>[^"]+)"')
    if ($match.Success) { return [string]$match.Groups['version'].Value }
    return ""
}
Assert-True ([string]$mcpPackage.dependencies.'@modelcontextprotocol/sdk' -eq "^1.29.0") "MCP SDK must remain on the current patched API line."
Assert-True ([version][string]$mcpPackage.overrides.'@hono/node-server' -ge [version]"2.0.11") "MCP runtime must override @hono/node-server to a version patched for the known HTTP adapter advisories."
Assert-True ([version][string]$mcpPackage.overrides.'fast-uri' -ge [version]"3.1.4") "MCP runtime must override fast-uri to a version patched for host-confusion advisory GHSA-v2hh-gcrm-f6hx."
$honoLockVersion = Get-LockPackageVersion -LockText $mcpLockText -PackagePath "node_modules/@hono/node-server"
$fastUriLockVersion = Get-LockPackageVersion -LockText $mcpLockText -PackagePath "node_modules/fast-uri"
Assert-True (-not [string]::IsNullOrWhiteSpace($honoLockVersion) -and [version]$honoLockVersion -ge [version]"2.0.11") "MCP lockfile does not resolve the patched @hono/node-server runtime."
Assert-True (-not [string]::IsNullOrWhiteSpace($fastUriLockVersion) -and [version]$fastUriLockVersion -ge [version]"3.1.4") "MCP lockfile does not resolve the patched fast-uri runtime."
$releaseNotes = Join-Path $ProjectRoot "docs\release\release-notes-0.9.6-alpha.md"
Assert-True (Test-Path -LiteralPath $releaseNotes -PathType Leaf) "0.9.6-alpha release notes are missing."
$workflowReadiness = Join-Path $ProjectRoot "scripts\verify\test-release-workflow-readiness.ps1"
Assert-True (Test-Path -LiteralPath $workflowReadiness -PathType Leaf) "Release workflow readiness test is missing."
& powershell -NoProfile -ExecutionPolicy Bypass -File $workflowReadiness -ProjectRoot $ProjectRoot
if ($LASTEXITCODE -ne 0) { throw "Release workflow readiness contract failed." }
Write-Host "[PASS] Supply-chain action pinning, patched MCP runtime dependencies, least privilege, release workflow readiness, Dependabot, and release evidence controls are verified."
