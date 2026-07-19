param(
    [string]$ProjectRoot = "",
    [switch]$Apply
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}
$root = [IO.Path]::GetFullPath($ProjectRoot)
$canonical = Join-Path $root "config\runtime-contract.json"
$derived = @(
    "plugin\runtime-contract.json",
    "plugin\skills\codex-praetor\scripts\runtime-contract.json",
    "skill\codex-praetor\scripts\runtime-contract.json"
)

if (-not (Test-Path -LiteralPath $canonical -PathType Leaf)) {
    throw "Canonical runtime contract is missing: $canonical"
}

$canonicalJson = Get-Content -LiteralPath $canonical -Raw -Encoding UTF8 | ConvertFrom-Json
$canonicalBytes = [IO.File]::ReadAllBytes($canonical)
$canonicalHash = (Get-FileHash -LiteralPath $canonical -Algorithm SHA256).Hash.ToLowerInvariant()
$mismatches = New-Object System.Collections.Generic.List[string]

foreach ($relative in $derived) {
    $path = Join-Path $root $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $mismatches.Add("missing:$relative")
        continue
    }
    try {
        $payload = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        $actualTools = @($payload.requiredMcpTools | ForEach-Object { [string]$_ })
        $expectedTools = @($canonicalJson.requiredMcpTools | ForEach-Object { [string]$_ })
        $missing = @($expectedTools | Where-Object { $_ -notin $actualTools })
        $extra = @($actualTools | Where-Object { $_ -notin $expectedTools })
        if ([string]$payload.version -ne [string]$canonicalJson.version -or $missing.Count -gt 0 -or $extra.Count -gt 0 -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $canonicalHash) {
            $mismatches.Add("drift:$relative")
        }
    } catch {
        $mismatches.Add("invalid:$relative")
    }
}

if ($Apply) {
    foreach ($relative in $derived) {
        $path = Join-Path $root $relative
        $parent = Split-Path -Parent $path
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
        [IO.File]::WriteAllBytes($path, $canonicalBytes)
    }
    Write-Host "[PASS] Generated $($derived.Count) runtime contract surfaces from config/runtime-contract.json (SHA256=$canonicalHash)."
    exit 0
}

if ($mismatches.Count -gt 0) {
    throw "Runtime contract surfaces drift from the canonical source: $($mismatches -join '; '). Run sync-codex-praetor-runtime-contract.ps1 -Apply."
}
Write-Host "[PASS] All derived runtime contract surfaces equal the canonical source (SHA256=$canonicalHash)."
exit 0
