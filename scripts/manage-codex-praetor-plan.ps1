param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Init", "UpsertTask", "RecordJob", "NextReady", "Get", "AppendEvent")]
    [string]$Action,

    [Parameter(Mandatory = $true)]
    [string]$PlanId,

    [string]$PlanRoot = "$env:USERPROFILE\.codex\codex-praetor-plans",
    [string]$Title = "",
    [string]$Repo = "",
    [string]$TaskId = "",
    [string]$TaskTitle = "",
    [string]$DependsOn = "",
    [ValidateSet("pending", "running", "completed", "failed", "blocked", "new_problem", "skipped")]
    [string]$Status = "pending",
    [string]$Acceptance = "",
    [string]$JobId = "",
    [string]$JobDir = "",
    [string]$Provider = "",
    [string]$Tier = "",
    [string]$Model = "",
    [string]$Mode = "",
    [string]$CompletionPath = "",
    [string]$Summary = "",
    [string]$EventType = "",
    [string]$EventMessage = "",
    [switch]$OutputJson
)

$ErrorActionPreference = "Stop"

function Get-SafeName {
    param([string]$Value)
    return ($Value -replace '[^A-Za-z0-9_.-]', '_')
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [object]$Value
    )
    $tmp = "$Path.tmp"
    $Value | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $tmp -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function ConvertTo-StringArray {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return @()
    }
    return @($Value -split "," | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function New-EmptyPlan {
    param([string]$Id)
    return [ordered]@{
        schema = "codex-praetor-plan/v1"
        plan_id = $Id
        title = ""
        repo = ""
        status = "active"
        created_at = (Get-Date).ToString("o")
        updated_at = (Get-Date).ToString("o")
        tasks = @()
        events = @()
    }
}

function Get-PlanPath {
    param([string]$Id)
    $dir = Join-Path $PlanRoot (Get-SafeName $Id)
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    return (Join-Path $dir "plan.json")
}

function Read-Plan {
    param([string]$Id)
    $path = Get-PlanPath -Id $Id
    if (Test-Path -LiteralPath $path) {
        return (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json)
    }
    return [pscustomobject](New-EmptyPlan -Id $Id)
}

function Save-Plan {
    param([object]$Plan)
    $Plan.updated_at = (Get-Date).ToString("o")
    Write-JsonFile -Path (Get-PlanPath -Id $Plan.plan_id) -Value $Plan
}

function Add-PlanEvent {
    param(
        [object]$Plan,
        [string]$Type,
        [string]$Message,
        [object]$Data = $null
    )
    $events = @($Plan.events)
    $events += [ordered]@{
        at = (Get-Date).ToString("o")
        type = $Type
        message = $Message
        data = $Data
    }
    $Plan.events = $events
}

function Upsert-Task {
    param(
        [object]$Plan,
        [string]$Id,
        [string]$TitleValue,
        [string]$DependsValue,
        [string]$StatusValue,
        [string]$AcceptanceValue,
        [string]$JobIdValue,
        [string]$JobDirValue,
        [string]$ProviderValue,
        [string]$TierValue,
        [string]$ModelValue,
        [string]$ModeValue,
        [string]$CompletionValue,
        [string]$SummaryValue
    )
    if ([string]::IsNullOrWhiteSpace($Id)) {
        throw "TaskId is required for $Action."
    }

    $tasks = @($Plan.tasks)
    $existing = $null
    foreach ($task in $tasks) {
        if ($task.task_id -eq $Id) {
            $existing = $task
            break
        }
    }

    if ($null -eq $existing) {
        $existing = [pscustomobject]@{
            task_id = $Id
            title = ""
            depends_on = @()
            status = "pending"
            acceptance = ""
            job_id = ""
            job_dir = ""
            provider = ""
            tier = ""
            model = ""
            mode = ""
            completion = ""
            summary = ""
            created_at = (Get-Date).ToString("o")
            updated_at = (Get-Date).ToString("o")
        }
        $tasks += $existing
    }

    if (-not [string]::IsNullOrWhiteSpace($TitleValue)) { $existing.title = $TitleValue }
    if (-not [string]::IsNullOrWhiteSpace($DependsValue)) { $existing.depends_on = @(ConvertTo-StringArray -Value $DependsValue) }
    if (-not [string]::IsNullOrWhiteSpace($StatusValue)) { $existing.status = $StatusValue }
    if (-not [string]::IsNullOrWhiteSpace($AcceptanceValue)) { $existing.acceptance = $AcceptanceValue }
    if (-not [string]::IsNullOrWhiteSpace($JobIdValue)) { $existing.job_id = $JobIdValue }
    if (-not [string]::IsNullOrWhiteSpace($JobDirValue)) { $existing.job_dir = $JobDirValue }
    if (-not [string]::IsNullOrWhiteSpace($ProviderValue)) { $existing.provider = $ProviderValue }
    if (-not [string]::IsNullOrWhiteSpace($TierValue)) { $existing.tier = $TierValue }
    if (-not [string]::IsNullOrWhiteSpace($ModelValue)) { $existing.model = $ModelValue }
    if (-not [string]::IsNullOrWhiteSpace($ModeValue)) { $existing.mode = $ModeValue }
    if (-not [string]::IsNullOrWhiteSpace($CompletionValue)) { $existing.completion = $CompletionValue }
    if (-not [string]::IsNullOrWhiteSpace($SummaryValue)) { $existing.summary = $SummaryValue }
    $existing.updated_at = (Get-Date).ToString("o")

    $Plan.tasks = @($tasks | Sort-Object task_id)
}

function Get-ReadyTasks {
    param([object]$Plan)
    $done = @{}
    foreach ($task in @($Plan.tasks)) {
        if ($task.status -eq "completed") {
            $done[$task.task_id] = $true
        }
    }

    $ready = @()
    foreach ($task in @($Plan.tasks)) {
        if ($task.status -ne "pending") {
            continue
        }
        $deps = @($task.depends_on)
        $ok = $true
        foreach ($dep in $deps) {
            if (-not $done.ContainsKey($dep)) {
                $ok = $false
                break
            }
        }
        if ($ok) {
            $ready += $task
        }
    }
    return $ready
}

$plan = Read-Plan -Id $PlanId

if ($Action -eq "Init") {
    if (-not [string]::IsNullOrWhiteSpace($Title)) { $plan.title = $Title }
    if (-not [string]::IsNullOrWhiteSpace($Repo)) { $plan.repo = $Repo }
    Add-PlanEvent -Plan $plan -Type "plan_initialized" -Message "Plan initialized or refreshed."
    Save-Plan -Plan $plan
} elseif ($Action -eq "UpsertTask") {
    Upsert-Task -Plan $plan -Id $TaskId -TitleValue $TaskTitle -DependsValue $DependsOn -StatusValue $Status -AcceptanceValue $Acceptance -JobIdValue $JobId -JobDirValue $JobDir -ProviderValue $Provider -TierValue $Tier -ModelValue $Model -ModeValue $Mode -CompletionValue $CompletionPath -SummaryValue $Summary
    Add-PlanEvent -Plan $plan -Type "task_upserted" -Message "Task $TaskId is $Status." -Data @{ task_id = $TaskId; status = $Status; job_id = $JobId }
    Save-Plan -Plan $plan
} elseif ($Action -eq "RecordJob") {
    if ([string]::IsNullOrWhiteSpace($JobDir)) {
        throw "JobDir is required for RecordJob."
    }
    $completionFile = $CompletionPath
    if ([string]::IsNullOrWhiteSpace($completionFile)) {
        $completionFile = Join-Path $JobDir "completion.json"
    }
    if (-not (Test-Path -LiteralPath $completionFile)) {
        throw "Completion file not found: $completionFile"
    }
    $completion = Get-Content -LiteralPath $completionFile -Raw | ConvertFrom-Json
    $recordTaskId = if (-not [string]::IsNullOrWhiteSpace($TaskId)) { $TaskId } else { [string]$completion.task_id }
    $recordStatus = if ($completion.status -eq "completed") { "completed" } elseif ($completion.status -eq "failed") { "failed" } else { "blocked" }
    $summaryText = "worker_status=$($completion.status); exit_code=$($completion.exit_code)"
    Upsert-Task -Plan $plan -Id $recordTaskId -TitleValue "" -DependsValue "" -StatusValue $recordStatus -AcceptanceValue ([string]$completion.acceptance) -JobIdValue ([string]$completion.job_id) -JobDirValue $JobDir -ProviderValue ([string]$completion.provider) -TierValue ([string]$completion.tier) -ModelValue ([string]$completion.model) -ModeValue ([string]$completion.mode) -CompletionValue $completionFile -SummaryValue $summaryText
    Add-PlanEvent -Plan $plan -Type "job_recorded" -Message "Job $($completion.job_id) recorded for task $recordTaskId as $recordStatus." -Data @{ task_id = $recordTaskId; job_id = $completion.job_id; status = $completion.status; exit_code = $completion.exit_code }
    Save-Plan -Plan $plan
} elseif ($Action -eq "AppendEvent") {
    Add-PlanEvent -Plan $plan -Type $EventType -Message $EventMessage
    Save-Plan -Plan $plan
} elseif ($Action -eq "NextReady") {
    $ready = @(Get-ReadyTasks -Plan $plan)
    if ($OutputJson) {
        $ready | ConvertTo-Json -Depth 20
    } else {
        foreach ($task in $ready) {
            Write-Output "$($task.task_id) $($task.title)"
        }
    }
    return
} elseif ($Action -eq "Get") {
    if ($OutputJson) {
        $plan | ConvertTo-Json -Depth 30
    } else {
        Write-Output "plan_id=$($plan.plan_id)"
        Write-Output "title=$($plan.title)"
        Write-Output "repo=$($plan.repo)"
        foreach ($task in @($plan.tasks)) {
            $deps = (@($task.depends_on) -join ",")
            Write-Output "$($task.task_id) status=$($task.status) depends_on=$deps job=$($task.job_id)"
        }
    }
    return
}

if ($OutputJson) {
    $plan | ConvertTo-Json -Depth 30
} else {
    Write-Output (Get-PlanPath -Id $PlanId)
}

