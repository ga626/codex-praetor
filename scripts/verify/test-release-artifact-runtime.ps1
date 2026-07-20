param(
    [string]$Version = "0.7.0-alpha",
    [string]$OutputRoot = ".codex-praetor\releases",
    [string]$ArtifactManifestPath = "",
    [string]$ObservedToolsPath = "",
    [switch]$MarkVerified,
    [string]$ProjectRoot = ""
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
$releaseName = "codex-praetor-setup-$Version"
$outputRootPath = [IO.Path]::GetFullPath((Join-Path $ProjectRoot $OutputRoot))
if ([string]::IsNullOrWhiteSpace($ArtifactManifestPath)) { $ArtifactManifestPath = Join-Path $outputRootPath "$releaseName.artifact.json" }
$ArtifactManifestPath = [IO.Path]::GetFullPath($ArtifactManifestPath)
$smoke = Join-Path $ProjectRoot "mcp\scripts\smoke-plugin-mcp.js"

if (-not (Test-Path -LiteralPath $ArtifactManifestPath -PathType Leaf)) { throw "Release artifact manifest is missing: $ArtifactManifestPath" }
if (-not (Test-Path -LiteralPath $smoke -PathType Leaf)) { throw "MCP protocol smoke script is missing: $smoke" }
$artifact = Get-Content -LiteralPath $ArtifactManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$artifact.status -ne "built") { throw "Artifact manifest is not publishable from build state: $($artifact.status)" }
$zipPath = [IO.Path]::GetFullPath([string]$artifact.artifact.path)
if (-not (Test-Path -LiteralPath $zipPath -PathType Leaf)) { throw "Release artifact is missing: $zipPath" }
$actualHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualHash -ne [string]$artifact.artifact.sha256) { throw "Artifact SHA256 differs from its manifest. Actual=$actualHash Manifest=$($artifact.artifact.sha256)" }

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("codex-praetor-artifact-runtime-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
try {
    Expand-Archive -LiteralPath $zipPath -DestinationPath $tmp -Force
    $runtime = Join-Path $tmp "plugin\mcp\dist\server.js"
    $generation = Join-Path $tmp "codex-praetor-release-generation.json"
    $contract = Join-Path $tmp "config\runtime-contract.json"
    if (-not (Test-Path -LiteralPath $runtime -PathType Leaf)) { throw "Artifact does not contain plugin/mcp/dist/server.js." }
    if (-not (Test-Path -LiteralPath $generation -PathType Leaf)) { throw "Artifact does not contain release generation manifest." }
    if (-not (Test-Path -LiteralPath $contract -PathType Leaf)) { throw "Artifact does not contain canonical runtime contract." }
    $observedArgument = @()
    if (-not [string]::IsNullOrWhiteSpace($ObservedToolsPath)) { $observedArgument = @("--observed-tools-output", [IO.Path]::GetFullPath($ObservedToolsPath)) }
    & node $smoke $runtime $tmp --skip-dry-run --expected-version $Version --expected-contract $contract --expected-generation $generation @observedArgument
    if ($LASTEXITCODE -ne 0) { throw "Final release zip MCP runtime/contract acceptance failed." }
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

if ($MarkVerified) {
    $artifact.status = "artifact_verified"
    $artifact.verification = [ordered]@{
        status = "passed"
        verified_at = [DateTime]::UtcNow.ToString("o")
        verifier = "test-release-artifact-runtime.ps1"
        artifact_sha256 = $actualHash
        observed_tools_path = if ([string]::IsNullOrWhiteSpace($ObservedToolsPath)) { "" } else { [IO.Path]::GetFullPath($ObservedToolsPath) }
    }
    [IO.File]::WriteAllText($ArtifactManifestPath, (($artifact | ConvertTo-Json -Depth 16) + [Environment]::NewLine), (New-Object Text.UTF8Encoding($false)))
}
Write-Host "[PASS] Final release zip starts its bundled MCP and proves one contract identity: $actualHash"
