param(
    [string]$Repo = (Get-Location).Path,

    [ValidateSet("qoder", "codebuddy")]
    [string]$Provider,

    [string]$Tier = "",

    [string]$ConfigPath = "",

    [ValidateSet("local_audit", "test_execution", "code_change")]
    [string]$TaskKind = "local_audit",

    [int]$ExpiresAfterHours = 168,

    [string]$ReadinessPath = "",

    # Test-only override. The production path always resolves the bundled
    # dispatcher from the installed/source generation.
    [string]$WrapperPath = "",

    [switch]$Apply
)

$ErrorActionPreference = "Stop"
$hashHelperCandidates = @(
    (Join-Path (Split-Path -Parent $PSScriptRoot) "shared\ensure-file-hash.ps1"),
    (Join-Path $PSScriptRoot "ensure-file-hash.ps1")
)
$hashHelper = @($hashHelperCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1)
if (@($hashHelper).Count -ne 1) { throw "Capability canary hash helper is missing." }
. ([string]$hashHelper[0])
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

    # The wrapper echoes its command, which includes the natural-language
    # prompt.  That echo is transport diagnostics, never worker evidence.
    $jobDir = Get-Field -Text $WrapperOutput -Name "job_dir"
    $jobPath = if ([string]::IsNullOrWhiteSpace($jobDir)) { "" } else { Join-Path $jobDir "job.json" }
    if (-not (Test-Path -LiteralPath $jobPath -PathType Leaf)) { throw "Capability canary did not publish job metadata." }
    $job = Get-Content -LiteralPath $jobPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $completionPath = [string]$job.completion
    if ([string]::IsNullOrWhiteSpace($completionPath)) { $completionPath = Join-Path $jobDir "completion.json" }
    if (-not (Test-Path -LiteralPath $completionPath -PathType Leaf)) { throw "Capability canary did not publish completion evidence." }
    $completion = Get-Content -LiteralPath $completionPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$completion.status -ne "process_exited" -or [int]$completion.exit_code -ne 0 -or -not [string]::IsNullOrWhiteSpace([string]$completion.failure_class)) {
        throw "Capability canary worker did not complete successfully."
    }
    $stdoutPath = [string]$job.stdout
    if ([string]::IsNullOrWhiteSpace($stdoutPath)) { $stdoutPath = Join-Path $jobDir "stdout.log" }
    if (-not (Test-Path -LiteralPath $stdoutPath -PathType Leaf)) { throw "Capability canary did not publish worker stdout." }
    $workerOutput = Get-Content -LiteralPath $stdoutPath -Raw -Encoding UTF8
    if ($workerOutput -notmatch [regex]::Escape($ExpectedMarker)) { throw "Worker stdout did not return the required marker." }
    return [pscustomobject]@{
        job = $job
        completion = $completion
        job_dir = $jobDir
        job_path = $jobPath
        stdout_path = $stdoutPath
        completion_path = $completionPath
        worker_stdout_sha256 = (Get-FileHash -LiteralPath $stdoutPath -Algorithm SHA256).Hash.ToLowerInvariant()
        completion_sha256 = (Get-FileHash -LiteralPath $completionPath -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}

function Get-CanaryFileSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function New-CodeChangeCanaryMaterial {
    param(
        [Parameter(Mandatory = $true)][string]$StatePath,
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$ScriptDirectory
    )

    $bundleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $ScriptDirectory))
    $templateCandidates = @(
        (Join-Path $ProjectRoot "config\evaluation-task-templates\bounded-test-fix"),
        (Join-Path $ProjectRoot "data\evaluation-task-templates\bounded-test-fix"),
        (Join-Path $bundleRoot "data\evaluation-task-templates\bounded-test-fix")
    )
    $template = @($templateCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Container } | Select-Object -First 1)
    if (@($template).Count -ne 1) { throw "Capability canary code-change template is missing from this generation." }

    $materialRoot = Join-Path (Split-Path -Parent $StatePath) ("canary-material-" + [guid]::NewGuid().ToString("N"))
    $sourceRoot = Join-Path $materialRoot "source"
    New-Item -ItemType Directory -Path $sourceRoot -Force | Out-Null
    Copy-Item -Path (Join-Path ([string]$template[0]) "*") -Destination $sourceRoot -Recurse -Force

    $files = @()
    foreach ($relativePath in @("compute.ps1", "task.json", "test.ps1")) {
        $sourcePath = Join-Path $sourceRoot $relativePath
        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) { throw "Capability canary material is missing $relativePath." }
        $files += [ordered]@{ path = $relativePath; sha256 = Get-CanaryFileSha256 -Path $sourcePath }
    }
    $destination = ".codex-praetor/evaluation/capability-canary-code-change"
    $material = [ordered]@{
        schema = "codex-praetor-task-material-instance/v1"
        source_root = $sourceRoot
        destination = $destination
        write_set = @("$destination/compute.ps1")
        immutable_paths = @("$destination/test.ps1", "$destination/task.json")
        baseline_command = "powershell -NoProfile -ExecutionPolicy Bypass -File $destination/test.ps1"
        baseline_exit_code = 1
        files = $files
    }
    $manifestPath = Join-Path $sourceRoot "material-manifest.json"
    $material | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    $material.manifest_sha256 = Get-CanaryFileSha256 -Path $manifestPath
    $contractPath = Join-Path $sourceRoot "task-material.json"
    $material | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $contractPath -Encoding UTF8
    return [pscustomobject]@{ material = [pscustomobject]$material; contract_path = $contractPath; root = $materialRoot }
}

if (-not [string]::IsNullOrWhiteSpace($WrapperPath)) {
    $wrapper = [System.IO.Path]::GetFullPath($WrapperPath)
}
if (@($wrapper).Count -ne 1 -or -not (Test-Path -LiteralPath $wrapper -PathType Leaf)) {
    throw "Dispatcher is missing: $wrapper"
}
if (@($nativeHelper).Count -ne 1) { throw "Native invocation helper is missing." }
$wrapper = if ($wrapper -is [array]) { [string]$wrapper[0] } else { [string]$wrapper }
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
# Keep the worker instruction natural and small. Readonly permissions,
# network policy, timeout, marker parsing and repository observations are
# supervisor-side protocol, not prompt padding.
$canaryMaterial = $null
$canaryMaterialRoot = ""
$taskMaterialVerifierCandidates = @(
    (Join-Path $projectRoot "scripts\verify\verify-codex-praetor-task-material.ps1"),
    (Join-Path $projectRoot "skill\codex-praetor\scripts\verify-codex-praetor-task-material.ps1"),
    (Join-Path $projectRoot "plugin\skills\codex-praetor\scripts\verify-codex-praetor-task-material.ps1"),
    (Join-Path $scriptDir "verify-codex-praetor-task-material.ps1")
)
$taskMaterialVerifier = @($taskMaterialVerifierCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1)
$task = if ($TaskKind -eq "code_change") {
    "Repair the supplied failing sum script. Change only compute.ps1, run the supplied test, then reply exactly $marker."
} elseif ($TaskKind -eq "test_execution") {
    "Run the fixed PowerShell check `"Test-Path README.md`" in the execution worktree. Do not edit files. Reply exactly $marker only if the command returns True."
} else {
    "Read README.md and reply exactly $marker."
}

if ($TaskKind -eq "code_change") {
    if (@($taskMaterialVerifier).Count -ne 1) { throw "Capability canary task-material verifier is missing." }
    $canaryMaterial = New-CodeChangeCanaryMaterial -StatePath $statePath -ProjectRoot $projectRoot -ScriptDirectory $scriptDir
    $canaryMaterialRoot = [string]$canaryMaterial.root
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
if ($TaskKind -eq "test_execution") {
    $argsList += @("-RequiredCheck", "Test-Path README.md")
}
if (-not [string]::IsNullOrWhiteSpace($Tier)) {
    $argsList += @("-Tier", $Tier)
}
if ($TaskKind -eq "code_change") {
    $material = $canaryMaterial.material
    $allowedPathsJson = @($material.write_set | ForEach-Object { Split-Path -Parent $_ }) | Select-Object -Unique | ConvertTo-Json -Compress
    $forbiddenPathsJson = @(".git", "plugin", "skill", "config", "**/*auth*") | ConvertTo-Json -Compress
    $requiredChecksJson = @([string]$material.baseline_command) | ConvertTo-Json -Compress
    $budgetJson = [ordered]@{ max_turns = 8; max_wall_seconds = 900 } | ConvertTo-Json -Compress
    $argsList += @(
        "-TaskMaterialPath", [string]$canaryMaterial.contract_path,
        "-AllowedPathsJson", $allowedPathsJson,
        "-ForbiddenPathsJson", $forbiddenPathsJson,
        "-RequiredChecksJson", $requiredChecksJson,
        "-BudgetJson", $budgetJson,
        "-FailureInjection", "baseline_must_fail; immutable_test_or_scope_drift_must_be_rejected",
        "-Sensitivity", "public_code_only",
        "-Acceptance", "Baseline fails first; only compute.ps1 changes; immutable files remain unchanged; supplied test passes.",
        "-PlanId", "capability-canary",
        "-TaskId", "bounded-code-change"
    )
}
if (-not $Apply) {
    $argsList += "-DryRun"
}

$beforeStatus = (& git -C $Repo status --short 2>$null | Out-String).Trim()
if ($Apply -and -not [string]::IsNullOrWhiteSpace($beforeStatus)) {
    throw "Capability canary requires a clean repository before it starts. Use an isolated checkout or commit/stash the current changes first."
}
$nativeResult = Invoke-CodexPraetorNative -FilePath "powershell.exe" -ArgumentList $argsList -WorkingDirectory $projectRoot -TimeoutSeconds 360
$exitCode = [int]$nativeResult.exit_code
$outputText = (([string]$nativeResult.stdout) + "`n" + ([string]$nativeResult.stderr)).Trim()
$afterStatus = (& git -C $Repo status --short 2>$null | Out-String).Trim()
Write-Output $outputText.Trim()

if (-not $Apply) {
    if ($exitCode -ne 0) {
        if (-not [string]::IsNullOrWhiteSpace($canaryMaterialRoot) -and (Test-Path -LiteralPath $canaryMaterialRoot)) { Remove-Item -LiteralPath $canaryMaterialRoot -Recurse -Force -ErrorAction SilentlyContinue }
        throw "Canary preview failed with exit code $exitCode."
    }
    if (-not [string]::IsNullOrWhiteSpace($canaryMaterialRoot) -and (Test-Path -LiteralPath $canaryMaterialRoot)) { Remove-Item -LiteralPath $canaryMaterialRoot -Recurse -Force -ErrorAction SilentlyContinue }
    Write-Host "[PASS] Preview only. No provider worker was started."
    exit 0
}

try {
    if ($exitCode -ne 0) { throw "Capability canary failed with exit code $exitCode." }
    $workerEvidence = Get-CanaryWorkerEvidence -WrapperOutput $outputText -ExpectedMarker $marker
    $materialVerification = $null
    if ($TaskKind -eq "code_change") {
        $job = $workerEvidence.job
        $workerRepo = [string]$job.execution_repo
        $taskContractPath = [string]$job.task_contract
        if ([string]::IsNullOrWhiteSpace($taskContractPath) -or -not (Test-Path -LiteralPath $taskContractPath -PathType Leaf)) { throw "Edit capability canary did not publish its task contract." }
        $taskContract = Get-Content -LiteralPath $taskContractPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $jobMaterial = $taskContract.task_material
        if ($null -eq $jobMaterial -or [string]$jobMaterial.manifest_sha256 -ne [string]$canaryMaterial.material.manifest_sha256) { throw "Edit capability canary did not retain the immutable material contract in its task contract evidence." }
        $materialVerificationText = & ([string]$taskMaterialVerifier[0]) -Worktree $workerRepo -TaskMaterialJson (([pscustomobject]$canaryMaterial.material) | ConvertTo-Json -Compress -Depth 8) -RequiredChecksJson (@([string]$canaryMaterial.material.baseline_command) | ConvertTo-Json -Compress)
        if ($LASTEXITCODE -ne 0) { throw "Edit capability canary independent material verifier did not complete." }
        $materialVerification = $materialVerificationText | ConvertFrom-Json
        if ([string]$materialVerification.verdict -ne "accepted_candidate") { throw "Edit capability canary failed independent contract verification: $(@($materialVerification.violations) -join '; ')." }
    }

# The worker proof and the caller checkout are independent observations. A
# concurrent editor can change the checkout while a genuinely readonly worker
# succeeds; losing that proof would deadlock every subsequent dispatch. A dirty
# *starting* checkout remains unsafe and is rejected above. Drift during the
# run is preserved as evidence rather than being misattributed to the worker.
$repoObservation = [ordered]@{
    clean_before = [string]::IsNullOrWhiteSpace($beforeStatus)
    clean_after = [string]::IsNullOrWhiteSpace($afterStatus)
    status = if ($beforeStatus -eq $afterStatus) { "unchanged" } else { "external_repo_drift_observed" }
    before_status = $beforeStatus
    after_status = $afterStatus
    observed_at = (Get-Date).ToString("o")
}
if ($repoObservation.status -eq "external_repo_drift_observed") {
    Write-Warning "Repository status changed while the canary ran. Provider proof remains valid; checkout drift was recorded for review."
}

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
    repo_observation = $repoObservation
    evidence = [ordered]@{
        schema = "codex-praetor-canary-evidence/v1"
        job_id = [string]$workerEvidence.job.job_id
        job_path = $workerEvidence.job_path
        stdout_path = $workerEvidence.stdout_path
        completion_path = $workerEvidence.completion_path
        worker_stdout_sha256 = $workerEvidence.worker_stdout_sha256
        completion_sha256 = $workerEvidence.completion_sha256
        completion_status = [string]$workerEvidence.completion.status
        worker_exit_code = [int]$workerEvidence.completion.exit_code
        failure_class = [string]$workerEvidence.completion.failure_class
        task_material_manifest_sha256 = if ($TaskKind -eq "code_change") { [string]$canaryMaterial.material.manifest_sha256 } else { "" }
        task_contract_sha256 = if ($TaskKind -eq "code_change") { Get-CanaryFileSha256 -Path ([string]$workerEvidence.job.task_contract) } else { "" }
        material_verdict = if ($null -eq $materialVerification) { "" } else { [string]$materialVerification.verdict }
        material_violations = if ($null -eq $materialVerification) { @() } else { @($materialVerification.violations) }
    }
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
    repo_observation = $repoObservation
    updated_at = (Get-Date).ToString("o")
    entries = $entries
}
$stateDirectory = Split-Path -Parent $statePath
if (-not (Test-Path -LiteralPath $stateDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $stateDirectory -Force | Out-Null
}
$state | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $statePath -Encoding UTF8
Write-Host "[PASS] Capability canary passed and readiness tuple was recorded."
} finally {
    if (-not [string]::IsNullOrWhiteSpace($canaryMaterialRoot) -and (Test-Path -LiteralPath $canaryMaterialRoot)) {
        Remove-Item -LiteralPath $canaryMaterialRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
