param(
    [string]$PluginPath = (Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))) "plugin"),
    [string]$MarketplacePath = (Join-Path $env:USERPROFILE ".agents\plugins\marketplace.json"),
    [switch]$Apply
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
$skillRoot = Join-Path $projectRoot "skill\codex-praetor"

function Get-MarketplaceName {
    param([string]$Path)
    $payload = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $payload.name) {
        throw "Marketplace name missing in $Path"
    }
    return [string]$payload.name
}

function Test-FileExists {
    param([string]$Path, [string]$Label)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Label missing: $Path"
    }
}

Test-FileExists (Join-Path $PluginPath ".codex-plugin\plugin.json") "Plugin manifest"
Test-FileExists $MarketplacePath "Marketplace"

Write-Host "Codex Praetor plugin publish plan"
Write-Host "Plugin:      $PluginPath"
Write-Host "Marketplace: $MarketplacePath"

if (-not $Apply) {
    Write-Host ""
    Write-Host "Dry run only. Re-run with -Apply to update cachebuster and confirm marketplace entry."
    exit 0
}

$pluginCreatorScripts = Join-Path $env:USERPROFILE ".codex\skills\.system\plugin-creator\scripts"
python (Join-Path $pluginCreatorScripts "update_plugin_cachebuster.py") $PluginPath

$marketplaceName = python (Join-Path $pluginCreatorScripts "read_marketplace_name.py") --marketplace-path $MarketplacePath
$marketplaceName = $marketplaceName.Trim()
if ([string]::IsNullOrWhiteSpace($marketplaceName)) {
    throw "Unable to read marketplace name from $MarketplacePath"
}

$marketplacePayload = Get-Content -LiteralPath $MarketplacePath -Raw -Encoding UTF8 | ConvertFrom-Json
$plugins = @($marketplacePayload.plugins)
$pluginName = "codex-praetor"
$existing = $plugins | Where-Object { $_.name -eq $pluginName } | Select-Object -First 1
if ($null -eq $existing) {
    throw "Marketplace entry for $pluginName is missing in $MarketplacePath. Use the scaffold flow or add the entry explicitly before reinstall."
}

Write-Host "Marketplace name: $marketplaceName"
Write-Host "Marketplace entry exists for: $($existing.name)"
Write-Host "Next step: codex plugin add $pluginName@$marketplaceName"
