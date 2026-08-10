param([string]$ProjectRoot = "")

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$paths = @(
    (Join-Path $ProjectRoot "scripts\dispatch\invoke-codex-praetor.ps1"),
    (Join-Path $ProjectRoot "plugin\skills\codex-praetor\scripts\invoke-codex-praetor.ps1"),
    (Join-Path $ProjectRoot "skill\codex-praetor\scripts\invoke-codex-praetor.ps1")
)
$hashes = @()
foreach ($path in $paths) {
    Assert-True (Test-Path -LiteralPath $path -PathType Leaf) "Qoder permission boundary script is missing: $path"
    $text = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    Assert-True ($text -match '\$allowedTools = if \(\$TaskKind -eq "test_execution"\)') "Qoder readonly dispatch must not grant Bash merely because a supervisor check exists: $path"
    Assert-True ($text -notmatch 'hasRequiredChecks|test_execution" -or \$hasRequiredChecks') "Qoder stream-json must not expose unrestricted Bash through required checks: $path"
    Assert-True ($text -match 'For readonly tasks where Bash is not in the declared tool list') "Readonly worker packet must delegate required checks to Codex: $path"
    $hashes += (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
}
Assert-True ((@($hashes | Select-Object -Unique)).Count -eq 1) "Source and both skill mirrors disagree on the Qoder permission boundary."
Write-Host "[PASS] Qoder stream-json readonly check boundary keeps Bash closed and assigns required checks to Codex."
