param([string]$ProjectRoot = "")

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}
$root = [System.IO.Path]::GetFullPath($ProjectRoot)
$wrapper = Join-Path $root "scripts\dispatch\invoke-codex-praetor.ps1"
$scratch = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-praetor-codebuddy-permission-" + [Guid]::NewGuid().ToString("N"))

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Invoke-ProtocolFixture {
    param(
        [string]$Mode,
        [string]$TaskKind,
        [string]$ExpectedTools,
        [string]$WorktreeName = "",
        [switch]$AllowNetwork
    )

    $arguments = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $wrapper,
        "-Provider", "codebuddy", "-Tier", "codebuddy-free",
        "-ConfigPath", $configPath,
        "-Repo", $repo,
        "-Task", "Return the fixture marker only.",
        "-Mode", $Mode,
        "-TaskKind", $TaskKind,
        "-NoNotify",
        "-TimeoutSeconds", "60",
        "-JobRoot", $jobRoot,
        "-LockRoot", $lockRoot,
        "-PlanRoot", $planRoot,
        "-ScratchRoot", $scratchRoot,
        "-DryRun"
    )
    if ($AllowNetwork) { $arguments += "-AllowWorkerNetwork" }
    if ($TaskKind -eq "code_change") { $arguments += @("-TaskMaterialPath", $codeChangeMaterialPath, "-CapabilityCanary") }
    if ($TaskKind -eq "test_execution") { $arguments += @("-RequiredCheck", "Test-Path README.md") }
    if (-not [string]::IsNullOrWhiteSpace($WorktreeName)) {
        $arguments += @("-WorktreeName", $WorktreeName)
    }
    $output = & powershell.exe @arguments
    $exitCode = $LASTEXITCODE
    Assert-True ($exitCode -eq 0) "CodeBuddy $Mode permission fixture failed with exit code $exitCode."
    $commandLine = @($output | Where-Object { [string]$_ -like "command=*" } | Select-Object -Last 1)
    Assert-True ($commandLine.Count -eq 1) "CodeBuddy $Mode fixture did not emit its command contract."
    $command = [string]$commandLine[0]
    Assert-True ($command -match "codebuddy-acp-runner\.js --options-file") "CodeBuddy $Mode dispatch did not select the ACP runner."
    Assert-True ($command -notmatch "--tools|--permission-mode|--allowedTools|--disallowedTools|dontAsk") "CodeBuddy $Mode ACP dispatch leaked the historical CLI permission protocol."
    $acpSource = Get-Content -LiteralPath (Join-Path $root "mcp\src\codebuddy-acp-runner.ts") -Raw -Encoding UTF8
    Assert-True ($acpSource -match '"--acp", "-y", "--setting-sources", "project"') "CodeBuddy ACP runner is missing its supported non-interactive launch contract."
    Assert-True ($acpSource -match 'session/request_permission' -and $acpSource -match 'pathAllowed') "CodeBuddy ACP runner no longer enforces its client-side path and permission proxy."
    if ($AllowNetwork) {
        $allOutput = $output | Out-String
        $source = Get-Content -LiteralPath $wrapper -Raw -Encoding UTF8
        Assert-True ($allOutput -match "worker_network=allowed_by_codex") "Allowed network contract was not recorded by the dry-run."
        Assert-True ($source -match '\$networkRule = if \(\$AllowWorkerNetwork\)' -and $source -match "External network access is allowed for this task") "Allowed network contract is not propagated into the worker prompt source."
    }
}

try {
    New-Item -ItemType Directory -Path $scratch -Force | Out-Null
    $repo = Join-Path $scratch "repo"
    New-Item -ItemType Directory -Path $repo -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $repo "README.md") -Value "fixture" -Encoding ASCII
    & git -C $repo init -q
    & git -C $repo config user.email "permission-test@example.invalid"
    & git -C $repo config user.name "Codex Praetor test"
    & git -C $repo add README.md
    & git -C $repo commit -qm "fixture"
    if ($LASTEXITCODE -ne 0) { throw "Unable to create the CodeBuddy permission fixture repository." }

    $fakeCodeBuddy = Join-Path $scratch "fake-codebuddy.js"
    Set-Content -LiteralPath $fakeCodeBuddy -Value "// Dry-run contract fixture; the wrapper must not invoke this file." -Encoding ASCII

    $config = Get-Content -LiteralPath (Join-Path $root "config\codex-praetor-tiers.example.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    $config.providers.codebuddy.nodePath = "node"
    $config.providers.codebuddy.cliPath = $fakeCodeBuddy
    $configPath = Join-Path $scratch "tiers.json"
    $config | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $configPath -Encoding UTF8
    $jobRoot = Join-Path $scratch "jobs"
    $lockRoot = Join-Path $scratch "locks"
    $planRoot = Join-Path $scratch "plans"
    $scratchRoot = Join-Path $scratch "worker-scratch"
    $initializer = Join-Path $root "scripts\evaluation\initialize-codex-praetor-evaluation.ps1"
    # Keep generated baseline refs and disposable staging worktrees inside the
    # fixture repository. This protocol test must not mutate the product
    # checkout merely to obtain evaluation material.
    & $initializer -ProjectRoot $repo -SuitePath (Join-Path $root 'config\evaluation-suite.json') -TemplateRoot (Join-Path $root 'config\evaluation-task-templates') -PlanScript (Join-Path $root 'scripts\dispatch\manage-codex-praetor-plan.ps1') -Action Prepare -PlanRoot $planRoot -PlanId "permission-protocol" -Apply | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Unable to prepare immutable task material for the CodeBuddy permission fixture." }
    $preparedPlan = Get-Content -LiteralPath (Join-Path $planRoot "permission-protocol\plan.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    $codeChangeTask = @($preparedPlan.tasks | Where-Object { $_.task_id -eq "bounded-test-fix" })[0]
    $codeChangeMaterialJson = $codeChangeTask.task_material | ConvertTo-Json -Compress -Depth 12
    Assert-True (-not [string]::IsNullOrWhiteSpace($codeChangeMaterialJson)) "Permission fixture did not prepare immutable code-change material."
    $codeChangeMaterialPath = Join-Path $scratch "code-change-task-material.json"
    Set-Content -LiteralPath $codeChangeMaterialPath -Value $codeChangeMaterialJson -Encoding UTF8

    Invoke-ProtocolFixture -Mode "readonly" -TaskKind "local_audit" -ExpectedTools "Read,Glob,Grep"
    Invoke-ProtocolFixture -Mode "readonly" -TaskKind "test_execution" -ExpectedTools "Read,Glob,Grep,Bash"
    Invoke-ProtocolFixture -Mode "edit" -TaskKind "code_change" -ExpectedTools "Read,Glob,Grep,Edit,Write,Bash" -WorktreeName "permission-protocol" -AllowNetwork
    Write-Host "[PASS] CodeBuddy permission fault-injection regression rejects the historical dontAsk protocol and accepts the supported headless allowlists without acquiring a Git worktree lock."
} finally {
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}
