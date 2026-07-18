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
$runtimeInfo = $observedPayload.runtime_info
$runtimeIdentity = if ($null -ne $runtimeInfo) { $runtimeInfo.runtime_identity } else { $null }
$validationFailures = New-Object System.Collections.Generic.List[string]

if ($missing.Count -gt 0) {
    $validationFailures.Add("missing_tools=$($missing -join ',')")
}
if ($null -eq $runtimeInfo -or $null -eq $runtimeIdentity) {
    $validationFailures.Add("runtime_info_missing")
} else {
    if ([string]$runtimeInfo.runtime_contract.version -ne [string]$generation.version) {
        $validationFailures.Add("runtime_version_mismatch")
    }
    if ([string]$runtimeInfo.runtime_contract.taskContractSchema -ne [string]$generation.task_contract_schema) {
        $validationFailures.Add("task_contract_schema_mismatch")
    }
    if ([string]$runtimeIdentity.runtime_contract_sha256 -ne [string]$generation.runtime_contract_sha256) {
        $validationFailures.Add("runtime_contract_sha256_mismatch")
    }
    if ([string]::IsNullOrWhiteSpace([string]$runtimeInfo.contract_path) -or [string]::IsNullOrWhiteSpace([string]$runtimeIdentity.project_root)) {
        $validationFailures.Add("runtime_path_missing")
    }
    if ([int64]$runtimeIdentity.process_id -le 0) {
        $validationFailures.Add("runtime_process_id_missing")
    }
    $startedAt = [DateTime]::MinValue
    if (-not [DateTime]::TryParse([string]$runtimeIdentity.process_started_at, [ref]$startedAt)) {
        $validationFailures.Add("runtime_process_started_at_invalid")
    }
}
$proof = [ordered]@{
    schema = "codex-praetor-fresh-context-proof/v2"
    status = if ($validationFailures.Count -eq 0) { "passed" } else { "failed" }
    generation_id = [string]$generation.generation_id
    observed_at = [DateTime]::UtcNow.ToString("o")
    required_tools = @($generation.required_mcp_tools)
    observed_tools = @($observedTools | Sort-Object -Unique)
    missing_tools = $missing
    runtime_info = $runtimeInfo
    runtime_identity = $runtimeIdentity
    validation_failures = @($validationFailures)
    source = [string]$observedPayload.source
}

Write-Host "Fresh-context proof plan"
Write-Host "Generation: $($proof.generation_id)"
Write-Host "Observed tools: $($proof.observed_tools.Count)"
Write-Host "Runtime contract SHA256: $($runtimeIdentity.runtime_contract_sha256)"
Write-Host "Runtime process: $($runtimeIdentity.process_id)"
Write-Host "Output: $OutputPath"
if (-not $Apply) {
    if ($proof.status -eq "passed") {
        Write-Host "Dry run passed. Re-run with -Apply after retaining the native runtime observation."
        exit 0
    }
    Write-Host "[FAIL] Fresh-context proof is incomplete: $($validationFailures -join '; ')"
    exit 2
}

$fullOutput = [System.IO.Path]::GetFullPath($OutputPath)
$parent = Split-Path -Parent $fullOutput
New-Item -ItemType Directory -Path $parent -Force | Out-Null
$temp = "$fullOutput.tmp-$([Guid]::NewGuid().ToString('N'))"
$json = ($proof | ConvertTo-Json -Depth 12) + [Environment]::NewLine
[System.IO.File]::WriteAllText($temp, $json, (New-Object System.Text.UTF8Encoding($false)))
Move-Item -LiteralPath $temp -Destination $fullOutput -Force
if ($proof.status -eq "passed") {
    Write-Host "[PASS] Fresh-context proof written: $fullOutput"
    exit 0
}
Write-Host "[FAIL] Fresh-context proof written with failures: $($validationFailures -join '; ')"
exit 2
