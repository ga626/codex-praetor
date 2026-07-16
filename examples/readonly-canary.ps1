param(
    [string]$Repo = (Get-Location).Path,
    [string]$Provider = "mimo",
    [string]$Tier = "mimo-isolated-audit",
    [string]$Marker = "CODEX_PRAETOR_CANARY_OK",
    [switch]$Apply
)

$ErrorActionPreference = "Stop"
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) {
    $global:PSNativeCommandUseErrorActionPreference = $false

}

[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
$canary = Join-Path $projectRoot "scripts\verify\test-provider-readonly-canary.ps1"

$argsList = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $canary,
    "-Provider", $Provider,
    "-Tier", $Tier,
    "-Repo", $Repo,
    "-Marker", $Marker
)
if ($Apply) {
    $argsList += "-Apply"
}

& powershell @argsList
