param(
    [Parameter(Mandatory = $true)][string]$ExpectedGenerationPath,
    [string]$InstallRoot = (Join-Path $env:USERPROFILE "plugins\codex-praetor"),
    [string]$MarketplacePath = (Join-Path $env:USERPROFILE ".agents\plugins\marketplace.json"),
    [string]$HostRuntimeInfoPath = "",
    [switch]$Json
)

$ErrorActionPreference = "Stop"

function Read-JsonRequired([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Label is missing: $Path" }
    try { return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json } catch { throw "$Label is invalid JSON: $Path" }
}
function Get-Generation([string]$Path, [string]$Label) {
    $value = Read-JsonRequired $Path $Label
    foreach ($name in @("product", "version", "generation_id", "commit", "runtime_contract_sha256")) {
        if ([string]::IsNullOrWhiteSpace([string]$value.$name)) { throw "${Label} lacks ${name}: $Path" }
    }
    if ([string]$value.product -ne "codex-praetor") { throw "$Label has unexpected product: $($value.product)" }
    return $value
}
function Test-GenerationEqual($Left, $Right) {
    return $null -ne $Left -and $null -ne $Right -and
        [string]$Left.version -eq [string]$Right.version -and
        [string]$Left.generation_id -eq [string]$Right.generation_id -and
        [string]$Left.commit -eq [string]$Right.commit -and
        [string]$Left.runtime_contract_sha256 -eq [string]$Right.runtime_contract_sha256
}

$expectedPath = [IO.Path]::GetFullPath($ExpectedGenerationPath)
$installPath = [IO.Path]::GetFullPath($InstallRoot)
$marketplacePath = [IO.Path]::GetFullPath($MarketplacePath)
$expected = Get-Generation $expectedPath "Expected release generation"
$installedPath = Join-Path $installPath "release-generation.json"
$installed = if (Test-Path -LiteralPath $installedPath -PathType Leaf) { Get-Generation $installedPath "Installed plugin generation" } else { $null }
$marketplaceOk = $false
if (Test-Path -LiteralPath $marketplacePath -PathType Leaf) {
    try {
        $marketplace = Get-Content -LiteralPath $marketplacePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $entry = @($marketplace.plugins | Where-Object { [string]$_.name -eq "codex-praetor" } | Select-Object -First 1)
        $marketplaceOk = $entry.Count -eq 1 -and [string]$entry[0].source.source -eq "local" -and [string]$entry[0].source.path -eq "./plugins/codex-praetor"
    } catch { $marketplaceOk = $false }
}

$status = "needs_install"
$reason = "stable_install_identity_mismatch"
$runtimeInfo = $null
if (Test-GenerationEqual $expected $installed -and $marketplaceOk) {
    $status = "needs_host_restart"
    $reason = "host_runtime_not_observed"
    if (-not [string]::IsNullOrWhiteSpace($HostRuntimeInfoPath)) {
        $observed = Read-JsonRequired ([IO.Path]::GetFullPath($HostRuntimeInfoPath)) "Host runtime observation"
        $runtimeInfo = if ($null -ne $observed.runtime_info) { $observed.runtime_info } else { $observed }
        $identity = $runtimeInfo.runtime_identity
        $contract = $runtimeInfo.runtime_contract
        $hostMatches = $null -ne $identity -and $null -ne $contract -and
            [string]$contract.version -eq [string]$expected.version -and
            [string]$identity.runtime_contract_sha256 -eq [string]$expected.runtime_contract_sha256 -and
            -not [string]::IsNullOrWhiteSpace([string]$runtimeInfo.contract_path) -and
            -not [string]::IsNullOrWhiteSpace([string]$identity.project_root) -and
            [int64]$identity.process_id -gt 0
        if ($hostMatches) {
            $status = "needs_canary"
            $reason = "host_matches_installed_generation"
        } else {
            $reason = "host_runtime_identity_mismatch"
        }
    }
}

$payload = [ordered]@{
    schema = "codex-praetor-installation-state/v1"
    status = $status
    reason = $reason
    expected_generation = $expected
    installed_generation = $installed
    stable_install_path = $installPath
    marketplace_path = $marketplacePath
    marketplace_matches = $marketplaceOk
    host_runtime_observed = ($null -ne $runtimeInfo)
    next_action = switch ($status) {
        "needs_install" { "Install the target Release into the stable marketplace, then re-check its identity." }
        "needs_host_restart" { "Refresh the Codex host through a supported action or restart it; a new task alone cannot refresh the host." }
        default { "Run one real readonly canary from a clean repository or isolated checkout before real worker dispatch." }
    }
}
if ($Json) { $payload | ConvertTo-Json -Depth 12 } else { Write-Host "Status: $($payload.status); reason: $($payload.reason)"; Write-Host "Next: $($payload.next_action)" }
