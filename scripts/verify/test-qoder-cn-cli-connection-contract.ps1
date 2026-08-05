param([string]$ProjectRoot = "")

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)

function Assert-Contains {
    param([string]$Text, [string]$Needle, [string]$Message)
    if (-not $Text.Contains($Needle)) { throw $Message }
}

$dispatcherPath = Join-Path $ProjectRoot "scripts\dispatch\invoke-codex-praetor.ps1"
$configPath = Join-Path $ProjectRoot "config\codex-praetor-tiers.example.json"
foreach ($path in @($dispatcherPath, $configPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required Qoder CN connection file is missing: $path" }
}

$dispatcher = Get-Content -LiteralPath $dispatcherPath -Raw -Encoding UTF8
$config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8
Assert-Contains $dispatcher 'function Get-QoderConnectionMode' "Dispatcher must resolve the connection from an explicit Qoder distribution."
Assert-Contains $dispatcher 'distribution qoder_cn must use connectionMode=supervised_cli_stream_json' "Qoder CN must reject global SDK fallback."
Assert-Contains $dispatcher 'distribution qoder_global requires explicit connectionMode=qoder_agent_sdk' "Global Qoder must require an explicit SDK opt-in."
Assert-Contains $dispatcher '"supervised_cli_stream_json"' "Qoder CN must use a distinct stream-json connection identity."
Assert-Contains $dispatcher '"--output-format", "stream-json"' "Qoder CN dispatch must request structured CLI output."
Assert-Contains $dispatcher '"--permission-mode", "dont_ask"' "Qoder CN headless dispatch must use the documented non-interactive permission mode."
Assert-Contains $dispatcher '"--disallowed-tools", "WebFetch,WebSearch,Agent,AskUserQuestion,Skill,TodoWrite"' "Qoder CN dispatch must explicitly exclude network and delegation tools."
Assert-Contains $dispatcher '"qoder_agent_sdk"' "Compatible global Qoder CLI must retain the official SDK route."
Assert-Contains $config '"distribution": "qoder_cn"' "Example configuration must explicitly pin the Qoder CN distribution."
Assert-Contains $config '"connectionMode": "supervised_cli_stream_json"' "Example configuration must explicitly pin Qoder CN stream-json."
Write-Host "[PASS] Qoder CN stream-json and explicit global SDK opt-in contracts are both present."
