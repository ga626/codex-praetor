param(
    [Parameter(Mandatory = $true)][string]$CandidateReceiptPath,
    [Parameter(Mandatory = $true)][string]$HostRuntimeInfoPath,
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
if ([string]::IsNullOrWhiteSpace($OutputPath)) { $OutputPath = Join-Path $ProjectRoot ".codex-praetor\receipts\candidate-host-$PullRequestNumber.json" }
$OutputPath = [IO.Path]::GetFullPath($OutputPath)
foreach ($path in @($CandidateReceiptPath, $HostRuntimeInfoPath)) { if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required evidence is missing: $path" } }

$candidate = Get-Content -LiteralPath $CandidateReceiptPath -Raw -Encoding UTF8 | ConvertFrom-Json
$runtimeEnvelope = Get-Content -LiteralPath $HostRuntimeInfoPath -Raw -Encoding UTF8 | ConvertFrom-Json
$runtime = if ($null -ne $runtimeEnvelope.runtime_identity) { $runtimeEnvelope.runtime_identity } elseif ($null -ne $runtimeEnvelope.result -and $null -ne $runtimeEnvelope.result.runtime_identity) { $runtimeEnvelope.result.runtime_identity } else { throw "runtime_info evidence has no runtime_identity." }
if ([string]$candidate.schema -ne "codex-praetor-release-candidate/v1" -or [string]$candidate.status -ne "artifact_verified") { throw "Candidate receipt is not an artifact_verified v1 receipt." }
if ([int]$candidate.pull_request.number -ne $PullRequestNumber) { throw "Candidate receipt belongs to a different PR." }
foreach ($value in @([string]$candidate.pull_request.head_sha, [string]$candidate.candidate.content_tree, [string]$candidate.artifact.zip_sha256, [string]$candidate.generation.runtime_contract_sha256)) { if ($value -notmatch '^[0-9a-fA-F]{40,64}$') { throw "Candidate receipt contains malformed identity evidence." } }
if ([string]$runtime.version -ne [string]$candidate.candidate.version) { throw "Desktop runtime version does not match the candidate generation." }
if ([string]$runtime.generation_id -ne [string]$candidate.generation.id) { throw "Desktop runtime generation does not match the candidate." }
if (([string]$runtime.runtime_contract_sha256).ToLowerInvariant() -ne ([string]$candidate.generation.runtime_contract_sha256).ToLowerInvariant()) { throw "Desktop runtime contract does not match the candidate." }

$receipt = [ordered]@{
    schema = "codex-praetor-candidate-host-receipt/v1"
    status = "accepted"
    pull_request = [ordered]@{ number = $PullRequestNumber; head_sha = ([string]$candidate.pull_request.head_sha).ToLowerInvariant() }
    candidate = [ordered]@{ version = [string]$candidate.candidate.version; content_tree = ([string]$candidate.candidate.content_tree).ToLowerInvariant(); generation_id = [string]$candidate.generation.id; runtime_contract_sha256 = ([string]$candidate.generation.runtime_contract_sha256).ToLowerInvariant() }
    artifact = [ordered]@{ zip_sha256 = ([string]$candidate.artifact.zip_sha256).ToLowerInvariant(); candidate_receipt_sha256 = (Get-FileHash -LiteralPath $CandidateReceiptPath -Algorithm SHA256).Hash.ToLowerInvariant() }
    host_runtime = [ordered]@{ version = [string]$runtime.version; generation_id = [string]$runtime.generation_id; runtime_contract_sha256 = ([string]$runtime.runtime_contract_sha256).ToLowerInvariant(); source_sha256 = (Get-FileHash -LiteralPath $HostRuntimeInfoPath -Algorithm SHA256).Hash.ToLowerInvariant() }
    checks = @($Checks | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    accepted_at = [DateTime]::UtcNow.ToString("o")
}
New-Item -ItemType Directory -Path (Split-Path -Parent $OutputPath) -Force | Out-Null
[IO.File]::WriteAllText($OutputPath, (($receipt | ConvertTo-Json -Depth 10) + [Environment]::NewLine), (New-Object Text.UTF8Encoding($false)))
Write-Host "[PASS] Candidate host receipt created: $OutputPath"
