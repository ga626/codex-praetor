param(
    [string]$Repo = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)),
    [switch]$Apply
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

function Invoke-Step {
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

function Move-DirectoryContents {
    param(
        [string]$Source,
        [string]$Destination
    )
    if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
        return
    }
    if (-not (Test-Path -LiteralPath $Destination -PathType Container)) {
        Invoke-Step "Move $Source -> $Destination" {
            $parent = Split-Path -Parent $Destination
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
            Move-Item -LiteralPath $Source -Destination $Destination
        }
        return
    }

    Get-ChildItem -LiteralPath $Source -Force | ForEach-Object {
        $target = Join-Path $Destination $_.Name
        if (Test-Path -LiteralPath $target) {
            $target = "$target.legacy-$script:MigrationStamp"
            if (Test-Path -LiteralPath $target) {
                throw "Refusing to overwrite existing runtime artifact: $target"
            }
        }
        Invoke-Step "Move $($_.FullName) -> $target" {
            Move-Item -LiteralPath $_.FullName -Destination $target
        }
    }
    Remove-EmptyDirectory -Path $Source
}

function Remove-EmptyDirectory {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return
    }
    $children = @(Get-ChildItem -LiteralPath $Path -Force)
    if ($children.Count -eq 0) {
        Invoke-Step "Remove empty directory $Path" {
            Remove-Item -LiteralPath $Path -Force
        }
    }
}

$projectRoot = Resolve-GitRoot -Path $Repo
$projectItem = Get-Item -LiteralPath $projectRoot
$projectParent = Split-Path -Parent $projectItem.FullName
$projectLeaf = Split-Path -Leaf $projectItem.FullName

$runtimeRoot = Join-Path $projectRoot ".codex-praetor"
$runtimeWorktrees = Join-Path $runtimeRoot "worktrees"
$legacyRuntimeRoot = Join-Path $projectParent "$projectLeaf.codex-praetor"
$legacyWorktreesRoot = Join-Path $projectParent "$projectLeaf.worktrees"
$legacyToolsRoot = Join-Path $projectParent "$projectLeaf.tools"
$runtimeToolsRoot = Join-Path $runtimeRoot "tools"
$script:MigrationStamp = Get-Date -Format "yyyyMMdd-HHmmss"

Assert-UnderPath -Path $runtimeRoot -Root $projectRoot -Label "New runtime root"
Assert-UnderPath -Path $runtimeWorktrees -Root $projectRoot -Label "New worktree root"
Assert-UnderPath -Path $runtimeToolsRoot -Root $projectRoot -Label "New tool cache root"
Assert-UnderPath -Path $legacyRuntimeRoot -Root $projectParent -Label "Legacy runtime root"
Assert-UnderPath -Path $legacyWorktreesRoot -Root $projectParent -Label "Legacy worktree root"
Assert-UnderPath -Path $legacyToolsRoot -Root $projectParent -Label "Legacy tools root"

Write-Host "Project root:       $projectRoot"
Write-Host "New runtime root:   $runtimeRoot"
Write-Host "Legacy runtime:     $legacyRuntimeRoot"
Write-Host "Legacy worktrees:   $legacyWorktreesRoot"
Write-Host "Legacy tools:       $legacyToolsRoot"
Write-Host ""

Invoke-Step "Ensure runtime root $runtimeRoot" {
    New-Item -ItemType Directory -Path $runtimeRoot -Force | Out-Null
}

foreach ($name in @("jobs", "plans", "locks", "scratch")) {
    Move-DirectoryContents -Source (Join-Path $legacyRuntimeRoot $name) -Destination (Join-Path $runtimeRoot $name)
}
Remove-EmptyDirectory -Path $legacyRuntimeRoot

if (Test-Path -LiteralPath $legacyWorktreesRoot -PathType Container) {
    Invoke-Step "Ensure runtime worktree root $runtimeWorktrees" {
        New-Item -ItemType Directory -Path $runtimeWorktrees -Force | Out-Null
    }

    Get-ChildItem -LiteralPath $legacyWorktreesRoot -Directory -Force | ForEach-Object {
        $target = Join-Path $runtimeWorktrees $_.Name
        if (Test-Path -LiteralPath $target) {
            throw "Refusing to overwrite existing worktree target: $target"
        }
        Invoke-Step "git worktree move $($_.FullName) -> $target" {
            & git -C $projectRoot worktree move $_.FullName $target
            if ($LASTEXITCODE -ne 0) {
                throw "git worktree move failed for $($_.FullName)"
            }
        }
    }
    Remove-EmptyDirectory -Path $legacyWorktreesRoot
}

Move-DirectoryContents -Source $legacyToolsRoot -Destination $runtimeToolsRoot

Write-Host ""
if ($Apply) {
    Write-Host "Runtime migration complete."
} else {
    Write-Host "Dry run complete. Re-run with -Apply to move legacy runtime folders."
}
