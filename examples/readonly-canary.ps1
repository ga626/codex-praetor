param(
    [string]$Repo = (Get-Location).Path,
    [string]$Provider = "mimo",
    [string]$Tier = "mimo-auto-readonly",
    [string]$Marker = "CODEX_PRAETOR_CANARY_OK"
)

$ErrorActionPreference = "Stop"
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) {
    $global:PSNativeCommandUseErrorActionPreference = $false

}

[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
$wrapper = Join-Path $projectRoot "scripts\invoke-codex-praetor.ps1"
$task = "Read README.md only. Final answer must start with $Marker. Do not modify files."

& powershell -NoProfile -ExecutionPolicy Bypass -File $wrapper `
    -Provider $Provider `
    -Tier $Tier `
    -Repo $Repo `
    -Mode readonly `
    -RunMode blocking `
    -Task $task `
    -NoNotify
