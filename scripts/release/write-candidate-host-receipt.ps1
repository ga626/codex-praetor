param(
    [Parameter(Mandatory = $true)][string]$CandidateReceiptPath,
    [Parameter(Mandatory = $true)][string]$HostRuntimeInfoPath,
    [Parameter(Mandatory = $true)][string]$UserPathEvidencePath,
    [Parameter(Mandatory = $true)][int]$PullRequestNumber,
    [string[]]$Checks = @("runtime_info"),
    [string]$OutputPath = "",
    [string]$ProjectRoot = ""
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
$CandidateReceiptPath = [IO.Path]::GetFullPath($CandidateReceiptPath)
$HostRuntimeInfoPath = [IO.Path]::GetFullPath($HostRuntimeInfoPath)
$UserPathEvidencePath = [IO.Path]::GetFullPath($UserPathEvidencePath)
if ([string]::IsNullOrWhiteSpace($OutputPath)) { $OutputPath = Join-Path $ProjectRoot ".codex-praetor\receipts\candidate-host-$PullRequestNumber.json" }
$OutputPath = [IO.Path]::GetFullPath($OutputPath)
foreach ($path in @($CandidateReceiptPath, $HostRuntimeInfoPath, $UserPathEvidencePath)) { if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required evidence is missing: $path" } }

$candidate = Get-Content -LiteralPath $CandidateReceiptPath -Raw -Encoding UTF8 | ConvertFrom-Json
$runtimeEnvelope = Get-Content -LiteralPath $HostRuntimeInfoPath -Raw -Encoding UTF8 | ConvertFrom-Json
$userPath = Get-Content -LiteralPath $UserPathEvidencePath -Raw -Encoding UTF8 | ConvertFrom-Json
$runtime = if ($null -ne $runtimeEnvelope.runtime_identity) { $runtimeEnvelope.runtime_identity } elseif ($null -ne $runtimeEnvelope.result -and $null -ne $runtimeEnvelope.result.runtime_identity) { $runtimeEnvelope.result.runtime_identity } else { throw "runtime_info evidence has no runtime_identity." }
if ([string]$candidate.schema -ne "codex-praetor-release-candidate/v1" -or [string]$candidate.status -ne "artifact_verified") { throw "Candidate receipt is not an artifact_verified v1 receipt." }
if ([int]$candidate.pull_request.number -ne $PullRequestNumber) { throw "Candidate receipt belongs to a different PR." }
foreach ($value in @([string]$candidate.pull_request.head_sha, [string]$candidate.candidate.content_tree, [string]$candidate.artifact.zip_sha256, [string]$candidate.generation.runtime_contract_sha256)) { if ($value -notmatch '^[0-9a-fA-F]{40,64}$') { throw "Candidate receipt contains malformed identity evidence." } }
if ([string]$runtime.version -ne [string]$candidate.candidate.version) { throw "Desktop runtime version does not match the candidate generation." }
if ([string]$runtime.generation_id -ne [string]$candidate.generation.id) { throw "Desktop runtime generation does not match the candidate." }
if (([string]$runtime.runtime_contract_sha256).ToLowerInvariant() -ne ([string]$candidate.generation.runtime_contract_sha256).ToLowerInvariant()) { throw "Desktop runtime contract does not match the candidate." }
if ([string]$userPath.schema -ne "codex-praetor-candidate-user-path-evidence/v1" -or [string]$userPath.status -ne "accepted") { throw "User path evidence is not accepted." }
if ([string]$userPath.candidate.version -ne [string]$candidate.candidate.version -or ([string]$userPath.candidate.pull_request_head).ToLowerInvariant() -ne ([string]$candidate.pull_request.head_sha).ToLowerInvariant() -or ([string]$userPath.candidate.artifact_sha256).ToLowerInvariant() -ne ([string]$candidate.artifact.zip_sha256).ToLowerInvariant() -or [string]$userPath.candidate.generation_id -ne [string]$candidate.generation.id) { throw "User path evidence is not bound to this exact candidate." }
if ([string]$userPath.host_runtime.generation_id -ne [string]$runtime.generation_id -or ([string]$userPath.host_runtime.runtime_contract_sha256).ToLowerInvariant() -ne ([string]$runtime.runtime_contract_sha256).ToLowerInvariant()) { throw "User path evidence is not bound to the observed host runtime." }
if ([string]$userPath.entry.kind -ne "new_task_execution_mode" -or [string]::IsNullOrWhiteSpace([string]$userPath.entry.skill_sha256)) { throw "User path evidence does not identify the execution-mode Skill entry." }
if ([string]$userPath.route.result -ne "delegated_code_change" -or [string]$userPath.preflight.kind -ne "real_code_change" -or $userPath.preflight.worker_started -ne $false) { throw "User path evidence does not prove route and non-starting code-change preflight." }
if ([string]$userPath.dispatch.job_id -eq "" -or $userPath.dispatch.worker_started -ne $true -or [string]::IsNullOrWhiteSpace([string]$userPath.dispatch.execution_worktree)) { throw "User path evidence does not prove actual worker startup." }
if ([string]$userPath.completion.status -ne "process_exited" -or [int]$userPath.completion.exit_code -ne 0 -or [string]$userPath.acceptance.verdict -ne "accepted" -or [string]$userPath.acceptance.governance_state -ne "accepted" -or $userPath.acceptance.required_checks_passed -ne $true) { throw "User path evidence does not prove completion and Codex acceptance." }

$receipt = [ordered]@{
    schema = "codex-praetor-candidate-host-receipt/v2"
    status = "accepted"
    pull_request = [ordered]@{ number = $PullRequestNumber; head_sha = ([string]$candidate.pull_request.head_sha).ToLowerInvariant() }
    candidate = [ordered]@{ version = [string]$candidate.candidate.version; content_tree = ([string]$candidate.candidate.content_tree).ToLowerInvariant(); generation_id = [string]$candidate.generation.id; runtime_contract_sha256 = ([string]$candidate.generation.runtime_contract_sha256).ToLowerInvariant() }
    artifact = [ordered]@{ zip_sha256 = ([string]$candidate.artifact.zip_sha256).ToLowerInvariant(); candidate_receipt_sha256 = (Get-FileHash -LiteralPath $CandidateReceiptPath -Algorithm SHA256).Hash.ToLowerInvariant() }
    host_runtime = [ordered]@{ version = [string]$runtime.version; generation_id = [string]$runtime.generation_id; runtime_contract_sha256 = ([string]$runtime.runtime_contract_sha256).ToLowerInvariant(); source_sha256 = (Get-FileHash -LiteralPath $HostRuntimeInfoPath -Algorithm SHA256).Hash.ToLowerInvariant() }
    user_path = [ordered]@{ evidence_sha256 = (Get-FileHash -LiteralPath $UserPathEvidencePath -Algorithm SHA256).Hash.ToLowerInvariant(); entry = $userPath.entry; route = $userPath.route; preflight = $userPath.preflight; dispatch = $userPath.dispatch; completion = $userPath.completion; acceptance = $userPath.acceptance }
    checks = @($Checks | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    accepted_at = [DateTime]::UtcNow.ToString("o")
}
New-Item -ItemType Directory -Path (Split-Path -Parent $OutputPath) -Force | Out-Null
[IO.File]::WriteAllText($OutputPath, (($receipt | ConvertTo-Json -Depth 10) + [Environment]::NewLine), (New-Object Text.UTF8Encoding($false)))
Write-Host "[PASS] Candidate host receipt created: $OutputPath"
