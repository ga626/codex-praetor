param([string]$ProjectRoot = "")

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)

function Assert-Contains {
    param([string]$Text, [string]$Needle, [string]$Message)
    if (-not $Text.Contains($Needle)) { throw $Message }
}

$installerPath = Join-Path $ProjectRoot "mcp\scripts\install-mcp-dependencies.ps1"
$preflightPath = Join-Path $ProjectRoot "scripts\verify\invoke-release-candidate-preflight.ps1"
$dispatcherPath = Join-Path $ProjectRoot "scripts\dispatch\invoke-codex-praetor.ps1"
$packagerPath = Join-Path $ProjectRoot "mcp\scripts\package-plugin-mcp.js"
foreach ($path in @($installerPath, $preflightPath, $dispatcherPath, $packagerPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required SDK install boundary is missing: $path" }
}

$installer = Get-Content -LiteralPath $installerPath -Raw -Encoding UTF8
$preflight = Get-Content -LiteralPath $preflightPath -Raw -Encoding UTF8
$dispatcher = Get-Content -LiteralPath $dispatcherPath -Raw -Encoding UTF8
$packager = Get-Content -LiteralPath $packagerPath -Raw -Encoding UTF8
Assert-Contains $installer '$env:QODER_SKIP_DOWNLOAD = "1"' "MCP installer must suppress the SDK's implicit global CLI download."
Assert-Contains $installer 'npm ci --prefix $mcpRoot' "MCP installer must own clean dependency installation."
Assert-Contains $preflight 'install-mcp-dependencies.ps1' "Release preflight must use the supervised MCP dependency installer."
Assert-Contains $dispatcher 'cli_path = $resolvedQoder' "Qoder SDK runner must receive the configured user CLI path."
Assert-Contains $dispatcher '-ProviderCliPath $resolvedQoder' "Qoder readiness evidence must identify the CLI actually used by the SDK runner."
if ($dispatcher.Contains('Bundled Qoder SDK CLI')) { throw "Dispatch must not replace the configured Qoder CLI with a bundled binary." }
if ($packager.Contains('qodercli.exe')) { throw "Plugin packaging must not include a second Qoder CLI binary." }
Write-Host "[PASS] Qoder SDK installation suppresses the implicit global download and dispatch uses the configured user CLI."
