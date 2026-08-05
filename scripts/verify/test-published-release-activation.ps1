param([string]$ProjectRoot = "")

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$root = [System.IO.Path]::GetFullPath($ProjectRoot)
$scratch = Join-Path $root (".codex-praetor\published-activation-" + [Guid]::NewGuid().ToString("N"))
$build = Join-Path $root "scripts\release\build-codex-praetor-release.ps1"
$generation = Join-Path $root "scripts\release\get-codex-praetor-generation.ps1"
$activation = Join-Path $root "scripts\release\activate-published-codex-praetor-release.ps1"
$candidateReceiptWriter = Join-Path $root "scripts\release\write-release-candidate-receipt.ps1"
$userPathEvidenceWriter = Join-Path $root "scripts\release\write-candidate-user-path-evidence.ps1"
$hostReceiptWriter = Join-Path $root "scripts\release\write-candidate-host-receipt.ps1"
$hostReceiptGate = Join-Path $root "scripts\verify\test-candidate-host-receipt.ps1"
$deferredRefresh = Join-Path $root "scripts\release\refresh-codex-praetor-plugin-cache-after-exit.ps1"

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

try {
    New-Item -ItemType Directory -Path $scratch -Force | Out-Null
    $current = (& $generation -ProjectRoot $root -Json | ConvertFrom-Json)
    $version = [string]$current.version
    $releaseRoot = Join-Path $scratch "release"
    $releaseRootRelative = $releaseRoot.Substring($root.Length).TrimStart("\\")
    & powershell -NoProfile -ExecutionPolicy Bypass -File $build -Version $version -OutputRoot $releaseRootRelative -Apply
    if ($LASTEXITCODE -ne 0) { throw "Fixture release build failed." }
    $zip = Join-Path $releaseRoot "codex-praetor-setup-$version.zip"
    $sha = "$zip.sha256"
    $artifactManifest = Join-Path $releaseRoot "codex-praetor-setup-$version.artifact.json"
    $artifact = Get-Content -LiteralPath $artifactManifest -Raw -Encoding UTF8 | ConvertFrom-Json
    $artifact.status = "artifact_verified"
    $artifact.verification = [ordered]@{ status = "passed" }
    $artifact | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $artifactManifest -Encoding UTF8
    $head = ((& git -C $root rev-parse HEAD) | Out-String).Trim()
    $base = ((& git -C $root rev-parse HEAD^) | Out-String).Trim()
    & powershell -NoProfile -ExecutionPolicy Bypass -File $candidateReceiptWriter -Version $version -PullRequestNumber 123 -HeadSha $head -BaseSha $base -ProjectRoot $root -OutputRoot $releaseRootRelative
    if ($LASTEXITCODE -ne 0) { throw "Candidate receipt writing fixture failed." }
    $candidateReceipt = Join-Path $releaseRoot "codex-praetor-setup-$version.candidate.json"
    $writtenCandidateReceipt = Get-Content -LiteralPath $candidateReceipt -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ([string]$writtenCandidateReceipt.generation.runtime_contract_sha256 -eq [string]$artifact.generation.runtime_contract_sha256) "Candidate receipt must retain the artifact runtime contract identity for stable activation."
    $profile = Join-Path $scratch "profile"
    $expectedCodexHome = Join-Path $profile ".codex"
    $fakeCodex = Join-Path $scratch "fake-codex.cmd"
    @"
@echo off
if /I not "%USERPROFILE%"=="$profile" exit /b 17
if /I not "%HOME%"=="$profile" exit /b 18
if /I not "%CODEX_HOME%"=="$expectedCodexHome" exit /b 19
if not exist "%CODEX_HOME%\\" exit /b 20
if "%1"=="plugin" if "%2"=="add" exit /b 0
 if "%1"=="plugin" if "%2"=="list" (
   echo PLUGIN                            STATUS              VERSION                     PATH
   echo codex-praetor@personal            installed, enabled  $version                 C:\fixture\plugins\codex-praetor
 )
exit /b 0
"@ | Set-Content -LiteralPath $fakeCodex -Encoding ASCII
    $result = (& powershell -NoProfile -ExecutionPolicy Bypass -File $activation -Version $version -ReleaseZip $zip -ReleaseSha256 $sha -UserProfileRoot $profile -CodexCommand $fakeCodex -SkipMaintenance -Json | Out-String | ConvertFrom-Json)
    Assert-True ([string]$result.source_kind -eq "explicit_release_fixture") "Fixture activation must be labeled as a fixture, never as a published delivery proof."
    Assert-True ([string]$result.status -eq "needs_host_restart") "Verified installation must stop at the explicit host refresh boundary."
    Assert-True ([string]$result.generation.generation_id -eq [string]$current.generation_id) "Activated plugin must retain the exact bundled generation (expected=$($current.generation_id); actual=$($result.generation.generation_id))."
    Assert-True (Test-Path -LiteralPath (Join-Path $profile "plugins\codex-praetor\release-generation.json") -PathType Leaf) "Activation did not install the bundled plugin generation."
    $candidate = (& powershell -NoProfile -ExecutionPolicy Bypass -File $activation -Version $version -ReleaseZip $zip -ReleaseSha256 $sha -CandidateReceiptPath $candidateReceipt -UserProfileRoot $profile -CodexCommand $fakeCodex -SkipMaintenance -Json | Out-String | ConvertFrom-Json)
    Assert-True ([string]$candidate.source_kind -eq "verified_pr_candidate") "Candidate activation must remain distinguishable from a published Release."
    Assert-True ([string]$candidate.status -eq "needs_host_restart") "Candidate activation must stop before host evidence is claimed."
    $deferredState = Join-Path $scratch "deferred-refresh.json"
    & powershell -NoProfile -ExecutionPolicy Bypass -File $deferredRefresh -UserProfileRoot $profile -CodexCommand $fakeCodex -ExpectedVersion $version -StatusPath $deferredState -SkipHostExitWait
    if ($LASTEXITCODE -ne 0) { throw "Deferred plugin-cache refresh fixture failed." }
    $deferred = Get-Content -LiteralPath $deferredState -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ([string]$deferred.status -eq "completed") "Deferred plugin-cache refresh did not confirm the official plugin install."
    $lockedMarker = Join-Path $scratch "plugin-cache-lock-once.marker"
    $lockedCodex = Join-Path $scratch "fake-codex-cache-lock-once.cmd"
    @"
@echo off
if "%1"=="plugin" if "%2"=="add" (
  if exist "$lockedMarker" goto success
  type nul > "$lockedMarker"
  echo Error: failed to back up plugin cache entry: Access is denied. 1>&2
  exit /b 1
)
:success
if "%1"=="plugin" if "%2"=="list" (
  echo PLUGIN                            STATUS              VERSION                     PATH
  echo codex-praetor@personal            installed, enabled  $version                 C:\fixture\plugins\codex-praetor
)
exit /b 0
"@ | Set-Content -LiteralPath $lockedCodex -Encoding ASCII
    $deferredActivation = (& powershell -NoProfile -ExecutionPolicy Bypass -File $activation -Version $version -ReleaseZip $zip -ReleaseSha256 $sha -UserProfileRoot $profile -CodexCommand $lockedCodex -SkipMaintenance -DeferPluginCacheRefresh -DeferredCacheRefreshWaitSeconds 1 -Json | Out-String | ConvertFrom-Json)
    Assert-True ([string]$deferredActivation.status -eq "awaiting_host_exit") "A recognized plugin-cache lock must become awaiting_host_exit, not an activation exception."
    $deferredActivationState = [string]$deferredActivation.deferred_refresh_state
    $deadline = (Get-Date).AddSeconds(5)
    while ((-not (Test-Path -LiteralPath $deferredActivationState -PathType Leaf)) -and (Get-Date -lt $deadline)) { Start-Sleep -Milliseconds 250 }
    Assert-True (Test-Path -LiteralPath $deferredActivationState -PathType Leaf) "Deferred cache refresh did not write a result state."
    $deferredActivationResult = Get-Content -LiteralPath $deferredActivationState -Raw -Encoding UTF8 | ConvertFrom-Json
    $deferredStatus = [string]$deferredActivationResult.status
    $deferredReason = [string]$deferredActivationResult.reason
    Assert-True (($deferredStatus -eq "completed") -or ($deferredStatus -eq "timed_out" -and $deferredReason -eq "codex_desktop_still_running")) "Deferred cache refresh did not either complete without a host or correctly wait for the host to exit."
    $runtimeInfo = Join-Path $scratch "runtime-info.json"
    [ordered]@{ runtime_contract = [ordered]@{ version = $version }; runtime_identity = [ordered]@{ version = $version; generation_id = [string]$current.generation_id; runtime_contract_sha256 = [string]$current.runtime_contract_sha256 } } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $runtimeInfo -Encoding UTF8
    $executionRepo = Join-Path $scratch "execution-worktree"
    New-Item -ItemType Directory -Path $executionRepo -Force | Out-Null
    & git -C $executionRepo init | Out-Null
    & git -C $executionRepo config user.email "release-user-path-test@example.invalid"
    & git -C $executionRepo config user.name "Release User Path Test"
    Set-Content -LiteralPath (Join-Path $executionRepo "README.md") -Value "fixture" -Encoding ASCII
    & git -C $executionRepo add README.md
    & git -C $executionRepo commit -m "fixture" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "User-path fixture worktree commit failed." }
    $executionBase = ((& git -C $executionRepo rev-parse HEAD | Out-String).Trim()).ToLowerInvariant()
    $jobDir = Join-Path $scratch "user-path-job"
    New-Item -ItemType Directory -Path $jobDir -Force | Out-Null
    $jobId = "candidate-user-path-fixture"
    [ordered]@{ job_id = $jobId; task_kind = "code_change"; base_commit = $executionBase; execution_repo = $executionRepo; provider = "qoder"; model = "fixture-model"; connection_mode = "qoder_agent_sdk" } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $jobDir "job.json") -Encoding UTF8
    [ordered]@{ job_id = $jobId; task_kind = "code_change"; status = "process_exited"; exit_code = 0; failure_class = ""; base_commit = $executionBase; worktree_head = $executionBase } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $jobDir "completion.json") -Encoding UTF8
    $planPath = Join-Path $scratch "user-path-plan.json"
    [ordered]@{ tasks = @([ordered]@{ task_id = "candidate-code-change"; task_kind = "code_change"; mode = "edit"; status = "completed"; governance_state = "accepted"; verification_verdict = "accepted"; task_family = "bounded_code_change"; base_commit = $executionBase; immutable_paths = @("README.md"); completion_definition = [ordered]@{ required_checks = @("git diff --check") }; job_id = $jobId; job_dir = $jobDir; completion = (Join-Path $jobDir "completion.json") }) } | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $planPath -Encoding UTF8
    $userPathEvidence = Join-Path $scratch "candidate-user-path.json"
    & powershell -NoProfile -ExecutionPolicy Bypass -File $userPathEvidenceWriter -CandidateReceiptPath $candidateReceipt -HostRuntimeInfoPath $runtimeInfo -PlanPath $planPath -TaskId "candidate-code-change" -SkillPath (Join-Path $root "plugin\skills\codex-praetor\SKILL.md") -OutputPath $userPathEvidence
    if ($LASTEXITCODE -ne 0) { throw "Candidate user-path evidence writing failed." }
    $hostReceipt = Join-Path $scratch "candidate-host.json"
    & powershell -NoProfile -ExecutionPolicy Bypass -File $hostReceiptWriter -CandidateReceiptPath $candidateReceipt -HostRuntimeInfoPath $runtimeInfo -UserPathEvidencePath $userPathEvidence -PullRequestNumber 123 -OutputPath $hostReceipt -ProjectRoot $root
    if ($LASTEXITCODE -ne 0) { throw "Candidate host receipt writing failed." }
    & powershell -NoProfile -ExecutionPolicy Bypass -File $hostReceiptGate -ReceiptPath $hostReceipt -ArtifactManifestPath $artifactManifest -ProjectRoot $root
    if ($LASTEXITCODE -ne 0) { throw "Candidate host receipt acceptance gate failed." }
    Write-Host "[PASS] Published Release activation accepts the official table-shaped plugin list, installs the verified bundle, and stops at host refresh."
} finally {
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}
