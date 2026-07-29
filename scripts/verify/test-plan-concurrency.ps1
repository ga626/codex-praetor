param(
    [string]$ProjectRoot = ""
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}
$projectPath = [IO.Path]::GetFullPath($ProjectRoot)
$planScript = Join-Path $projectPath "scripts\dispatch\manage-codex-praetor-plan.ps1"
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("codex-praetor-plan-concurrency-" + [Guid]::NewGuid().ToString("N"))
$planId = "concurrency"

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Start-PlanWriter {
    param([string]$Writer)
    return Start-Job -ScriptBlock {
        param([string]$ScriptPath, [string]$Id, [string]$Root, [string]$WriterName)
        for ($index = 1; $index -le 10; $index++) {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ScriptPath -Action AppendEvent -PlanId $Id -PlanRoot $Root -EventType "concurrency_probe" -EventMessage ("writer=$WriterName;index=$index") | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "writer=$WriterName index=$index exit=$LASTEXITCODE" }
        }
    } -ArgumentList $planScript, $planId, $testRoot, $Writer
}

try {
    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $planScript -Action Init -PlanId $planId -PlanRoot $testRoot -Title "Concurrency regression" -Repo $projectPath | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) "Could not initialize concurrency fixture plan."

    $writers = @(
        (Start-PlanWriter -Writer "A"),
        (Start-PlanWriter -Writer "B")
    )
    Wait-Job -Job $writers | Out-Null
    foreach ($writerJob in $writers) {
        $messages = @((Receive-Job -Job $writerJob -ErrorAction SilentlyContinue) | ForEach-Object { [string]$_ })
        $state = [string]$writerJob.State
        Remove-Job -Job $writerJob -Force
        Assert-True ($state -eq "Completed") ("Concurrent plan writer failed: " + ($messages -join " | "))
    }

    $planPath = Join-Path (Join-Path $testRoot $planId) "plan.json"
    $plan = Get-Content -LiteralPath $planPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $events = @($plan.events | Where-Object { [string]$_.type -eq "concurrency_probe" })
    $messages = @($events | ForEach-Object { [string]$_.message } | Sort-Object -Unique)
    Assert-True ($events.Count -eq 20) "Concurrent plan writes lost events: expected=20 observed=$($events.Count)."
    Assert-True ($messages.Count -eq 20) "Concurrent plan writes lost unique event messages: expected=20 observed=$($messages.Count)."
    Assert-True ([int]$plan.revision -eq 21) "Plan revision is not monotonic across concurrent writes: expected=21 observed=$($plan.revision)."
    Write-Host "[PASS] Concurrent plan writers retain all events and leave a parseable monotonic ledger."
} finally {
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
