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
    foreach ($match in $uses) { Assert-True ($match.Groups[1].Value -match '@[0-9a-f]{40}$') "Action is not pinned to a full SHA: $($match.Groups[1].Value)" }
    if ($workflow.Name -eq "release-on-main.yml") {
        Assert-True ($text -match '(?ms)permissions:\s*\r?\n\s+contents:\s*write') "Release workflow must explicitly request contents: write for immutable publication."
        Assert-True ($text -notmatch '(?m)^\s+id-token:\s*write') "Release workflow must not request unused id-token: write."
    } else {
        Assert-True ($text -match '(?ms)permissions:\s*\r?\n\s+contents:\s*read') "Workflow lacks explicit least-privilege contents: read: $($workflow.Name)"
    }
}
$dependabot = Join-Path $ProjectRoot ".github\dependabot.yml"
Assert-True (Test-Path -LiteralPath $dependabot -PathType Leaf) "Dependabot configuration is missing."
$dependabotText = Get-Content -LiteralPath $dependabot -Raw -Encoding UTF8
Assert-True ($dependabotText -match 'package-ecosystem: github-actions') "Dependabot does not monitor GitHub Actions."
Assert-True ($dependabotText -match 'package-ecosystem: npm') "Dependabot does not monitor npm dependencies."
$releaseNotes = Join-Path $ProjectRoot "docs\release\release-notes-0.6.0-alpha.md"
Assert-True (Test-Path -LiteralPath $releaseNotes -PathType Leaf) "0.6.0-alpha release notes are missing."
Write-Host "[PASS] Supply-chain action pinning, least privilege, Dependabot, and release evidence controls are verified."
