param(
    [string]$ProjectRoot = ""
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $ProjectRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
}

$projectPath = [System.IO.Path]::GetFullPath($ProjectRoot)
$closeoutScript = Join-Path $projectPath "scripts\release\complete-codex-praetor-release.ps1"
$generationScript = Join-Path $projectPath "scripts\release\get-codex-praetor-generation.ps1"
if (-not (Test-Path -LiteralPath $closeoutScript -PathType Leaf)) { throw "Closeout script is missing: $closeoutScript" }

$testRoot = Join-Path $projectPath (".codex-praetor\dev-isolation-" + [Guid]::NewGuid().ToString("N"))
$profileRoot = Join-Path $testRoot "profile"
$stableRoot = Join-Path $testRoot "stable-sentinel"
try {
    New-Item -ItemType Directory -Path $stableRoot -Force | Out-Null
    $generation = (& $generationScript -ProjectRoot $projectPath -Json | ConvertFrom-Json)
    & $closeoutScript -Phase stage -Channel dev -ProjectRoot $projectPath -UserProfileRoot $profileRoot -Apply
    if ($LASTEXITCODE -ne 0) { throw "Dev stage failed." }

    $devReceiptRoot = Join-Path $profileRoot ".codex\codex-praetor-releases\dev"
    $devReceiptPath = Join-Path $devReceiptRoot "receipts\$($generation.generation_id).json"
    $stableReceiptPath = Join-Path $profileRoot ".codex\codex-praetor-releases\stable\active.json"
    if (-not (Test-Path -LiteralPath $devReceiptPath -PathType Leaf)) { throw "Dev stage did not write a dev receipt." }
    if (Test-Path -LiteralPath $stableReceiptPath -PathType Leaf) { throw "Dev stage must not write a stable active receipt." }

    $devReceipt = Get-Content -LiteralPath $devReceiptPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$devReceipt.channel -ne "dev" -or [string]$devReceipt.status -ne "staged") { throw "Dev receipt has an invalid channel or status." }
    if ([string]$devReceipt.delivery.state -ne "awaiting_host_refresh") { throw "Dev receipt must wait for host refresh." }
    if ([System.IO.Path]::GetFullPath($profileRoot) -eq [System.IO.Path]::GetFullPath($env:USERPROFILE)) { throw "Dev validation profile must be isolated from the stable user profile." }

    Write-Host "[PASS] Dev channel stages into an isolated profile without creating a stable active receipt."
} finally {
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
