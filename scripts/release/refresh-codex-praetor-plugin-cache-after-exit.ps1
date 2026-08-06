param(
    [string]$UserProfileRoot = $env:USERPROFILE,
    [string]$CodexCommand = "codex",
    [string]$PluginSelector = "codex-praetor@personal",
    [Parameter(Mandatory = $true)][string]$ExpectedVersion,
    [Parameter(Mandatory = $true)][string]$StatusPath,
    [string]$PendingStatusPath = "",
    [string]$ExpectedGenerationId = "",
    [string]$ExpectedRuntimeContractSha256 = "",
    [string]$ExpectedZipSha256 = "",
    # Zero means keep waiting for the supported Desktop exit. A finite value is
    # reserved for tests or an explicitly bounded maintenance invocation.
    [int]$WaitTimeoutSeconds = 0,
    [switch]$SkipHostExitWait
)

$ErrorActionPreference = "Stop"
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) {
    $global:PSNativeCommandUseErrorActionPreference = $false
}

function Write-State {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Status,
        [Parameter(Mandatory = $true)][string]$Reason,
        [int]$ExitCode = 0,
        [object[]]$ObservedHostProcesses = @(),
        [object]$ObservedGeneration = $null
    )
    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $payload = [ordered]@{
        schema = "codex-praetor-deferred-plugin-cache-refresh/v1"
        status = $Status
        reason = $Reason
        expected_version = $ExpectedVersion
        expected_generation_id = $ExpectedGenerationId
        expected_runtime_contract_sha256 = $ExpectedRuntimeContractSha256
        expected_zip_sha256 = $ExpectedZipSha256
        observed_host_processes = @($ObservedHostProcesses)
        observed_generation = $ObservedGeneration
        updated_at = [DateTime]::UtcNow.ToString("o")
        exit_code = $ExitCode
    }
    $temporaryPath = "$Path.$([Guid]::NewGuid().ToString('N')).tmp"
    [IO.File]::WriteAllText($temporaryPath, (($payload | ConvertTo-Json -Depth 12) + [Environment]::NewLine), (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
}

function Write-Status {
    param([string]$Status, [string]$Reason, [int]$ExitCode = 0, [object[]]$ObservedHostProcesses = @(), [object]$ObservedGeneration = $null)
    Write-State -Path $StatusPath -Status $Status -Reason $Reason -ExitCode $ExitCode -ObservedHostProcesses $ObservedHostProcesses -ObservedGeneration $ObservedGeneration
}

$profileRoot = [IO.Path]::GetFullPath($UserProfileRoot)
$StatusPath = [IO.Path]::GetFullPath($StatusPath)
if ([string]::IsNullOrWhiteSpace($PendingStatusPath)) { $PendingStatusPath = [IO.Path]::ChangeExtension($StatusPath, "pending.json") }
$PendingStatusPath = [IO.Path]::GetFullPath($PendingStatusPath)
if ($WaitTimeoutSeconds -lt 0) { throw "WaitTimeoutSeconds must be zero (unbounded) or positive." }

$initialHostProcesses = @(Get-Process -Name "codex" -ErrorAction SilentlyContinue | ForEach-Object {
    [ordered]@{ id = [int]$_.Id; started_at = $_.StartTime.ToUniversalTime().ToString("o") }
})
Write-State -Path $PendingStatusPath -Status "pending" -Reason "waiting_for_host_exit" -ObservedHostProcesses $initialHostProcesses

if (-not $SkipHostExitWait) {
    $deadline = if ($WaitTimeoutSeconds -gt 0) { (Get-Date).AddSeconds($WaitTimeoutSeconds) } else { $null }
    while ($true) {
        $hostProcesses = @(Get-Process -Name "codex" -ErrorAction SilentlyContinue)
        if ($hostProcesses.Count -eq 0) { break }
        if ($null -ne $deadline -and (Get-Date) -ge $deadline) {
            $observed = @($hostProcesses | ForEach-Object { [ordered]@{ id = [int]$_.Id; started_at = $_.StartTime.ToUniversalTime().ToString("o") } })
            Write-Status -Status "timed_out" -Reason "codex_desktop_still_running" -ExitCode 2 -ObservedHostProcesses $observed
            exit 2
        }
        Start-Sleep -Seconds 2
    }
}

$previous = @{ USERPROFILE = $env:USERPROFILE; HOME = $env:HOME; CODEX_HOME = $env:CODEX_HOME }
try {
    $env:USERPROFILE = $profileRoot
    $env:HOME = $profileRoot
    $env:CODEX_HOME = Join-Path $profileRoot ".codex"
    New-Item -ItemType Directory -Path $env:CODEX_HOME -Force | Out-Null
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        & $CodexCommand plugin add $PluginSelector
        $addExitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($addExitCode -ne 0) {
        Write-Status -Status "failed" -Reason "official_plugin_add_failed" -ExitCode $addExitCode
        exit $addExitCode
    }
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $pluginList = (& $CodexCommand plugin list | Out-String)
        $listExitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    $expectedPattern = "(?m)^\s*" + [regex]::Escape($PluginSelector) + "\s+.*?\s+" + [regex]::Escape($ExpectedVersion) + "(?:\s|$)"
    if ($listExitCode -ne 0 -or $pluginList -notmatch $expectedPattern) {
        Write-Status -Status "failed" -Reason "plugin_list_does_not_confirm_expected_version" -ExitCode $listExitCode
        exit 3
    }
    $observedGeneration = $null
    if (-not [string]::IsNullOrWhiteSpace($ExpectedGenerationId)) {
        $cacheGenerationPath = Join-Path $env:CODEX_HOME ("plugins\cache\personal\codex-praetor\$ExpectedVersion\release-generation.json")
        if (-not (Test-Path -LiteralPath $cacheGenerationPath -PathType Leaf)) {
            Write-Status -Status "failed" -Reason "candidate_cache_generation_missing" -ExitCode 5
            exit 5
        }
        try { $observedGeneration = Get-Content -LiteralPath $cacheGenerationPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch {
            Write-Status -Status "failed" -Reason "candidate_cache_generation_invalid" -ExitCode 5
            exit 5
        }
        if ([string]$observedGeneration.generation_id -ne $ExpectedGenerationId -or ([string]$ExpectedRuntimeContractSha256 -and [string]$observedGeneration.runtime_contract_sha256 -ne $ExpectedRuntimeContractSha256)) {
            Write-Status -Status "failed" -Reason "candidate_cache_generation_mismatch" -ExitCode 5 -ObservedGeneration $observedGeneration
            exit 5
        }
    }
    Write-Status -Status "completed" -Reason "official_plugin_add_list_and_generation_confirmed" -ObservedGeneration $observedGeneration
} catch {
    Write-Status -Status "failed" -Reason "deferred_refresh_exception" -ExitCode 4
    throw
} finally {
    foreach ($name in $previous.Keys) {
        if ($null -eq $previous[$name]) { Remove-Item -LiteralPath ("Env:" + $name) -ErrorAction SilentlyContinue }
        else { Set-Item -LiteralPath ("Env:" + $name) -Value $previous[$name] }
    }
}
