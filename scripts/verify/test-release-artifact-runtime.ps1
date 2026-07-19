param(
    [string]$Version = "0.6.1-alpha",
    [string]$OutputRoot = ".codex-praetor\releases",
    [string]$ProjectRoot = ""
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}
$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
$releaseName = "codex-praetor-setup-$Version"
$zipPath = Join-Path ([System.IO.Path]::GetFullPath((Join-Path $ProjectRoot $OutputRoot))) "$releaseName.zip"
$smoke = Join-Path $ProjectRoot "mcp\scripts\smoke-plugin-mcp.js"
if (-not (Test-Path -LiteralPath $zipPath -PathType Leaf)) { throw "Release artifact is missing: $zipPath" }
if (-not (Test-Path -LiteralPath $smoke -PathType Leaf)) { throw "MCP protocol smoke script is missing: $smoke" }

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-praetor-artifact-runtime-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
try {
    Expand-Archive -LiteralPath $zipPath -DestinationPath $tmp -Force
    $runtime = Join-Path $tmp "plugin\mcp\dist\server.js"
    $manifest = Join-Path $tmp "codex-praetor-release-generation.json"
    if (-not (Test-Path -LiteralPath $runtime -PathType Leaf)) { throw "Artifact does not contain plugin/mcp/dist/server.js." }
    if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { throw "Artifact does not contain release generation manifest." }
    & node $smoke $runtime $tmp --skip-dry-run --expected-version $Version
    if ($LASTEXITCODE -ne 0) { throw "Downloaded artifact MCP runtime smoke failed." }
    Write-Host "[PASS] Final release zip starts its bundled MCP runtime and exposes version $Version."
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
