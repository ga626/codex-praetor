param(
    [string]$Repo = (Get-Location).Path,
    [string]$Provider = "mimo",
    [string]$Tier = "mimo-isolated-audit",
    [string]$Task = "Read README.md only and summarize the project. Do not modify files."
)

$ErrorActionPreference = "Stop"
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) {
    $global:PSNativeCommandUseErrorActionPreference = $false

}

[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
$wrapper = Join-Path $projectRoot "scripts\dispatch\invoke-codex-praetor.ps1"

& powershell -NoProfile -ExecutionPolicy Bypass -File $wrapper `
    -Provider $Provider `
    -Tier $Tier `
    -Repo $Repo `
    -Mode readonly `
    -Task $Task `
    -DryRun `
    -NoNotify
