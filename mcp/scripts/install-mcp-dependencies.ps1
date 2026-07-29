param(
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$mcpRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$sdkPostinstall = Join-Path $mcpRoot "node_modules\@qoder-ai\qoder-agent-sdk\scripts\postinstall.cjs"

if ((-not $Force) -and (Test-Path -LiteralPath $sdkPostinstall -PathType Leaf)) {
    Write-Host "[PASS] MCP dependencies are already present."
    exit 0
}

# The Qoder SDK dependency downloads a global CLI in its own postinstall hook.
# Codex Praetor deliberately skips that implicit download: real dispatch uses
# the user's configured Qoder CLI, rather than packaging a second CLI binary.
$previousSkipDownload = $env:QODER_SKIP_DOWNLOAD
try {
    $env:QODER_SKIP_DOWNLOAD = "1"
    & npm ci --prefix $mcpRoot
    if ($LASTEXITCODE -ne 0) {
        throw "MCP dependency installation failed."
    }
} finally {
    if ($null -eq $previousSkipDownload) {
        Remove-Item Env:QODER_SKIP_DOWNLOAD -ErrorAction SilentlyContinue
    } else {
        $env:QODER_SKIP_DOWNLOAD = $previousSkipDownload
    }
}

if (-not (Test-Path -LiteralPath $sdkPostinstall -PathType Leaf)) {
    throw "Qoder Agent SDK postinstall helper is missing after npm ci."
}

Write-Host "[PASS] MCP dependencies installed with the SDK implicit CLI download disabled."
