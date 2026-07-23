param([string]$ProjectRoot = "")

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$root = [IO.Path]::GetFullPath($ProjectRoot)
$manifestPath = Join-Path $root "config\public-capabilities.json"
$contractPath = Join-Path $root "config\runtime-contract.json"
function Assert-True([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }

$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$contract = Get-Content -LiteralPath $contractPath -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-True ([string]$manifest.schema -eq "codex-praetor-public-capabilities/v1") "Public capability manifest schema is invalid."
$capabilities = @($manifest.capabilities)
Assert-True ($capabilities.Count -gt 0) "Public capability manifest is empty."
Assert-True (@($capabilities.id | Select-Object -Unique).Count -eq $capabilities.Count) "Public capability ids must be unique."
$scenarios = @("mcp_contract", "route_intent", "provider_operations", "evaluation_suite", "evaluation_prepare", "evaluation_verify", "provider_contract", "release_activation_contract")
foreach ($capability in $capabilities) {
    foreach ($name in @("id", "audience", "entry", "package_requirements", "scenario", "risk_tier")) {
        Assert-True ($capability.PSObject.Properties.Name -contains $name) "Public capability is missing $name."
    }
    Assert-True ([string]$capability.audience -in @("installed_plugin", "release_bundle", "developer_only")) "Public capability $($capability.id) has an invalid audience."
    Assert-True ([string]$capability.scenario -in $scenarios) "Public capability $($capability.id) has no supported scenario."
    foreach ($relative in @($capability.package_requirements)) {
        Assert-True (Test-Path -LiteralPath (Join-Path $root ([string]$relative)) -PathType Leaf) "Public capability $($capability.id) requires a missing source path: $relative"
    }
    if ([string]$capability.entry.kind -eq "mcp_tool") {
        Assert-True ([string]$capability.entry.name -in @($contract.requiredMcpTools)) "Public capability $($capability.id) points to a tool missing from the runtime contract."
    }
}
Assert-True (@($capabilities | Where-Object { $_.id -eq "evaluation.prepare" -and $_.entry.name -eq "codex_praetor_prepare_evaluation" }).Count -eq 1) "The installed evaluation preparation capability is missing."
Write-Host "[PASS] Public capability contract covers $($capabilities.Count) declared user-facing capabilities and their runtime entries."
