param(
    [Parameter(Mandatory = $true)]
    [string]$ThreadId,

    [Parameter(Mandatory = $true)]
    [string]$Workspace,

    [Parameter(Mandatory = $true)]
    [string]$CompletionPath,

    [Parameter(Mandatory = $true)]
    [string]$JobDir,

    [string]$QueueRoot = "$env:USERPROFILE\.codex\codex-praetor-notifications",

    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

function Write-JsonFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [object]$Value
    )
    $Value | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Get-SafeName {
    param([string]$Value)
    return ($Value -replace '[^A-Za-z0-9_.-]', '_')
}

function Move-EventFiles {
    param(
        [System.IO.FileInfo[]]$Files,
        [string]$Destination
    )
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    $moved = @()
    foreach ($file in $Files) {
        $target = Join-Path $Destination $file.Name
        Move-Item -LiteralPath $file.FullName -Destination $target -Force
        $moved += Get-Item -LiteralPath $target
    }
    return $moved
}

function Restore-EventFiles {
    param(
        [System.IO.FileInfo[]]$Files,
        [string]$PendingDir
    )
    New-Item -ItemType Directory -Path $PendingDir -Force | Out-Null
    foreach ($file in $Files) {
        Move-Item -LiteralPath $file.FullName -Destination (Join-Path $PendingDir $file.Name) -Force
    }
}

$safeThread = Get-SafeName $ThreadId
$threadDir = Join-Path $QueueRoot $safeThread
$pendingDir = Join-Path $threadDir "pending"
$processingRoot = Join-Path $threadDir "processing"
$sentRoot = Join-Path $threadDir "sent"
$failedRoot = Join-Path $threadDir "failed"
$logPath = Join-Path $threadDir "notifier.log"
$lockPath = Join-Path $threadDir "notify.lock"

New-Item -ItemType Directory -Path $pendingDir -Force | Out-Null
New-Item -ItemType Directory -Path $processingRoot -Force | Out-Null
New-Item -ItemType Directory -Path $sentRoot -Force | Out-Null
New-Item -ItemType Directory -Path $failedRoot -Force | Out-Null

$completion = Get-Content -LiteralPath $CompletionPath -Raw | ConvertFrom-Json
$jobId = if ($completion.job_id) { [string]$completion.job_id } else { Split-Path -Leaf $JobDir }
$eventName = "{0}-{1}.json" -f (Get-Date -Format "yyyyMMdd-HHmmss-fff"), (Get-SafeName $jobId)
$eventPath = Join-Path $pendingDir $eventName
$event = [ordered]@{
    thread_id = $ThreadId
    workspace = $Workspace
    completion_path = $CompletionPath
    job_dir = $JobDir
    job_id = $jobId
    provider = $completion.provider
    tier = $completion.tier
    model = $completion.model
    plan_id = $completion.plan_id
    task_id = $completion.task_id
    depends_on = $completion.depends_on
    acceptance = $completion.acceptance
    repo = $completion.repo
    mode = $completion.mode
    status = $completion.status
    exit_code = $completion.exit_code
    stdout = $completion.stdout
    stderr = $completion.stderr
    queued_at = (Get-Date).ToString("o")
}
Write-JsonFile -Path $eventPath -Value $event

$lockStream = $null
try {
    if (Test-Path -LiteralPath $lockPath) {
        $stale = $false
        try {
            $lockText = Get-Content -LiteralPath $lockPath -Raw
            $match = [regex]::Match($lockText, 'pid=(\d+)')
            if ($match.Success) {
                $lockPid = [int]$match.Groups[1].Value
                try {
                    $null = Get-Process -Id $lockPid -ErrorAction Stop
                } catch {
                    $stale = $true
                }
            } else {
                $item = Get-Item -LiteralPath $lockPath
                if ($item.LastWriteTimeUtc -lt (Get-Date).ToUniversalTime().AddMinutes(-30)) {
                    $stale = $true
                }
            }
        } catch {
            $stale = $false
        }
        if ($stale) {
            Remove-Item -LiteralPath $lockPath -Force
            "removed_stale_lock $(Get-Date -Format o)" | Add-Content -LiteralPath $logPath -Encoding UTF8
        }
    }

    try {
        $lockStream = [System.IO.File]::Open($lockPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        $lockBytes = [Text.Encoding]::UTF8.GetBytes("pid=$PID`ncreated_at=$((Get-Date).ToString('o'))`n")
        $lockStream.Write($lockBytes, 0, $lockBytes.Length)
        $lockStream.Flush()
    } catch {
        "queued_only $(Get-Date -Format o) job=$jobId lock_busy" | Add-Content -LiteralPath $logPath -Encoding UTF8
        return
    }

    $sendScript = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "send-codex-thread-message.ps1"
    while ($true) {
        $pending = @(Get-ChildItem -LiteralPath $pendingDir -Filter "*.json" -File -ErrorAction SilentlyContinue | Sort-Object Name)
        if ($pending.Count -eq 0) {
            break
        }

        $batchId = Get-Date -Format "yyyyMMdd-HHmmss-fff"
        $processingDir = Join-Path $processingRoot $batchId
        $batchFiles = @(Move-EventFiles -Files $pending -Destination $processingDir)
        $items = @()
        foreach ($file in $batchFiles) {
            $items += (Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json)
        }

        $lines = @()
        $lines += "codex-praetor jobs finished. Please verify this batch before merging or dispatching dependent work."
        $lines += ""
        foreach ($item in $items) {
            $lines += "- Job: $($item.job_id)"
            if ($item.plan_id -or $item.task_id) {
                $lines += "  Plan/task: $($item.plan_id) / $($item.task_id)"
            }
            $lines += "  Provider/tier/model: $($item.provider) / $($item.tier) / $($item.model)"
            $lines += "  Repo: $($item.repo)"
            $lines += "  Mode/status/exit: $($item.mode) / $($item.status) / $($item.exit_code)"
            if ($item.acceptance) {
                $lines += "  Acceptance: $($item.acceptance)"
            }
            $lines += "  Completion: $($item.completion_path)"
            $lines += "  Logs: $($item.stdout) ; $($item.stderr)"
        }
        $lines += ""
        $lines += "Important: validate changed files, tests, and risks yourself. If more worker events arrived while you were validating, the notifier will send the next batch after this turn finishes."
        $message = $lines -join "`n"

        if ($DryRun) {
            $message
            $sentDir = Join-Path $sentRoot $batchId
            Move-EventFiles -Files $batchFiles -Destination $sentDir | Out-Null
            "dry_sent $(Get-Date -Format o) batch=$batchId count=$($items.Count)" | Add-Content -LiteralPath $logPath -Encoding UTF8
            continue
        }

        $sendExitCode = 1
        try {
            $result = & powershell -NoProfile -ExecutionPolicy Bypass -File $sendScript -ThreadId $ThreadId -Workspace $Workspace -Message $message -ReasoningEffort minimal -WaitTurnComplete -TimeoutMs 600000 2>&1
            $sendExitCode = $LASTEXITCODE
        } catch {
            $result = @($_.Exception.Message)
            $sendExitCode = 1
        }
        $textResult = ($result -join "`n")
        if ($sendExitCode -eq 0 -and $textResult -match '"id":2') {
            $sentDir = Join-Path $sentRoot $batchId
            Move-EventFiles -Files $batchFiles -Destination $sentDir | Out-Null
            $textResult | Set-Content -LiteralPath (Join-Path $sentDir "send-result.log") -Encoding UTF8
            "sent $(Get-Date -Format o) batch=$batchId count=$($items.Count)" | Add-Content -LiteralPath $logPath -Encoding UTF8
        } else {
            $failedDir = Join-Path $failedRoot $batchId
            Move-EventFiles -Files $batchFiles -Destination $failedDir | Out-Null
            $textResult | Set-Content -LiteralPath (Join-Path $failedDir "send-error.log") -Encoding UTF8
            Restore-EventFiles -Files @(Get-ChildItem -LiteralPath $failedDir -Filter "*.json" -File) -PendingDir $pendingDir
            "send_failed $(Get-Date -Format o) batch=$batchId count=$($items.Count)" | Add-Content -LiteralPath $logPath -Encoding UTF8
            break
        }
    }
} finally {
    if ($null -ne $lockStream) {
        $lockStream.Dispose()
        if (Test-Path -LiteralPath $lockPath) {
            Remove-Item -LiteralPath $lockPath -Force
        }
    }
}

