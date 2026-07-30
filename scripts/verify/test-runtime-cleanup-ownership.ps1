param([string]$ProjectRoot = "")

$ErrorActionPreference = "Stop"
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) {
    $global:PSNativeCommandUseErrorActionPreference = $false
}
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$root = [System.IO.Path]::GetFullPath($ProjectRoot)
$cleaner = Join-Path $root "scripts\maintenance\clean-codex-praetor-runtime.ps1"
$scratch = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-praetor-cleanup-ownership-" + [Guid]::NewGuid().ToString("N"))

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

try {
    New-Item -ItemType Directory -Path $scratch -Force | Out-Null
    $repo = Join-Path $scratch "repo"
    New-Item -ItemType Directory -Path $repo -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $repo "README.md") -Value "fixture" -Encoding ASCII
    & git -C $repo init -q
    & git -C $repo config user.email "cleanup-test@example.invalid"
    & git -C $repo config user.name "Codex Praetor test"
    & git -C $repo add README.md
    & git -C $repo commit -qm "fixture"
    if ($LASTEXITCODE -ne 0) { throw "Unable to create cleanup fixture repository." }

    $runtimeRoot = Join-Path $repo ".codex-praetor"
    $worktreeRoot = Join-Path $runtimeRoot "worktrees"
    $ownedTree = Join-Path $worktreeRoot "owned"
    $foreignTree = Join-Path $worktreeRoot "foreign"
    New-Item -ItemType Directory -Path $worktreeRoot -Force | Out-Null
    & git -C $repo worktree add -q -b cw-owned $ownedTree HEAD 2>$null
    if ($LASTEXITCODE -ne 0) { throw "Unable to create owned worker fixture." }
    & git -C $repo worktree add -q -b foreign-worker $foreignTree HEAD 2>$null
    if ($LASTEXITCODE -ne 0) { throw "Unable to create foreign worktree fixture." }
    $owner = [ordered]@{ schema = "codex-praetor-runtime-owner/v1"; canonical_project_root = $repo; git_common_directory = (Join-Path $repo ".git"); managed_worktree_root = $worktreeRoot; created_at = (Get-Date).ToString("o") }
    $owner | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $runtimeRoot "runtime-owner.json") -Encoding UTF8
    $ownershipRoot = Join-Path $runtimeRoot "worktree-ownership"
    New-Item -ItemType Directory -Path $ownershipRoot -Force | Out-Null
    $workerOwner = [ordered]@{ schema = "codex-praetor-worker-worktree-owner/v1"; runtime_owner = (Join-Path $runtimeRoot "runtime-owner.json"); canonical_project_root = $repo; worktree_name = "owned"; worktree_path = $ownedTree; branch = "cw-owned"; created_at = (Get-Date).ToString("o") }
    $workerOwner | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $ownershipRoot "owned.json") -Encoding UTF8
    $manifestPath = Join-Path $scratch "cleanup-candidates.json"

    $cleanOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cleaner -Repo $repo -RetentionDays 0 -CandidateManifestPath $manifestPath | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Ownership-aware cleanup dry run failed." }
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "Cleanup did not write its requested candidate manifest: $cleanOutput" }
    Assert-True (Test-Path -LiteralPath $ownedTree -PathType Container) "Cleanup dry run removed the owned worktree."
    Assert-True (Test-Path -LiteralPath $foreignTree -PathType Container) "Cleanup dry run removed the foreign worktree."
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $ownedCandidate = @($manifest.candidates | Where-Object { [System.IO.Path]::GetFullPath([string]$_.path) -eq [System.IO.Path]::GetFullPath($ownedTree) } | Select-Object -First 1)
    $foreignCandidate = @($manifest.candidates | Where-Object { [System.IO.Path]::GetFullPath([string]$_.path) -eq [System.IO.Path]::GetFullPath($foreignTree) } | Select-Object -First 1)
    Assert-True ($ownedCandidate.Count -eq 1 -and [string]$ownedCandidate[0].disposition -eq "eligible" -and [bool]$ownedCandidate[0].praetor_owned) "Clean merged Praetor-owned worktree was not eligible: $($manifest.candidates | ConvertTo-Json -Compress)"
    Assert-True ($foreignCandidate.Count -eq 1 -and [string]$foreignCandidate[0].disposition -eq "protected" -and -not [bool]$foreignCandidate[0].praetor_owned) "Unowned worktree was not protected."
    Write-Output "[PASS] Cleanup emits an ownership-aware candidate manifest and protects unowned worktrees in dry-run mode."
} finally {
    $repo = Join-Path $scratch "repo"
    foreach ($entry in @(@{ path = (Join-Path $repo ".codex-praetor\worktrees\owned"); branch = "cw-owned" }, @{ path = (Join-Path $repo ".codex-praetor\worktrees\foreign"); branch = "foreign-worker" })) {
        if (Test-Path -LiteralPath $entry.path -PathType Container) {
            & git -C $repo worktree remove --force $entry.path 2>$null | Out-Null
            & git -C $repo branch -D $entry.branch 2>$null | Out-Null
        }
    }
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}
