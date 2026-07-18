$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
$installer = Join-Path $projectRoot "scripts\install\install-codex-praetor-maintenance.ps1"
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-praetor-maintenance-test-" + [Guid]::NewGuid().ToString("N"))

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Throws {
    param([scriptblock]$Action, [string]$Message)
    try { & $Action } catch { return }
    throw $Message
}

New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
try {
    $SkipMain = $true
    . $installer -UserProfileRoot $tempRoot -SourceRoot $projectRoot
    Remove-Variable SkipMain -ErrorAction SilentlyContinue

    $script:taskExists = $false
    $script:fallbackCalls = 0
    function global:Register-ScheduledTask { throw "Access is denied" }
    $successfulFallback = {
        param($Name, $Executable, $TaskArguments, $UserId)
        $script:fallbackCalls++
        $script:taskExists = $true
    }
    $successfulVerification = {
        param($Name, $Executable, $TaskArguments)
        if (-not $script:taskExists) { throw "fallback did not register a task" }
    }

    Install-MaintenanceTask -Name "CodexPraetor-TestFallback" -ApplyChanges -FallbackRegistration $successfulFallback -RegistrationVerification $successfulVerification
    Assert-True ($script:fallbackCalls -eq 1) "ScheduledTasks failure must invoke the schtasks fallback."
    Assert-True $script:taskExists "Fallback path must be verified as a registered task."

    $script:taskExists = $false
    $failedFallback = { throw "fallback denied" }
    Assert-Throws { Install-MaintenanceTask -Name "CodexPraetor-TestFailure" -ApplyChanges -FallbackRegistration $failedFallback } "A failed fallback must stop installation."

    $activation = Get-Content (Join-Path $projectRoot "scripts\release\complete-codex-praetor-release.ps1") -Raw
    $maintenanceOffset = $activation.IndexOf('& $maintenanceScript -UserProfileRoot $profilePath -SourceRoot $projectPath -Apply')
    $activeReceiptOffset = $activation.IndexOf('Write-JsonAtomically -Path $activeReceiptPath -Value $receipt')
    Assert-True ($maintenanceOffset -ge 0 -and $activeReceiptOffset -gt $maintenanceOffset) "Activation must install maintenance before writing the active receipt."

    Write-Host "[PASS] Maintenance task fallback, failure propagation, and activation ordering are verified."
} finally {
    foreach ($name in @('Register-ScheduledTask')) {
        Remove-Item "function:\global:$name" -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}
