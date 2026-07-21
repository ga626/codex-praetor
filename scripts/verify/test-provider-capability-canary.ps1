param(
    [string]$Repo = (Get-Location).Path,

    [ValidateSet("qoder", "codebuddy", "mimo")]
    [string]$Provider,

    [string]$Tier = "",

    [string]$ConfigPath = "",

    [ValidateSet("local_audit", "code_change")]
    [string]$TaskKind = "local_audit",

    [int]$ExpiresAfterHours = 168,

    [string]$ReadinessPath = "",

    # Test-only override. The production path always resolves the bundled
    # dispatcher from the installed/source generation.
    [string]$WrapperPath = "",

    [switch]$Apply
)

$ErrorActionPreference = "Stop"
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
$task = "Read README.md and reply exactly $marker."

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
if ($Apply -and -not [string]::IsNullOrWhiteSpace($beforeStatus)) {
    throw "Capability canary requires a clean repository before it starts. Use an isolated checkout or commit/stash the current changes first."
}
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
if ($outputText -notmatch [regex]::Escape($marker)) { throw "Worker did not return the required marker." }

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
    model = Get-Field -Text $outputText -Name "model"
    permission_profile = Get-Field -Text $outputText -Name "permission_profile"
    task_kind = $TaskKind
    status = "passed"
    passed_at = (Get-Date).ToString("o")
    expires_at = (Get-Date).AddHours($ExpiresAfterHours).ToString("o")
    wrapper_protocol = [string]$runtimeContract.wrapperProtocol
    provider_source = "capability_canary"
    cli_version = Get-Field -Text $outputText -Name "version"
    repo_observation = $repoObservation
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
    schema = "codex-praetor-generation-readiness/v2"
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
