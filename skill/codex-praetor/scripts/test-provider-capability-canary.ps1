param(
    [string]$Repo = (Get-Location).Path,

    [ValidateSet("qoder", "codebuddy", "mimo")]
    [string]$Provider,

    [string]$Tier = "",

    [string]$ConfigPath = "",

    [ValidateSet("local_audit", "test_execution", "code_change")]
    [string]$TaskKind = "local_audit",

    [int]$ExpiresAfterHours = 168,

    [string]$ReadinessPath = "",

    [switch]$Apply
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "ensure-file-hash.ps1")
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
$wrapperCandidates = @(
    (Join-Path $projectRoot "scripts\dispatch\invoke-codex-praetor.ps1"),
    (Join-Path $scriptDir "invoke-codex-praetor.ps1")
)
$wrapper = @($wrapperCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1)
$generationScript = Join-Path $projectRoot "scripts\release\get-codex-praetor-generation.ps1"
$runtimeContractCandidates = @(
    (Join-Path $projectRoot "config\runtime-contract.json"),
    (Join-Path $scriptDir "runtime-contract.json")
)
$runtimeContractPath = @($runtimeContractCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1)
$nativeHelperCandidates = @(
    (Join-Path $projectRoot "scripts\maintenance\invoke-codex-praetor-native.ps1"),
    (Join-Path $scriptDir "invoke-codex-praetor-native.ps1")
)
$runningGenerationHelperCandidates = @(
    (Join-Path $projectRoot "scripts\verify\resolve-codex-praetor-running-generation.ps1"),
    (Join-Path $scriptDir "resolve-codex-praetor-running-generation.ps1")
)
$nativeHelper = @($nativeHelperCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1)
$statePath = if ([string]::IsNullOrWhiteSpace($ReadinessPath)) {
    Join-Path $env:USERPROFILE ".codex\codex-praetor-readiness.json"
} else {
    [System.IO.Path]::GetFullPath($ReadinessPath)
}
$marker = "CODEX_PRAETOR_CAPABILITY_CANARY_OK"

function Get-Field {
    param([string]$Text, [string]$Name)
    $match = [regex]::Match($Text, "(?m)^" + [regex]::Escape($Name) + "=(.+)$")
    if ($match.Success) { return $match.Groups[1].Value.Trim() }
    return ""
}

function Get-ProviderCliPath {
    param([string]$Path, [string]$ProviderName)
    $config = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    return [string]$config.providers.$ProviderName.cliPath
}

function Get-CanaryWorkerEvidence {
    param([string]$WrapperOutput, [string]$ExpectedMarker)

    $jobDir = Get-Field -Text $WrapperOutput -Name "job_dir"
    $jobPath = if ([string]::IsNullOrWhiteSpace($jobDir)) { "" } else { Join-Path $jobDir "job.json" }
    if (-not (Test-Path -LiteralPath $jobPath -PathType Leaf)) { throw "Capability canary did not publish job metadata." }
    $job = Get-Content -LiteralPath $jobPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $completionPath = [string]$job.completion
    if ([string]::IsNullOrWhiteSpace($completionPath)) { $completionPath = Join-Path $jobDir "completion.json" }
    if (-not (Test-Path -LiteralPath $completionPath -PathType Leaf)) { throw "Capability canary did not publish completion evidence." }
    $completion = Get-Content -LiteralPath $completionPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$completion.status -ne "process_exited" -or [int]$completion.exit_code -ne 0 -or -not [string]::IsNullOrWhiteSpace([string]$completion.failure_class)) { throw "Capability canary worker did not complete successfully." }
    $stdoutPath = [string]$job.stdout
    if ([string]::IsNullOrWhiteSpace($stdoutPath)) { $stdoutPath = Join-Path $jobDir "stdout.log" }
    if (-not (Test-Path -LiteralPath $stdoutPath -PathType Leaf)) { throw "Capability canary did not publish worker stdout." }
    if ((Get-Content -LiteralPath $stdoutPath -Raw -Encoding UTF8) -notmatch [regex]::Escape($ExpectedMarker)) { throw "Worker stdout did not return the required marker." }
    return [pscustomobject]@{ job = $job; completion = $completion; job_dir = $jobDir; job_path = $jobPath; stdout_path = $stdoutPath; completion_path = $completionPath; worker_stdout_sha256 = (Get-FileHash -LiteralPath $stdoutPath -Algorithm SHA256).Hash.ToLowerInvariant(); completion_sha256 = (Get-FileHash -LiteralPath $completionPath -Algorithm SHA256).Hash.ToLowerInvariant() }
}

if (@($wrapper).Count -ne 1) {
    throw "Dispatcher is missing: $wrapper"
}
if (@($nativeHelper).Count -ne 1) { throw "Native invocation helper is missing." }
$wrapper = [string]$wrapper[0]
$nativeHelper = [string]$nativeHelper[0]
. $nativeHelper
$runningGenerationHelperPath = @($runningGenerationHelperCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1)
if (@($runningGenerationHelperPath).Count -ne 1) { throw "Running generation helper is missing." }
. ([string]$runningGenerationHelperPath[0])
if (@($runtimeContractPath).Count -ne 1) { throw "Runtime contract is missing." }
$runtimeContractPath = [string]$runtimeContractPath[0]
$runtimeContract = Get-Content -LiteralPath $runtimeContractPath -Raw -Encoding UTF8 | ConvertFrom-Json
$runtimeContractHash = (Get-FileHash -LiteralPath $runtimeContractPath -Algorithm SHA256).Hash.ToLowerInvariant()
$generation = Resolve-CodexPraetorRunningGeneration -RuntimeContractPath $runtimeContractPath -ProjectRoot $projectRoot -ScriptDirectory $scriptDir
if (-not (Test-Path -LiteralPath $Repo -PathType Container)) {
    throw "Repository path does not exist: $Repo"
}
if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $env:USERPROFILE ".codex\codex-praetor.local.json"
}
if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    throw "Provider configuration is missing: $ConfigPath"
}

$mode = if ($TaskKind -eq "code_change") { "edit" } else { "readonly" }
$canaryFileName = "CODEX_PRAETOR_EDIT_CANARY.txt"
$task = if ($TaskKind -eq "code_change") {
    "Create $canaryFileName at the repository root with exactly $marker, run git status --short, then reply exactly $marker."
} elseif ($TaskKind -eq "test_execution") {
    "Run the fixed PowerShell check `"Test-Path README.md`" in the execution worktree. Do not edit files. Reply exactly $marker only if the command returns True."
} else {
    "Read README.md and return exactly $marker in the final response. Do not perform external network research. Do not modify files."
}

$argsList = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $wrapper,
    "-Provider", $Provider,
    "-Repo", $Repo,
    "-Task", $task,
    "-Mode", $mode,
    "-TaskKind", $TaskKind,
    "-RunMode", "blocking",
    "-TimeoutSeconds", "300",
    "-ConfigPath", $ConfigPath,
    "-ReadinessPath", $statePath,
    "-CapabilityCanary",
    "-NoNotify"
)
if (-not [string]::IsNullOrWhiteSpace($Tier)) {
    $argsList += @("-Tier", $Tier)
}
if (-not $Apply) {
    $argsList += "-DryRun"
}

$beforeStatus = (& git -C $Repo status --short 2>$null | Out-String).Trim()
$nativeResult = Invoke-CodexPraetorNative -FilePath "powershell.exe" -ArgumentList $argsList -WorkingDirectory $projectRoot -TimeoutSeconds 360
$exitCode = [int]$nativeResult.exit_code
$outputText = (([string]$nativeResult.stdout) + "`n" + ([string]$nativeResult.stderr)).Trim()
$afterStatus = (& git -C $Repo status --short 2>$null | Out-String).Trim()
Write-Output $outputText.Trim()

if (-not $Apply) {
    if ($exitCode -ne 0) { throw "Canary preview failed with exit code $exitCode." }
    Write-Host "[PASS] Preview only. No provider worker was started."
    exit 0
}

if ($exitCode -ne 0) { throw "Capability canary failed with exit code $exitCode." }
$workerEvidence = Get-CanaryWorkerEvidence -WrapperOutput $outputText -ExpectedMarker $marker
if ($TaskKind -eq "code_change") {
    $job = $workerEvidence.job
    $workerRepo = [string]$job.execution_repo
    $canaryPath = Join-Path $workerRepo $canaryFileName
    if (-not (Test-Path -LiteralPath $canaryPath -PathType Leaf)) { throw "Edit capability canary produced no canary file in the worker worktree." }
    if ((Get-Content -LiteralPath $canaryPath -Raw -Encoding UTF8) -notmatch [regex]::Escape($marker)) { throw "Edit capability canary file does not contain the required marker." }
    if ([string]::IsNullOrWhiteSpace((& git -C $workerRepo status --short 2>$null | Out-String).Trim())) { throw "Edit capability canary produced no observable worker worktree change." }
}
if ($beforeStatus -ne $afterStatus) { throw "Canary changed the main checkout status." }

$cliPath = Get-ProviderCliPath -Path $ConfigPath -ProviderName $Provider
$cliHash = if (Test-Path -LiteralPath $cliPath -PathType Leaf) { (Get-FileHash -LiteralPath $cliPath -Algorithm SHA256).Hash } else { "" }
$entry = [pscustomobject]@{
    generation_id = [string]$generation.generation_id
    runtime_contract_sha256 = $runtimeContractHash
    task_contract_schema = [string]$runtimeContract.taskContractSchema
    provider = $Provider
    cli_path = $cliPath
    cli_hash = $cliHash
    model = [string]$workerEvidence.job.provider_tuple.model
    permission_profile = [string]$workerEvidence.job.provider_tuple.permission_profile
    task_kind = $TaskKind
    status = "passed"
    passed_at = (Get-Date).ToString("o")
    expires_at = (Get-Date).AddHours($ExpiresAfterHours).ToString("o")
    wrapper_protocol = [string]$runtimeContract.wrapperProtocol
    provider_source = "capability_canary"
    cli_version = Get-Field -Text $outputText -Name "version"
    evidence = [ordered]@{ schema = "codex-praetor-canary-evidence/v1"; job_id = [string]$workerEvidence.job.job_id; job_path = $workerEvidence.job_path; stdout_path = $workerEvidence.stdout_path; completion_path = $workerEvidence.completion_path; worker_stdout_sha256 = $workerEvidence.worker_stdout_sha256; completion_sha256 = $workerEvidence.completion_sha256; completion_status = [string]$workerEvidence.completion.status; worker_exit_code = [int]$workerEvidence.completion.exit_code; failure_class = [string]$workerEvidence.completion.failure_class }
}

$entries = @()
if (Test-Path -LiteralPath $statePath -PathType Leaf) {
    try {
        $previous = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $entries = @($previous.entries)
    } catch {
        $entries = @()
    }
}
$entries = @($entries | Where-Object {
    -not ([string]$_.provider -eq $entry.provider -and
        [string]$_.cli_path -eq $entry.cli_path -and
        [string]$_.model -eq $entry.model -and
        [string]$_.permission_profile -eq $entry.permission_profile -and
        [string]$_.task_kind -eq $entry.task_kind)
})
$entries += $entry
$state = [pscustomobject]@{
    schema = "codex-praetor-generation-readiness/v3"
    status = "passed"
    generation_id = [string]$generation.generation_id
    runtime_contract_sha256 = $runtimeContractHash
    task_contract_schema = [string]$runtimeContract.taskContractSchema
    provider = $Provider
    tuple = [ordered]@{
        cli_path = $cliPath
        cli_hash = $cliHash
        model = [string]$entry.model
        permission_profile = [string]$entry.permission_profile
        task_kind = [string]$entry.task_kind
    }
    provider_source = "capability_canary"
    updated_at = (Get-Date).ToString("o")
    entries = $entries
}
$stateDirectory = Split-Path -Parent $statePath
if (-not (Test-Path -LiteralPath $stateDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $stateDirectory -Force | Out-Null
}
$state | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $statePath -Encoding UTF8
Write-Host "[PASS] Capability canary passed and readiness tuple was recorded."
