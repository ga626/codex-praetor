param([string]$ProjectRoot = "")

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$root = [System.IO.Path]::GetFullPath($ProjectRoot)
$healthScript = Join-Path $root "scripts\verify\get-codex-praetor-health.ps1"
$pluginHealth = Join-Path $root "plugin\skills\codex-praetor\scripts\get-codex-praetor-health.ps1"
$skillHealth = Join-Path $root "skill\codex-praetor\scripts\get-codex-praetor-health.ps1"
$profile = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-praetor-fast-health-" + [Guid]::NewGuid().ToString("N"))

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Invoke-HealthPayload {
    param([string[]]$Arguments)
    $raw = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $healthScript @Arguments | Out-String
    return [pscustomobject]@{ exit_code = $LASTEXITCODE; payload = ($raw | ConvertFrom-Json) }
}

try {
    foreach ($copyPath in @($pluginHealth, $skillHealth)) {
        $copyText = Get-Content -LiteralPath $copyPath -Raw -Encoding UTF8
        Assert-True ($copyText -match '\[switch\]\$IncludeRuntimeInventory') "Health script copy does not expose IncludeRuntimeInventory: $copyPath"
        Assert-True ($copyText -match 'maintenance_status' -and $copyText -match '"not_run"') "Health script copy does not preserve the fast-path maintenance boundary: $copyPath"
    }
    New-Item -ItemType Directory -Path $profile -Force | Out-Null
    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    $default = Invoke-HealthPayload -Arguments @("-Repo", $root, "-UserProfileRoot", $profile, "-Json")
    $stopwatch.Stop()
    Assert-True ([string]$default.payload.maintenance_status.runtime_inventory -eq "not_run") "Default health unexpectedly ran the full runtime inventory."
    $inventoryCheck = @($default.payload.checks | Where-Object { $_.name -eq "runtime_inventory" } | Select-Object -First 1)
    Assert-True ($inventoryCheck.Count -eq 1 -and [string]$inventoryCheck[0].details -eq "not_run") "Default health did not report the explicit maintenance boundary."
    Assert-True ($stopwatch.Elapsed.TotalSeconds -lt 15) "Default health exceeded the fast-path budget: $($stopwatch.Elapsed.TotalSeconds) seconds."
    $explicit = Invoke-HealthPayload -Arguments @("-Repo", $root, "-UserProfileRoot", $profile, "-IncludeRuntimeInventory", "-Json")
    Assert-True ([string]$explicit.payload.maintenance_status.runtime_inventory -eq "completed") "Explicit health did not run the runtime inventory."
    Write-Output "[PASS] Default health skipped historical inventory in $([math]::Round($stopwatch.Elapsed.TotalSeconds, 2)) seconds; explicit maintenance inventory remained available."
} finally {
    if (Test-Path -LiteralPath $profile) { Remove-Item -LiteralPath $profile -Recurse -Force -ErrorAction SilentlyContinue }
}
