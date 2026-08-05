param(
    [string]$Repo = (Get-Location).Path,
    [string]$UserProfileRoot = $env:USERPROFILE,
    [ValidateSet("stable", "dev")][string]$Channel = "stable",
    [switch]$Json
)

$ErrorActionPreference = "Stop"
$profileRoot = [System.IO.Path]::GetFullPath($UserProfileRoot)
$codexRoot = Join-Path $profileRoot ".codex"
$releaseRoot = Join-Path $codexRoot "codex-praetor-releases\$Channel"
$artifactRoot = Join-Path $releaseRoot "artifacts"
$cacheRoot = Join-Path $codexRoot "plugins\cache\personal\codex-praetor"
$activePath = Join-Path $releaseRoot "active.json"
$retirementPath = Join-Path $releaseRoot "retirement.json"

function Read-JsonOrNull { param([string]$Path) if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }; try { return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null } }
function Add-InventoryItem { param([System.Collections.Generic.List[object]]$List, [string]$Category, [string]$Path, [string]$Identity, [string]$Reason, [bool]$Protected) $List.Add([pscustomobject]@{ category = $Category; path = $Path; identity = $Identity; reason = $Reason; protected = $Protected }) }

$items = New-Object 'System.Collections.Generic.List[object]'
$canonicalRepo = (Resolve-Path -LiteralPath $Repo).Path
try {
    $commonRaw = (& git -C $canonicalRepo rev-parse --git-common-dir 2>$null | Out-String).Trim().Replace('/', '\\')
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($commonRaw)) {
        $commonPath = if ($commonRaw -match '^[A-Za-z]:\\') { [IO.Path]::GetFullPath($commonRaw) } else { [IO.Path]::GetFullPath((Join-Path $canonicalRepo $commonRaw)) }
        if ((Split-Path -Leaf $commonPath) -eq '.git') { $canonicalRepo = Split-Path -Parent $commonPath }
    }
} catch { }
$managedWorktreeRoot = Join-Path $canonicalRepo '.codex\worktrees'
$legacyWorktreeRoot = Join-Path $canonicalRepo '.codex-praetor\worktrees'
$active = Read-JsonOrNull -Path $activePath
$activeGeneration = if ($null -ne $active) { [string]$active.generation.generation_id } else { "" }
$retired = @{}
$retirement = Read-JsonOrNull -Path $retirementPath
foreach ($entry in @($retirement.entries)) { if (-not [string]::IsNullOrWhiteSpace([string]$entry.generation_id)) { $retired[[string]$entry.generation_id] = [string]$entry.status } }

if (Test-Path -LiteralPath $artifactRoot -PathType Container) {
    foreach ($dir in @(Get-ChildItem -LiteralPath $artifactRoot -Directory -Force)) {
        $id = [string]$dir.Name
        if ($id -eq $activeGeneration) { Add-InventoryItem $items "active" $dir.FullName $id "active receipt 指向当前代际" $true }
        elseif ($retired.ContainsKey($id)) { Add-InventoryItem $items "retired" $dir.FullName $id "retirement manifest: $($retired[$id])" $true }
        else { Add-InventoryItem $items "audit-retained" $dir.FullName $id "未被 active/retirement 证明覆盖，默认保留" $true }
    }
}
if (Test-Path -LiteralPath $cacheRoot -PathType Container) {
    foreach ($dir in @(Get-ChildItem -LiteralPath $cacheRoot -Directory -Force)) {
        $category = if ($dir.Name.StartsWith(".")) { "test-scratch" } elseif ($dir.Name -eq [string]$active.generation.version) { "active" } elseif ($retired.ContainsKey($dir.Name)) { "retired" } else { "audit-retained" }
        Add-InventoryItem $items $category $dir.FullName $dir.Name "cache generation；inventory 只读" ($category -in @("active", "retired", "audit-retained"))
    }
}

try {
    # Do not use `git worktree list`: a repository may retain hundreds of
    # unrelated historical checkout registrations. The product owns only the
    # fixed project-local root below, so inspect that one bounded directory.
    if (Test-Path -LiteralPath $managedWorktreeRoot -PathType Container) {
        foreach ($dir in @(Get-ChildItem -LiteralPath $managedWorktreeRoot -Directory -Force)) {
            $status = (& git -C $dir.FullName status --porcelain 2>$null | Out-String).Trim()
            $branch = (& git -C $dir.FullName branch --show-current 2>$null | Out-String).Trim()
            if ([string]::IsNullOrWhiteSpace($branch)) { Add-InventoryItem $items "audit-retained" $dir.FullName "" "managed worktree detached；不自动回收" $true }
            else {
                & git -C $canonicalRepo merge-base --is-ancestor $branch origin/main 2>$null
                $merged = ($LASTEXITCODE -eq 0)
                if ($status) { Add-InventoryItem $items "dirty/unmerged" $dir.FullName $branch "worktree 有未提交修改" $true }
                elseif ($merged) { Add-InventoryItem $items "clean+merged" $dir.FullName $branch "worktree clean 且 branch 已并入 origin/main" $false }
                else { Add-InventoryItem $items "clean+unmerged" $dir.FullName $branch "worktree clean 但 branch 尚未并入 origin/main" $true }
            }
        }
    }
    if (Test-Path -LiteralPath $legacyWorktreeRoot -PathType Container -and $legacyWorktreeRoot -ne $managedWorktreeRoot) {
        Add-InventoryItem $items "audit-retained" $legacyWorktreeRoot "legacy-worktree-root" "旧版派工目录仅登记；不在健康检查中逐个扫描或自动删除" $true
    }
} catch { }

$itemArray = $items.ToArray()
$counts = [ordered]@{
    active = @($itemArray | Where-Object { $_.category -eq "active" }).Count
    retired = @($itemArray | Where-Object { $_.category -eq "retired" }).Count
    clean_merged = @($itemArray | Where-Object { $_.category -eq "clean+merged" }).Count
    dirty_unmerged = @($itemArray | Where-Object { $_.category -eq "dirty/unmerged" }).Count
    audit_retained = @($itemArray | Where-Object { $_.category -eq "audit-retained" }).Count
    test_scratch = @($itemArray | Where-Object { $_.category -eq "test-scratch" }).Count
}
$payload = [ordered]@{
    schema = "codex-praetor-runtime-inventory/v1"; generated_at = (Get-Date).ToString("o"); channel = $Channel; active_generation = $activeGeneration
    policy = "read-only; active/dirty/unmerged/audit-retained protected"; items = $itemArray; counts = $counts
}
if ($Json) { $payload | ConvertTo-Json -Depth 20 } else { Write-Output "Codex Praetor runtime inventory: active=$($payload.counts.active) retired=$($payload.counts.retired) clean+merged=$($payload.counts.clean_merged) dirty/unmerged=$($payload.counts.dirty_unmerged) audit-retained=$($payload.counts.audit_retained) test-scratch=$($payload.counts.test_scratch)" }
