$ErrorActionPreference = "Stop"
$hashHelperCandidates = @(
    (Join-Path (Split-Path -Parent $PSScriptRoot) "shared\ensure-file-hash.ps1"),
    (Join-Path $PSScriptRoot "ensure-file-hash.ps1")
)
$hashHelper = @($hashHelperCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1)
if (@($hashHelper).Count -ne 1) { throw "Readiness hash helper is missing." }
. ([string]$hashHelper[0])

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

function Get-CodexPraetorProviderCompatibilityFingerprint {
    param(
        [string]$ProviderName,
        [string]$CliHash,
        [string]$ModelName,
        [string]$Permission,
        [string]$Kind,
        [string]$Distribution,
        [string]$ConnectionMode,
        [string]$RunnerIdentity,
        [string]$TaskContractSchema
    )

    # A release generation identifies a package.  It does not, by itself,
    # describe whether an already-proved external provider connection changed.
    # Keep this compact and explicit so documentation or packaging-only changes
    # cannot silently spend a fresh provider credit, while a runner/protocol,
    # CLI, model, permission or task-contract change fails closed.
    $canonical = @(
        "provider=$ProviderName",
        "cli_hash=$CliHash",
        "model=$ModelName",
        "permission=$Permission",
        "task_kind=$Kind",
        "distribution=$Distribution",
        "connection_mode=$ConnectionMode",
        "runner_identity=$RunnerIdentity",
        "task_contract_schema=$TaskContractSchema"
    ) -join "`n"
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($canonical)))).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Test-CodexPraetorReadinessEvidence {
    param([object]$Entry)

    # Readiness is a compact pointer to a real worker receipt.  Legacy entries
    # without this shape may be historical, but cannot authorize a new task.
    $evidence = $Entry.evidence
    if ($null -eq $evidence) { return $false }
    $basicEvidence = (
        [string]$evidence.schema -eq "codex-praetor-canary-evidence/v1" -and
        -not [string]::IsNullOrWhiteSpace([string]$evidence.job_id) -and
        -not [string]::IsNullOrWhiteSpace([string]$evidence.worker_stdout_sha256) -and
        -not [string]::IsNullOrWhiteSpace([string]$evidence.completion_sha256) -and
        [string]$evidence.completion_status -eq "process_exited" -and
        [int]$evidence.worker_exit_code -eq 0 -and
        [string]$evidence.failure_class -eq "" -and
        -not [string]::IsNullOrWhiteSpace([string]$Entry.distribution) -and
        -not [string]::IsNullOrWhiteSpace([string]$Entry.connection_mode)
    )
    if (-not $basicEvidence) { return $false }

    # A prior canary may have recorded a marker even though the provider said
    # its permission classifier could not run a required check.  Readiness is
    # an authorization decision, so such a receipt must fail closed whenever
    # its retained stdout is still available.
    $stdoutPath = [string]$evidence.stdout_path
    if (-not [string]::IsNullOrWhiteSpace($stdoutPath) -and (Test-Path -LiteralPath $stdoutPath -PathType Leaf)) {
        $stdout = Get-Content -LiteralPath $stdoutPath -Raw -Encoding UTF8
        if ($stdout -match '(?i)classifier unavailable|cannot approve bash') { return $false }
    }
    return $true
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
        [string]$ExpectedTaskContract,
        [string]$ExpectedDistribution = "",
        [string]$ExpectedConnectionMode = "",
        [string]$ExpectedRunnerIdentity = "",
        [string]$ExpectedCompatibilityFingerprint = ""
    )

    $state = Read-CodexPraetorJson -Path $Path
    $cliHash = Get-CodexPraetorFileSha256 -Path $Cli
    $result = [ordered]@{
        ok = $false; reason = ""; readiness_path = $Path; provider = $ProviderName; model = $ModelName
        permission_profile = $Permission; task_kind = $Kind; distribution = $ExpectedDistribution; cli_path = $Cli; cli_hash = $cliHash
        generation_id = $ExpectedGeneration; runtime_contract_sha256 = $ExpectedRuntimeContract
        task_contract_schema = $ExpectedTaskContract; checked_at = (Get-Date).ToString("o")
    }
    if ($null -eq $state -or [string]$state.schema -notin @("codex-praetor-provider-readiness/v2", "codex-praetor-generation-readiness/v2", "codex-praetor-provider-readiness/v3", "codex-praetor-generation-readiness/v3", "codex-praetor-provider-readiness/v4", "codex-praetor-generation-readiness/v4", "codex-praetor-provider-readiness/v5", "codex-praetor-generation-readiness/v5") -or $null -eq $state.entries) {
        $result.reason = "缺少可解析的 readiness canary。"
        return [pscustomobject]$result
    }
    # The file is a multi-generation ledger. Its legacy top-level generation
    # is only a last-write summary and must never hide a valid matching entry.
    foreach ($entry in @($state.entries)) {
        if ([string]$entry.status -ne "passed") { continue }
        if (-not (Test-CodexPraetorReadinessEvidence -Entry $entry)) { continue }
        if ([string]$entry.provider -ne $ProviderName -or [string]$entry.cli_path -ne $Cli -or [string]$entry.cli_hash -ne $cliHash) { continue }
        if ([string]$entry.model -ne $ModelName -or [string]$entry.permission_profile -ne $Permission -or [string]$entry.task_kind -ne $Kind) { continue }
        if (-not [string]::IsNullOrWhiteSpace($ExpectedDistribution) -and [string]$entry.distribution -ne $ExpectedDistribution) { continue }
        if (-not [string]::IsNullOrWhiteSpace($ExpectedConnectionMode) -and [string]$entry.connection_mode -ne $ExpectedConnectionMode) { continue }
        if (-not [string]::IsNullOrWhiteSpace($ExpectedRunnerIdentity) -and [string]$entry.runner_identity -ne $ExpectedRunnerIdentity) { continue }
        $entryFingerprint = [string]$entry.provider_compatibility_fingerprint
        if ([string]::IsNullOrWhiteSpace($entryFingerprint)) {
            # Migration read: v2/v3 records remain usable only after their
            # complete tuple is recomputed.  There is no generation fallback.
            $entryFingerprint = Get-CodexPraetorProviderCompatibilityFingerprint -ProviderName ([string]$entry.provider) -CliHash ([string]$entry.cli_hash) -ModelName ([string]$entry.model) -Permission ([string]$entry.permission_profile) -Kind ([string]$entry.task_kind) -Distribution ([string]$entry.distribution) -ConnectionMode ([string]$entry.connection_mode) -RunnerIdentity ([string]$entry.runner_identity) -TaskContractSchema ([string]$entry.task_contract_schema)
        }
        $expectedFingerprint = $ExpectedCompatibilityFingerprint
        if ([string]::IsNullOrWhiteSpace($expectedFingerprint)) {
            $expectedFingerprint = Get-CodexPraetorProviderCompatibilityFingerprint -ProviderName $ProviderName -CliHash $cliHash -ModelName $ModelName -Permission $Permission -Kind $Kind -Distribution $ExpectedDistribution -ConnectionMode $ExpectedConnectionMode -RunnerIdentity $ExpectedRunnerIdentity -TaskContractSchema $ExpectedTaskContract
        }
        if ($entryFingerprint -ne $expectedFingerprint) { continue }
        try { $expires = [DateTime]::Parse([string]$entry.expires_at) } catch { continue }
        if ($expires -le (Get-Date)) { continue }
        $result.ok = $true; $result.reason = "当前 readiness 与 provider compatibility fingerprint 及 CLI hash 匹配。"; $result.entry = $entry; $result.provider_compatibility_fingerprint = $entryFingerprint
        return [pscustomobject]$result
    }
    $result.reason = "没有匹配当前 compatibility fingerprint、CLI hash 且未过期的 readiness 证据。"
    return [pscustomobject]$result
}

function Get-CodexPraetorCurrentReadinessEntries {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$ExpectedGeneration,
        [string]$ExpectedRuntimeContract,
        [string]$ExpectedTaskContract
    )

    $state = Read-CodexPraetorJson -Path $Path
    $result = [ordered]@{
        ok = $false; reason = ""; readiness_path = $Path
        generation_id = $ExpectedGeneration; runtime_contract_sha256 = $ExpectedRuntimeContract
        task_contract_schema = $ExpectedTaskContract; entries = @(); checked_at = (Get-Date).ToString("o")
    }
    if ($null -eq $state -or [string]$state.schema -notin @("codex-praetor-provider-readiness/v2", "codex-praetor-generation-readiness/v2", "codex-praetor-provider-readiness/v3", "codex-praetor-generation-readiness/v3", "codex-praetor-provider-readiness/v4", "codex-praetor-generation-readiness/v4", "codex-praetor-provider-readiness/v5", "codex-praetor-generation-readiness/v5") -or $null -eq $state.entries) {
        $result.reason = "缺少可解析的 readiness canary。"
        return [pscustomobject]$result
    }
    # See Test-CodexPraetorProviderReadiness: entries, not the legacy
    # last-write summary, are the authority for a requested generation.

    $valid = New-Object System.Collections.Generic.List[object]
    foreach ($entry in @($state.entries)) {
        if ([string]$entry.status -ne "passed") { continue }
        if (-not (Test-CodexPraetorReadinessEvidence -Entry $entry)) { continue }
        # This summary is intentionally a discovery surface.  Dispatch makes
        # the exact compatibility-fingerprint decision for its selected tuple.
        $cliPath = [string]$entry.cli_path
        $cliHash = Get-CodexPraetorFileSha256 -Path $cliPath
        if ([string]::IsNullOrWhiteSpace($cliHash) -or $cliHash -ne [string]$entry.cli_hash) { continue }
        try { $expires = [DateTime]::Parse([string]$entry.expires_at) } catch { continue }
        if ($expires -le (Get-Date)) { continue }
        $valid.Add($entry)
    }
    $result.entries = $valid.ToArray()
    $result.ok = $valid.Count -gt 0
    $result.reason = if ($result.ok) { "存在未过期且 CLI hash 匹配的 readiness tuple；派工仍会校验精确 compatibility fingerprint。" } else { "没有未过期且 CLI hash 匹配的 readiness tuple；首条受限真实计划任务可自动建立证据。" }
    return [pscustomobject]$result
}

# Function-only module: dispatch and health dot-source this file. A top-level
# param block would execute in the caller scope and overwrite its variables.
