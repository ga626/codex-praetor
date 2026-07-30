param(
    [string]$Repo = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))),
    [int]$RetentionDays = 14,
    [string]$CandidateManifestPath = "",
    [switch]$Apply,
    [switch]$DeleteMergedBranches
)

$ErrorActionPreference = "Stop"
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) {
    $global:PSNativeCommandUseErrorActionPreference = $false
}

function Resolve-GitRoot {
    param([string]$Path)
    $resolved = (Resolve-Path -LiteralPath $Path).Path
    $gitRoot = & git -C $resolved rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($gitRoot)) {
        return [System.IO.Path]::GetFullPath($gitRoot.Trim())
    }
    throw "Not a git repository: $Path"
}

function Assert-UnderPath {
    param(
        [string]$Path,
        [string]$Root,
        [string]$Label
    )
    $full = [System.IO.Path]::GetFullPath($Path)
    $rootFull = [System.IO.Path]::GetFullPath($Root)
    $prefix = $rootFull.TrimEnd("\") + "\"
    if (($full -ne $rootFull) -and (-not $full.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase))) {
        throw "$Label is outside allowed root: $full"
    }
}

function Invoke-MaintenanceAction {
    param(
        [string]$Message,
        [scriptblock]$Action
    )
    if ($Apply) {
        Write-Host "APPLY: $Message"
        & $Action
    } else {
        Write-Host "DRY-RUN: $Message"
    }
}

function Add-CleanupCandidate {
    param(
        [System.Collections.Generic.List[object]]$List,
        [string]$Kind,
        [string]$Path,
        [string]$Branch,
        [string]$Disposition,
        [string]$Reason,
        [bool]$Owned
    )
    $List.Add([pscustomobject]@{
        kind = $Kind
        path = $Path
        branch = $Branch
        disposition = $Disposition
        reason = $Reason
        praetor_owned = $Owned
    })
}

function Get-WorkerOwnershipRecord {
    param(
        [string]$OwnershipRoot,
        [string]$ProjectRoot,
        [object]$WorktreeRecord
    )
    $name = Split-Path -Leaf ([string]$WorktreeRecord.Worktree)
    $path = Join-Path $OwnershipRoot ($name + ".json")
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    try { $record = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json } catch { return $null }
    if ([string]$record.schema -ne "codex-praetor-worker-worktree-owner/v1") { return $null }
    if (-not [string]::Equals([string]$record.canonical_project_root, $ProjectRoot, [System.StringComparison]::OrdinalIgnoreCase)) { return $null }
    if (-not [string]::Equals([System.IO.Path]::GetFullPath([string]$record.worktree_path), [System.IO.Path]::GetFullPath([string]$WorktreeRecord.Worktree), [System.StringComparison]::OrdinalIgnoreCase)) { return $null }
    if (-not [string]::Equals([string]$record.branch, [string]$WorktreeRecord.Branch, [System.StringComparison]::OrdinalIgnoreCase)) { return $null }
    return $record
}

function Get-WorktreeRecords {
    param([string]$ProjectRoot)

    $lines = @(& git -C $ProjectRoot worktree list --porcelain)
    if ($LASTEXITCODE -ne 0) {
        throw "git worktree list failed."
    }

    $records = @()
    $current = $null
    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            if ($null -ne $current) {
                $records += [pscustomobject]$current
                $current = $null
            }
            continue
        }
        if ($line.StartsWith("worktree ")) {
            if ($null -ne $current) {
                $records += [pscustomobject]$current
            }
            $current = @{
                Worktree = $line.Substring("worktree ".Length)
                Head = ""
                Branch = ""
                Detached = $false
            }
            continue
        }
        if ($null -eq $current) { continue }
        if ($line.StartsWith("HEAD ")) {
            $current.Head = $line.Substring("HEAD ".Length)
        } elseif ($line.StartsWith("branch ")) {
            $branchRef = $line.Substring("branch ".Length)
            $current.Branch = $branchRef -replace "^refs/heads/", ""
        } elseif ($line -eq "detached") {
            $current.Detached = $true
        }
    }
    if ($null -ne $current) {
        $records += [pscustomobject]$current
    }
    return @($records)
}

function Test-WorktreeClean {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return $true
    }
    $status = @(& git -C $Path status --porcelain 2>$null)
    if ($LASTEXITCODE -ne 0) {
        return $false
    }
    return ($status.Count -eq 0)
}

function Get-MergedBranches {
    param([string]$ProjectRoot)

    $merged = @(& git -C $ProjectRoot branch --merged HEAD --format "%(refname:short)")
    if ($LASTEXITCODE -ne 0) {
        throw "git branch --merged failed."
    }
    return @($merged | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

$projectRoot = Resolve-GitRoot -Path $Repo
$runtimeRoot = Join-Path $projectRoot ".codex-praetor"
$worktreeRoot = Join-Path $runtimeRoot "worktrees"
$jobsRoot = Join-Path $runtimeRoot "jobs"
$scratchRoot = Join-Path $runtimeRoot "scratch"
$archiveRoot = Join-Path $runtimeRoot "archive"
$archiveJobsRoot = Join-Path $archiveRoot "jobs"
$runtimeOwnerPath = Join-Path $runtimeRoot "runtime-owner.json"
$ownershipRoot = Join-Path $runtimeRoot "worktree-ownership"
$cutoff = (Get-Date).AddDays(-1 * $RetentionDays)

Assert-UnderPath -Path $runtimeRoot -Root $projectRoot -Label "Runtime root"
Assert-UnderPath -Path $worktreeRoot -Root $projectRoot -Label "Worktree root"
Assert-UnderPath -Path $jobsRoot -Root $projectRoot -Label "Jobs root"
Assert-UnderPath -Path $scratchRoot -Root $projectRoot -Label "Scratch root"
Assert-UnderPath -Path $archiveRoot -Root $projectRoot -Label "Archive root"

Write-Host "Codex Praetor runtime cleanup"
Write-Host "Project root:    $projectRoot"
Write-Host "Runtime root:    $runtimeRoot"
Write-Host "Retention days:  $RetentionDays"
Write-Host "Mode:            $(if ($Apply) { 'apply' } else { 'dry-run' })"
Write-Host ""

if (-not (Test-Path -LiteralPath $runtimeRoot -PathType Container)) {
    Write-Host "[PASS] Runtime root does not exist; nothing to clean."
    exit 0
}

$runtimeOwner = $null
if (Test-Path -LiteralPath $runtimeOwnerPath -PathType Leaf) {
    try { $runtimeOwner = Get-Content -LiteralPath $runtimeOwnerPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $runtimeOwner = $null }
}
if ($null -eq $runtimeOwner -or [string]$runtimeOwner.schema -ne "codex-praetor-runtime-owner/v1" -or -not [string]::Equals([string]$runtimeOwner.canonical_project_root, $projectRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    Write-Host "[PROTECTED] Runtime root has no matching Codex Praetor ownership record; no cleanup candidate can be acted on."
    exit 0
}

$mergedBranches = Get-MergedBranches -ProjectRoot $projectRoot
$worktreeRecords = @(Get-WorktreeRecords -ProjectRoot $projectRoot)
$runtimeWorktrees = @($worktreeRecords | Where-Object {
    $full = [System.IO.Path]::GetFullPath($_.Worktree)
    $prefix = ([System.IO.Path]::GetFullPath($worktreeRoot)).TrimEnd("\") + "\"
    $full.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)
})

$candidates = New-Object 'System.Collections.Generic.List[object]'

$removedWorktrees = 0
foreach ($record in $runtimeWorktrees) {
    $branch = [string]$record.Branch
    $ownership = Get-WorkerOwnershipRecord -OwnershipRoot $ownershipRoot -ProjectRoot $projectRoot -WorktreeRecord $record
    $isWorkerBranch = $null -ne $ownership
    $isMerged = $mergedBranches -contains $branch
    $isClean = Test-WorktreeClean -Path $record.Worktree

    if (-not $isWorkerBranch) {
        Add-CleanupCandidate -List $candidates -Kind "worktree" -Path $record.Worktree -Branch $branch -Disposition "protected" -Reason "No matching Codex Praetor ownership record." -Owned $false
        Write-Host "[PROTECTED] Worktree has no matching Codex Praetor ownership record: $($record.Worktree) branch=$branch"
        continue
    }
    if (-not $isMerged) {
        Add-CleanupCandidate -List $candidates -Kind "worktree" -Path $record.Worktree -Branch $branch -Disposition "review" -Reason "Praetor-owned worker branch is not merged." -Owned $true
        Write-Host "[SKIP] Worker branch is not merged: $branch"
        continue
    }
    if (-not $isClean) {
        Add-CleanupCandidate -List $candidates -Kind "worktree" -Path $record.Worktree -Branch $branch -Disposition "protected" -Reason "Praetor-owned worker worktree is not clean." -Owned $true
        Write-Host "[SKIP] Worker worktree is not clean: $($record.Worktree)"
        continue
    }

    $worktreePath = [string]$record.Worktree
    Add-CleanupCandidate -List $candidates -Kind "worktree" -Path $worktreePath -Branch $branch -Disposition "eligible" -Reason "Praetor-owned, clean, and merged." -Owned $true
    Invoke-MaintenanceAction "Remove clean merged worker worktree $worktreePath" {
        & git -C $projectRoot worktree remove $worktreePath
        if ($LASTEXITCODE -ne 0) {
            throw "git worktree remove failed: $worktreePath"
        }
    }
    $removedWorktrees += 1

    if ($DeleteMergedBranches) {
        Invoke-MaintenanceAction "Delete merged worker branch $branch" {
            & git -C $projectRoot branch -d $branch
            if ($LASTEXITCODE -ne 0) {
                throw "git branch -d failed: $branch"
            }
        }
    }
}

$archivedJobs = 0
if (Test-Path -LiteralPath $jobsRoot -PathType Container) {
    Get-ChildItem -LiteralPath $jobsRoot -Directory -Force | Sort-Object LastWriteTimeUtc | ForEach-Object {
        $jobPath = $_.FullName
        $jobName = $_.Name
        $jobLastWriteTime = $_.LastWriteTime
        $completion = Join-Path $jobPath "completion.json"
        $reason = if (-not (Test-Path -LiteralPath $completion -PathType Leaf)) { "Job has no completion receipt." } elseif ($jobLastWriteTime -gt $cutoff) { "Job is newer than retention window." } else { "Job archival requires a future job ownership record; retained by this version." }
        Add-CleanupCandidate -List $candidates -Kind "job" -Path $jobPath -Branch "" -Disposition "protected" -Reason $reason -Owned $false
        Write-Host "[PROTECTED] Job retained: $jobName ($reason)"
    }
}

$removedScratch = 0
if (Test-Path -LiteralPath $scratchRoot -PathType Container) {
    Get-ChildItem -LiteralPath $scratchRoot -Force | Where-Object { $_.LastWriteTime -le $cutoff } | Sort-Object LastWriteTimeUtc | ForEach-Object {
        $scratchPath = $_.FullName
        Add-CleanupCandidate -List $candidates -Kind "scratch" -Path $scratchPath -Branch "" -Disposition "protected" -Reason "Scratch ownership is not recorded; retained by this version." -Owned $false
        Write-Host "[PROTECTED] Scratch artifact retained without ownership record: $scratchPath"
    }
}

if (-not [string]::IsNullOrWhiteSpace($CandidateManifestPath)) {
    $resolvedManifestPath = [System.IO.Path]::GetFullPath($CandidateManifestPath)
    $candidatePayload = [ordered]@{
        schema = "codex-praetor-runtime-cleanup-candidates/v1"
        generated_at = (Get-Date).ToString("o")
        project_root = $projectRoot
        runtime_owner = $runtimeOwnerPath
        mode = if ($Apply) { "apply" } else { "dry_run" }
        policy = "Only a matching Praetor ownership record can make a clean merged worker worktree eligible. Jobs and scratch remain protected until ownership records exist."
        candidates = $candidates.ToArray()
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $resolvedManifestPath) -Force | Out-Null
    $candidatePayload | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resolvedManifestPath -Encoding UTF8
    Write-Host "Candidate manifest: $resolvedManifestPath"
}

Write-Host ""
Write-Host "Summary"
Write-Host "Candidate merged worker worktrees: $removedWorktrees"
Write-Host "Candidate completed jobs to archive: $archivedJobs"
Write-Host "Candidate old scratch artifacts: $removedScratch"
if (-not $Apply) {
    Write-Host "No files were changed. Re-run with -Apply to perform these actions."
}
