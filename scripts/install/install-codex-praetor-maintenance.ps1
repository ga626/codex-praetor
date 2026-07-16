param(
    [string]$UserProfileRoot = $env:USERPROFILE,
    [string]$SourceRoot = "",
    [string]$TaskName = "CodexPraetor-GenerationReconcile",
    [switch]$Apply,
    [switch]$Uninstall
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
if ([string]::IsNullOrWhiteSpace($SourceRoot)) { $SourceRoot = $projectRoot }

$profilePath = [System.IO.Path]::GetFullPath($UserProfileRoot)
$sourcePath = [System.IO.Path]::GetFullPath($SourceRoot)
$sourceRetirement = Join-Path $sourcePath "scripts\maintenance\codex-praetor-retirement.ps1"
$sourceReconcile = Join-Path $sourcePath "scripts\maintenance\reconcile-codex-praetor-generations.ps1"
$targetRoot = Join-Path $profilePath ".codex\codex-praetor-maintenance"
$targetRetirement = Join-Path $targetRoot "codex-praetor-retirement.ps1"
$targetReconcile = Join-Path $targetRoot "reconcile-codex-praetor-generations.ps1"

if ($Uninstall) {
    Write-Host "Codex Praetor maintenance uninstall plan"
    Write-Host "Task: $TaskName"
    Write-Host "Root: $targetRoot"
    if (-not $Apply) { Write-Host "Dry run only."; exit 0 }
    if (Get-Command Unregister-ScheduledTask -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $targetRoot) { Remove-Item -LiteralPath $targetRoot -Recurse -Force }
    Write-Host "[PASS] Maintenance task and installed scripts removed."
    exit 0
}

foreach ($path in @($sourceRetirement, $sourceReconcile)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Maintenance source is missing: $path" }
}

Write-Host "Codex Praetor maintenance install plan"
Write-Host "Task: $TaskName"
Write-Host "Profile: $profilePath"
Write-Host "Root: $targetRoot"
if (-not $Apply) {
    Write-Host "Dry run only. Re-run with -Apply to install the user-level retry task."
    exit 0
}

if (-not (Get-Command Register-ScheduledTask -ErrorAction SilentlyContinue)) {
    throw "Windows ScheduledTasks module is unavailable; automatic generation cleanup cannot be installed."
}

New-Item -ItemType Directory -Path $targetRoot -Force | Out-Null
Copy-Item -LiteralPath $sourceRetirement -Destination $targetRetirement -Force
Copy-Item -LiteralPath $sourceReconcile -Destination $targetReconcile -Force

$quotedProfile = '"' + $profilePath.Replace('"', '\"') + '"'
$quotedScript = '"' + $targetReconcile.Replace('"', '\"') + '"'
$taskArguments = "-NoProfile -ExecutionPolicy Bypass -File $quotedScript -UserProfileRoot $quotedProfile -Channel stable -Apply"
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $taskArguments
$logonTrigger = New-ScheduledTaskTrigger -AtLogOn
$repeatTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 15) -RepetitionDuration (New-TimeSpan -Days 3650)
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger @($logonTrigger, $repeatTrigger) -Settings $settings -Principal $principal -Force | Out-Null
Write-Host "[PASS] Installed maintenance scripts and registered user-level retry task."
