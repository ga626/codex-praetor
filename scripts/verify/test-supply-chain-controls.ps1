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
$releaseNotes = Join-Path $ProjectRoot "docs\release\release-notes-0.8.3-alpha.md"
Assert-True (Test-Path -LiteralPath $releaseNotes -PathType Leaf) "0.8.3-alpha release notes are missing."
$workflowReadiness = Join-Path $ProjectRoot "scripts\verify\test-release-workflow-readiness.ps1"
Assert-True (Test-Path -LiteralPath $workflowReadiness -PathType Leaf) "Release workflow readiness test is missing."
& powershell -NoProfile -ExecutionPolicy Bypass -File $workflowReadiness -ProjectRoot $ProjectRoot
if ($LASTEXITCODE -ne 0) { throw "Release workflow readiness contract failed." }
Write-Host "[PASS] Supply-chain action pinning, least privilege, release workflow readiness, Dependabot, and release evidence controls are verified."
