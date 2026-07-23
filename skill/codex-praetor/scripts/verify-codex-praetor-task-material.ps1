param(
    [Parameter(Mandatory = $true)]
    [string]$Worktree,
    [Parameter(Mandatory = $true)]
    [string]$TaskMaterialJson,
    [string[]]$RequiredCheck = @(),
    [string]$RequiredChecksJson = ""
)

$ErrorActionPreference = "Stop"
if (-not [string]::IsNullOrWhiteSpace($RequiredChecksJson)) { try { $RequiredCheck = @($RequiredChecksJson | ConvertFrom-Json) } catch { throw "RequiredChecksJson is not valid JSON." } }

function Get-FileSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    $stream = [IO.File]::OpenRead($Path)
    try {
        $sha = [Security.Cryptography.SHA256]::Create()
        try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '').ToLowerInvariant() } finally { $sha.Dispose() }
    } finally { $stream.Dispose() }
}

function Get-SafeRelativePath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    $normalized = $PathValue.Replace('/', '\\').Trim()
    if ([string]::IsNullOrWhiteSpace($normalized) -or [IO.Path]::IsPathRooted($normalized)) { throw "Task material path must be relative: $PathValue" }
    $parts = @($normalized -split '\\' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($parts.Count -eq 0 -or @($parts | Where-Object { $_ -in @('.', '..') }).Count -gt 0) { throw "Task material path escapes its root: $PathValue" }
    return ($parts -join '\\')
}

function Join-CheckedChildPath {
    param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][string]$RelativePath)
    $rootFull = [IO.Path]::GetFullPath($Root)
    $childFull = [IO.Path]::GetFullPath((Join-Path $rootFull (Get-SafeRelativePath -PathValue $RelativePath)))
    $prefix = $rootFull.TrimEnd('\\') + [IO.Path]::DirectorySeparatorChar
    if (-not $childFull.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw "Task material path escapes its root: $RelativePath" }
    return $childFull
}

function Invoke-DeclaredCheck {
    param([Parameter(Mandatory = $true)][string]$WorkingDirectory, [Parameter(Mandatory = $true)][string]$Command)
    $processInfo = New-Object System.Diagnostics.ProcessStartInfo
    $processInfo.FileName = $env:ComSpec
    $processInfo.Arguments = "/d /s /c $Command"
    $processInfo.WorkingDirectory = $WorkingDirectory
    $processInfo.UseShellExecute = $false
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true
    $process = [System.Diagnostics.Process]::Start($processInfo)
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    [void]$process.WaitForExit()
    [void]$stdoutTask.GetAwaiter().GetResult()
    [void]$stderrTask.GetAwaiter().GetResult()
    $exitCode = $process.ExitCode
    [void]$process.Dispose()
    return $exitCode
}

if (-not (Test-Path -LiteralPath $Worktree -PathType Container)) { throw "Worktree does not exist: $Worktree" }
try { $material = $TaskMaterialJson | ConvertFrom-Json } catch { throw "TaskMaterialJson is not valid JSON." }
foreach ($name in @('schema', 'destination', 'write_set', 'immutable_paths', 'files', 'manifest_sha256')) {
    if (-not ($material.PSObject.Properties.Name -contains $name)) { throw "Task material lacks $name." }
}
if ([string]$material.schema -ne 'codex-praetor-task-material-instance/v1') { throw "Task material schema is not supported." }
$destination = Get-SafeRelativePath -PathValue ([string]$material.destination)
$destinationRoot = Join-CheckedChildPath -Root $Worktree -RelativePath $destination
$violations = @()
$checks = @()
$expectedFiles = @($material.files)
$expectedPaths = @($expectedFiles | ForEach-Object { (Get-SafeRelativePath -PathValue ([string]$_.path)).Replace('\\', '/') })

if (-not (Test-Path -LiteralPath $destinationRoot -PathType Container)) {
    $violations += "material_destination_missing"
} else {
    $actualPaths = @(
        Get-ChildItem -LiteralPath $destinationRoot -File -Recurse |
            ForEach-Object { $_.FullName.Substring($destinationRoot.Length + 1).Replace('\\', '/') }
    )
    foreach ($pathValue in $expectedPaths) { if ($actualPaths -notcontains $pathValue) { $violations += "material_file_missing:$pathValue" } }
    foreach ($pathValue in $actualPaths) { if ($expectedPaths -notcontains $pathValue) { $violations += "material_file_unexpected:$pathValue" } }
}

foreach ($immutablePath in @($material.immutable_paths)) {
    $fullRelative = (Get-SafeRelativePath -PathValue ([string]$immutablePath)).Replace('\\', '/')
    $prefix = $destination.Replace('\\', '/') + '/'
    if (-not $fullRelative.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        $violations += "immutable_path_outside_destination:$fullRelative"
        continue
    }
    $materialRelative = $fullRelative.Substring($prefix.Length)
    $entry = @($expectedFiles | Where-Object { ((Get-SafeRelativePath -PathValue ([string]$_.path)).Replace('\\', '/')) -eq $materialRelative }) | Select-Object -First 1
    $target = Join-CheckedChildPath -Root $destinationRoot -RelativePath $materialRelative
    if ($null -eq $entry -or -not (Test-Path -LiteralPath $target -PathType Leaf)) {
        $violations += "immutable_file_missing:$fullRelative"
    } elseif ((Get-FileSha256 -Path $target) -ne [string]$entry.sha256) {
        $violations += "immutable_file_changed:$fullRelative"
    }
}

$trackedDiff = @(& git -C $Worktree diff --name-only --no-ext-diff)
if ($LASTEXITCODE -ne 0) { throw "git diff could not inspect the worktree." }
$allowedWriteSet = @($material.write_set | ForEach-Object { (Get-SafeRelativePath -PathValue ([string]$_)).Replace('\\', '/') })
foreach ($pathValue in $trackedDiff) {
    $normalized = ([string]$pathValue).Replace('\\', '/')
    if ($normalized -and $allowedWriteSet -notcontains $normalized) { $violations += "tracked_diff_outside_write_set:$normalized" }
}

$statusLines = @(& git -C $Worktree status --porcelain=v1 --untracked-files=all)
if ($LASTEXITCODE -ne 0) { throw "git status could not inspect the worktree." }
$materialStatusPaths = @($expectedPaths | ForEach-Object { ($destination.Replace('\\', '/') + '/' + $_) })
foreach ($line in $statusLines) {
    if ([string]$line -notmatch '^.. ') { $violations += "unparseable_git_status"; continue }
    $pathValue = ([string]$line).Substring(3).Replace('\\', '/')
    if ($pathValue -and $materialStatusPaths -notcontains $pathValue -and $allowedWriteSet -notcontains $pathValue) { $violations += "worktree_change_outside_material:$pathValue" }
}

foreach ($command in @($RequiredCheck)) {
    if ([string]::IsNullOrWhiteSpace([string]$command)) { continue }
    $exitCode = Invoke-DeclaredCheck -WorkingDirectory $Worktree -Command ([string]$command)
    $checks += [ordered]@{ command = [string]$command; exit_code = $exitCode; passed = ($exitCode -eq 0) }
    if ($exitCode -ne 0) { $violations += "required_check_failed:$command" }
}

[ordered]@{
    schema = 'codex-praetor-task-material-verification/v1'
    verdict = if ($violations.Count -eq 0) { 'accepted_candidate' } else { 'rejected' }
    final_acceptance = 'Codex must independently record the final plan verdict.'
    worktree = (Resolve-Path -LiteralPath $Worktree).Path
    destination = $destination.Replace('\\', '/')
    task_material_manifest_sha256 = [string]$material.manifest_sha256
    checks = $checks
    violations = $violations
} | ConvertTo-Json -Depth 10
