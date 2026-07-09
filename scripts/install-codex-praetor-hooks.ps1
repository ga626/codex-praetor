param(
    [switch]$Apply,
    [switch]$Json
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
$hooksRoot = Join-Path $projectRoot ".githooks"
$required = @(
    (Join-Path $hooksRoot "pre-commit"),
    (Join-Path $hooksRoot "pre-push")
)

$missing = @($required | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) })
$steps = New-Object System.Collections.Generic.List[object]

if ($missing.Count -gt 0) {
    $payload = [ordered]@{
        schema = "codex-praetor-hook-install/v1"
        status = "FAIL"
        missing_hooks = $missing
    }
    if ($Json) { $payload | ConvertTo-Json -Depth 5 } else { Write-Host "Missing hooks: $($missing -join ', ')" }
    exit 1
}

if (-not $Apply) {
    $payload = [ordered]@{
        schema = "codex-praetor-hook-install/v1"
        status = "PLAN"
        action = "git config core.hooksPath .githooks"
        apply_required = $true
    }
    if ($Json) { $payload | ConvertTo-Json -Depth 5 } else { Write-Host "Plan: set git config core.hooksPath .githooks. Add -Apply to execute." }
    exit 0
}

$set = & git -C $projectRoot config core.hooksPath .githooks 2>&1
$steps.Add([ordered]@{ command = "git config core.hooksPath .githooks"; output = ($set | Out-String).Trim(); exit_code = $LASTEXITCODE })
$verify = & git -C $projectRoot config --get core.hooksPath 2>&1
$steps.Add([ordered]@{ command = "git config --get core.hooksPath"; output = ($verify | Out-String).Trim(); exit_code = $LASTEXITCODE })

$ok = ($LASTEXITCODE -eq 0 -and (($verify | Out-String).Trim()) -eq ".githooks")
$payload = [ordered]@{
    schema = "codex-praetor-hook-install/v1"
    status = if ($ok) { "PASS" } else { "FAIL" }
    git_hooks_path = (($verify | Out-String).Trim())
    steps = $steps
}

if ($Json) {
    $payload | ConvertTo-Json -Depth 8
} else {
    Write-Host "Codex Praetor hooks: $($payload.status)"
    Write-Host "core.hooksPath=$($payload.git_hooks_path)"
}

if (-not $ok) { exit 1 }
exit 0
