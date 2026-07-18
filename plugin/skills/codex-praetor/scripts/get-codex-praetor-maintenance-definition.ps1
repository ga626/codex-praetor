param(
    [string]$ProfilePath = $env:USERPROFILE,
    [string]$SourceRoot = "",
    [string]$TaskName = "CodexPraetor-GenerationReconcile",
    [switch]$EmitJson
)

$ErrorActionPreference = "Stop"

function Get-CodexPraetorMaintenanceDefinition {
    param([string]$Profile, [string]$Source, [string]$Name)
    $profileFull = [System.IO.Path]::GetFullPath($Profile)
    $sourceFull = if ([string]::IsNullOrWhiteSpace($Source)) { "" } else { [System.IO.Path]::GetFullPath($Source) }
    $targetRoot = Join-Path $profileFull ".codex\codex-praetor-maintenance"
    $targetReconcile = Join-Path $targetRoot "reconcile-codex-praetor-generations.ps1"
    $quotedProfile = '"' + $profileFull.Replace('"', '\"') + '"'
    $quotedScript = '"' + $targetReconcile.Replace('"', '\"') + '"'
    return [pscustomobject][ordered]@{
        task_name = $Name; profile_root = $profileFull; source_root = $sourceFull; target_root = $targetRoot
        executable = "powershell.exe"; arguments = "-NoProfile -ExecutionPolicy Bypass -File $quotedScript -UserProfileRoot $quotedProfile -Channel stable -Apply"
        reconcile_script = $targetReconcile; expected_triggers = @("AtLogOn", "Every15Minutes"); enabled = $true
    }
}

function Get-CodexPraetorMaintenanceTaskInspection {
    param([Parameter(Mandatory = $true)]$Definition)
    $result = [ordered]@{ task_name = $Definition.task_name; backend = "none"; exists = $false; enabled = $false; state = "missing"; action_matches = $false; triggers_match = $false; reason = "" }
    $cmdlet = Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue
    if ($null -ne $cmdlet) {
        try {
            $task = Get-ScheduledTask -TaskName $Definition.task_name -ErrorAction Stop
            $result.backend = "ScheduledTasks"; $result.exists = $true; $result.enabled = ($task.Settings.Enabled -ne $false); $result.state = [string]$task.State
            $action = @($task.Actions | Select-Object -First 1)[0]
            $result.action_matches = $null -ne $action -and [string]$action.Execute -eq $Definition.executable -and [string]$action.Arguments -eq $Definition.arguments
            $triggerKinds = @($task.Triggers | ForEach-Object { [string]$_.CimClass.CimClassName })
            $result.triggers_match = ($triggerKinds -match "LogonTrigger").Count -gt 0 -and ($triggerKinds -match "TimeTrigger").Count -gt 0
            $result.reason = if ($result.enabled -and $result.action_matches -and $result.triggers_match) { "任务定义、启用状态和触发器匹配。" } else { "任务存在但定义、启用状态或触发器发生漂移。" }
            return [pscustomobject]$result
        } catch { }
    }
    try {
        & schtasks.exe /Query /TN $Definition.task_name /FO LIST 2>$null | Out-Null
        $result.backend = "schtasks"; $result.exists = ($LASTEXITCODE -eq 0); $result.state = if ($result.exists) { "unknown" } else { "missing" }
        $result.reason = if ($result.exists) { "schtasks 能找到任务，但当前环境不能读取 action/triggers，health 保守降级。" } else { "未找到维护任务。" }
    } catch { $result.reason = "无法查询 Windows 维护任务：$($_.Exception.Message)" }
    return [pscustomobject]$result
}

if ($MyInvocation.InvocationName -ne ".") {
    $definition = Get-CodexPraetorMaintenanceDefinition -Profile $ProfilePath -Source $SourceRoot -Name $TaskName
    $inspection = Get-CodexPraetorMaintenanceTaskInspection -Definition $definition
    if ($EmitJson) { [pscustomobject]@{ definition = $definition; inspection = $inspection } | ConvertTo-Json -Depth 20 } else { Write-Output "[$($inspection.state)] $($inspection.reason)" }
}
