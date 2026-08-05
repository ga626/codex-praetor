param([string]$ProjectRoot = "")

$ErrorActionPreference = "Stop"
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) {
    $global:PSNativeCommandUseErrorActionPreference = $false
}
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$root = [System.IO.Path]::GetFullPath($ProjectRoot)
$wrapper = Join-Path $root "scripts\dispatch\invoke-codex-praetor.ps1"
$scratch = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-praetor-linked-worktree-" + [Guid]::NewGuid().ToString("N"))

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

try {
    New-Item -ItemType Directory -Path $scratch -Force | Out-Null
    $canonicalRepo = Join-Path $scratch "canonical-repo"
    New-Item -ItemType Directory -Path $canonicalRepo -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $canonicalRepo "README.md") -Value "fixture" -Encoding ASCII
    & git -C $canonicalRepo init -q
    & git -C $canonicalRepo config user.email "dispatch-test@example.invalid"
    & git -C $canonicalRepo config user.name "Codex Praetor test"
    & git -C $canonicalRepo add README.md
    & git -C $canonicalRepo commit -qm "fixture"
    if ($LASTEXITCODE -ne 0) { throw "Unable to create the canonical fixture repository." }
    $linkedRepo = Join-Path $scratch "linked-worktree"
    & git -C $canonicalRepo worktree add -q -b linked-source $linkedRepo HEAD 2>$null
    if ($LASTEXITCODE -ne 0) { throw "Unable to create the linked fixture worktree." }

    $fakeQoder = Join-Path $scratch "fake-qoder.cmd"
    "@echo off`r`necho CODEX_PRAETOR_CAPABILITY_CANARY_OK`r`nexit /b 0`r`n" | Set-Content -LiteralPath $fakeQoder -Encoding ASCII
    $config = Get-Content -LiteralPath (Join-Path $root "config\codex-praetor-tiers.example.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    $config.providers.qoder.cliPath = $fakeQoder
    $configPath = Join-Path $scratch "tiers.json"
    $config | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $configPath -Encoding UTF8
    $worktreeName = "linked-regression"
    $jobRoot = Join-Path $scratch "jobs"
    $lockRoot = Join-Path $scratch "locks"
    $planRoot = Join-Path $scratch "plans"
    $scratchRoot = Join-Path $scratch "dispatch-scratch"

    & powershell -NoProfile -ExecutionPolicy Bypass -File $wrapper -Provider qoder -Tier qoder-day-cheap -ConfigPath $configPath -Repo $linkedRepo -Task "Return the canary marker only." -Mode readonly -TaskKind test_execution -RequiredCheck "Test-Path README.md" -CapabilityCanary -WorktreeName $worktreeName -JobRoot $jobRoot -LockRoot $lockRoot -PlanRoot $planRoot -ScratchRoot $scratchRoot -NoNotify -TimeoutSeconds 30 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Linked-worktree dispatch failed." }

    $workerTree = Join-Path $canonicalRepo ".codex\worktrees\$worktreeName"
    $nestedWorkerTree = Join-Path $linkedRepo ".codex\worktrees\$worktreeName"
    Assert-True (Test-Path -LiteralPath $workerTree -PathType Container) "Worker worktree was not created under the canonical project root."
    Assert-True (-not (Test-Path -LiteralPath $nestedWorkerTree -PathType Container)) "Worker worktree was incorrectly nested below the source linked worktree."
    $runtimeOwner = Get-Content -LiteralPath (Join-Path $canonicalRepo ".codex-praetor\runtime-owner.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ([string]$runtimeOwner.canonical_project_root -eq $canonicalRepo) "Runtime ownership record does not name the canonical project root."
    $workerOwner = Get-Content -LiteralPath (Join-Path $canonicalRepo ".codex-praetor\worktree-ownership\$worktreeName.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ([string]$workerOwner.worktree_path -eq $workerTree) "Worker ownership record does not name the actual worker worktree."
    Write-Output "[PASS] Linked source worktree dispatch uses the canonical Git checkout, writes Praetor ownership records, and never nests worker runtime below the source worktree."
} finally {
    $canonicalRepo = Join-Path $scratch "canonical-repo"
    $workerTree = Join-Path $canonicalRepo ".codex\worktrees\linked-regression"
    if (Test-Path -LiteralPath $workerTree -PathType Container) {
        & git -C $canonicalRepo worktree remove --force $workerTree 2>$null | Out-Null
        & git -C $canonicalRepo branch -D "cw-linked-regression" 2>$null | Out-Null
    }
    $linkedRepo = Join-Path $scratch "linked-worktree"
    if (Test-Path -LiteralPath $linkedRepo -PathType Container) {
        & git -C $canonicalRepo worktree remove --force $linkedRepo 2>$null | Out-Null
        & git -C $canonicalRepo branch -D "linked-source" 2>$null | Out-Null
    }
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}
