param([string]$ProjectRoot = "")

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$root = [IO.Path]::GetFullPath($ProjectRoot)
$wrapper = Join-Path $root "scripts\dispatch\invoke-codex-praetor.ps1"
$planScript = Join-Path $root "scripts\dispatch\manage-codex-praetor-plan.ps1"
$scratch = Join-Path ([IO.Path]::GetTempPath()) ("codex-praetor-real-worktree-" + [Guid]::NewGuid().ToString("N"))

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

try {
    New-Item -ItemType Directory -Path $scratch -Force | Out-Null
    $repo = Join-Path $scratch "repo"
    New-Item -ItemType Directory -Path (Join-Path $repo "src") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $repo "mcp") -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $repo "README.md") -Value "immutable" -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $repo "src\allowed.txt") -Value "broken" -Encoding ASCII
    '{"name":"fixture-mcp","version":"1.0.0"}' | Set-Content -LiteralPath (Join-Path $repo "mcp\package.json") -Encoding ASCII
    '{"name":"fixture-mcp","version":"1.0.0","lockfileVersion":3,"requires":true,"packages":{"":{"name":"fixture-mcp","version":"1.0.0"}}}' | Set-Content -LiteralPath (Join-Path $repo "mcp\package-lock.json") -Encoding ASCII
    & git -C $repo init -q
    & git -C $repo config user.email "dispatch-test@example.invalid"
    & git -C $repo config user.name "Codex Praetor test"
    & git -C $repo add README.md src/allowed.txt mcp/package.json mcp/package-lock.json
    & git -C $repo commit -qm "fixture"
    if ($LASTEXITCODE -ne 0) { throw "Unable to create the real-worktree fixture repository." }
    $baseCommit = (& git -C $repo rev-parse HEAD | Out-String).Trim()

    $fakeQoder = Join-Path $scratch "fake-qoder.cmd"
    "@echo off`r`necho fixed> src\allowed.txt`r`necho worker completed`r`nexit /b 0`r`n" | Set-Content -LiteralPath $fakeQoder -Encoding ASCII
    $config = Get-Content -LiteralPath (Join-Path $root "config\codex-praetor-tiers.example.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    $config.providers.qoder.cliPath = $fakeQoder
    $configPath = Join-Path $scratch "tiers.json"
    $config | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $configPath -Encoding UTF8
    $jobRoot = Join-Path $scratch "jobs"; $lockRoot = Join-Path $scratch "locks"; $planRoot = Join-Path $scratch "plans"; $scratchRoot = Join-Path $scratch "worker-scratch"

    & powershell -NoProfile -ExecutionPolicy Bypass -File $planScript -Action Init -PlanId real-edit -PlanRoot $planRoot -Title "real edit" -Repo $repo | Out-Null
    & powershell -NoProfile -ExecutionPolicy Bypass -File $planScript -Action UpsertTask -PlanId real-edit -PlanRoot $planRoot -TaskId change -TaskTitle "repair allowed file" -TaskFamily bounded_code_change -TaskKind code_change -Mode edit -AllowedPath "src/allowed.txt" -ForbiddenPath ".git/**" -RequiredCheck "cmd /c findstr /x fixed src\allowed.txt" -BudgetJson '{"max_attempts":1,"max_turns":1,"max_wall_seconds":30}' -BaseCommit $baseCommit -ImmutablePath "README.md" -Acceptance "real diff" | Out-Null
    & powershell -NoProfile -ExecutionPolicy Bypass -File $wrapper -Provider qoder -Tier qoder-day-cheap -ConfigPath $configPath -Repo $repo -Task "Repair src/allowed.txt so it contains fixed." -Mode edit -TaskKind code_change -TaskFamily bounded_code_change -RealWorktree -BaseCommit $baseCommit -ImmutablePath "README.md" -AllowedPath "src/allowed.txt" -ForbiddenPath ".git/**" -RequiredCheck "cmd /c findstr /x fixed src\allowed.txt" -CapabilityCanary -PlanId real-edit -TaskId change -WorktreeName real-edit -JobRoot $jobRoot -LockRoot $lockRoot -PlanRoot $planRoot -ScratchRoot $scratchRoot -NoNotify -TimeoutSeconds 30 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Real-worktree fixture dispatch failed." }
    $workerTree = Join-Path $repo ".codex-praetor\worktrees\real-edit"
    Assert-True (Test-Path -LiteralPath $workerTree -PathType Container) "Real code-change did not create its Git worktree."
    $changed = (& git -C $workerTree diff --name-only $baseCommit | Out-String).Trim()
    Assert-True ($changed -eq "src/allowed.txt") "Real code-change did not produce the expected source Git diff."
    $immutable = (& git -C $workerTree show HEAD:README.md | Out-String).Trim()
    Assert-True ($immutable -eq "immutable") "Real code-change changed an immutable path."
    Push-Location $workerTree
    try { cmd /c "findstr /x fixed src\allowed.txt" | Out-Null; if ($LASTEXITCODE -ne 0) { throw "Independent required check failed." } } finally { Pop-Location }
    & powershell -NoProfile -ExecutionPolicy Bypass -File $planScript -Action VerifyTask -PlanId real-edit -PlanRoot $planRoot -TaskId change -VerificationVerdict accepted -VerificationSummary "independent check passed" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Real-worktree acceptance gate rejected a valid source diff." }
    $plan = Get-Content -LiteralPath (Join-Path $planRoot "real-edit\plan.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ([string]$plan.tasks[0].governance_state -eq "accepted") "Accepted real worktree task was not written to the ledger."

    $previousErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        & powershell -NoProfile -ExecutionPolicy Bypass -File $wrapper -Provider qoder -Tier qoder-day-cheap -ConfigPath $configPath -Repo $repo -Task "invalid copied source task" -Mode edit -TaskKind code_change -TaskFamily bounded_code_change -CapabilityCanary -DryRun -NoNotify 2>$null | Out-Null
        Assert-True ($LASTEXITCODE -ne 0) "A non-real code_change was not blocked before dispatch."
    } finally {
        $ErrorActionPreference = $previousErrorAction
    }
    Write-Output "[PASS] Real code-change uses a frozen Git worktree, limits its diff, preserves immutable files, and requires independent acceptance evidence."
} finally {
    $workerTree = Join-Path $scratch "repo\.codex-praetor\worktrees\real-edit"
    $repoPath = Join-Path $scratch "repo"
    if (Test-Path -LiteralPath $workerTree -PathType Container) {
        & git -C $repoPath worktree remove --force $workerTree 2>$null | Out-Null
        & git -C $repoPath branch -D "cw-real-edit" 2>$null | Out-Null
    }
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}
