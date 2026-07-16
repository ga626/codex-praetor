param(
    [string]$Repo = (Get-Location).Path,

    [ValidateSet("qoder", "codebuddy", "mimo")]
    [string]$Provider,

    [string]$Tier = "",

    [string]$ConfigPath = "",

    [ValidateSet("local_audit", "code_change")]
    [string]$TaskKind = "local_audit",

    [int]$ExpiresAfterHours = 168,

    [switch]$Apply
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
$wrapper = Join-Path $projectRoot "scripts\dispatch\invoke-codex-praetor.ps1"
$nativeHelper = Join-Path $projectRoot "scripts\maintenance\invoke-codex-praetor-native.ps1"
. $nativeHelper
$statePath = Join-Path $env:USERPROFILE ".codex\codex-praetor-readiness.json"
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

if (-not (Test-Path -LiteralPath $wrapper -PathType Leaf)) {
    throw "Dispatcher is missing: $wrapper"
}
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
$task = @"
Read README.md and return exactly $marker in the final response.
Do not perform external network research.
Do not modify files.
"@

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
if ($outputText -notmatch [regex]::Escape($marker)) { throw "Worker did not return the required marker." }
if ($beforeStatus -ne $afterStatus) { throw "Canary changed the main checkout status." }

$cliPath = Get-ProviderCliPath -Path $ConfigPath -ProviderName $Provider
$cliHash = if (Test-Path -LiteralPath $cliPath -PathType Leaf) { (Get-FileHash -LiteralPath $cliPath -Algorithm SHA256).Hash } else { "" }
$entry = [pscustomobject]@{
    provider = $Provider
    cli_path = $cliPath
    cli_hash = $cliHash
    model = Get-Field -Text $outputText -Name "model"
    permission_profile = Get-Field -Text $outputText -Name "permission_profile"
    task_kind = $TaskKind
    status = "passed"
    passed_at = (Get-Date).ToString("o")
    expires_at = (Get-Date).AddHours($ExpiresAfterHours).ToString("o")
    wrapper_protocol = "2"
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
    schema = "codex-praetor-provider-readiness/v1"
    updated_at = (Get-Date).ToString("o")
    entries = $entries
}
$state | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $statePath -Encoding UTF8
Write-Host "[PASS] Capability canary passed and readiness tuple was recorded."
