param(
    [Parameter(Mandatory = $true)][string]$JobDir,
    [Parameter(Mandatory = $true)][string]$ReadinessPath,
    [int]$ExpiresAfterHours = 168
)

$ErrorActionPreference = "Stop"

function Read-Json([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Sha256([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return "" }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$jobPath = Join-Path $JobDir "job.json"
$completionPath = Join-Path $JobDir "completion.json"
$job = Read-Json $jobPath
$completion = Read-Json $completionPath
if ($null -eq $job -or $null -eq $completion) { throw "Readiness bootstrap requires job.json and completion.json." }
if (-not [bool]$job.evidence_bootstrap) { Write-Output "readiness_bootstrap=not_requested"; exit 0 }
if ([string]$completion.status -ne "process_exited" -or [int]$completion.exit_code -ne 0 -or -not [string]::IsNullOrWhiteSpace([string]$completion.failure_class)) {
    Write-Output "readiness_bootstrap=not_recorded"
    Write-Output "readiness_bootstrap_reason=worker_not_successful"
    exit 0
}

$stdoutPath = [string]$job.stdout
$completionPath = [string]$job.completion
$providerTuple = $completion.provider_tuple
if ($null -eq $providerTuple) { $providerTuple = $job.provider_tuple }
foreach ($name in @("provider", "cli_path", "cli_hash", "model", "permission_profile", "task_kind", "connection_mode")) {
    if ([string]::IsNullOrWhiteSpace([string]$providerTuple.$name)) { throw "Readiness bootstrap is missing provider tuple field: $name" }
}
if ([string]$providerTuple.cli_hash -ne (Sha256 ([string]$providerTuple.cli_path))) { throw "Readiness bootstrap CLI hash does not match the current CLI." }

$entry = [ordered]@{
    generation_id = [string]$job.generation_id
    runtime_contract_sha256 = [string]$job.runtime_contract_sha256
    task_contract_schema = [string]$job.task_contract_schema
    provider = [string]$providerTuple.provider
    cli_path = [string]$providerTuple.cli_path
    cli_hash = [string]$providerTuple.cli_hash
    model = [string]$providerTuple.model
    permission_profile = [string]$providerTuple.permission_profile
    task_kind = [string]$providerTuple.task_kind
    connection_mode = [string]$providerTuple.connection_mode
    runner_identity = [string]$providerTuple.runner_identity
    status = "passed"
    passed_at = (Get-Date).ToString("o")
    expires_at = (Get-Date).AddHours($ExpiresAfterHours).ToString("o")
    wrapper_protocol = [string]$job.wrapper_protocol
    provider_source = "real_user_task_bootstrap"
    evidence = [ordered]@{
        schema = "codex-praetor-canary-evidence/v1"
        job_id = [string]$job.job_id
        job_path = $jobPath
        stdout_path = $stdoutPath
        completion_path = $completionPath
        worker_stdout_sha256 = Sha256 $stdoutPath
        completion_sha256 = Sha256 $completionPath
        completion_status = [string]$completion.status
        worker_exit_code = [int]$completion.exit_code
        failure_class = [string]$completion.failure_class
        source = "real_user_task"
    }
}
if ([string]::IsNullOrWhiteSpace([string]$entry.evidence.worker_stdout_sha256) -or [string]::IsNullOrWhiteSpace([string]$entry.evidence.completion_sha256)) { throw "Readiness bootstrap evidence files are missing." }

$state = Read-Json $ReadinessPath
$entries = if ($null -eq $state -or $null -eq $state.entries) { @() } else { @($state.entries) }
$entries = @($entries | Where-Object {
    -not ([string]$_.provider -eq [string]$entry.provider -and
        [string]$_.cli_path -eq [string]$entry.cli_path -and
        [string]$_.model -eq [string]$entry.model -and
        [string]$_.permission_profile -eq [string]$entry.permission_profile -and
        [string]$_.task_kind -eq [string]$entry.task_kind -and
        [string]$_.connection_mode -eq [string]$entry.connection_mode)
})
$entries += [pscustomobject]$entry
$stateOut = [ordered]@{
    schema = "codex-praetor-generation-readiness/v3"
    status = "passed"
    generation_id = [string]$entry.generation_id
    runtime_contract_sha256 = [string]$entry.runtime_contract_sha256
    task_contract_schema = [string]$entry.task_contract_schema
    provider = [string]$entry.provider
    tuple = [ordered]@{ cli_path = [string]$entry.cli_path; cli_hash = [string]$entry.cli_hash; model = [string]$entry.model; permission_profile = [string]$entry.permission_profile; task_kind = [string]$entry.task_kind; connection_mode = [string]$entry.connection_mode; runner_identity = [string]$entry.runner_identity }
    provider_source = "real_user_task_bootstrap"
    updated_at = (Get-Date).ToString("o")
    entries = $entries
}
$parent = Split-Path -Parent ([IO.Path]::GetFullPath($ReadinessPath))
if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
$stateOut | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $ReadinessPath -Encoding UTF8
Write-Output "readiness_bootstrap=recorded"
Write-Output "readiness_job_id=$($entry.evidence.job_id)"
