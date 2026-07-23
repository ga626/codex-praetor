param(
    [string]$Root = ""
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}
$Root = [IO.Path]::GetFullPath($Root)
$expected = @("qoder", "codebuddy")

function Assert-EqualSet {
    param([string]$Label, [string[]]$Actual)
    $missing = @($expected | Where-Object { $_ -notin $Actual })
    $extra = @($Actual | Where-Object { $_ -notin $expected })
    if ($missing.Count -gt 0 -or $extra.Count -gt 0) {
        throw "$Label provider allowlist mismatch. Missing: $($missing -join ', '); extra: $($extra -join ', ')"
    }
    Write-Host "[PASS] $Label has the exact provider allowlist."
}

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Missing required file: $Path" }
    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

$config = Read-JsonFile (Join-Path $Root "config\codex-praetor-tiers.example.json")
Assert-EqualSet -Label "Source provider registry" -Actual @($config.providers.PSObject.Properties.Name)
Assert-EqualSet -Label "Source tier registry" -Actual @($config.tiers.PSObject.Properties.Value | ForEach-Object { [string]$_.provider } | Sort-Object -Unique)

$sourceAdapters = @(Get-ChildItem -LiteralPath (Join-Path $Root "config\provider-adapters") -File -Filter "*.json" | ForEach-Object { $_.BaseName })
Assert-EqualSet -Label "Source adapters" -Actual $sourceAdapters

$pluginAdapters = @(Get-ChildItem -LiteralPath (Join-Path $Root "plugin\data\provider-adapters") -File -Filter "*.json" | ForEach-Object { $_.BaseName })
Assert-EqualSet -Label "Bundled adapters" -Actual $pluginAdapters

$suite = Read-JsonFile (Join-Path $Root "config\evaluation-suite.json")
foreach ($task in @($suite.tasks)) {
    Assert-EqualSet -Label "Evaluation task $($task.task_id)" -Actual @($task.provider_candidates)
}

$server = Get-Content -LiteralPath (Join-Path $Root "mcp\src\server.ts") -Raw -Encoding UTF8
if ($server -notmatch 'z\.enum\(\["qoder", "codebuddy"\]\)') {
    throw "MCP schema does not declare the two-provider allowlist."
}

$dispatcher = Get-Content -LiteralPath (Join-Path $Root "scripts\dispatch\invoke-codex-praetor.ps1") -Raw -Encoding UTF8
if ($dispatcher -notmatch '\[ValidateSet\("auto", "qoder", "codebuddy"\)\]') {
    throw "Dispatcher does not declare the expected provider allowlist."
}

Write-Host "Provider surface allowlist verification passed."
