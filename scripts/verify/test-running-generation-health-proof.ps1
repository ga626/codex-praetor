param([string]$ProjectRoot = "")

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$profile = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-praetor-health-profile-" + [Guid]::NewGuid().ToString("N"))
$cli = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-praetor-health-cli-" + [Guid]::NewGuid().ToString("N") + ".bin")
$generationScript = Join-Path $ProjectRoot "scripts\release\get-codex-praetor-generation.ps1"
$contractPath = Join-Path $ProjectRoot "config\runtime-contract.json"

function Assert-True { param([bool]$Condition, [string]$Message) if (-not $Condition) { throw $Message } }
function Find-Check { param([object]$Payload, [string]$Name) return @($Payload.checks | Where-Object { $_.name -eq $Name } | Select-Object -First 1)[0] }

try {
    $contract = Get-Content -LiteralPath $contractPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $generation = (& $generationScript -ProjectRoot $ProjectRoot -Json | ConvertFrom-Json)
    $contractHash = (Get-FileHash -LiteralPath $contractPath -Algorithm SHA256).Hash.ToLowerInvariant()
    Set-Content -LiteralPath $cli -Value "health-proof-cli" -Encoding UTF8
    $cliHash = (Get-FileHash -LiteralPath $cli -Algorithm SHA256).Hash.ToLowerInvariant()

    $installedPlugin = Join-Path $profile "plugins\codex-praetor"
    New-Item -ItemType Directory -Path (Split-Path -Parent $installedPlugin) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $ProjectRoot "plugin") -Destination $installedPlugin -Recurse -Force
    $generation | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $installedPlugin "release-generation.json") -Encoding UTF8
    $healthScript = Join-Path $installedPlugin "skills\codex-praetor\scripts\get-codex-praetor-health.ps1"
    $codexRoot = Join-Path $profile ('.' + 'codex')
    $cacheRoot = Join-Path $codexRoot (Join-Path "plugins" (Join-Path "cache" (Join-Path "personal" "codex-praetor")))
    New-Item -ItemType Directory -Path (Join-Path $cacheRoot ([string]$contract.version)) -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $profile ".agents\plugins") -Force | Out-Null
    [ordered]@{ plugins = @([ordered]@{ name = "codex-praetor"; source = [ordered]@{ path = "./plugins/codex-praetor" } }) } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $profile ".agents\plugins\marketplace.json") -Encoding UTF8

    $oldReceipt = [ordered]@{
        schema = "codex-praetor-release-receipt/v2"; status = "active"; channel = "stable"
        generation = [ordered]@{ generation_id = "0.4.1-alpha--old"; version = "0.4.1-alpha"; runtime_contract_sha256 = "old-contract"; task_contract_schema = "codex-praetor-task-contract/v4" }
    }
    $receiptPath = Join-Path $profile ".codex\codex-praetor-releases\stable\active.json"
    New-Item -ItemType Directory -Path (Split-Path -Parent $receiptPath) -Force | Out-Null
    $oldReceipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $receiptPath -Encoding UTF8

    $entry = [ordered]@{
        generation_id = [string]$generation.generation_id; runtime_contract_sha256 = $contractHash; task_contract_schema = [string]$contract.taskContractSchema
        provider = "codebuddy"; cli_path = $cli; cli_hash = $cliHash; model = "hy3"; permission_profile = "local-audit-v1"; task_kind = "local_audit"
        status = "passed"; expires_at = (Get-Date).AddHours(1).ToString("o")
    }
    [ordered]@{
        schema = "codex-praetor-generation-readiness/v2"; status = "passed"; generation_id = [string]$generation.generation_id
        runtime_contract_sha256 = $contractHash; task_contract_schema = [string]$contract.taskContractSchema; entries = @($entry)
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $profile ".codex\codex-praetor-readiness.json") -Encoding UTF8

    $payload = ((& powershell -NoProfile -ExecutionPolicy Bypass -File $healthScript -Repo $ProjectRoot -UserProfileRoot $profile -Json | Out-String) | ConvertFrom-Json)
    $legacy = Find-Check -Payload $payload -Name "legacy_active_receipt"
    $running = Find-Check -Payload $payload -Name "running_generation"
    $readiness = Find-Check -Payload $payload -Name "provider_readiness"
    Assert-True ([string]$legacy.status -eq "degraded") "An old active receipt must remain diagnostic only."
    Assert-True ([string]$running.status -eq "ready") "Health must resolve the running generation from the current plugin contract."
    Assert-True ([string]$running.details -eq [string]$generation.generation_id) "Bundled health must resolve the packaged Release generation, not a synthetic runtime-contract ID."
    Assert-True ([string]$readiness.status -eq "ready") "Current-generation readiness must pass even when active.json is old."
    Assert-True ([string]$payload.status -ne "blocked") "Old receipt plus current plugin/readiness must not block health."

    $entry.generation_id = "wrong-generation"
    [ordered]@{
        schema = "codex-praetor-generation-readiness/v2"; status = "passed"; generation_id = "wrong-generation"
        runtime_contract_sha256 = $contractHash; task_contract_schema = [string]$contract.taskContractSchema; entries = @($entry)
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $profile ".codex\codex-praetor-readiness.json") -Encoding UTF8
    $previousErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $wrongPayload = ((& powershell -NoProfile -ExecutionPolicy Bypass -File $healthScript -Repo $ProjectRoot -UserProfileRoot $profile -Json | Out-String) | ConvertFrom-Json)
        $wrongExitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorAction
    }
    $wrongReadiness = Find-Check -Payload $wrongPayload -Name "provider_readiness"
    Assert-True ($wrongExitCode -ne 0) "A readiness proof for another generation must fail closed."
    Assert-True ([string]$wrongReadiness.status -eq "blocked") "Wrong-generation readiness proof must be blocked."
    Write-Host "[PASS] Running generation is the health readiness authority."
} finally {
    foreach ($path in @($profile, $cli)) { if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue } }
}
