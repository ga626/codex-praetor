param()

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
. (Join-Path $projectRoot "scripts\maintenance\invoke-codex-praetor-native.ps1")

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$powershell = (Get-Command powershell.exe -ErrorAction Stop).Source
$success = Invoke-CodexPraetorNative -FilePath $powershell -ArgumentList @("-NoProfile", "-Command", "Write-Output native-output; Write-Error native-diagnostic; exit 0") -WorkingDirectory $projectRoot -TimeoutSeconds 10
Assert-True $success.started "Native success process did not start."
Assert-True (-not $success.timed_out) "Native success process timed out."
Assert-True ([int]$success.exit_code -eq 0) "Exit code 0 with stderr must remain successful."
Assert-True ([string]$success.stdout -match "native-output") "Native stdout was not captured."
Assert-True ([string]$success.stderr -match "native-diagnostic") "Native stderr was not captured separately."

$failure = Invoke-CodexPraetorNative -FilePath $powershell -ArgumentList @("-NoProfile", "-Command", "Write-Error native-failure; exit 7") -WorkingDirectory $projectRoot -TimeoutSeconds 10
Assert-True ([int]$failure.exit_code -eq 7) "Non-zero native exit code was not preserved."
Assert-True ([string]$failure.stderr -match "native-failure") "Native failure stderr was not preserved."

$timeout = Invoke-CodexPraetorNative -FilePath $powershell -ArgumentList @("-NoProfile", "-Command", "Start-Sleep -Seconds 3") -WorkingDirectory $projectRoot -TimeoutSeconds 1
Assert-True $timeout.timed_out "Native timeout was not classified."
Assert-True ([int]$timeout.exit_code -eq 124) "Native timeout must use exit code 124."

Write-Host "[PASS] Native invocation regression matrix passed: separated streams, exit-code-first, and timeout classification."
