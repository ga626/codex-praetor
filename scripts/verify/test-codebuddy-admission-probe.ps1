param([string]$ProjectRoot = "")

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
. (Join-Path $ProjectRoot "scripts\dispatch\resolve-codebuddy-admission.ps1")
function Assert-True { param([bool]$Condition, [string]$Message) if (-not $Condition) { throw $Message } }

$expired = Resolve-CodexPraetorCodeBuddyAdmissionOutput -ModelName "hy3" -Stdout "CodeBuddy 2.115.0`nSession expired. You have been automatically logged out." -ExitCode 0
Assert-True ($expired.status -eq "blocked" -and $expired.failure_class -eq "provider_auth_required") "Expired sessions must stop before worker creation."
$missing = Resolve-CodexPraetorCodeBuddyAdmissionOutput -ModelName "hy3" -Stdout "CodeBuddy 2.115.0`nModels: deepseek-v4-flash" -ExitCode 0
Assert-True ($missing.status -eq "ready" -and $missing.advisory_class -eq "configured_model_not_advertised") "Unadvertised custom fixed models must require final task evidence without being confused with authentication failure."
$ready = Resolve-CodexPraetorCodeBuddyAdmissionOutput -ModelName "hy3" -Stdout "CodeBuddy 2.115.0`nModels: Hy3, deepseek-v4-flash" -ExitCode 0
Assert-True ($ready.status -eq "ready" -and $ready.model_advertised) "Case-insensitive advertised fixed model must pass."
$failed = Resolve-CodexPraetorCodeBuddyAdmissionOutput -ModelName "hy3" -Stderr "launcher failure" -ExitCode 1
Assert-True ($failed.status -eq "blocked" -and $failed.failure_class -eq "provider_cli_probe_failed") "CLI launch errors must stop before worker creation."
foreach ($record in @($expired, $missing, $ready, $failed)) {
    Assert-True (-not ($record.PSObject.Properties.Name -contains "stdout") -and -not ($record.PSObject.Properties.Name -contains "stderr")) "Admission probe must not persist CLI transcripts."
}
Write-Host "[PASS] CodeBuddy admission probe rejects expired sessions and unadvertised models without retaining CLI output."
