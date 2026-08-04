param(
    [Parameter(Mandatory = $true)][int]$PullRequestNumber,
    [Parameter(Mandatory = $true)][string]$ReceiptPath,
    [string]$Repository = "ga626/codex-praetor"
)

$ErrorActionPreference = "Stop"
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw "gh is required to attach candidate host evidence to the release PR." }
$ReceiptPath = [IO.Path]::GetFullPath($ReceiptPath)
if (-not (Test-Path -LiteralPath $ReceiptPath -PathType Leaf)) { throw "Candidate host receipt is missing: $ReceiptPath" }
$receipt = Get-Content -LiteralPath $ReceiptPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$receipt.schema -ne "codex-praetor-candidate-host-receipt/v1" -or [string]$receipt.status -ne "accepted" -or [int]$receipt.pull_request.number -ne $PullRequestNumber) { throw "Receipt is not an accepted candidate host receipt for this PR." }
$body = (& gh pr view $PullRequestNumber --repo $Repository --json body --jq .body | Out-String).TrimEnd()
$marker = "<!-- codex-praetor-candidate-host-receipt -->"
$block = $marker + [Environment]::NewLine + '```json' + [Environment]::NewLine + ((Get-Content -LiteralPath $ReceiptPath -Raw -Encoding UTF8).Trim()) + [Environment]::NewLine + '```'
$index = $body.IndexOf($marker, [StringComparison]::Ordinal)
if ($index -ge 0) {
    $tail = $body.Substring($index + $marker.Length)
    $match = [regex]::Match($tail, '(?s)^\s*```json\s*.*?\s*```')
    if ($match.Success -ne $true) { throw "Existing candidate host marker is malformed; refuse to overwrite it." }
    $body = $body.Substring(0, $index).TrimEnd() + [Environment]::NewLine + [Environment]::NewLine + $block + $tail.Substring($match.Length)
} else { $body = $body.TrimEnd() + [Environment]::NewLine + [Environment]::NewLine + $block + [Environment]::NewLine }
$temp = [IO.Path]::GetTempFileName()
try {
    [IO.File]::WriteAllText($temp, $body, (New-Object Text.UTF8Encoding($false)))
    & gh pr edit $PullRequestNumber --repo $Repository --body-file $temp
    if ($LASTEXITCODE -ne 0) { throw "Unable to attach the candidate host receipt to PR #$PullRequestNumber." }
    Write-Host "[PASS] Candidate host receipt attached to PR #$PullRequestNumber."
} finally { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
