param(
    [string]$ProjectRoot = "",
    [Parameter(Mandatory = $true)]
    [string]$ObservedToolsPath,
    [Parameter(Mandatory = $true)]
    [string]$OutputPath,
    [switch]$Apply
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $ProjectRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
}

$projectPath = [System.IO.Path]::GetFullPath($ProjectRoot)
$generationScript = Join-Path $projectPath "scripts\release\get-codex-praetor-generation.ps1"
if (-not (Test-Path -LiteralPath $generationScript -PathType Leaf)) {
    throw "Generation script is missing: $generationScript"
}
if (-not (Test-Path -LiteralPath $ObservedToolsPath -PathType Leaf)) {
    throw "Observed tools file is missing: $ObservedToolsPath"
}

$generation = (& $generationScript -ProjectRoot $projectPath -Json | ConvertFrom-Json)
$observedPayload = Get-Content -LiteralPath $ObservedToolsPath -Raw -Encoding UTF8 | ConvertFrom-Json
$observedTools = @()
if ($observedPayload.tool_names) {
    $observedTools = @($observedPayload.tool_names | ForEach-Object { [string]$_ })
} elseif ($observedPayload.observed_tools) {
    $observedTools = @($observedPayload.observed_tools | ForEach-Object { [string]$_ })
} else {
    throw "Observed tools payload must contain tool_names or observed_tools."
}

$missing = @($generation.required_mcp_tools | Where-Object { $observedTools -notcontains [string]$_ })
$proof = [ordered]@{
    schema = "codex-praetor-fresh-context-proof/v1"
    status = if ($missing.Count -eq 0) { "passed" } else { "failed" }
    generation_id = [string]$generation.generation_id
    observed_at = [DateTime]::UtcNow.ToString("o")
    required_tools = @($generation.required_mcp_tools)
    observed_tools = @($observedTools | Sort-Object -Unique)
    missing_tools = $missing
    source = [string]$observedPayload.source
}

if ($missing.Count -gt 0) {
    throw "Fresh-context tool surface is incomplete: $($missing -join ', ')"
}

Write-Host "Fresh-context proof plan"
Write-Host "Generation: $($proof.generation_id)"
Write-Host "Observed tools: $($proof.observed_tools.Count)"
Write-Host "Output: $OutputPath"
if (-not $Apply) {
    Write-Host "Dry run only. Re-run with -Apply after collecting tool names from a new Codex thread."
    exit 0
}

$fullOutput = [System.IO.Path]::GetFullPath($OutputPath)
$parent = Split-Path -Parent $fullOutput
New-Item -ItemType Directory -Path $parent -Force | Out-Null
$temp = "$fullOutput.tmp-$([Guid]::NewGuid().ToString('N'))"
$json = ($proof | ConvertTo-Json -Depth 12) + [Environment]::NewLine
[System.IO.File]::WriteAllText($temp, $json, (New-Object System.Text.UTF8Encoding($false)))
Move-Item -LiteralPath $temp -Destination $fullOutput -Force
Write-Host "[PASS] Fresh-context proof written: $fullOutput"
