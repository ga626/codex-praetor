param(
    [Parameter(Mandatory = $true)][string]$Repository,
    [Parameter(Mandatory = $true)][string]$MainCommit,
    [Parameter(Mandatory = $true)][string]$Version,
    [string]$OutputRoot = ".codex-praetor\releases\promoted",
    [string]$ProjectRoot = ""
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
if ($MainCommit -notmatch "^[0-9a-fA-F]{40}$") { throw "Promotion requires the full main commit SHA." }
foreach ($command in @("gh", "git")) { if (-not (Get-Command $command -ErrorAction SilentlyContinue)) { throw "Required command is missing: $command" } }

$pulls = ((& gh api "repos/$Repository/commits/$MainCommit/pulls" | ConvertFrom-Json) | Where-Object { $_.merged_at -and $_.base.ref -eq "main" })
if (@($pulls).Count -ne 1) { throw "Unable to identify exactly one merged PR for main commit $MainCommit." }
$pr = @($pulls)[0]
$headSha = [string]$pr.head.sha
if ($headSha -notmatch "^[0-9a-f]{40}$") { throw "Merged PR does not expose a full head SHA." }
$releaseName = "codex-praetor-setup-$Version"
$artifactName = (& (Join-Path $ProjectRoot "scripts\release\get-release-candidate-artifact-name.ps1") -Version $Version -PullRequestNumber ([int]$pr.number) -HeadSha $headSha | Out-String).Trim()
if ([string]::IsNullOrWhiteSpace($artifactName)) { throw "Candidate artifact name helper returned no name." }
$artifactPage = & gh api "repos/$Repository/actions/artifacts?name=$artifactName&per_page=100" | ConvertFrom-Json
$artifact = @($artifactPage.artifacts | Where-Object { -not $_.expired }) | Sort-Object created_at -Descending | Select-Object -First 1
if ($null -eq $artifact) { throw "No retained candidate artifact named $artifactName exists for merged PR #$($pr.number)." }

$output = [IO.Path]::GetFullPath((Join-Path $ProjectRoot $OutputRoot))
$download = Join-Path ([IO.Path]::GetTempPath()) ("codex-praetor-promotion-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $output -Force | Out-Null
New-Item -ItemType Directory -Path $download -Force | Out-Null
try {
    & gh run download ([int64]$artifact.workflow_run.id) --repo $Repository --name $artifactName --dir $download
    if ($LASTEXITCODE -ne 0) { throw "Unable to download candidate artifact from workflow run $($artifact.workflow_run.id)." }
    $zipSource = Join-Path $download "$releaseName.zip"
    $shaSource = Join-Path $download "$releaseName.zip.sha256"
    $manifestSource = Join-Path $download "$releaseName.artifact.json"
    $receiptSource = Join-Path $download "$releaseName.candidate.json"
    foreach ($path in @($zipSource, $shaSource, $manifestSource, $receiptSource)) { if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Candidate artifact is incomplete: $path" } }
    $receipt = Get-Content -LiteralPath $receiptSource -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([int]$receipt.pull_request.number -ne [int]$pr.number -or [string]$receipt.pull_request.head_sha -ne $headSha) { throw "Candidate receipt does not belong to merged PR #$($pr.number)." }
    $mainTree = ((& git -C $ProjectRoot rev-parse "$MainCommit^{tree}" 2>$null) | Out-String).Trim().ToLowerInvariant()
    if ($mainTree -notmatch "^[0-9a-f]{40}$" -or [string]$receipt.candidate.content_tree -ne $mainTree) { throw "Merged main content tree does not equal the verified candidate content tree." }
    $zipTarget = Join-Path $output "$releaseName.zip"
    $shaTarget = Join-Path $output "$releaseName.zip.sha256"
    $manifestTarget = Join-Path $output "$releaseName.artifact.json"
    $receiptTarget = Join-Path $output "$releaseName.candidate.json"
    Copy-Item -LiteralPath $zipSource -Destination $zipTarget -Force
    Copy-Item -LiteralPath $shaSource -Destination $shaTarget -Force
    Copy-Item -LiteralPath $receiptSource -Destination $receiptTarget -Force
    $manifest = Get-Content -LiteralPath $manifestSource -Raw -Encoding UTF8 | ConvertFrom-Json
    $hash = (Get-FileHash -LiteralPath $zipTarget -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($hash -ne [string]$receipt.artifact.zip_sha256 -or $hash -ne [string]$manifest.artifact.sha256) { throw "Promoted ZIP digest does not equal the verified candidate digest." }
    $manifest.artifact.path = $zipTarget
    [IO.File]::WriteAllText($manifestTarget, (($manifest | ConvertTo-Json -Depth 16) + [Environment]::NewLine), (New-Object Text.UTF8Encoding($false)))
    Write-Host "[PASS] Promoted verified candidate artifact: $zipTarget"
    Write-Host "[PASS] Candidate PR: #$($pr.number); workflow run: $($artifact.workflow_run.id); SHA256: $hash"
} finally {
    if (Test-Path -LiteralPath $download) { Remove-Item -LiteralPath $download -Recurse -Force -ErrorAction SilentlyContinue }
}
