param(
    [string]$Repo = (Get-Location).Path,

    [ValidateSet("qoder", "codebuddy", "mimo")]
    [string]$Provider = "mimo",

    [string]$Tier = "",

    [string]$ConfigPath = "",

    [string]$Marker = "CODEX_PRAETOR_CANARY_OK",

    [switch]$Apply
)

$ErrorActionPreference = "Stop"
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) {
    $global:PSNativeCommandUseErrorActionPreference = $false
}
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $utf8NoBom
$OutputEncoding = $utf8NoBom

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
$wrapper = Join-Path $projectRoot "scripts\dispatch\invoke-codex-praetor.ps1"
$nativeHelper = Join-Path $projectRoot "scripts\maintenance\invoke-codex-praetor-native.ps1"
. $nativeHelper

function Get-DefaultTier {
    param([string]$ProviderName)
    switch ($ProviderName) {
        "mimo" { return "mimo-isolated-audit" }
        "codebuddy" { return "codebuddy-free" }
        default { return "" }
    }
}

function Get-GitStatusText {
    param([string]$Path)
    try {
        return ((& git -C $Path status --short 2>$null) | Out-String).Trim()
    } catch {
        return ""
    }
}

function Add-OptionalArg {
    param(
        [System.Collections.Generic.List[string]]$Args,
        [string]$Name,
        [string]$Value
    )
    if (-not [string]::IsNullOrWhiteSpace($Value)) {
        $Args.Add($Name)
        $Args.Add($Value)
    }
}

if (-not (Test-Path -LiteralPath $Repo)) {
    throw "Repo/path does not exist: $Repo"
}
if (-not (Test-Path -LiteralPath $wrapper -PathType Leaf)) {
    throw "Codex Praetor dispatch wrapper is missing: $wrapper"
}

if ([string]::IsNullOrWhiteSpace($Tier)) {
    $Tier = Get-DefaultTier -ProviderName $Provider
}

$task = @"
Read README.md only.
Final answer must contain $Marker.
Do not modify files.
Briefly report whether the repository looks readable from this worker.
"@

$argsList = [System.Collections.Generic.List[string]]::new()
$argsList.Add("-NoProfile")
$argsList.Add("-ExecutionPolicy")
$argsList.Add("Bypass")
$argsList.Add("-File")
$argsList.Add($wrapper)
$argsList.Add("-Provider")
$argsList.Add($Provider)
Add-OptionalArg -Args $argsList -Name "-Tier" -Value $Tier
Add-OptionalArg -Args $argsList -Name "-ConfigPath" -Value $ConfigPath
$argsList.Add("-Repo")
$argsList.Add($Repo)
$argsList.Add("-Mode")
$argsList.Add("readonly")
$argsList.Add("-RunMode")
$argsList.Add("blocking")
$argsList.Add("-Task")
$argsList.Add($task)
$argsList.Add("-NoNotify")
if (-not $Apply) {
    $argsList.Add("-DryRun")
}

Write-Host "Codex Praetor readonly provider canary"
Write-Host "Provider: $Provider"
if (-not [string]::IsNullOrWhiteSpace($Tier)) { Write-Host "Tier:     $Tier" }
Write-Host "Repo:     $Repo"
Write-Host "Mode:     $(if ($Apply) { 'apply' } else { 'preview' })"
Write-Host ""

if (-not $Apply) {
    Write-Host "Preview only. Re-run with -Apply after the provider is installed and logged in."
    Write-Host ""
}

$beforeStatus = Get-GitStatusText -Path $Repo
$nativeResult = Invoke-CodexPraetorNative -FilePath "powershell.exe" -ArgumentList $argsList -WorkingDirectory $projectRoot -TimeoutSeconds 360
$exitCode = [int]$nativeResult.exit_code
$outputText = (([string]$nativeResult.stdout) + "`n" + ([string]$nativeResult.stderr)).Trim()
$afterStatus = Get-GitStatusText -Path $Repo

Write-Host $outputText.Trim()

if ($exitCode -ne 0) {
    throw "Readonly canary failed for provider '$Provider' with exit code $exitCode. If this was an apply run, complete the provider's normal login flow and rerun. No token, cookie, or account database should be pasted into Codex Praetor."
}

if ($Apply -and $outputText -notmatch [regex]::Escape($Marker)) {
    throw "Readonly canary completed but did not return the marker '$Marker'. Treat this as inconclusive and inspect the provider output before real dispatch."
}

if ($Apply -and $beforeStatus -ne $afterStatus) {
    throw "Readonly canary changed the main repository git status. Inspect the diff before any real dispatch."
}

if ($Apply) {
    Write-Host "[PASS] Readonly provider canary completed and the main repository status stayed unchanged."
} else {
    Write-Host "[PASS] Readonly provider canary preview completed. No real worker was started."
}
