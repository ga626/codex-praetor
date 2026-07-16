param(
    [string]$Repo = (Get-Location).Path,
    [ValidateSet("stable", "dev")]
    [string]$Channel = "stable",
    [string]$UserProfileRoot = $env:USERPROFILE,
    [switch]$Json
)

$ErrorActionPreference = "Stop"
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
$codexRoot = Join-Path $profileRoot ('.' + 'codex')
$installedSkill = Join-Path $codexRoot "skills\codex-praetor"
$installedPlugin = Join-Path $profileRoot "plugins\codex-praetor"
$marketplacePath = Join-Path $profileRoot ".agents\plugins\marketplace.json"
$cacheRoot = Join-Path $codexRoot (Join-Path "plugins" (Join-Path "cache" (Join-Path "personal" "codex-praetor")))
$activeReceiptPath = Join-Path $codexRoot "codex-praetor-releases\$Channel\active.json"
$checks = @()

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
    Add-HealthCheck -Name "source_generation" -Status "ready" -Message "Source generation is not present in this runtime surface; active receipt is authoritative." -Details $sourcePluginRoot
}

$receipt = $null
if (Test-Path -LiteralPath $activeReceiptPath -PathType Leaf) {
    try { $receipt = Get-Content -LiteralPath $activeReceiptPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $receipt = $null }
}
if ($null -eq $receipt -or [string]$receipt.status -ne "active") {
    Add-HealthCheck -Name "active_receipt" -Status "blocked" -Message "No active release receipt exists for this channel; real dispatch must refuse." -Details $activeReceiptPath
} elseif ($null -eq $contract -or [string]$receipt.generation.version -ne [string]$contract.version) {
    Add-HealthCheck -Name "active_receipt" -Status "blocked" -Message "Active receipt does not match the runtime contract version." -Details $activeReceiptPath
} else {
    Add-HealthCheck -Name "active_receipt" -Status "ready" -Message "Active release receipt matches the runtime contract." -Details ([string]$receipt.generation.generation_id)
}

$installedSkillDigest = Get-TreeDigest $installedSkill
$expectedSkillDigest = if ($null -ne $receipt) { [string]$receipt.surfaces.skill.tree_sha256 } else { "" }
if ($expectedSkillDigest -and $installedSkillDigest -and $expectedSkillDigest -eq $installedSkillDigest) {
    Add-HealthCheck -Name "installed_skill" -Status "ready" -Message "Installed Skill matches the active release receipt." -Details $installedSkill
} else {
    Add-HealthCheck -Name "installed_skill" -Status "blocked" -Message "Installed Skill is missing or differs from the active release receipt." -Details $installedSkill
}

$installedPluginDigest = Get-TreeDigest $installedPlugin
$expectedPluginDigest = if ($null -ne $receipt) { [string]$receipt.surfaces.plugin.tree_sha256 } else { "" }
if ($expectedPluginDigest -and $installedPluginDigest -and $expectedPluginDigest -eq $installedPluginDigest) {
    Add-HealthCheck -Name "installed_plugin" -Status "ready" -Message "Installed plugin matches the active release receipt." -Details $installedPlugin
} else {
    Add-HealthCheck -Name "installed_plugin" -Status "blocked" -Message "Installed plugin is missing or differs from the active release receipt." -Details $installedPlugin
}

$cachePath = if ($null -ne $contract) { Join-Path $cacheRoot ([string]$contract.version) } else { "" }
$cacheDigest = Get-TreeDigest $cachePath
$expectedCacheDigest = if ($null -ne $receipt) { [string]$receipt.surfaces.cache.tree_sha256 } else { "" }
if ($expectedCacheDigest -and $cacheDigest -and $expectedCacheDigest -eq $cacheDigest) {
    Add-HealthCheck -Name "plugin_cache_generation" -Status "ready" -Message "Personal cache matches the active release receipt." -Details $cachePath
} else {
    $versions = if (Test-Path -LiteralPath $cacheRoot -PathType Container) { @(Get-ChildItem -LiteralPath $cacheRoot -Directory -Force | Where-Object { -not $_.Name.StartsWith(".") } | ForEach-Object Name) } else { @() }
    Add-HealthCheck -Name "plugin_cache_generation" -Status "blocked" -Message "Personal cache is missing or differs from the active release receipt; real dispatch must refuse." -Details $versions
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

if ($null -ne $receipt -and [string]$receipt.fresh_context.status -eq "passed") {
    Add-HealthCheck -Name "fresh_context" -Status "ready" -Message "Fresh-context MCP proof passed for the active generation." -Details ([string]$receipt.fresh_context.observed_at)
} else {
    Add-HealthCheck -Name "fresh_context" -Status "blocked" -Message "Fresh-context MCP proof is missing or failed; real dispatch must refuse." -Details $activeReceiptPath
}

if ($null -ne $receipt -and [string]$receipt.provider_readiness.status -eq "passed") {
    Add-HealthCheck -Name "provider_readiness" -Status "ready" -Message "Provider readiness passed for the active generation." -Details $activeReceiptPath
} else {
    Add-HealthCheck -Name "provider_readiness" -Status "blocked" -Message "Versioned provider readiness is missing or failed; real dispatch must refuse." -Details $activeReceiptPath
}

$overall = if (@($checks | Where-Object { $_.status -eq "blocked" }).Count -gt 0) { "blocked" } elseif (@($checks | Where-Object { $_.status -ne "ready" }).Count -gt 0) { "degraded" } else { "ready" }
$payload = [pscustomobject]@{
    schema = "codex-praetor-health/v3"
    status = $overall
    repo = (Resolve-Path -LiteralPath $Repo).Path
    channel = $Channel
    runtime_contract = if ($null -eq $contract) { "" } else { [string]$contract.version }
    active_receipt = $activeReceiptPath
    checks = $checks
}
if ($Json) { $payload | ConvertTo-Json -Depth 12 } else { Write-Host "Codex Praetor health: $overall"; $checks | ForEach-Object { Write-Host "[$($_.status)] $($_.name): $($_.message)" } }
if ($overall -eq "blocked") { exit 2 }
