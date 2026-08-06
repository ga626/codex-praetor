param(
    [Parameter(Mandatory = $true)][string]$Version,
    [Parameter(Mandatory = $true)][int]$PullRequestNumber,
    [Parameter(Mandatory = $true)][string]$HeadSha,
    [Parameter(Mandatory = $true)][string]$BaseSha,
    [string]$OutputRoot = ".codex-praetor\releases",
    [string]$ProjectRoot = ""
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
$output = [IO.Path]::GetFullPath((Join-Path $ProjectRoot $OutputRoot))
$releaseName = "codex-praetor-setup-$Version"
$manifestPath = Join-Path $output "$releaseName.artifact.json"
$zipPath = Join-Path $output "$releaseName.zip"
$receiptPath = Join-Path $output "$releaseName.candidate.json"

foreach ($value in @($HeadSha, $BaseSha)) {
    if ($value -notmatch "^[0-9a-fA-F]{40}$") { throw "Candidate receipt requires full commit SHAs." }
}
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "Verified artifact manifest is missing: $manifestPath" }
if (-not (Test-Path -LiteralPath $zipPath -PathType Leaf)) { throw "Verified candidate zip is missing: $zipPath" }

$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$manifest.status -ne "artifact_verified" -or [string]$manifest.verification.status -ne "passed") { throw "Candidate artifact is not verified." }
$zipHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($zipHash -ne [string]$manifest.artifact.sha256) { throw "Candidate zip hash differs from artifact manifest." }
$head = ((& git -C $ProjectRoot rev-parse HEAD 2>$null) | Out-String).Trim().ToLowerInvariant()
$tree = ((& git -C $ProjectRoot rev-parse "HEAD^{tree}" 2>$null) | Out-String).Trim().ToLowerInvariant()
if ($head -notmatch "^[0-9a-f]{40}$" -or $tree -notmatch "^[0-9a-f]{40}$") { throw "Candidate checkout does not expose a commit and content tree." }
if ($HeadSha.ToLowerInvariant() -ne $head) { throw "Candidate receipt PR head does not match the checked-out commit." }
if ([string]$manifest.generation.commit -ne $head -or [string]$manifest.generation.source_tree -ne $tree) { throw "Artifact generation is not bound to this candidate checkout." }

$receipt = [ordered]@{
    schema = "codex-praetor-release-candidate/v1"
    status = "artifact_verified"
    pull_request = [ordered]@{ number = $PullRequestNumber; head_sha = $HeadSha.ToLowerInvariant(); base_sha = $BaseSha.ToLowerInvariant() }
    candidate = [ordered]@{ version = $Version; checkout_commit = $head; content_tree = $tree }
    artifact = [ordered]@{ name = $releaseName; zip_sha256 = $zipHash; manifest_sha256 = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant() }
    generation = [ordered]@{ id = [string]$manifest.generation.id; commit = [string]$manifest.generation.commit; source_tree = [string]$manifest.generation.source_tree; runtime_contract_sha256 = [string]$manifest.generation.runtime_contract_sha256; content_manifest_sha256 = [string]$manifest.generation.content_manifest_sha256 }
    created_at = [DateTime]::UtcNow.ToString("o")
}
[IO.File]::WriteAllText($receiptPath, (($receipt | ConvertTo-Json -Depth 12) + [Environment]::NewLine), (New-Object Text.UTF8Encoding($false)))
Write-Host "[PASS] Release candidate receipt created: $receiptPath"
