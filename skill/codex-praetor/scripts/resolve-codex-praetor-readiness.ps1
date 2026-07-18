$ErrorActionPreference = "Stop"

function Get-CodexPraetorFileSha256 {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return "" }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Read-CodexPraetorJson {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try { return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}

function Test-CodexPraetorProviderReadiness {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ProviderName,
        [string]$Cli,
        [string]$ModelName,
        [string]$Permission,
        [string]$Kind,
        [string]$ExpectedGeneration,
        [string]$ExpectedRuntimeContract,
        [string]$ExpectedTaskContract
    )

    $state = Read-CodexPraetorJson -Path $Path
    $cliHash = Get-CodexPraetorFileSha256 -Path $Cli
    $result = [ordered]@{
        ok = $false; reason = ""; readiness_path = $Path; provider = $ProviderName; model = $ModelName
        permission_profile = $Permission; task_kind = $Kind; cli_path = $Cli; cli_hash = $cliHash
        generation_id = $ExpectedGeneration; runtime_contract_sha256 = $ExpectedRuntimeContract
        task_contract_schema = $ExpectedTaskContract; checked_at = (Get-Date).ToString("o")
    }
    if ($null -eq $state -or [string]$state.schema -notin @("codex-praetor-provider-readiness/v2", "codex-praetor-generation-readiness/v2") -or $null -eq $state.entries) {
        $result.reason = "缺少可解析的 readiness canary。"
        return [pscustomobject]$result
    }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedGeneration) -and [string]$state.generation_id -ne $ExpectedGeneration) {
        $result.reason = "readiness generation 与当前 generation 不一致。"
        return [pscustomobject]$result
    }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedRuntimeContract) -and [string]$state.runtime_contract_sha256 -ne $ExpectedRuntimeContract) {
        $result.reason = "readiness runtime contract 已漂移。"
        return [pscustomobject]$result
    }
    foreach ($entry in @($state.entries)) {
        if ([string]$entry.status -ne "passed") { continue }
        if ([string]$entry.provider -ne $ProviderName -or [string]$entry.cli_path -ne $Cli -or [string]$entry.cli_hash -ne $cliHash) { continue }
        if ([string]$entry.model -ne $ModelName -or [string]$entry.permission_profile -ne $Permission -or [string]$entry.task_kind -ne $Kind) { continue }
        if (-not [string]::IsNullOrWhiteSpace($ExpectedGeneration) -and [string]$entry.generation_id -ne $ExpectedGeneration) { continue }
        if (-not [string]::IsNullOrWhiteSpace($ExpectedRuntimeContract) -and [string]$entry.runtime_contract_sha256 -ne $ExpectedRuntimeContract) { continue }
        if (-not [string]::IsNullOrWhiteSpace($ExpectedTaskContract) -and [string]$entry.task_contract_schema -ne $ExpectedTaskContract) { continue }
        try { $expires = [DateTime]::Parse([string]$entry.expires_at) } catch { continue }
        if ($expires -le (Get-Date)) { continue }
        $result.ok = $true; $result.reason = "当前 readiness 与 provider/model/permission/task tuple 及 CLI hash 匹配。"; $result.entry = $entry
        return [pscustomobject]$result
    }
    $result.reason = "没有匹配当前 tuple、CLI hash 且未过期的 readiness canary。"
    return [pscustomobject]$result
}

# Function-only module: dispatch and health dot-source this file. A top-level
# param block would execute in the caller scope and overwrite its variables.
