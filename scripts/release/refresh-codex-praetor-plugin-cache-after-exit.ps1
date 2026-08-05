param(
    [string]$UserProfileRoot = $env:USERPROFILE,
    [string]$CodexCommand = "codex",
    [string]$PluginSelector = "codex-praetor@personal",
    [Parameter(Mandatory = $true)][string]$ExpectedVersion,
    [Parameter(Mandatory = $true)][string]$StatusPath,
    [int]$WaitTimeoutSeconds = 900,
    [switch]$SkipHostExitWait
)

$ErrorActionPreference = "Stop"

function Write-Status {
    param([string]$Status, [string]$Reason, [int]$ExitCode = 0)
    $parent = Split-Path -Parent $StatusPath
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $payload = [ordered]@{
        schema = "codex-praetor-deferred-plugin-cache-refresh/v1"
        status = $Status
        reason = $Reason
        expected_version = $ExpectedVersion
        completed_at = [DateTime]::UtcNow.ToString("o")
        exit_code = $ExitCode
    }
    [IO.File]::WriteAllText($StatusPath, (($payload | ConvertTo-Json -Depth 8) + [Environment]::NewLine), (New-Object Text.UTF8Encoding($false)))
}

$profileRoot = [IO.Path]::GetFullPath($UserProfileRoot)
$StatusPath = [IO.Path]::GetFullPath($StatusPath)
if ($WaitTimeoutSeconds -lt 1) { throw "WaitTimeoutSeconds must be positive." }

if (-not $SkipHostExitWait) {
    $deadline = (Get-Date).AddSeconds($WaitTimeoutSeconds)
    while ($true) {
        $hostProcesses = @(Get-Process -Name "codex" -ErrorAction SilentlyContinue)
        if ($hostProcesses.Count -eq 0) { break }
        if ((Get-Date) -ge $deadline) {
            Write-Status -Status "timed_out" -Reason "codex_desktop_still_running" -ExitCode 2
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
    & $CodexCommand plugin add $PluginSelector
    $addExitCode = $LASTEXITCODE
    if ($addExitCode -ne 0) {
        Write-Status -Status "failed" -Reason "official_plugin_add_failed" -ExitCode $addExitCode
        exit $addExitCode
    }
    $pluginList = (& $CodexCommand plugin list | Out-String)
    $listExitCode = $LASTEXITCODE
    $expectedPattern = "(?m)^\s*" + [regex]::Escape($PluginSelector) + "\s+.*?\s+" + [regex]::Escape($ExpectedVersion) + "(?:\s|$)"
    if ($listExitCode -ne 0 -or $pluginList -notmatch $expectedPattern) {
        Write-Status -Status "failed" -Reason "plugin_list_does_not_confirm_expected_version" -ExitCode $listExitCode
        exit 3
    }
    Write-Status -Status "completed" -Reason "official_plugin_add_and_list_confirmed"
} catch {
    Write-Status -Status "failed" -Reason "deferred_refresh_exception" -ExitCode 4
    throw
} finally {
    foreach ($name in $previous.Keys) {
        if ($null -eq $previous[$name]) { Remove-Item -LiteralPath ("Env:" + $name) -ErrorAction SilentlyContinue }
        else { Set-Item -LiteralPath ("Env:" + $name) -Value $previous[$name] }
    }
}
