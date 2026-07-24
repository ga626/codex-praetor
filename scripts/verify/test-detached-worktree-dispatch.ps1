param([string]$ProjectRoot = "")

$ErrorActionPreference = "Stop"
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) {
    $global:PSNativeCommandUseErrorActionPreference = $false
}
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$root = [System.IO.Path]::GetFullPath($ProjectRoot)
$wrapper = Join-Path $root "scripts\dispatch\invoke-codex-praetor.ps1"
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
    & git -C $repo checkout --detach -q
    if ($LASTEXITCODE -ne 0) { throw "Unable to detach the fixture HEAD." }

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
    & powershell -NoProfile -ExecutionPolicy Bypass -File $wrapper -Provider qoder -Tier qoder-day-cheap -ConfigPath $configPath -Repo $repo -Task "Return the canary marker only." -Mode readonly -TaskKind test_execution -RequiredCheck "Test-Path README.md" -CapabilityCanary -WorktreeName $worktreeName -JobRoot $jobRoot -LockRoot $lockRoot -PlanRoot $planRoot -ScratchRoot $scratchRoot -NoNotify -TimeoutSeconds 30 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Detached-HEAD dispatch failed." }
    $workerTree = Join-Path $repo ".codex-praetor\worktrees\$worktreeName"
    Assert-True (Test-Path -LiteralPath $workerTree -PathType Container) "Detached HEAD did not create a worker worktree."
    $branch = (& git -C $workerTree branch --show-current | Out-String).Trim()
    Assert-True ($branch -eq "cw-$worktreeName") "Worker worktree did not receive its isolated branch."
    $jobDirs = @(Get-ChildItem -LiteralPath $jobRoot -Directory | Select-Object -First 1)
    Assert-True ($jobDirs.Count -eq 1) "Test-execution fixture did not record a dispatch job."
    $job = Get-Content -LiteralPath (Join-Path $jobDirs[0].FullName "job.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ([string]$job.dependency_bootstrap -eq "mcp_npm_ci") "Test-execution worker worktree did not complete its MCP dependency bootstrap."
    Write-Output "[PASS] Detached HEAD resolves HEAD commit, creates an isolated worker branch, and bootstraps MCP dependencies before test execution."
} finally {
    $workerTree = Join-Path $scratch "repo\.codex-praetor\worktrees\detached-regression"
    $repoPath = Join-Path $scratch "repo"
    if (Test-Path -LiteralPath $workerTree -PathType Container) {
        & git -C $repoPath worktree remove --force $workerTree 2>$null | Out-Null
        & git -C $repoPath branch -D "cw-detached-regression" 2>$null | Out-Null
    }
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}
