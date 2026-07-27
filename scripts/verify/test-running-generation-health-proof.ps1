param([string]$ProjectRoot = "")

$ErrorActionPreference = "Stop"
. (Join-Path (Split-Path -Parent $PSScriptRoot) "shared\ensure-file-hash.ps1")
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$profile = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-praetor-health-profile-" + [Guid]::NewGuid().ToString("N"))
$cli = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-praetor-health-cli-" + [Guid]::NewGuid().ToString("N") + ".bin")
$generationScript = Join-Path $ProjectRoot "scripts\release\get-codex-praetor-generation.ps1"
$contractPath = Join-Path $ProjectRoot "config\runtime-contract.json"

function Assert-True { param([bool]$Condition, [string]$Message) if (-not $Condition) { throw $Message } }
function Find-Check { param([object]$Payload, [string]$Name) return @($Payload.checks | Where-Object { $_.name -eq $Name } | Select-Object -First 1)[0] }
function Invoke-HealthProof {
    param([string]$HealthScript, [string]$Repo, [string]$Profile, [switch]$BootstrapDispatch)
    $arguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $HealthScript, "-Repo", $Repo, "-UserProfileRoot", $Profile, "-Json")
    if ($BootstrapDispatch) { $arguments += "-BootstrapDispatch" }
    $previousErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $raw = & powershell @arguments
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorAction
    }
    return [pscustomobject]@{ exit_code = [int]$exitCode; payload = (($raw | Out-String) | ConvertFrom-Json) }
}

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
    $healthRepo = Join-Path $profile "health-repo"
    New-Item -ItemType Directory -Path $healthRepo -Force | Out-Null
    $null = & git -C $healthRepo init -q

    $oldReceipt = [ordered]@{
        schema = "codex-praetor-release-receipt/v2"; status = "active"; channel = "stable"
        generation = [ordered]@{ generation_id = "0.4.1-alpha--old"; version = "0.4.1-alpha"; runtime_contract_sha256 = "old-contract"; task_contract_schema = "codex-praetor-task-contract/v4" }
    }
    $receiptPath = Join-Path $profile ".codex\codex-praetor-releases\stable\active.json"
    New-Item -ItemType Directory -Path (Split-Path -Parent $receiptPath) -Force | Out-Null
    $oldReceipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $receiptPath -Encoding UTF8

    $normalWithoutReadiness = Invoke-HealthProof -HealthScript $healthScript -Repo $healthRepo -Profile $profile
    Assert-True ($normalWithoutReadiness.exit_code -eq 2) "Normal dispatch health must remain blocked without a provider readiness tuple."
    Assert-True ([string]$normalWithoutReadiness.payload.status -eq "blocked") "Missing provider readiness must block normal dispatch health."
    $bootstrapWithoutReadiness = Invoke-HealthProof -HealthScript $healthScript -Repo $healthRepo -Profile $profile -BootstrapDispatch
    $bootstrapReadiness = Find-Check -Payload $bootstrapWithoutReadiness.payload -Name "provider_readiness"
    Assert-True ($bootstrapWithoutReadiness.exit_code -eq 0) "A frozen evidence bootstrap must pass runtime health when provider readiness is the only missing proof."
    Assert-True ([string]$bootstrapWithoutReadiness.payload.status -eq "ready") "Bootstrap dispatch health must be ready when all runtime identity checks pass."
    Assert-True ([string]$bootstrapWithoutReadiness.payload.diagnostic_status -eq "blocked") "Bootstrap dispatch must retain missing provider readiness as a visible diagnostic."
    Assert-True ([bool]$bootstrapWithoutReadiness.payload.bootstrap_dispatch) "Bootstrap health payload must identify the exceptional dispatch mode."
    Assert-True ([string]$bootstrapReadiness.status -eq "blocked") "Bootstrap dispatch must not manufacture provider readiness."
    Assert-True (@($bootstrapWithoutReadiness.payload.dispatch_authority_checks) -notcontains "provider_readiness") "Only provider readiness may be removed from bootstrap dispatch authority."
    foreach ($requiredCheck in @("running_generation", "installed_plugin", "plugin_cache_generation", "marketplace_activation")) {
        Assert-True (@($bootstrapWithoutReadiness.payload.dispatch_authority_checks) -contains $requiredCheck) "Bootstrap dispatch must retain runtime identity check '$requiredCheck'."
    }

    $entry = [ordered]@{
        generation_id = [string]$generation.generation_id; runtime_contract_sha256 = $contractHash; task_contract_schema = [string]$contract.taskContractSchema
        provider = "codebuddy"; cli_path = $cli; cli_hash = $cliHash; model = "hy3"; permission_profile = "local-audit-v1"; task_kind = "local_audit"
        status = "passed"; expires_at = (Get-Date).AddHours(1).ToString("o"); evidence = [ordered]@{ schema = "codex-praetor-canary-evidence/v1"; job_id = "health-proof"; worker_stdout_sha256 = "a"; completion_sha256 = "b"; completion_status = "process_exited"; worker_exit_code = 0; failure_class = "" }
    }
    [ordered]@{
        schema = "codex-praetor-generation-readiness/v3"; status = "passed"; generation_id = [string]$generation.generation_id
        runtime_contract_sha256 = $contractHash; task_contract_schema = [string]$contract.taskContractSchema; entries = @($entry)
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $profile ".codex\codex-praetor-readiness.json") -Encoding UTF8

    $payload = ((& powershell -NoProfile -ExecutionPolicy Bypass -File $healthScript -Repo $healthRepo -UserProfileRoot $profile -Json | Out-String) | ConvertFrom-Json)
    $legacy = Find-Check -Payload $payload -Name "legacy_active_receipt"
    $running = Find-Check -Payload $payload -Name "running_generation"
    $readiness = Find-Check -Payload $payload -Name "provider_readiness"
    Assert-True ([string]$legacy.status -eq "degraded") "An old active receipt must remain diagnostic only."
    Assert-True ([string]$running.status -eq "ready") "Health must resolve the running generation from the current plugin contract."
    Assert-True ([string]$running.details -eq [string]$generation.generation_id) "Bundled health must resolve the packaged Release generation, not a synthetic runtime-contract ID."
    Assert-True ([string]$readiness.status -eq "ready") "Current-generation readiness must pass even when active.json is old."
    Assert-True ([string]$payload.status -eq "ready") "Old receipt plus current plugin/readiness must leave dispatch health ready."
    Assert-True ([string]$payload.diagnostic_status -eq "degraded") "Old receipt must remain visible as diagnostic degradation without changing dispatch health."

    $entry.generation_id = "wrong-generation"
    [ordered]@{
        schema = "codex-praetor-generation-readiness/v3"; status = "passed"; generation_id = "wrong-generation"
        runtime_contract_sha256 = $contractHash; task_contract_schema = [string]$contract.taskContractSchema; entries = @($entry)
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $profile ".codex\codex-praetor-readiness.json") -Encoding UTF8
    $previousErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $wrongPayload = ((& powershell -NoProfile -ExecutionPolicy Bypass -File $healthScript -Repo $healthRepo -UserProfileRoot $profile -Json | Out-String) | ConvertFrom-Json)
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
