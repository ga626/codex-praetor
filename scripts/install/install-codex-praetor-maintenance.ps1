param(
    [string]$UserProfileRoot = $env:USERPROFILE,
    [string]$SourceRoot = "",
    [string]$TaskName = "CodexPraetor-GenerationReconcile",
    [switch]$Apply,
    [switch]$Uninstall,
    [switch]$SkipMain
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
$maintenanceDefinitionPath = Join-Path $sourcePath "scripts\maintenance\get-codex-praetor-maintenance-definition.ps1"
if (Test-Path -LiteralPath $maintenanceDefinitionPath -PathType Leaf) { . $maintenanceDefinitionPath }
$maintenanceDefinition = if (Get-Command Get-CodexPraetorMaintenanceDefinition -ErrorAction SilentlyContinue) { Get-CodexPraetorMaintenanceDefinition -Profile $profilePath -Source $sourcePath -Name $TaskName } else { $null }

$script:TaskExecutable = if ($null -ne $maintenanceDefinition) { [string]$maintenanceDefinition.executable } else { "powershell.exe" }
$script:TaskArguments = if ($null -ne $maintenanceDefinition) { [string]$maintenanceDefinition.arguments } else { "-NoProfile -ExecutionPolicy Bypass -File `"$targetReconcile`" -UserProfileRoot `"$profilePath`" -Channel stable -Apply" }
$script:TaskUserId = "$env:USERDOMAIN\$env:USERNAME"

function Build-TaskXml {
    param([string]$Executable, [string]$TaskArguments, [string]$UserId)

    $safeExe = [System.Security.SecurityElement]::Escape($Executable)
    $safeArgs = [System.Security.SecurityElement]::Escape($TaskArguments)
    $safeUserId = [System.Security.SecurityElement]::Escape($UserId)
    return @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo><Description>Codex Praetor generation reconciliation</Description></RegistrationInfo>
  <Triggers>
    <LogonTrigger><Enabled>true</Enabled><UserId>$safeUserId</UserId></LogonTrigger>
    <TimeTrigger>
      <Enabled>true</Enabled><StartBoundary>2000-01-01T00:00:00</StartBoundary>
      <Repetition><Interval>PT15M</Interval><Duration>P3650D</Duration><StopAtDurationEnd>false</StopAtDurationEnd></Repetition>
    </TimeTrigger>
  </Triggers>
  <Principals><Principal id="Author"><UserId>$safeUserId</UserId><LogonType>InteractiveToken</LogonType><RunLevel>LeastPrivilege</RunLevel></Principal></Principals>
  <Settings><MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy><StartWhenAvailable>true</StartWhenAvailable><AllowHardTerminate>true</AllowHardTerminate><AllowStartOnDemand>true</AllowStartOnDemand><Enabled>true</Enabled><Hidden>false</Hidden><RunOnlyIfIdle>false</RunOnlyIfIdle><WakeToRun>false</WakeToRun></Settings>
  <Actions Context="Author"><Exec><Command>$safeExe</Command><Arguments>$safeArgs</Arguments></Exec></Actions>
</Task>
"@
}

function Register-TaskSchtasksFallback {
    param([string]$Name, [string]$Executable, [string]$TaskArguments, [string]$UserId)

    $xmlPath = [System.IO.Path]::GetTempFileName()
    try {
        $xml = Build-TaskXml -Executable $Executable -TaskArguments $TaskArguments -UserId $UserId
        [System.IO.File]::WriteAllText($xmlPath, $xml, (New-Object System.Text.UnicodeEncoding($false, $true)))
        & schtasks.exe /Create /TN $Name /XML $xmlPath /F | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "schtasks.exe /Create failed with exit code $LASTEXITCODE."
        }
    } finally {
        Remove-Item -LiteralPath $xmlPath -Force -ErrorAction SilentlyContinue
    }
}

function Test-MaintenanceTaskExists {
    param([string]$Name)

    try {
        if (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue) {
            $null = Get-ScheduledTask -TaskName $Name -ErrorAction Stop
            return $true
        }
    } catch {
        # Some managed Windows images deny the cmdlet but still allow schtasks.
    }
    & schtasks.exe /Query /TN $Name /FO LIST | Out-Null
    return ($LASTEXITCODE -eq 0)
}

function Assert-MaintenanceTaskRegistration {
    param([string]$Name, [string]$ExpectedExecutable, [string]$ExpectedArguments)

    if (-not (Test-MaintenanceTaskExists -Name $Name)) {
        throw "Scheduled task '$Name' was not registered."
    }
    $task = $null
    try {
        if (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue) {
            $task = Get-ScheduledTask -TaskName $Name -ErrorAction Stop
        }
    } catch {
        $task = $null
    }
    if ($null -eq $task) {
        return
    }
    if ($task.Enabled -eq $false) { throw "Scheduled task '$Name' is disabled." }
    $action = @($task.Actions | Select-Object -First 1)[0]
    if ($null -eq $action) { throw "Scheduled task '$Name' has no action." }
    if ([string]$action.Execute -ne $ExpectedExecutable) {
        throw "Scheduled task '$Name' executable drifted."
    }
    if ([string]$action.Arguments -ne $ExpectedArguments) {
        throw "Scheduled task '$Name' arguments drifted."
    }
}

function Install-MaintenanceTask {
    param(
        [string]$Name,
        [switch]$ApplyChanges,
        [scriptblock]$FallbackRegistration = $null,
        [scriptblock]$RegistrationVerification = $null
    )

    foreach ($path in @($sourceRetirement, $sourceReconcile)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Maintenance source is missing: $path" }
    }
    Write-Host "Codex Praetor maintenance install plan"
    Write-Host "Task: $Name"
    Write-Host "Profile: $profilePath"
    Write-Host "Root: $targetRoot"
    if (-not $ApplyChanges) {
        Write-Host "Dry run only. Re-run with -Apply to install the user-level retry task."
        return
    }

    New-Item -ItemType Directory -Path $targetRoot -Force | Out-Null
    Copy-Item -LiteralPath $sourceRetirement -Destination $targetRetirement -Force
    Copy-Item -LiteralPath $sourceReconcile -Destination $targetReconcile -Force

    $registered = $false
    if (Get-Command Register-ScheduledTask -ErrorAction SilentlyContinue) {
        try {
            $action = New-ScheduledTaskAction -Execute $script:TaskExecutable -Argument $script:TaskArguments
            $logonTrigger = New-ScheduledTaskTrigger -AtLogOn
            $repeatTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 15) -RepetitionDuration (New-TimeSpan -Days 3650)
            $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew
            $principal = New-ScheduledTaskPrincipal -UserId $script:TaskUserId -LogonType Interactive -RunLevel Limited
            Register-ScheduledTask -TaskName $Name -Action $action -Trigger @($logonTrigger, $repeatTrigger) -Settings $settings -Principal $principal -Force -ErrorAction Stop | Out-Null
            $registered = $true
        } catch {
            Write-Warning "ScheduledTasks registration failed: $($_.Exception.Message). Trying schtasks.exe fallback."
        }
    }
    if (-not $registered) {
        if ($null -ne $FallbackRegistration) {
            & $FallbackRegistration $Name $script:TaskExecutable $script:TaskArguments $script:TaskUserId
        } else {
            Register-TaskSchtasksFallback -Name $Name -Executable $script:TaskExecutable -TaskArguments $script:TaskArguments -UserId $script:TaskUserId
        }
    }
    if ($null -ne $RegistrationVerification) {
        & $RegistrationVerification $Name $script:TaskExecutable $script:TaskArguments
    } else {
        Assert-MaintenanceTaskRegistration -Name $Name -ExpectedExecutable $script:TaskExecutable -ExpectedArguments $script:TaskArguments
    }
    Write-Host "[PASS] Installed maintenance scripts and registered user-level retry task."
}

function Uninstall-MaintenanceTask {
    param([string]$Name, [string]$Root)

    if (Test-MaintenanceTaskExists -Name $Name) {
        if (Get-Command Unregister-ScheduledTask -ErrorAction SilentlyContinue) {
            Unregister-ScheduledTask -TaskName $Name -Confirm:$false -ErrorAction Stop
        } else {
            & schtasks.exe /Delete /TN $Name /F | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "schtasks.exe /Delete failed with exit code $LASTEXITCODE." }
        }
    }
    if (Test-MaintenanceTaskExists -Name $Name) {
        throw "Maintenance task '$Name' still exists after uninstall. Scripts at '$Root' were preserved."
    }
    if (Test-Path -LiteralPath $Root) {
        Remove-Item -LiteralPath $Root -Recurse -Force -ErrorAction Stop
    }
}

if (-not $SkipMain) {
    if ($Uninstall) {
        Uninstall-MaintenanceTask -Name $TaskName -Root $targetRoot
        Write-Host "[PASS] Maintenance task and installed scripts removed."
        exit 0
    }
    Install-MaintenanceTask -Name $TaskName -ApplyChanges:$Apply
}
