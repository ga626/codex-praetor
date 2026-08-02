param([string]$ProjectRoot = "")

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$root = Join-Path ([IO.Path]::GetTempPath()) ("codex-praetor-readiness-bootstrap-" + [Guid]::NewGuid().ToString("N"))
$jobDir = Join-Path $root "job"
$readiness = Join-Path $root "readiness.json"
$recorder = Join-Path $ProjectRoot "scripts\dispatch\record-codex-praetor-readiness.ps1"
$cli = (Get-Command powershell.exe -CommandType Application | Select-Object -First 1).Source

function Assert-True { param([bool]$Condition, [string]$Message) if (-not $Condition) { throw $Message } }

try {
    New-Item -ItemType Directory -Path $jobDir -Force | Out-Null
    $stdout = Join-Path $jobDir "stdout.log"
    $completion = Join-Path $jobDir "completion.json"
    $job = [ordered]@{
        job_id = "bootstrap-fixture"
        provider = "codebuddy"
        generation_id = "generation-fixture"
        runtime_contract_sha256 = "runtime-fixture"
        task_contract_schema = "contract-fixture"
        wrapper_protocol = "4"
        evidence_bootstrap = $true
        stdout = $stdout
        completion = $completion
        readiness_path = $readiness
        provider_tuple = [ordered]@{ provider = "codebuddy"; cli_path = $cli; cli_hash = (Get-FileHash -LiteralPath $cli -Algorithm SHA256).Hash.ToLowerInvariant(); model = "fixture-model"; permission_profile = "local-audit-v1"; task_kind = "local_audit"; connection_mode = "codebuddy_acp"; runner_identity = "fixture-runner" }
    }
    $job | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $jobDir "job.json") -Encoding UTF8
    "fixture worker output" | Set-Content -LiteralPath $stdout -Encoding UTF8
    [ordered]@{ schema = "codex-praetor-job-completion/v2"; job_id = "bootstrap-fixture"; status = "process_exited"; exit_code = 0; failure_class = ""; provider_tuple = $job.provider_tuple } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $completion -Encoding UTF8

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $recorder -JobDir $jobDir -ReadinessPath $readiness | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) "Readiness recorder failed."
    $state = Get-Content -LiteralPath $readiness -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ([string]$state.schema -eq "codex-praetor-generation-readiness/v3") "Unexpected readiness schema."
    Assert-True (@($state.entries).Count -eq 1) "Readiness entry was not recorded."
    Assert-True ([string]$state.entries[0].provider_source -eq "real_user_task_bootstrap") "Readiness source was not recorded."
    Assert-True ([string]$state.entries[0].connection_mode -eq "codebuddy_acp") "Connection mode was not recorded."

    $failed = Join-Path $root "failed-completion.json"
    [ordered]@{ schema = "codex-praetor-job-completion/v2"; job_id = "bootstrap-fixture"; status = "process_exited"; exit_code = 1; failure_class = "worker_process_failed" } | ConvertTo-Json | Set-Content -LiteralPath $completion -Encoding UTF8
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $recorder -JobDir $jobDir -ReadinessPath $readiness | Out-Null
    Assert-True (@((Get-Content -LiteralPath $readiness -Raw -Encoding UTF8 | ConvertFrom-Json).entries).Count -eq 1) "Failed worker changed readiness unexpectedly."
    Write-Host "[PASS] Real-task readiness bootstrap records only successful jobs and preserves provider identity."
} finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
