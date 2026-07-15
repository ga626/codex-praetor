param(
    [string]$Repo = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))),
    [int]$RetentionDays = 14,
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
        return $gitRoot.Trim()
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

$mergedBranches = Get-MergedBranches -ProjectRoot $projectRoot
$worktreeRecords = @(Get-WorktreeRecords -ProjectRoot $projectRoot)
$runtimeWorktrees = @($worktreeRecords | Where-Object {
    $full = [System.IO.Path]::GetFullPath($_.Worktree)
    $prefix = ([System.IO.Path]::GetFullPath($worktreeRoot)).TrimEnd("\") + "\"
    $full.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)
})

$removedWorktrees = 0
foreach ($record in $runtimeWorktrees) {
    $branch = [string]$record.Branch
    $isWorkerBranch = $branch -like "cw-*"
    $isMerged = $mergedBranches -contains $branch
    $isClean = Test-WorktreeClean -Path $record.Worktree

    if (-not $isWorkerBranch) {
        Write-Host "[SKIP] Non-worker worktree: $($record.Worktree) branch=$branch"
        continue
    }
    if (-not $isMerged) {
        Write-Host "[SKIP] Worker branch is not merged: $branch"
        continue
    }
    if (-not $isClean) {
        Write-Host "[SKIP] Worker worktree is not clean: $($record.Worktree)"
        continue
    }

    $worktreePath = [string]$record.Worktree
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
        if (-not (Test-Path -LiteralPath $completion -PathType Leaf)) {
            Write-Host "[SKIP] Job has no completion.json: $jobName"
        } elseif ($jobLastWriteTime -gt $cutoff) {
            Write-Host "[SKIP] Job is newer than retention window: $jobName"
        } else {
            $day = $jobLastWriteTime.ToString("yyyyMMdd")
            $destination = Join-Path (Join-Path $archiveJobsRoot $day) $jobName
            if (Test-Path -LiteralPath $destination) {
                $destination = "$destination.$([Guid]::NewGuid().ToString("N").Substring(0, 8))"
            }
            Invoke-MaintenanceAction "Archive completed job $jobPath -> $destination" {
                New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
                Move-Item -LiteralPath $jobPath -Destination $destination
            }
            $archivedJobs += 1
        }
    }
}

$removedScratch = 0
if (Test-Path -LiteralPath $scratchRoot -PathType Container) {
    Get-ChildItem -LiteralPath $scratchRoot -Force | Where-Object { $_.LastWriteTime -le $cutoff } | Sort-Object LastWriteTimeUtc | ForEach-Object {
        $scratchPath = $_.FullName
        Invoke-MaintenanceAction "Remove old scratch artifact $scratchPath" {
            Remove-Item -LiteralPath $scratchPath -Recurse -Force
        }
        $removedScratch += 1
    }
}

Write-Host ""
Write-Host "Summary"
Write-Host "Candidate merged worker worktrees: $removedWorktrees"
Write-Host "Candidate completed jobs to archive: $archivedJobs"
Write-Host "Candidate old scratch artifacts: $removedScratch"
if (-not $Apply) {
    Write-Host "No files were changed. Re-run with -Apply to perform these actions."
}
