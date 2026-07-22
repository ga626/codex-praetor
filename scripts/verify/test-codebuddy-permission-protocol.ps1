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
        [string]$WorktreeName = ""
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
    if (-not [string]::IsNullOrWhiteSpace($WorktreeName)) {
        $arguments += @("-WorktreeName", $WorktreeName)
    }
    $output = & powershell.exe @arguments
    $exitCode = $LASTEXITCODE
    Assert-True ($exitCode -eq 0) "CodeBuddy $Mode permission fixture failed with exit code $exitCode."
    $commandLine = @($output | Where-Object { [string]$_ -like "command=*" } | Select-Object -Last 1)
    Assert-True ($commandLine.Count -eq 1) "CodeBuddy $Mode fixture did not emit its command contract."
    $command = [string]$commandLine[0]
    Assert-True ($command -match "(?:^|\s)-y(?:\s|$)") "CodeBuddy $Mode command is missing the supported headless approval flag."
    Assert-True ($command -match [regex]::Escape("--tools $ExpectedTools")) "CodeBuddy $Mode command did not receive the expected tool allowlist."
    Assert-True ($command -notmatch "--permission-mode|--allowedTools|--disallowedTools|dontAsk") "CodeBuddy $Mode command regressed to the historical unsupported permission protocol."
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

    Invoke-ProtocolFixture -Mode "readonly" -TaskKind "local_audit" -ExpectedTools "Read,Glob,Grep"
    Invoke-ProtocolFixture -Mode "edit" -TaskKind "code_change" -ExpectedTools "Read,Glob,Grep,Edit,Write,Bash" -WorktreeName "permission-protocol"
    Write-Host "[PASS] CodeBuddy permission fault-injection regression rejects the historical dontAsk protocol and accepts the supported headless allowlists without acquiring a Git worktree lock."
} finally {
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}
