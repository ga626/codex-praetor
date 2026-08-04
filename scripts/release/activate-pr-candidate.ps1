param(
    [Parameter(Mandatory = $true)][int]$PullRequestNumber,
    [Parameter(Mandatory = $true)][string]$Version,
    [string]$Repository = "ga626/codex-praetor",
    [string]$UserProfileRoot = $env:USERPROFILE,
    [string]$CodexCommand = "codex",
    [string]$DownloadRoot = "",
    [switch]$SkipMaintenance,
    [switch]$Json
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
foreach ($command in @("gh", "git")) { if (-not (Get-Command $command -ErrorAction SilentlyContinue)) { throw "Required command is missing: $command" } }
$pr = & gh api "repos/$Repository/pulls/$PullRequestNumber" | ConvertFrom-Json
$head = ([string]$pr.head.sha).ToLowerInvariant()
if ($head -notmatch '^[0-9a-f]{40}$') { throw "Pull request does not expose a full head SHA." }
$artifactName = (& (Join-Path $root "scripts\release\get-release-candidate-artifact-name.ps1") -Version $Version -PullRequestNumber $PullRequestNumber -HeadSha $head | Out-String).Trim()
$artifactPage = & gh api "repos/$Repository/actions/artifacts?name=$artifactName&per_page=100" | ConvertFrom-Json
$artifact = @($artifactPage.artifacts | Where-Object { -not $_.expired }) | Sort-Object created_at -Descending | Select-Object -First 1
if ($null -eq $artifact) { throw "No retained candidate artifact exists for PR #$PullRequestNumber. Wait for PR CI to pass first." }
if ([string]::IsNullOrWhiteSpace($DownloadRoot)) { $DownloadRoot = Join-Path $UserProfileRoot ("plugins\.codex-praetor-candidates\" + $artifactName) }
$DownloadRoot = [IO.Path]::GetFullPath($DownloadRoot)
New-Item -ItemType Directory -Path $DownloadRoot -Force | Out-Null
& gh run download ([int64]$artifact.workflow_run.id) --repo $Repository --name $artifactName --dir $DownloadRoot
if ($LASTEXITCODE -ne 0) { throw "Unable to download verified candidate artifact from workflow run $($artifact.workflow_run.id)." }
$releaseName = "codex-praetor-setup-$Version"
$zip = Join-Path $DownloadRoot "$releaseName.zip"
$sha = Join-Path $DownloadRoot "$releaseName.zip.sha256"
$receipt = Join-Path $DownloadRoot "$releaseName.candidate.json"
foreach ($path in @($zip, $sha, $receipt)) { if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Downloaded candidate artifact is incomplete: $path" } }
$candidate = Get-Content -LiteralPath $receipt -Raw -Encoding UTF8 | ConvertFrom-Json
if ([int]$candidate.pull_request.number -ne $PullRequestNumber -or ([string]$candidate.pull_request.head_sha).ToLowerInvariant() -ne $head) { throw "Downloaded candidate receipt is not bound to PR #$PullRequestNumber at $head." }
$activation = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "scripts\release\activate-published-codex-praetor-release.ps1") -Version $Version -ReleaseZip $zip -ReleaseSha256 $sha -CandidateReceiptPath $receipt -UserProfileRoot $UserProfileRoot -CodexCommand $CodexCommand -SkipMaintenance:$SkipMaintenance -Json
if ($LASTEXITCODE -ne 0) { throw "Verified candidate activation failed." }
$payload = $activation | Out-String | ConvertFrom-Json
$payload | Add-Member -NotePropertyName candidate_artifact_directory -NotePropertyValue $DownloadRoot
$payload | Add-Member -NotePropertyName candidate_receipt_path -NotePropertyValue $receipt
$payload | Add-Member -NotePropertyName workflow_run_id -NotePropertyValue ([int64]$artifact.workflow_run.id)
if ($Json) { $payload | ConvertTo-Json -Depth 16 } else { Write-Host "Candidate activation status: $($payload.status)"; Write-Host "Next: $($payload.next_action)" }
