param(
    [string]$Repo = (Get-Location).Path,
    [ValidateSet("stable", "dev")]
    [string]$Channel = "stable",
    [string]$UserProfileRoot = $env:USERPROFILE,
    [switch]$Json
)

$ErrorActionPreference = "Stop"
. (Join-Path (Split-Path -Parent $PSScriptRoot) "shared\ensure-file-hash.ps1")
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$candidateRoot = $scriptDir
$projectRoot = ""
for ($index = 0; $index -lt 5; $index++) {
    if (Test-Path -LiteralPath (Join-Path $candidateRoot "config\runtime-contract.json") -PathType Leaf) {
        $projectRoot = $candidateRoot
        break
    }
    if (Test-Path -LiteralPath (Join-Path $candidateRoot "runtime-contract.json") -PathType Leaf) {
        $projectRoot = $candidateRoot
        break
    }
    $parentRoot = Split-Path -Parent $candidateRoot
    if ($parentRoot -eq $candidateRoot) { break }
    $candidateRoot = $parentRoot
}
if ([string]::IsNullOrWhiteSpace($projectRoot)) {
    $projectRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
}

$contractPath = Join-Path $projectRoot "config\runtime-contract.json"
if (-not (Test-Path -LiteralPath $contractPath -PathType Leaf)) {
    $contractPath = Join-Path $projectRoot "runtime-contract.json"
}
$sourcePluginRoot = Join-Path $projectRoot "plugin"
if (-not (Test-Path -LiteralPath (Join-Path $sourcePluginRoot ".codex-plugin\plugin.json") -PathType Leaf)) {
    $sourcePluginRoot = $projectRoot
}
$sourceSkillRoot = Join-Path $projectRoot "skill\codex-praetor"
if (-not (Test-Path -LiteralPath $sourceSkillRoot -PathType Container)) {
    $sourceSkillRoot = Join-Path $projectRoot "skills\codex-praetor"
}

$profileRoot = [System.IO.Path]::GetFullPath($UserProfileRoot)
$isIsolatedProfile = -not [string]::Equals($profileRoot, [System.IO.Path]::GetFullPath($env:USERPROFILE), [System.StringComparison]::OrdinalIgnoreCase)
$codexRoot = Join-Path $profileRoot ('.' + 'codex')
$installedPlugin = Join-Path $profileRoot "plugins\codex-praetor"
$marketplacePath = Join-Path $profileRoot ".agents\plugins\marketplace.json"
$cacheRoot = Join-Path $codexRoot (Join-Path "plugins" (Join-Path "cache" (Join-Path "personal" "codex-praetor")))
$activeReceiptPath = Join-Path $codexRoot "codex-praetor-releases\$Channel\active.json"
$checks = @()
$readinessHelperCandidates = @(
    (Join-Path $projectRoot "scripts\verify\resolve-codex-praetor-readiness.ps1"),
    (Join-Path $scriptDir "resolve-codex-praetor-readiness.ps1")
)
$readinessHelperPath = @($readinessHelperCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1)
if (@($readinessHelperPath).Count -eq 1) { . ([string]$readinessHelperPath[0]) }
$runningGenerationHelperCandidates = @(
    (Join-Path $projectRoot "scripts\verify\resolve-codex-praetor-running-generation.ps1"),
    (Join-Path $scriptDir "resolve-codex-praetor-running-generation.ps1")
)
$runningGenerationHelperPath = @($runningGenerationHelperCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1)
if (@($runningGenerationHelperPath).Count -eq 1) { . ([string]$runningGenerationHelperPath[0]) }
$maintenanceHelperCandidates = @(
    (Join-Path $projectRoot "scripts\maintenance\get-codex-praetor-maintenance-definition.ps1"),
    (Join-Path $scriptDir "get-codex-praetor-maintenance-definition.ps1")
)
$maintenanceHelperPath = @($maintenanceHelperCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1)
if (@($maintenanceHelperPath).Count -eq 1) { . ([string]$maintenanceHelperPath[0]) }
$inventoryScriptCandidates = @(
    (Join-Path $projectRoot "scripts\verify\get-codex-praetor-runtime-inventory.ps1"),
    (Join-Path $scriptDir "get-codex-praetor-runtime-inventory.ps1")
)
$inventoryScriptPath = @($inventoryScriptCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1)

function Add-HealthCheck {
    param([string]$Name, [string]$Status, [string]$Message, [object]$Details)
    $script:checks += [pscustomobject]@{ name = $Name; status = $Status; message = $Message; details = $Details }
}

function Get-TreeDigest {
    param([string]$Root)
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { return "" }
    $rows = @(
        Get-ChildItem -LiteralPath $Root -Recurse -File -Force |
            Sort-Object FullName |
            ForEach-Object {
                $relative = $_.FullName.Substring($Root.Length).TrimStart("\\") -replace "\\", "/"
                "$relative|$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant())"
            }
    )
    $bytes = [Text.Encoding]::UTF8.GetBytes(($rows -join "`n"))
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant() } finally { $sha.Dispose() }
}

if (-not (Test-Path -LiteralPath $contractPath -PathType Leaf)) {
    Add-HealthCheck -Name "runtime_contract" -Status "blocked" -Message "Runtime contract is missing." -Details $contractPath
    $contract = $null
} else {
    $contract = Get-Content -LiteralPath $contractPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Add-HealthCheck -Name "runtime_contract" -Status "ready" -Message "Runtime contract is loaded." -Details ([string]$contract.version)
}
$runtimeContractHash = if ($null -eq $contract) { "" } else { (Get-FileHash -LiteralPath $contractPath -Algorithm SHA256).Hash.ToLowerInvariant() }

$runningGeneration = if ($null -eq $contract -or @($runningGenerationHelperPath).Count -ne 1) { $null } else {
    Resolve-CodexPraetorRunningGeneration -RuntimeContractPath $contractPath -ProjectRoot $projectRoot -ScriptDirectory $scriptDir
}
if ($null -ne $runningGeneration -and [string]$runningGeneration.version -eq [string]$contract.version -and [string]$runningGeneration.runtime_contract_sha256 -eq $runtimeContractHash -and [string]$runningGeneration.task_contract_schema -eq [string]$contract.taskContractSchema -and -not [string]::IsNullOrWhiteSpace([string]$runningGeneration.generation_id)) {
    Add-HealthCheck -Name "running_generation" -Status "ready" -Message "当前运行插件 generation 与其 bundled runtime contract 一致。" -Details ([string]$runningGeneration.generation_id)
} else {
    Add-HealthCheck -Name "running_generation" -Status "blocked" -Message "当前运行插件 generation 缺失，或与 bundled runtime contract 不一致。" -Details $sourcePluginRoot
}

$sourcePluginInspectable = $null -ne $contract -and (Test-Path -LiteralPath (Join-Path $sourcePluginRoot ".codex-plugin\plugin.json") -PathType Leaf) -and (Test-Path -LiteralPath (Join-Path $sourcePluginRoot "mcp\package.json") -PathType Leaf)
if ($sourcePluginInspectable) {
    $manifest = Get-Content -LiteralPath (Join-Path $sourcePluginRoot ".codex-plugin\plugin.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    $package = Get-Content -LiteralPath (Join-Path $sourcePluginRoot "mcp\package.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$manifest.version -eq [string]$contract.version -and [string]$package.version -eq [string]$contract.version) {
        Add-HealthCheck -Name "source_generation" -Status "ready" -Message "Source plugin and MCP match the runtime contract." -Details ([string]$contract.version)
    } else {
        Add-HealthCheck -Name "source_generation" -Status "blocked" -Message "Source plugin or MCP does not match the runtime contract." -Details "$($manifest.version) | $($package.version) | expected=$($contract.version)"
    }
} else {
    Add-HealthCheck -Name "source_generation" -Status "ready" -Message "Source generation is not present in this runtime surface; the running bundled contract is authoritative." -Details $sourcePluginRoot
}

$receipt = $null
if (Test-Path -LiteralPath $activeReceiptPath -PathType Leaf) {
    try { $receipt = Get-Content -LiteralPath $activeReceiptPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $receipt = $null }
}
if ($null -eq $receipt -or [string]$receipt.status -ne "active") {
    Add-HealthCheck -Name "legacy_active_receipt" -Status "degraded" -Message "Legacy local release receipt is absent; published artifact and running plugin remain independently usable." -Details $activeReceiptPath
} elseif ($null -eq $contract -or [string]$receipt.schema -ne "codex-praetor-release-receipt/v2" -or [string]$receipt.generation.version -ne [string]$contract.version -or [string]$receipt.generation.task_contract_schema -ne [string]$contract.taskContractSchema) {
    Add-HealthCheck -Name "legacy_active_receipt" -Status "degraded" -Message "Legacy local release receipt differs from the running plugin; it is diagnostic only and must not block dispatch." -Details $activeReceiptPath
} else {
    Add-HealthCheck -Name "legacy_active_receipt" -Status "ready" -Message "Legacy local release receipt matches the runtime contract." -Details ([string]$receipt.generation.generation_id)
}

Add-HealthCheck -Name "global_skill" -Status "ready" -Message "Global Skill is not a runtime dependency; the active plugin bundles its own Skill." -Details "plugin/skills/codex-praetor"

$installedPluginDigest = Get-TreeDigest $installedPlugin
if ($installedPluginDigest) {
    Add-HealthCheck -Name "installed_plugin" -Status "ready" -Message "Marketplace source plugin is present." -Details $installedPlugin
} else {
    Add-HealthCheck -Name "installed_plugin" -Status "blocked" -Message "Marketplace source plugin is missing." -Details $installedPlugin
}

$cachePath = if ($null -ne $contract) { Join-Path $cacheRoot ([string]$contract.version) } else { "" }
if (Test-Path -LiteralPath $cachePath -PathType Container) {
    Add-HealthCheck -Name "plugin_cache_generation" -Status "ready" -Message "Codex-managed cache contains the running plugin version." -Details $cachePath
} else {
    $versions = if (Test-Path -LiteralPath $cacheRoot -PathType Container) { @(Get-ChildItem -LiteralPath $cacheRoot -Directory -Force | Where-Object { -not $_.Name.StartsWith(".") } | ForEach-Object Name) } else { @() }
    Add-HealthCheck -Name "plugin_cache_generation" -Status "blocked" -Message "Codex-managed cache is missing the runtime contract version." -Details $versions
}

$marketplaceOk = $false
if (Test-Path -LiteralPath $marketplacePath -PathType Leaf) {
    try {
        $marketplace = Get-Content -LiteralPath $marketplacePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $entry = @($marketplace.plugins | Where-Object { $_.name -eq "codex-praetor" } | Select-Object -First 1)
        $marketplaceOk = $entry.Count -eq 1 -and [string]$entry[0].source.path -eq "./plugins/codex-praetor"
    } catch { $marketplaceOk = $false }
}
if ($marketplaceOk) {
    Add-HealthCheck -Name "marketplace_activation" -Status "ready" -Message "Marketplace points at the active plugin path." -Details $marketplacePath
} else {
    Add-HealthCheck -Name "marketplace_activation" -Status "blocked" -Message "Marketplace does not point at the expected Codex Praetor plugin path." -Details $marketplacePath
}

if ($null -ne $receipt -and [string]$receipt.fresh_context.schema -eq "codex-praetor-fresh-context-proof/v2" -and [string]$receipt.fresh_context.status -eq "passed" -and [string]$receipt.fresh_context.generation_id -eq [string]$runningGeneration.generation_id -and [string]$receipt.fresh_context.runtime_identity.runtime_contract_sha256 -eq $runtimeContractHash -and [string]$receipt.fresh_context.runtime_info.runtime_contract.version -eq [string]$contract.version -and [int64]$receipt.fresh_context.runtime_identity.process_id -gt 0) {
    Add-HealthCheck -Name "fresh_context" -Status "ready" -Message "Fresh-context MCP proof passed for the active generation." -Details ([string]$receipt.fresh_context.observed_at)
} else {
    Add-HealthCheck -Name "fresh_context" -Status "degraded" -Message "No running-generation proof is stored in the legacy receipt. Native runtime_info remains the authoritative host observation." -Details $activeReceiptPath
}

$readinessPath = Join-Path $profileRoot ".codex\codex-praetor-readiness.json"
$readinessResult = $null
if ($null -ne $runningGeneration -and (Get-Command Get-CodexPraetorCurrentReadinessEntries -ErrorAction SilentlyContinue)) {
    $readinessResult = Get-CodexPraetorCurrentReadinessEntries -Path $readinessPath -ExpectedGeneration ([string]$runningGeneration.generation_id) -ExpectedRuntimeContract $runtimeContractHash -ExpectedTaskContract ([string]$contract.taskContractSchema)
}
if ($null -ne $readinessResult -and $readinessResult.ok) {
    Add-HealthCheck -Name "provider_readiness" -Status "ready" -Message "当前运行 generation 已有有效 provider readiness tuple；真实派工仍会逐项校验实际选择的 tuple。" -Details $readinessResult
} else {
    $details = if ($null -eq $readinessResult) { $readinessPath } else { $readinessResult }
    Add-HealthCheck -Name "provider_readiness" -Status "blocked" -Message "当前运行 generation 没有有效 readiness tuple；先真实运行一次 capability canary，再派工。" -Details $details
}

$retirementManifestPath = Join-Path (Split-Path -Parent $activeReceiptPath) "retirement.json"
$retirement = $null
$retirementSummary = [pscustomobject]@{
    manifest = $retirementManifestPath
    status = "not_initialized"
    counts = [pscustomobject]@{ total = 0; pending = 0; blocked_by_process = 0; deferred = 0; deleted = 0 }
}
if (Test-Path -LiteralPath $retirementManifestPath -PathType Leaf) {
    try {
        $retirement = Get-Content -LiteralPath $retirementManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $entries = @($retirement.entries)
        $retirementSummary.counts.total = @($entries).Count
        $retirementSummary.counts.pending = @($entries | Where-Object { [string]$_.status -eq "pending" }).Count
        $retirementSummary.counts.blocked_by_process = @($entries | Where-Object { [string]$_.status -eq "blocked_by_process" }).Count
        $retirementSummary.counts.deferred = @($entries | Where-Object { [string]$_.status -like "deferred_*" }).Count
        $retirementSummary.counts.deleted = @($entries | Where-Object { [string]$_.status -eq "deleted" }).Count
        $retirementSummary.status = "readable"
        Add-HealthCheck -Name "generation_retirement" -Status "ready" -Message "退休回收状态已读取；待回收或占用路径不会阻断当前 active generation。" -Details $retirementSummary
    } catch {
        $retirementSummary.status = "invalid"
        $retirementSummary.error = $_.Exception.Message
        Add-HealthCheck -Name "generation_retirement" -Status "degraded" -Message "退休清单无法读取；active generation 未回滚，但需要维护任务重试或人工检查。" -Details $retirementSummary
    }
} else {
    Add-HealthCheck -Name "generation_retirement" -Status "ready" -Message "当前没有退休清单；没有待回收代际。" -Details $retirementSummary
}

if (@($inventoryScriptPath).Count -eq 1) {
    try {
        $inventory = (& powershell -NoProfile -ExecutionPolicy Bypass -File ([string]$inventoryScriptPath[0]) -Repo $Repo -UserProfileRoot $profileRoot -Channel $Channel -Json | Out-String) | ConvertFrom-Json
        $inventoryStatus = if (@($inventory.items | Where-Object { $_.category -eq "dirty/unmerged" }).Count -gt 0) { "degraded" } else { "ready" }
        Add-HealthCheck -Name "runtime_inventory" -Status $inventoryStatus -Message "runtime inventory 已生成；当前默认只读且保留 active/dirty/audit 项。" -Details $inventory
    } catch { Add-HealthCheck -Name "runtime_inventory" -Status "degraded" -Message "runtime inventory 生成失败；不得据此删除任何代际。" -Details $_.Exception.Message }
} else {
    Add-HealthCheck -Name "runtime_inventory" -Status "degraded" -Message "runtime inventory adapter 缺失。" -Details $projectRoot
}

$maintenanceTaskName = "CodexPraetor-GenerationReconcile"
 $hasMaintenanceAdapter = $null -ne (Get-Command Get-CodexPraetorMaintenanceDefinition -ErrorAction SilentlyContinue) -and $null -ne (Get-Command Get-CodexPraetorMaintenanceTaskInspection -ErrorAction SilentlyContinue)
if ($isIsolatedProfile) {
    Add-HealthCheck -Name "generation_maintenance" -Status "ready" -Message "隔离 profile 不安装 Windows 维护任务；这不会阻断开发验收。" -Details ([pscustomobject]@{ task_name = $maintenanceTaskName; status = "not_applicable" })
} elseif ($hasMaintenanceAdapter) {
    $definition = Get-CodexPraetorMaintenanceDefinition -Profile $profileRoot -Source $projectRoot -Name $maintenanceTaskName
    $inspection = Get-CodexPraetorMaintenanceTaskInspection -Definition $definition
    $taskReady = $inspection.exists -and $inspection.enabled -and $inspection.action_matches -and $inspection.triggers_match -and ([string]$inspection.state -in @("Ready", "Running"))
    $taskStatus = if ($taskReady) { "ready" } elseif (-not $inspection.exists) { "degraded" } else { "blocked" }
    Add-HealthCheck -Name "generation_maintenance" -Status $taskStatus -Message ([string]$inspection.reason) -Details ([pscustomobject]@{ definition = $definition; inspection = $inspection })
} else {
    Add-HealthCheck -Name "generation_maintenance" -Status "degraded" -Message "维护任务 adapter 缺失，无法验证任务定义。" -Details $maintenanceTaskName
}

$authoritativeDispatchChecks = @("running_generation", "installed_plugin", "plugin_cache_generation", "marketplace_activation", "provider_readiness")
$dispatchBlocked = @($checks | Where-Object { $_.name -in $authoritativeDispatchChecks -and $_.status -eq "blocked" }).Count -gt 0
$dispatchStatus = if ($dispatchBlocked) { "blocked" } else { "ready" }
$diagnosticStatus = if (@($checks | Where-Object { $_.status -eq "blocked" }).Count -gt 0) { "blocked" } elseif (@($checks | Where-Object { $_.status -ne "ready" }).Count -gt 0) { "degraded" } else { "ready" }
$payload = [pscustomobject]@{
    schema = "codex-praetor-health/v5"
    status = $dispatchStatus
    diagnostic_status = $diagnosticStatus
    dispatch_authority_checks = $authoritativeDispatchChecks
    repo = (Resolve-Path -LiteralPath $Repo).Path
    channel = $Channel
    runtime_contract = if ($null -eq $contract) { "" } else { [string]$contract.version }
    active_receipt = $activeReceiptPath
    generation_retirement = $retirementSummary
    checks = $checks
}
if ($Json) { $payload | ConvertTo-Json -Depth 12 } else { Write-Host "Codex Praetor dispatch health: $dispatchStatus; diagnostic health: $diagnosticStatus"; $checks | ForEach-Object { Write-Host "[$($_.status)] $($_.name): $($_.message)" } }
if ($dispatchStatus -eq "blocked") { exit 2 }
