param(
    [string]$UserProfileRoot = $env:USERPROFILE,
    [ValidateSet("stable", "dev")][string]$Channel = "stable",
    [int]$RetentionDays = 14,
    [switch]$Apply,
    [switch]$Json
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir "codex-praetor-retirement.ps1")

function Resolve-FullPath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Assert-UnderRoot {
    param([string]$Path, [string[]]$Roots)
    $full = Resolve-FullPath $Path
    foreach ($root in $Roots) {
        $rootFull = (Resolve-FullPath $root).TrimEnd("\") + "\"
        if ($full.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

$profileRoot = Resolve-FullPath $UserProfileRoot
$codexRoot = Join-Path $profileRoot ".codex"
$receiptRoot = Join-Path $codexRoot "codex-praetor-releases\$Channel"
$retirementPath = Get-CodexPraetorRetirementPath -UserProfileRoot $profileRoot -Channel $Channel
$activeReceiptPath = Join-Path $receiptRoot "active.json"
$cacheRoot = Join-Path $codexRoot "plugins\cache\personal\codex-praetor"
$pluginParent = Join-Path $profileRoot "plugins"
$pluginBackupRoot = Join-Path $pluginParent ".codex-praetor-backups"
$skillBackupRoot = Join-Path $codexRoot "codex-praetor-backups\skills"
$cacheBackupRoot = Join-Path $cacheRoot ".backups"
$allowedRoots = @($cacheRoot, $pluginBackupRoot, $skillBackupRoot, $pluginParent)
$protected = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
$activeReceipt = $null

if (Test-Path -LiteralPath $activeReceiptPath -PathType Leaf) {
    try { $activeReceipt = Get-Content -LiteralPath $activeReceiptPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $activeReceipt = $null }
}
if ($null -ne $activeReceipt -and [string]$activeReceipt.status -eq "active") {
    foreach ($surface in @("skill", "plugin", "cache")) {
        $surfacePath = [string]$activeReceipt.surfaces.$surface.path
        if (-not [string]::IsNullOrWhiteSpace($surfacePath)) { $null = $protected.Add((Resolve-FullPath $surfacePath)) }
    }
}

$state = Read-CodexPraetorRetirementState -Path $retirementPath -Channel $Channel
$discovered = New-Object 'System.Collections.Generic.List[object]'

function Add-CandidateDirectory {
    param(
        [string]$Root,
        [string]$Kind,
        [string[]]$NamePatterns = @()
    )
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { return }
    foreach ($item in @(Get-ChildItem -LiteralPath $Root -Directory -Force)) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
        if ($Root -ieq $cacheRoot -and $item.Name -eq ".backups") { continue }
        if (@($NamePatterns).Count -gt 0 -and -not (@($NamePatterns | Where-Object { $item.Name -like $_ }).Count -gt 0)) { continue }
        $path = Resolve-FullPath $item.FullName
        if ($protected.Contains($path)) { continue }
        if (Assert-UnderRoot -Path $path -Roots $allowedRoots) {
            $discovered.Add([pscustomobject]@{ path = $path; kind = $Kind })
        }
    }
}

Add-CandidateDirectory -Root $cacheRoot -Kind "cache_generation"
Add-CandidateDirectory -Root $cacheBackupRoot -Kind "cache_backup"
Add-CandidateDirectory -Root $pluginBackupRoot -Kind "plugin_backup"
Add-CandidateDirectory -Root $skillBackupRoot -Kind "skill_backup"
Add-CandidateDirectory -Root $pluginParent -Kind "plugin_scratch" -NamePatterns @(".codex-praetor.publish-*.tmp", "codex-praetor.failed-*")

foreach ($candidate in $discovered) {
    $null = Add-CodexPraetorRetirementEntry -State $state -Path $candidate.path -Kind $candidate.kind
}

$now = [DateTimeOffset]::UtcNow
$cutoff = $now.AddDays(-1 * [Math]::Max(0, $RetentionDays))
$results = New-Object System.Collections.Generic.List[object]
$hasActiveReceipt = $null -ne $activeReceipt -and [string]$activeReceipt.status -eq "active"

foreach ($entry in @($state.entries)) {
    $path = [string]$entry.path
    $result = [ordered]@{ path = $path; status = [string]$entry.status; action = "kept"; error = "" }
    if (-not (Assert-UnderRoot -Path $path -Roots $allowedRoots)) {
        $entry.status = "failed_manual_review"
        $entry.last_error = "Path is outside approved retirement roots."
        $result.status = $entry.status
        $result.error = $entry.last_error
        $results.Add([pscustomobject]$result)
        continue
    }
    if (-not (Test-Path -LiteralPath $path)) {
        $entry.status = "deleted"
        $entry.last_error = ""
        $result.status = $entry.status
        $result.action = "already_absent"
        $results.Add([pscustomobject]$result)
        continue
    }
    if ($protected.Contains((Resolve-FullPath $path))) {
        $entry.status = "protected_active"
        $result.status = $entry.status
        $results.Add([pscustomobject]$result)
        continue
    }
    if (-not $hasActiveReceipt) {
        $entry.status = "deferred_no_active_receipt"
        $result.status = $entry.status
        $results.Add([pscustomobject]$result)
        continue
    }

    $item = Get-Item -LiteralPath $path -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        $entry.status = "failed_manual_review"
        $entry.last_error = "Retirement path is a reparse point; refusing to follow it."
        $result.status = $entry.status
        $result.error = $entry.last_error
        $results.Add([pscustomobject]$result)
        continue
    }
    if ($item.LastWriteTimeUtc -gt $cutoff.UtcDateTime) {
        $entry.status = "deferred_retention"
        $result.status = $entry.status
        $results.Add([pscustomobject]$result)
        continue
    }
    if (-not $Apply) {
        $entry.status = "pending"
        $result.status = $entry.status
        $result.action = "would_delete"
        $results.Add([pscustomobject]$result)
        continue
    }

    $entry.last_attempt_at = $now.ToString("o")
    $entry.attempts = [int]$entry.attempts + 1
    try {
        Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
        $entry.status = "deleted"
        $entry.last_error = ""
        $entry.next_attempt_at = ""
        $result.status = $entry.status
        $result.action = "deleted"
    } catch {
        $entry.status = "blocked_by_process"
        $entry.last_error = $_.Exception.Message
        $entry.next_attempt_at = $now.AddMinutes(15).ToString("o")
        $result.status = $entry.status
        $result.error = $entry.last_error
    }
    $results.Add([pscustomobject]$result)
}

if ($Apply) {
    Write-CodexPraetorRetirementState -Path $retirementPath -State $state
}

$summary = [pscustomobject]@{
    schema = "codex-praetor-generation-retirement-result/v1"
    channel = $Channel
    applied = [bool]$Apply
    active_receipt = $activeReceiptPath
    retirement_manifest = $retirementPath
    counts = [pscustomobject]@{
        discovered = $discovered.Count
        total = @($state.entries).Count
        deleted = @($state.entries | Where-Object { $_.status -eq "deleted" }).Count
        blocked = @($state.entries | Where-Object { $_.status -eq "blocked_by_process" }).Count
        deferred = @($state.entries | Where-Object { $_.status -like "deferred_*" }).Count
    }
    results = $results.ToArray()
}
if ($Json) {
    $summary | ConvertTo-Json -Depth 12
} else {
    Write-Host "Codex Praetor generation retirement reconcile"
    Write-Host "Channel: $Channel"
    Write-Host "Mode: $(if ($Apply) { 'apply' } else { 'dry-run' })"
    Write-Host "Manifest: $retirementPath"
    Write-Host "Discovered: $($summary.counts.discovered); total: $($summary.counts.total); deleted: $($summary.counts.deleted); blocked: $($summary.counts.blocked); deferred: $($summary.counts.deferred)"
    foreach ($item in $results) {
        Write-Host "[$($item.status)] $($item.action) $($item.path)"
        if (-not [string]::IsNullOrWhiteSpace([string]$item.error)) { Write-Host "  $($item.error)" }
    }
}
