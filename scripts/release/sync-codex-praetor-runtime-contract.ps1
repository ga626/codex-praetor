param(
    [string]$ProjectRoot = "",
    [switch]$Apply
)

$ErrorActionPreference = "Stop"
. (Join-Path (Split-Path -Parent $PSScriptRoot) "shared\ensure-file-hash.ps1")
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
$runtimeData = @(
    [ordered]@{ source = "config\evaluation-suite.json"; target = "plugin\data\evaluation-suite.json" },
    [ordered]@{ source = "config\evaluation-task-templates"; target = "plugin\data\evaluation-task-templates" },
    [ordered]@{ source = "config\public-capabilities.json"; target = "plugin\data\public-capabilities.json" },
    [ordered]@{ source = "config\provider-onboarding-checklist.json"; target = "plugin\data\provider-onboarding-checklist.json" },
    [ordered]@{ source = "config\provider-adapters\qoder.json"; target = "plugin\data\provider-adapters\qoder.json" },
    [ordered]@{ source = "config\provider-adapters\codebuddy.json"; target = "plugin\data\provider-adapters\codebuddy.json" }
)

if (-not (Test-Path -LiteralPath $canonical -PathType Leaf)) {
    throw "Canonical runtime contract is missing: $canonical"
}

$canonicalJson = Get-Content -LiteralPath $canonical -Raw -Encoding UTF8 | ConvertFrom-Json
$canonicalBytes = [IO.File]::ReadAllBytes($canonical)
$canonicalHash = (Get-FileHash -LiteralPath $canonical -Algorithm SHA256).Hash.ToLowerInvariant()
$mismatches = New-Object System.Collections.Generic.List[string]

function Get-DataSurfaceHash {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { throw "Data surface is missing: $Path" }
    $root = (Resolve-Path -LiteralPath $Path).Path.TrimEnd('\\')
    $entries = foreach ($file in @(Get-ChildItem -LiteralPath $root -File -Recurse)) {
        $relative = $file.FullName.Substring($root.Length + 1).Replace('\\', '/')
        "$relative $((Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant())"
    }
    $text = (($entries | Sort-Object) -join "`n")
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text)))).Replace('-', '').ToLowerInvariant() } finally { $sha.Dispose() }
}

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

foreach ($item in $runtimeData) {
    $source = Join-Path $root ([string]$item.source)
    $target = Join-Path $root ([string]$item.target)
    if (-not (Test-Path -LiteralPath $source)) {
        $mismatches.Add("missing-source:$($item.source)")
        continue
    }
    if (-not (Test-Path -LiteralPath $target)) {
        $mismatches.Add("missing:$($item.target)")
        continue
    }
    if ((Test-Path -LiteralPath $source -PathType Leaf) -ne (Test-Path -LiteralPath $target -PathType Leaf)) {
        $mismatches.Add("type-drift:$($item.target)")
        continue
    }
    if ((Get-DataSurfaceHash -Path $source) -ne (Get-DataSurfaceHash -Path $target)) {
        $mismatches.Add("drift:$($item.target)")
    }
}

if ($Apply) {
    foreach ($relative in $derived) {
        $path = Join-Path $root $relative
        $parent = Split-Path -Parent $path
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
        [IO.File]::WriteAllBytes($path, $canonicalBytes)
    }
    foreach ($item in $runtimeData) {
        $source = Join-Path $root ([string]$item.source)
        $target = Join-Path $root ([string]$item.target)
        if (Test-Path -LiteralPath $source -PathType Leaf) {
            $parent = Split-Path -Parent $target
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
            Copy-Item -LiteralPath $source -Destination $target -Force
        } else {
            New-Item -ItemType Directory -Path $target -Force | Out-Null
            Copy-Item -Path (Join-Path $source '*') -Destination $target -Recurse -Force
        }
    }
    Write-Host "[PASS] Generated $($derived.Count) runtime contract surfaces and $($runtimeData.Count) runtime data surfaces from config."
    exit 0
}

if ($mismatches.Count -gt 0) {
    throw "Runtime contract surfaces drift from the canonical source: $($mismatches -join '; '). Run sync-codex-praetor-runtime-contract.ps1 -Apply."
}
Write-Host "[PASS] All derived runtime contract and provider data surfaces equal the canonical source (SHA256=$canonicalHash)."
exit 0
