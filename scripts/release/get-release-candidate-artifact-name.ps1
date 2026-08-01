param(
    [Parameter(Mandatory = $true)][string]$Version,
    [Parameter(Mandatory = $true)][int]$PullRequestNumber,
    [Parameter(Mandatory = $true)][string]$HeadSha
)

$ErrorActionPreference = "Stop"
if ($Version -notmatch '^[0-9]+\.[0-9]+\.[0-9]+-[0-9A-Za-z.-]+$') { throw "Candidate artifact name requires a prerelease semantic version." }
if ($PullRequestNumber -lt 1) { throw "Candidate artifact name requires a positive pull request number." }
if ($HeadSha -notmatch '^[0-9a-fA-F]{40}$') { throw "Candidate artifact name requires a full head SHA." }

Write-Output ("codex-praetor-candidate-{0}-pr{1}-{2}" -f $Version, $PullRequestNumber, $HeadSha.ToLowerInvariant())
