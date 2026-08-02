param([string]$ProjectRoot = "")

$ErrorActionPreference = "Stop"
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) {
    $global:PSNativeCommandUseErrorActionPreference = $false
}
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$root = [System.IO.Path]::GetFullPath($ProjectRoot)
$wrapper = Join-Path $root "scripts\dispatch\invoke-codex-praetor.ps1"
$planScript = Join-Path $root "scripts\dispatch\manage-codex-praetor-plan.ps1"
$scratch = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-praetor-detached-worktree-" + [Guid]::NewGuid().ToString("N"))

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

try {
    New-Item -ItemType Directory -Path $scratch -Force | Out-Null
    $repo = Join-Path $scratch "repo"
    New-Item -ItemType Directory -Path $repo -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $repo "README.md") -Value "fixture" -Encoding UTF8
    $fixtureMcp = Join-Path $repo "mcp"
    New-Item -ItemType Directory -Path $fixtureMcp -Force | Out-Null
    '{"name":"fixture-mcp","version":"1.0.0"}' | Set-Content -LiteralPath (Join-Path $fixtureMcp "package.json") -Encoding UTF8
    '{"name":"fixture-mcp","version":"1.0.0","lockfileVersion":3,"requires":true,"packages":{"":{"name":"fixture-mcp","version":"1.0.0"}}}' | Set-Content -LiteralPath (Join-Path $fixtureMcp "package-lock.json") -Encoding UTF8
    & git -C $repo init -q
    & git -C $repo config user.email "dispatch-test@example.invalid"
    & git -C $repo config user.name "Codex Praetor test"
    & git -C $repo add README.md mcp/package.json mcp/package-lock.json
    & git -C $repo commit -qm "fixture"
    if ($LASTEXITCODE -ne 0) { throw "Unable to create the detached-HEAD fixture repository." }
    $baseCommit = (& git -C $repo rev-parse HEAD | Out-String).Trim()
    Set-Content -LiteralPath (Join-Path $repo "README.md") -Value "fixture-newer" -Encoding UTF8
    & git -C $repo add README.md
    & git -C $repo commit -qm "newer fixture"
    if ($LASTEXITCODE -ne 0) { throw "Unable to create the newer fixture commit." }
    $newerCommit = (& git -C $repo rev-parse HEAD | Out-String).Trim()

    $fakeQoder = Join-Path $scratch "fake-qoder.cmd"
    "@echo off`r`necho CODEX_PRAETOR_CAPABILITY_CANARY_OK`r`nexit /b 0`r`n" | Set-Content -LiteralPath $fakeQoder -Encoding ASCII
    $config = Get-Content -LiteralPath (Join-Path $root "config\codex-praetor-tiers.example.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    $config.providers.qoder.cliPath = $fakeQoder
    $configPath = Join-Path $scratch "tiers.json"
    $config | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $configPath -Encoding UTF8
    $worktreeName = "detached-regression"
    $jobRoot = Join-Path $scratch "jobs"
    $lockRoot = Join-Path $scratch "locks"
    $planRoot = Join-Path $scratch "plans"
    $scratchRoot = Join-Path $scratch "scratch"
    & powershell -NoProfile -ExecutionPolicy Bypass -File $planScript -Action Init -PlanId detached-base -PlanRoot $planRoot -Title "detached base commit" -Repo $repo | Out-Null
    & powershell -NoProfile -ExecutionPolicy Bypass -File $planScript -Action UpsertTask -PlanId detached-base -PlanRoot $planRoot -TaskId audit -TaskTitle "audit frozen base" -TaskFamily read_only_diagnosis -TaskKind local_audit -Mode readonly -Acceptance "frozen base" -BaseCommit $baseCommit | Out-Null
    & powershell -NoProfile -ExecutionPolicy Bypass -File $wrapper -Provider qoder -Tier qoder-day-cheap -ConfigPath $configPath -Repo $repo -Task "Return the canary marker only." -Mode readonly -TaskKind local_audit -TaskFamily read_only_diagnosis -Acceptance "frozen base" -BaseCommit $baseCommit -CapabilityCanary -PlanId detached-base -TaskId audit -WorktreeName $worktreeName -JobRoot $jobRoot -LockRoot $lockRoot -PlanRoot $planRoot -ScratchRoot $scratchRoot -NoNotify -TimeoutSeconds 30 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Detached-HEAD dispatch failed." }
    $workerTree = Join-Path $repo ".codex-praetor\worktrees\$worktreeName"
    Assert-True (Test-Path -LiteralPath $workerTree -PathType Container) "Detached HEAD did not create a worker worktree."
    $branch = (& git -C $workerTree branch --show-current | Out-String).Trim()
    Assert-True ($branch -eq "cw-$worktreeName") "Worker worktree did not receive its isolated branch."
    $workerHead = (& git -C $workerTree rev-parse HEAD | Out-String).Trim()
    Assert-True ($workerHead -eq $baseCommit) "Worker worktree did not start from the requested base commit."
    $jobDirs = @(Get-ChildItem -LiteralPath $jobRoot -Directory | Select-Object -First 1)
    Assert-True ($jobDirs.Count -eq 1) "Local-audit fixture did not record a dispatch job."
    $job = Get-Content -LiteralPath (Join-Path $jobDirs[0].FullName "job.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    $contract = Get-Content -LiteralPath (Join-Path $jobDirs[0].FullName "task-contract.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    $completion = Get-Content -LiteralPath (Join-Path $jobDirs[0].FullName "completion.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    $plan = Get-Content -LiteralPath (Join-Path $planRoot "detached-base\plan.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ([string]$contract.base_commit -eq $baseCommit) "Task contract did not retain the requested base commit."
    Assert-True ([string]$contract.worktree_head -eq $baseCommit) "Task contract did not record the actual frozen worktree head."
    Assert-True ([string]$job.base_commit -eq $baseCommit -and [string]$job.worktree_head -eq $baseCommit) "Job metadata did not retain the frozen base commit evidence."
    Assert-True ([string]$completion.base_commit -eq $baseCommit -and [string]$completion.worktree_head -eq $baseCommit) "Completion did not retain the frozen base commit evidence."
    Assert-True ([string]$plan.tasks[0].attempts[0].base_commit -eq $baseCommit -and [string]$plan.tasks[0].attempts[0].worktree_head -eq $baseCommit) "Ledger attempt did not retain the frozen base commit evidence."

    $defaultName = "default-head"
    & powershell -NoProfile -ExecutionPolicy Bypass -File $wrapper -Provider qoder -Tier qoder-day-cheap -ConfigPath $configPath -Repo $repo -Task "Return the canary marker only." -Mode readonly -TaskKind local_audit -TaskFamily read_only_diagnosis -Acceptance "current head" -CapabilityCanary -WorktreeName $defaultName -JobRoot $jobRoot -LockRoot $lockRoot -PlanRoot $planRoot -ScratchRoot $scratchRoot -NoNotify -TimeoutSeconds 30 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Default-head local audit dispatch failed." }
    $defaultTree = Join-Path $repo ".codex-praetor\worktrees\$defaultName"
    $defaultHead = (& git -C $defaultTree rev-parse HEAD | Out-String).Trim()
    Assert-True ($defaultHead -eq $newerCommit) "Local audit without base_commit did not start from the repository's current HEAD."

    & git -C $repo branch "cw-mismatched-branch" $newerCommit
    if ($LASTEXITCODE -ne 0) { throw "Unable to create the mismatched worker branch fixture." }
    $previousErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        & powershell -NoProfile -ExecutionPolicy Bypass -File $wrapper -Provider qoder -Tier qoder-day-cheap -ConfigPath $configPath -Repo $repo -Task "Must not start." -Mode readonly -TaskKind local_audit -TaskFamily read_only_diagnosis -Acceptance "reject mismatch" -BaseCommit $baseCommit -CapabilityCanary -WorktreeName "mismatched-branch" -JobRoot $jobRoot -LockRoot $lockRoot -PlanRoot $planRoot -ScratchRoot $scratchRoot -NoNotify -TimeoutSeconds 30 2>$null | Out-Null
        Assert-True ($LASTEXITCODE -ne 0) "A pre-existing worker branch at a different commit was reused."
    } finally {
        $ErrorActionPreference = $previousErrorAction
    }
    Write-Output "[PASS] Read-only dispatch honors an explicit base commit across the contract, job, completion, and ledger; an undeclared base still uses current HEAD."
} finally {
    $workerTree = Join-Path $scratch "repo\.codex-praetor\worktrees\detached-regression"
    $repoPath = Join-Path $scratch "repo"
    if (Test-Path -LiteralPath $workerTree -PathType Container) {
        & git -C $repoPath worktree remove --force $workerTree 2>$null | Out-Null
        & git -C $repoPath branch -D "cw-detached-regression" 2>$null | Out-Null
    }
    $defaultTree = Join-Path $scratch "repo\.codex-praetor\worktrees\default-head"
    if (Test-Path -LiteralPath $defaultTree -PathType Container) {
        & git -C $repoPath worktree remove --force $defaultTree 2>$null | Out-Null
        & git -C $repoPath branch -D "cw-default-head" 2>$null | Out-Null
    }
    if (Test-Path -LiteralPath $repoPath -PathType Container) {
        & git -C $repoPath branch -D "cw-mismatched-branch" 2>$null | Out-Null
    }
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}
