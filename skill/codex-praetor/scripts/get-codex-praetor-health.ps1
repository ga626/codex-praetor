param(
    [string]$Repo = (Get-Location).Path,
    [switch]$Json
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = ""
$candidateRoot = $scriptDir
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
$manifestPath = Join-Path $projectRoot "plugin\.codex-plugin\plugin.json"
$packagePath = Join-Path $projectRoot "plugin\mcp\package.json"
$skillPath = Join-Path $env:USERPROFILE ".codex\skills\codex-praetor"
$codexHome = Join-Path $env:USERPROFILE ('.' + 'codex')
$cacheRoot = Join-Path $codexHome (Join-Path "plugins" (Join-Path "cache" (Join-Path "personal" "codex-praetor")))
$readinessPath = Join-Path $env:USERPROFILE ".codex\codex-praetor-readiness.json"

function Add-HealthCheck {
    param([string]$Name, [string]$Status, [string]$Message, [object]$Details)
    $script:checks += [pscustomobject]@{
        name = $Name
        status = $Status
        message = $Message
        details = $Details
    }
}

$checks = @()
$contract = $null
if (Test-Path -LiteralPath $contractPath -PathType Leaf) {
    $contract = Get-Content -LiteralPath $contractPath -Raw -Encoding UTF8 | ConvertFrom-Json
}
$expectedVersion = if ($null -eq $contract) { "" } else { [string]$contract.version }
if ([string]::IsNullOrWhiteSpace($expectedVersion)) {
    Add-HealthCheck -Name "runtime_contract" -Status "blocked" -Message "运行时合同缺失或无版本。" -Details $contractPath
} else {
    Add-HealthCheck -Name "runtime_contract" -Status "ready" -Message "运行时合同已加载。" -Details $expectedVersion
}

$manifestVersion = ""
$packageVersion = ""
if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
    $manifestVersion = [string]((Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json).version)
}
if (Test-Path -LiteralPath $packagePath -PathType Leaf) {
    $packageVersion = [string]((Get-Content -LiteralPath $packagePath -Raw -Encoding UTF8 | ConvertFrom-Json).version)
}
if ($manifestVersion -eq $expectedVersion -and $packageVersion -eq $expectedVersion -and -not [string]::IsNullOrWhiteSpace($expectedVersion)) {
    Add-HealthCheck -Name "source_generation" -Status "ready" -Message "源码 Plugin/MCP 版本与合同一致。" -Details $expectedVersion
} else {
    Add-HealthCheck -Name "source_generation" -Status "blocked" -Message "源码 Plugin/MCP 版本与合同不一致。" -Details "$manifestVersion | $packageVersion | expected=$expectedVersion"
}

if (Test-Path -LiteralPath $skillPath -PathType Container) {
    Add-HealthCheck -Name "installed_skill" -Status "ready" -Message "已安装 Skill 目录存在。" -Details $skillPath
} else {
    Add-HealthCheck -Name "installed_skill" -Status "blocked" -Message "未找到已安装 Skill。" -Details $skillPath
}

$cacheManifest = Join-Path (Join-Path $cacheRoot $expectedVersion) ".codex-plugin\plugin.json"
if (Test-Path -LiteralPath $cacheManifest -PathType Leaf) {
    Add-HealthCheck -Name "plugin_cache_generation" -Status "ready" -Message "personal cache 含当前合同版本。" -Details $cacheManifest
} else {
    $found = @()
    if (Test-Path -LiteralPath $cacheRoot -PathType Container) {
        $cacheDirectories = Get-ChildItem -LiteralPath $cacheRoot -Directory -Force
        foreach ($cacheDirectory in $cacheDirectories) {
            if (-not $cacheDirectory.Name.StartsWith([string][char]46)) {
                $found += $cacheDirectory.Name
            }
        }
    }
    Add-HealthCheck -Name "plugin_cache_generation" -Status "blocked" -Message "personal cache 缺少当前合同版本；真实派工必须拒绝。" -Details $found
}

if (Test-Path -LiteralPath $readinessPath -PathType Leaf) {
    Add-HealthCheck -Name "provider_readiness" -Status "ready" -Message "存在 provider canary 状态；派工时仍需校验完整 tuple。" -Details $readinessPath
} else {
    Add-HealthCheck -Name "provider_readiness" -Status "unknown" -Message "尚未记录版本化 capability canary；真实派工应拒绝。" -Details $readinessPath
}

$overall = "ready"
if (@($checks | Where-Object { $_.status -eq "blocked" }).Count -gt 0) {
    $overall = "blocked"
} elseif (@($checks | Where-Object { $_.status -eq "unknown" }).Count -gt 0) {
    $overall = "degraded"
}

$payload = [pscustomobject]@{
    schema = "codex-praetor-health/v2"
    status = $overall
    repo = (Resolve-Path -LiteralPath $Repo).Path
    runtime_contract = $expectedVersion
    checks = $checks
}

if ($Json) {
    $payload | ConvertTo-Json -Depth 8
} else {
    Write-Host "Codex Praetor health: $overall"
    $checks | ForEach-Object { Write-Host ("[{0}] {1}: {2}" -f $_.status, $_.name, $_.message) }
}

if ($overall -eq "blocked") { exit 2 }
