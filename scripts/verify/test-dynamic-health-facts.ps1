param([string]$ProjectRoot = "")

$ErrorActionPreference = "Stop"
. (Join-Path (Split-Path -Parent $PSScriptRoot) "shared\ensure-file-hash.ps1")
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$readiness = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-praetor-readiness-" + [Guid]::NewGuid().ToString("N") + ".json")
$cli = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-praetor-cli-" + [Guid]::NewGuid().ToString("N") + ".bin")
$helper = Join-Path $ProjectRoot "scripts\verify\resolve-codex-praetor-readiness.ps1"
$maintenance = Join-Path $ProjectRoot "scripts\maintenance\get-codex-praetor-maintenance-definition.ps1"
function Assert-True { param([bool]$Condition, [string]$Message) if (-not $Condition) { throw $Message } }
try {
    Set-Content -LiteralPath $cli -Value "cli-v1" -Encoding UTF8
    $providerSentinel = "codebuddy"
    . $helper
    Assert-True ($providerSentinel -eq "codebuddy") "Readiness helper dot-source must not overwrite caller variables."
    $cliHash = (Get-FileHash $cli -Algorithm SHA256).Hash.ToLowerInvariant()
    $evidence = [ordered]@{ schema = "codex-praetor-canary-evidence/v1"; job_id = "fixture-job"; worker_stdout_sha256 = "a"; completion_sha256 = "b"; completion_status = "process_exited"; worker_exit_code = 0; failure_class = "" }
    $entry = [ordered]@{ generation_id = "gen-1"; runtime_contract_sha256 = "contract-1"; task_contract_schema = "task-v4"; provider = "codebuddy"; cli_path = $cli; cli_hash = $cliHash; model = "hy3"; permission_profile = "local-audit-v1"; task_kind = "local_audit"; status = "passed"; expires_at = (Get-Date).AddHours(1).ToString("o"); evidence = $evidence }
    [ordered]@{ schema = "codex-praetor-provider-readiness/v3"; generation_id = "gen-1"; runtime_contract_sha256 = "contract-1"; entries = @($entry) } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $readiness -Encoding UTF8
    $ok = Test-CodexPraetorProviderReadiness -Path $readiness -ProviderName codebuddy -Cli $cli -ModelName hy3 -Permission local-audit-v1 -Kind local_audit -ExpectedGeneration gen-1 -ExpectedRuntimeContract contract-1 -ExpectedTaskContract task-v4
    Assert-True $ok.ok "Current readiness tuple should pass."
    $currentEntries = Get-CodexPraetorCurrentReadinessEntries -Path $readiness -ExpectedGeneration gen-1 -ExpectedRuntimeContract contract-1 -ExpectedTaskContract task-v4
    Assert-True $currentEntries.ok "Current-generation readiness summary should find the valid tuple."
    $wrongGeneration = Get-CodexPraetorCurrentReadinessEntries -Path $readiness -ExpectedGeneration gen-2 -ExpectedRuntimeContract contract-1 -ExpectedTaskContract task-v4
    Assert-True (-not $wrongGeneration.ok) "A readiness summary must reject a different running generation."
    $entryGen2 = [ordered]@{ generation_id = "gen-2"; runtime_contract_sha256 = "contract-2"; task_contract_schema = "task-v4"; provider = "qoder"; cli_path = $cli; cli_hash = $cliHash; model = "Qwen3.7-Plus"; permission_profile = "local-audit-v1"; task_kind = "local_audit"; status = "passed"; expires_at = (Get-Date).AddHours(1).ToString("o"); evidence = $evidence }
    [ordered]@{ schema = "codex-praetor-generation-readiness/v3"; generation_id = "gen-2"; runtime_contract_sha256 = "contract-2"; entries = @($entry, $entryGen2) } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $readiness -Encoding UTF8
    $multiGeneration = Get-CodexPraetorCurrentReadinessEntries -Path $readiness -ExpectedGeneration gen-1 -ExpectedRuntimeContract contract-1 -ExpectedTaskContract task-v4
    Assert-True $multiGeneration.ok "A legacy top-level generation must not hide a valid matching entry."
    Set-Content -LiteralPath $cli -Value "cli-v2" -Encoding UTF8
    $drift = Test-CodexPraetorProviderReadiness -Path $readiness -ProviderName codebuddy -Cli $cli -ModelName hy3 -Permission local-audit-v1 -Kind local_audit -ExpectedGeneration gen-1 -ExpectedRuntimeContract contract-1 -ExpectedTaskContract task-v4
    Assert-True (-not $drift.ok) "CLI hash drift must fail closed."
    [ordered]@{ schema = "codex-praetor-provider-readiness/v3"; generation_id = "gen-1"; runtime_contract_sha256 = "contract-1"; entries = @([ordered]@{ generation_id = "gen-1"; runtime_contract_sha256 = "contract-1"; task_contract_schema = "task-v4"; provider = "codebuddy"; cli_path = $cli; cli_hash = (Get-FileHash $cli -Algorithm SHA256).Hash.ToLowerInvariant(); model = "hy3"; permission_profile = "local-audit-v1"; task_kind = "local_audit"; status = "passed"; expires_at = (Get-Date).AddMinutes(-1).ToString("o"); evidence = $evidence }) } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $readiness -Encoding UTF8
    $expired = Test-CodexPraetorProviderReadiness -Path $readiness -ProviderName codebuddy -Cli $cli -ModelName hy3 -Permission local-audit-v1 -Kind local_audit -ExpectedGeneration gen-1 -ExpectedRuntimeContract contract-1 -ExpectedTaskContract task-v4
    Assert-True (-not $expired.ok) "Expired readiness must fail closed."
    . $maintenance
    $definition = Get-CodexPraetorMaintenanceDefinition -Profile (Join-Path $env:TEMP "codex-praetor-profile") -Source $ProjectRoot -Name CodexPraetor-Test
    Assert-True ([string]$definition.executable -eq "powershell.exe") "Maintenance adapter executable is not canonical."
    Assert-True ([string]$definition.arguments -match "reconcile-codex-praetor-generations.ps1") "Maintenance adapter arguments are not canonical."
    Write-Host "[PASS] Dynamic readiness and canonical maintenance facts are verified."
} finally {
    foreach ($path in @($readiness, $cli)) { if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue } }
}
