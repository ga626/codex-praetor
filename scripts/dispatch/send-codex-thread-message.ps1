param(
    [Parameter(Mandatory = $true)]
    [string]$ThreadId,

    [Parameter(Mandatory = $true)]
    [string]$Message,

    [string]$Workspace = (Get-Location).Path,

    [ValidateSet("none", "minimal", "low", "medium", "high", "xhigh", "max")]
    [string]$ReasoningEffort = "minimal",

    [switch]$WaitTurnComplete,

    [int]$TimeoutMs = 600000
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$invokeScript = Join-Path $scriptDir "invoke-codex-app-server.js"
if (-not (Test-Path -LiteralPath $invokeScript)) {
    throw "Missing app-server invoker: $invokeScript"
}

$resume = @{
    id = 1
    method = "thread/resume"
    params = @{
        threadId = $ThreadId
        cwd = $Workspace
        approvalPolicy = "never"
        sandbox = "danger-full-access"
        excludeTurns = $true
    }
}

$turn = @{
    id = 2
    method = "turn/start"
    params = @{
        threadId = $ThreadId
        cwd = $Workspace
        approvalPolicy = "never"
        sandboxPolicy = @{ type = "dangerFullAccess" }
        effort = $ReasoningEffort
        input = @(@{ type = "text"; text = $Message })
    }
}

$payload = @($resume, $turn) | ConvertTo-Json -Depth 20 -Compress
$encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($payload))
$args = @($invokeScript, $encoded, "--timeout-ms", "$TimeoutMs")
if ($WaitTurnComplete) {
    $args += "--wait-turn-complete"
}

node @args
exit $LASTEXITCODE

