param(
    [string]$ServerName = "codex-praetor",
    [int]$TimeoutMs = 60000,
    [switch]$Json
)

$ErrorActionPreference = "Stop"
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) {
    $global:PSNativeCommandUseErrorActionPreference = $false
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
$appServerInvoker = Join-Path $scriptDir "invoke-codex-app-server.js"

function Write-Result {
    param([hashtable]$Result)
    if ($Json) {
        $Result | ConvertTo-Json -Depth 10 -Compress
    } else {
        if ($Result.status -eq "ok") {
            Write-Host "ok: $($Result.server) found, tools=$($Result.tool_count)"
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

if (-not (Test-Path -LiteralPath $appServerInvoker -PathType Leaf)) {
    Write-Result @{
        status = "manual_reload_needed"
        server = $ServerName
        message = "app-server invoker missing: $appServerInvoker"
    }
    exit 1
}

$payload = @(
    @{ id = 1; method = "config/mcpServer/reload"; params = @{} },
    @{ id = 2; method = "mcpServerStatus/list"; params = @{ detail = "toolsAndAuthOnly"; limit = 100 } }
) | ConvertTo-Json -Depth 20 -Compress

$payloadB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($payload))
$invokeResult = Invoke-AppServerPayload -PayloadB64 $payloadB64 -Timeout $TimeoutMs
$lines = @($invokeResult.stdout -split "\r?\n")

$reloadOk = $false
$server = $null
foreach ($line in $lines) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    try {
        $message = $line | ConvertFrom-Json
    } catch {
        continue
    }

    if ($message.id -eq 1 -and $null -ne $message.result) {
        $reloadOk = $true
    }
    if ($message.id -eq 2 -and $message.result.data) {
        $server = @($message.result.data | Where-Object { $_.name -eq $ServerName } | Select-Object -First 1)
    }
}

if ($reloadOk -and $server.Count -gt 0) {
    $toolCount = 0
    if ($server[0].tools) {
        $toolCount = @($server[0].tools.PSObject.Properties).Count
    }
    Write-Result @{
        status = "ok"
        server = $ServerName
        tool_count = $toolCount
        version = [string]$server[0].serverInfo.version
        auth_status = [string]$server[0].authStatus
        message = "MCP server is visible after reload."
    }
    exit 0
}

Write-Result @{
    status = "manual_reload_needed"
    server = $ServerName
    message = "Codex app-server reload ran, but $ServerName was not visible in mcpServerStatus/list."
}
exit 2
