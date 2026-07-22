param([string]$ProjectRoot = "")

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$root = [IO.Path]::GetFullPath($ProjectRoot)
$scratch = Join-Path ([IO.Path]::GetTempPath()) ("codex-praetor-contract-mutation-" + [Guid]::NewGuid().ToString("N"))
$smoke = Join-Path $root "mcp\scripts\smoke-plugin-mcp.js"
function Assert-True([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
try {
    $pluginRoot = Join-Path $scratch "plugin"
    New-Item -ItemType Directory -Path $pluginRoot -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $root "plugin\mcp") -Destination (Join-Path $pluginRoot "mcp") -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $root "plugin\data") -Destination (Join-Path $pluginRoot "data") -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $root "mcp\node_modules") -Destination (Join-Path $pluginRoot "mcp\node_modules") -Recurse -Force
    $pluginContract = Join-Path $pluginRoot "runtime-contract.json"
    Copy-Item -LiteralPath (Join-Path $root "plugin\runtime-contract.json") -Destination $pluginContract -Force
    $contract = Get-Content -LiteralPath $pluginContract -Raw -Encoding UTF8 | ConvertFrom-Json
    $contract.requiredMcpTools = @($contract.requiredMcpTools | Where-Object { $_ -ne "codex_praetor_governance_summary" })
    $contract | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $pluginContract -Encoding UTF8
    $runtime = Join-Path $pluginRoot "mcp\dist\server.js"
    $canonicalContractPath = Join-Path $root "config\runtime-contract.json"
    $canonicalContract = Get-Content -LiteralPath $canonicalContractPath -Raw | ConvertFrom-Json
    $expectedVersion = [string]$canonicalContract.version
    $stdout = Join-Path $scratch "mutation.stdout.log"
    $stderr = Join-Path $scratch "mutation.stderr.log"
    $arguments = @($smoke, $runtime, $scratch, "--skip-dry-run", "--expected-version", $expectedVersion, "--expected-contract", $canonicalContractPath)
    $process = Start-Process -FilePath "node" -ArgumentList $arguments -Wait -PassThru -NoNewWindow -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    Assert-True ($process.ExitCode -ne 0) "Mutation removing a tool from the packaged contract must fail final runtime acceptance."

    Copy-Item -LiteralPath (Join-Path $root "plugin\runtime-contract.json") -Destination $pluginContract -Force
    Remove-Item -LiteralPath (Join-Path $pluginRoot "data") -Recurse -Force
    $dataStdout = Join-Path $scratch "provider-data.stdout.log"
    $dataStderr = Join-Path $scratch "provider-data.stderr.log"
    $dataProcess = Start-Process -FilePath "node" -ArgumentList $arguments -Wait -PassThru -NoNewWindow -RedirectStandardOutput $dataStdout -RedirectStandardError $dataStderr
    Assert-True ($dataProcess.ExitCode -ne 0) "Removing packaged provider operations data must fail final runtime acceptance."
    Write-Host "[PASS] Contract and provider-operations runtime-data fault injection are killed by the final artifact mutation gate."
} finally {
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}
