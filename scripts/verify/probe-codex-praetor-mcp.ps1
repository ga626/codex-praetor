param(
    [string]$ThreadId = $env:CODEX_THREAD_ID,
    [string]$Repo = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))),
    [string]$Request = "",
    [int]$TimeoutMs = 60000,
    [switch]$AfterDirectHandleFailure,
    [switch]$Json
)

$ErrorActionPreference = "Stop"
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) {
    $global:PSNativeCommandUseErrorActionPreference = $false
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
$appServerInvoker = Join-Path $projectRoot "scripts\dispatch\invoke-codex-app-server.js"

if ([string]::IsNullOrWhiteSpace($Request)) {
    $Request = "Split the task for external agents in readonly validation mode. Do not create Codex native subagents."
}

function Write-Result {
    param([hashtable]$Result)
    if ($Json) {
        $Result | ConvertTo-Json -Depth 12 -Compress
    } else {
        if ($Result.status -eq "ok") {
            Write-Host "ok: codex-praetor route-intent probe succeeded, route=$($Result.route)"
        } elseif ($Result.status -eq "service_visible_but_direct_handle_stale") {
            Write-Host "service_visible_but_direct_handle_stale: app-server probe succeeded; retry through app-server or start a fresh turn before using the native handle again."
        } else {
            Write-Host "$($Result.status): $($Result.message)"
        }
    }
}

function Invoke-AppServerPayload {
    param(
        [string]$PayloadB64,
        [int]$Timeout
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "node"
    $psi.Arguments = "`"$appServerInvoker`" $PayloadB64 --timeout-ms $Timeout"
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    $null = $process.Start()
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit($Timeout + 5000)) {
        $process.Kill()
        return @{ exit_code = 124; stdout = $stdoutTask.Result; stderr = $stderrTask.Result + [Environment]::NewLine + "app-server proxy timed out" }
    }
    return @{ exit_code = $process.ExitCode; stdout = $stdoutTask.Result; stderr = $stderrTask.Result }
}

if ([string]::IsNullOrWhiteSpace($ThreadId)) {
    Write-Result @{
        status = "manual_reload_needed"
        message = "CODEX_THREAD_ID is not available. Run this inside a Codex thread or pass -ThreadId."
    }
    exit 2
}

if (-not (Test-Path -LiteralPath $appServerInvoker -PathType Leaf)) {
    Write-Result @{
        status = "manual_reload_needed"
        message = "app-server invoker missing: $appServerInvoker"
    }
    exit 2
}

$payload = @(
    @{ id = 1; method = "thread/resume"; params = @{ threadId = $ThreadId; excludeTurns = $true } },
    @{ id = 2; method = "mcpServer/tool/call"; params = @{
        threadId = $ThreadId
        server = "codex-praetor"
        tool = "codex_praetor_route_intent"
        arguments = @{
            request = $Request
            repo = $Repo
            allow_native_codex_subagents = $false
        }
    } }
) | ConvertTo-Json -Depth 30 -Compress

$payloadB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($payload))
$invokeResult = Invoke-AppServerPayload -PayloadB64 $payloadB64 -Timeout $TimeoutMs
$lines = @($invokeResult.stdout -split "\r?\n")

$resumeOk = $false
$toolText = ""
$toolError = ""
foreach ($line in $lines) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    try {
        $message = $line | ConvertFrom-Json
    } catch {
        continue
    }

    if ($message.id -eq 1 -and $message.result.thread.id) {
        $resumeOk = $true
    }
    if ($message.id -eq 2) {
        if ($message.result.content) {
            $toolText = [string]$message.result.content[0].text
        } elseif ($message.error) {
            $toolError = [string]$message.error.message
        }
    }
}

if ($resumeOk -and -not [string]::IsNullOrWhiteSpace($toolText)) {
    try {
        $routePayload = $toolText | ConvertFrom-Json
        $status = if ($AfterDirectHandleFailure) { "service_visible_but_direct_handle_stale" } else { "ok" }
        Write-Result @{
            status = $status
            thread_id = $ThreadId
            route = [string]$routePayload.route
            confidence = [string]$routePayload.confidence
            native_codex_subagents_allowed = [bool]$routePayload.native_codex_subagents_allowed
            message = "app-server mcpServer/tool/call succeeded."
        }
        exit 0
    } catch {
        Write-Result @{
            status = "manual_reload_needed"
            thread_id = $ThreadId
            message = "Probe returned non-JSON tool content."
            raw = $toolText
        }
        exit 3
    }
}

$messageText = if ($toolError) { $toolError } else { "app-server probe did not return tool content." }
Write-Result @{
    status = "manual_reload_needed"
    thread_id = $ThreadId
    message = $messageText
}
exit 4
