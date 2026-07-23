param(
    [ValidateSet("auto", "qoder", "codebuddy")]
    [string]$Provider = "auto",

    [string]$Tier = "",

    [string]$ConfigPath = "",

    [Parameter(Mandatory = $true)]
    [string]$Repo,

    [Parameter(Mandatory = $true)]
    [string]$Task,

    [ValidateSet("readonly", "edit")]
    [string]$Mode = "readonly",

    [ValidateSet("", "local_audit", "test_execution", "code_change", "external_research")]
    [string]$TaskKind = "",

    [ValidateSet("blocking", "background")]
    [string]$RunMode = "blocking",

    [switch]$DryRun,

    [switch]$PreflightOnly,

    [switch]$PreferQoder,

    [int]$MaxTurns = 8,

    [ValidateRange(30, 86400)]
    [int]$TimeoutSeconds = 1200,

    [string]$OutputFormat = "",

    [string]$ReasoningEffort = "",

    [int]$ContextWindow = 0,

    [string]$Agent = "",

    [string]$PermissionProfile = "",

    [string]$JsonSchema = "",

    [string]$ModelOverride = "",

    [switch]$AllowAutoModel,

    [switch]$AllowUnlistedModel,

    [switch]$AllowExpensiveModel,

    [switch]$AllowExtremeReasoning,

    [switch]$AllowConcurrentRepoEdit,

    [string]$WorktreeName = "",

    [string]$JobRoot = "",

    [string]$LockRoot = "",

    [string]$NotifyThreadId = $env:CODEX_THREAD_ID,

    [string]$NotifyWorkspace = (Get-Location).Path,

    [string]$PlanId = "",

    [string]$TaskId = "",

    [string]$ResearchContractJson = "",

    [string]$DependsOn = "",

    [string]$Acceptance = "",

    [string]$PlanRoot = "",

    [string]$ScratchRoot = "",

    [string]$ReadinessPath = "",

    [string]$UserProfileRoot = "",

    [ValidateSet("stable", "dev")]
    [string]$RuntimeChannel = "stable",

    [switch]$NoNotify,

    [string[]]$AllowedPath = @(),

    [string]$AllowedPathsJson = "",

    [string[]]$ForbiddenPath = @(".git/**", ".env*", "auth/**", "node_modules/**"),

    [string]$ForbiddenPathsJson = "",

    [string[]]$RequiredCheck = @(),

    [string]$RequiredChecksJson = "",

    [string]$BudgetJson = "",

    [string]$FailureInjection = "",

    [string]$Sensitivity = "",

    [string]$TaskMaterialJson = "",

    [string]$TaskMaterialPath = "",

    [string]$TaskMaterialBase64 = "",

    [switch]$AllowWorkerNetwork,

    [switch]$CapabilityCanary
)

$ErrorActionPreference = "Stop"
if (@($TaskMaterialJson, $TaskMaterialPath, $TaskMaterialBase64 | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count -gt 1) { throw "Specify only one task material transport." }
if (-not [string]::IsNullOrWhiteSpace($TaskMaterialPath)) {
    if (-not (Test-Path -LiteralPath $TaskMaterialPath -PathType Leaf)) { throw "TaskMaterialPath does not exist: $TaskMaterialPath" }
    $TaskMaterialJson = Get-Content -LiteralPath $TaskMaterialPath -Raw -Encoding UTF8
}
if (-not [string]::IsNullOrWhiteSpace($TaskMaterialBase64)) {
    try { $TaskMaterialJson = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($TaskMaterialBase64)) } catch { throw "TaskMaterialBase64 is not valid UTF-8 Base64." }
}
if (-not [string]::IsNullOrWhiteSpace($AllowedPathsJson)) { try { $AllowedPath = @($AllowedPathsJson | ConvertFrom-Json) } catch { throw "AllowedPathsJson is not valid JSON." } }
if (-not [string]::IsNullOrWhiteSpace($ForbiddenPathsJson)) { try { $ForbiddenPath = @($ForbiddenPathsJson | ConvertFrom-Json) } catch { throw "ForbiddenPathsJson is not valid JSON." } }
if (-not [string]::IsNullOrWhiteSpace($RequiredChecksJson)) { try { $RequiredCheck = @($RequiredChecksJson | ConvertFrom-Json) } catch { throw "RequiredChecksJson is not valid JSON." } }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[Console]::InputEncoding = $utf8NoBom
[Console]::OutputEncoding = $utf8NoBom
$OutputEncoding = $utf8NoBom

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$scriptParent = Split-Path -Parent $scriptDir
$scriptGrandparent = Split-Path -Parent $scriptParent
$configCandidates = New-Object System.Collections.Generic.List[string]
if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
    $configCandidates.Add($ConfigPath)
}
if (-not [string]::IsNullOrWhiteSpace($env:CODEX_PRAETOR_CONFIG)) {
    $configCandidates.Add($env:CODEX_PRAETOR_CONFIG)
}
$configCandidates.Add((Join-Path (Get-Location).Path "config\codex-praetor.local.json"))
$configCandidates.Add((Join-Path $env:USERPROFILE ".codex\codex-praetor.local.json"))
$configCandidates.Add((Join-Path $scriptDir "codex-praetor-tiers.local.json"))
$configCandidates.Add((Join-Path $scriptDir "codex-praetor-tiers.json"))
$configCandidates.Add((Join-Path $scriptParent "config\codex-praetor.local.json"))
$configCandidates.Add((Join-Path $scriptParent "config\codex-praetor-tiers.example.json"))
$configCandidates.Add((Join-Path $scriptGrandparent "config\codex-praetor.local.json"))
$configCandidates.Add((Join-Path $scriptGrandparent "config\codex-praetor-tiers.example.json"))

$resolvedConfigPath = ""
foreach ($candidate in $configCandidates) {
    if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        $resolvedConfigPath = $candidate
        break
    }
}

if ([string]::IsNullOrWhiteSpace($resolvedConfigPath)) {
    throw "Missing Codex Praetor config. Checked: $($configCandidates -join '; ')"
}

$config = Get-Content -LiteralPath $resolvedConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$runtimeContractCandidates = @(
    (Join-Path $scriptGrandparent "config\runtime-contract.json"),
    (Join-Path $scriptDir "runtime-contract.json")
)
$runtimeContractPath = @($runtimeContractCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1)
if (@($runtimeContractPath).Count -ne 1) { throw "Codex Praetor runtime contract is missing." }
function Get-FileSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        try {
            return (([System.BitConverter]::ToString($sha256.ComputeHash($stream))).Replace("-", "").ToLowerInvariant())
        } finally { $sha256.Dispose() }
    } finally { $stream.Dispose() }
}

function Get-SafeRelativePath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    $normalized = $PathValue.Replace('/', '\\').Trim()
    if ([string]::IsNullOrWhiteSpace($normalized) -or [IO.Path]::IsPathRooted($normalized)) {
        throw "Task material path must be a non-empty relative path: $PathValue"
    }
    $parts = @($normalized -split '\\' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($parts.Count -eq 0 -or @($parts | Where-Object { $_ -in @('.', '..') }).Count -gt 0) {
        throw "Task material path escapes its declared root: $PathValue"
    }
    return ($parts -join '\\')
}

function Join-CheckedChildPath {
    param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][string]$RelativePath)
    $rootFull = [IO.Path]::GetFullPath($Root)
    $childFull = [IO.Path]::GetFullPath((Join-Path $rootFull (Get-SafeRelativePath -PathValue $RelativePath)))
    $prefix = $rootFull.TrimEnd('\\') + [IO.Path]::DirectorySeparatorChar
    if (-not $childFull.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Task material path escapes its declared root: $RelativePath"
    }
    return $childFull
}

function ConvertTo-TaskMaterial {
    param([string]$Json)
    if ([string]::IsNullOrWhiteSpace($Json)) { return $null }
    try { $material = $Json | ConvertFrom-Json } catch { throw "TaskMaterialJson is not valid JSON." }
    foreach ($name in @('schema', 'source_root', 'destination', 'write_set', 'immutable_paths', 'baseline_command', 'baseline_exit_code', 'files', 'manifest_sha256')) {
        if (-not ($material.PSObject.Properties.Name -contains $name)) { throw "Task material is missing $name." }
    }
    if ([string]$material.schema -ne 'codex-praetor-task-material-instance/v1') { throw "Task material schema is not supported." }
    if ([string]::IsNullOrWhiteSpace([string]$material.baseline_command) -or [int]$material.baseline_exit_code -lt 1) { throw "Task material baseline contract is invalid." }
    if (@($material.files).Count -eq 0 -or @($material.write_set).Count -eq 0 -or @($material.immutable_paths).Count -eq 0) { throw "Task material file, write-set, or immutable-path contract is empty." }
    $destination = Get-SafeRelativePath -PathValue ([string]$material.destination)
    foreach ($pathValue in @($material.write_set) + @($material.immutable_paths)) {
        $relative = Get-SafeRelativePath -PathValue ([string]$pathValue)
        if (-not $relative.StartsWith($destination + '\\', [StringComparison]::OrdinalIgnoreCase)) { throw "Task material path is outside its destination: $pathValue" }
    }
    return $material
}

function Test-TaskMaterialSource {
    param([Parameter(Mandatory = $true)][object]$Material)
    $sourceRoot = [string]$Material.source_root
    if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container)) { throw "Task material source root is missing: $sourceRoot" }
    $manifestPath = Join-Path $sourceRoot 'material-manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf) -or (Get-FileSha256 -Path $manifestPath) -ne [string]$Material.manifest_sha256) {
        throw "Task material manifest hash mismatch."
    }
    foreach ($entry in @($Material.files)) {
        if (-not ($entry.PSObject.Properties.Name -contains 'path') -or -not ($entry.PSObject.Properties.Name -contains 'sha256')) { throw "Task material file manifest is malformed." }
        $source = Join-CheckedChildPath -Root $sourceRoot -RelativePath ([string]$entry.path)
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Task material file is missing: $($entry.path)" }
        if ((Get-FileSha256 -Path $source) -ne [string]$entry.sha256) { throw "Task material hash mismatch: $($entry.path)" }
    }
}

function Inject-TaskMaterial {
    param([Parameter(Mandatory = $true)][object]$Material, [Parameter(Mandatory = $true)][string]$ExecutionRoot)
    Test-TaskMaterialSource -Material $Material
    $destination = Get-SafeRelativePath -PathValue ([string]$Material.destination)
    $destinationRoot = Join-CheckedChildPath -Root $ExecutionRoot -RelativePath $destination
    if (Test-Path -LiteralPath $destinationRoot) { throw "Task material destination already exists in the isolated worktree: $destination. Refuse to overwrite prior evidence." }
    New-Item -ItemType Directory -Path $destinationRoot -Force | Out-Null
    foreach ($entry in @($Material.files)) {
        $source = Join-CheckedChildPath -Root ([string]$Material.source_root) -RelativePath ([string]$entry.path)
        $target = Join-CheckedChildPath -Root $destinationRoot -RelativePath ([string]$entry.path)
        New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
        Copy-Item -LiteralPath $source -Destination $target -Force
        if ((Get-FileSha256 -Path $target) -ne [string]$entry.sha256) { throw "Injected task material hash mismatch: $($entry.path)" }
    }
    $processInfo = New-Object System.Diagnostics.ProcessStartInfo
    $processInfo.FileName = $env:ComSpec
    $processInfo.Arguments = "/d /s /c $([string]$Material.baseline_command)"
    $processInfo.WorkingDirectory = $ExecutionRoot
    $processInfo.UseShellExecute = $false
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true
    $process = [System.Diagnostics.Process]::Start($processInfo)
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    [void]$process.WaitForExit()
    [void]$stdoutTask.GetAwaiter().GetResult()
    [void]$stderrTask.GetAwaiter().GetResult()
    $baselineExitCode = $process.ExitCode
    [void]$process.Dispose()
    if ($baselineExitCode -ne [int]$Material.baseline_exit_code) { throw "Task material baseline exit code was $baselineExitCode, expected $($Material.baseline_exit_code). Worker launch is blocked." }
    return [ordered]@{ schema = [string]$Material.schema; destination = $destination.Replace('\\', '/'); write_set = @($Material.write_set); immutable_paths = @($Material.immutable_paths); baseline_command = [string]$Material.baseline_command; baseline_exit_code = [int]$Material.baseline_exit_code; baseline_observed_exit_code = $baselineExitCode; files = @($Material.files); manifest_sha256 = [string]$Material.manifest_sha256 }
}

$runtimeContractPath = [string]$runtimeContractPath[0]
$generationScript = Join-Path $scriptGrandparent "scripts\release\get-codex-praetor-generation.ps1"
$runtimeContract = Get-Content -LiteralPath $runtimeContractPath -Raw -Encoding UTF8 | ConvertFrom-Json
$runtimeContractHash = Get-FileSha256 -Path $runtimeContractPath
$readinessHelperCandidates = @(
    (Join-Path $scriptGrandparent "scripts\verify\resolve-codex-praetor-readiness.ps1"),
    (Join-Path $scriptDir "resolve-codex-praetor-readiness.ps1")
)
$readinessHelperPath = @($readinessHelperCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1)
if (@($readinessHelperPath).Count -eq 1) { . ([string]$readinessHelperPath[0]) }
$generation = $null
if (Test-Path -LiteralPath $generationScript -PathType Leaf) {
    $generation = (& $generationScript -ProjectRoot $scriptGrandparent -Json | ConvertFrom-Json)
} else {
    $pluginRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $scriptDir))
    $packagedGenerationPath = Join-Path $pluginRoot "release-generation.json"
    if (Test-Path -LiteralPath $packagedGenerationPath -PathType Leaf) {
        $generation = Get-Content -LiteralPath $packagedGenerationPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } else {
        $generation = [pscustomobject]@{
        schema = "codex-praetor-release-generation/v2"
        product = "codex-praetor"
        version = [string]$runtimeContract.version
        commit = "packaged"
        content_manifest_sha256 = $runtimeContractHash
        generation_id = "$( [string]$runtimeContract.version )--packaged--$($runtimeContractHash.Substring(0, 12))"
        runtime_contract_sha256 = $runtimeContractHash
        wrapper_protocol = [string]$runtimeContract.wrapperProtocol
        task_contract_schema = [string]$runtimeContract.taskContractSchema
        }
    }
}

function Test-OffPeak {
    $now = Get-Date
    $hour = $now.Hour
    return ($hour -ge 22 -or $hour -lt 8)
}

function Quote-Arg {
    param([string]$Value)
    if ($null -eq $Value) { return '""' }
    if ($Value -notmatch '[\s"`&|<>]') { return $Value }
    return '"' + ($Value -replace '"', '\"') + '"'
}

function Join-CommandLine {
    param([string]$Exe, [object[]]$ArgumentList)
    $parts = @((Quote-Arg $Exe))
    foreach ($arg in $ArgumentList) {
        $parts += Quote-Arg ([string]$arg)
    }
    return ($parts -join " ")
}

function New-WorkerJobId {
    param([string]$ProviderName, [string]$TierName)
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $suffix = [guid]::NewGuid().ToString("N").Substring(0, 8)
    return "$stamp-$ProviderName-$TierName-$suffix"
}

function Get-TextSha256 {
    param([string]$Text)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return (-join ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") }))
    } finally {
        $sha.Dispose()
    }
}

function Get-FileSha256OrEmpty {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return ""
    }
    return (Get-FileSha256 -Path $Path)
}

function Read-JsonOrNull {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }
    try {
        return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
    } catch {
        return $null
    }
}

function Test-ProviderReadiness {
    param(
        [string]$ReadinessPath,
        [string]$ProviderName,
        [string]$CliPath,
        [string]$ModelName,
        [string]$PermissionProfileName,
        [string]$TaskKindName
    )

    if (Get-Command Test-CodexPraetorProviderReadiness -ErrorAction SilentlyContinue) {
        return (Test-CodexPraetorProviderReadiness -Path $ReadinessPath -ProviderName $ProviderName -Cli $CliPath -ModelName $ModelName -Permission $PermissionProfileName -Kind $TaskKindName -ExpectedGeneration ([string]$generation.generation_id) -ExpectedRuntimeContract $runtimeContractHash -ExpectedTaskContract ([string]$runtimeContract.taskContractSchema))
    }
    return [ordered]@{ ok = $false; reason = "Readiness helper is missing."; cli_hash = (Get-FileSha256OrEmpty -Path $CliPath) }
}

function Get-CurrentGitBranch {
    param([string]$Path)
    try {
        $branch = & git -C $Path branch --show-current 2>$null
        if (-not [string]::IsNullOrWhiteSpace($branch)) {
            return $branch.Trim()
        }
    } catch {
        return ""
    }
    return ""
}

function Test-GitHeadExists {
    param([string]$Path)
    try {
        & git -C $Path rev-parse --verify HEAD 2>$null | Out-Null
        return ($LASTEXITCODE -eq 0)
    } catch {
        return $false
    }
}

function Get-WorkerWorktreePath {
    param(
        [string]$RepoPath,
        [string]$Name
    )
    $artifactRoot = Get-ProjectArtifactRoot -RepoPath $RepoPath
    return (Join-Path (Join-Path $artifactRoot "worktrees") $Name)
}

function Get-ProjectRootPath {
    param([string]$RepoPath)
    $resolved = (Resolve-Path -LiteralPath $RepoPath).Path
    try {
        $gitRoot = & git -C $resolved rev-parse --show-toplevel 2>$null
        if (-not [string]::IsNullOrWhiteSpace($gitRoot)) {
            return $gitRoot.Trim()
        }
    } catch {
        return $resolved
    }
    return $resolved
}

function Get-ProjectArtifactRoot {
    param([string]$RepoPath)
    $projectRoot = Get-ProjectRootPath -RepoPath $RepoPath
    return (Join-Path $projectRoot ".codex-praetor")
}

function Ensure-WorkerWorktree {
    param(
        [string]$RepoPath,
        [string]$Name
    )

    if (-not (Test-GitHeadExists -Path $RepoPath)) {
        throw "Cannot create worker worktree because this repository has no commits yet: $RepoPath. Create a clean initial commit first; otherwise external workers cannot inspect the current project through a Git worktree."
    }

    $baseBranch = Get-CurrentGitBranch -Path $RepoPath
    $baseRef = $baseBranch
    if ([string]::IsNullOrWhiteSpace($baseRef)) {
        $baseRef = (& git -C $RepoPath rev-parse --verify HEAD 2>$null | Out-String).Trim()
        if ([string]::IsNullOrWhiteSpace($baseRef)) {
            throw "Cannot resolve a commit for worker worktree creation: $RepoPath"
        }
    }

    $worktreePath = Get-WorkerWorktreePath -RepoPath $RepoPath -Name $Name
    if (Test-Path -LiteralPath $worktreePath) {
        throw "Worker worktree path already exists: $worktreePath"
    }

    $branchName = "cw-$Name"
    $existingBranch = & git -C $RepoPath branch --list $branchName 2>$null
    New-Item -ItemType Directory -Path (Split-Path -Parent $worktreePath) -Force | Out-Null

    $previousErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        if ([string]::IsNullOrWhiteSpace($existingBranch)) {
            $worktreeOutput = (& git -C $RepoPath worktree add -b $branchName $worktreePath $baseRef 2>&1 | Out-String).Trim()
        } else {
            $worktreeOutput = (& git -C $RepoPath worktree add $worktreePath $branchName 2>&1 | Out-String).Trim()
        }
        $worktreeExitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorAction
    }
    if ($worktreeExitCode -ne 0) {
        throw "git worktree add failed for $worktreePath. $worktreeOutput"
    }

    return $worktreePath
}

function Initialize-WorkerDependencyBootstrap {
    param(
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [Parameter(Mandatory = $true)][string]$TaskKindName
    )
    if ($TaskKindName -ne "code_change") { return "not_required" }
    $mcpRoot = Join-Path $WorkingDirectory "mcp"
    $lockPath = Join-Path $mcpRoot "package-lock.json"
    if (-not (Test-Path -LiteralPath $lockPath -PathType Leaf)) { return "not_applicable" }
    $npm = Get-Command npm.cmd -ErrorAction SilentlyContinue
    if ($null -eq $npm) { $npm = Get-Command npm -ErrorAction SilentlyContinue }
    if ($null -eq $npm) { throw "MCP dependency bootstrap requires npm, but npm is not available on PATH." }
    $bootstrapOutput = & $npm.Source --prefix $mcpRoot ci --ignore-scripts --no-audit --fund=false 2>&1
    if ($LASTEXITCODE -ne 0) { throw "MCP dependency bootstrap failed in the isolated worker worktree: $($bootstrapOutput | Out-String)" }
    return "mcp_npm_ci"
}

function Get-RepoLockPath {
    param([string]$RepoPath)
    $resolved = (Resolve-Path -LiteralPath $RepoPath).Path.ToLowerInvariant()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($resolved)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hashBytes = $sha.ComputeHash($bytes)
    } finally {
        $sha.Dispose()
    }
    $hash = -join ($hashBytes | ForEach-Object { $_.ToString("x2") })
    return (Join-Path $LockRoot "$hash.json")
}

function Test-ProcessAlive {
    param([int]$ProcessId)
    if ($ProcessId -le 0) {
        return $false
    }
    try {
        $null = Get-Process -Id $ProcessId -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

function Acquire-RepoEditLock {
    param(
        [string]$RepoPath,
        [string]$ProviderName,
        [string]$TierName
    )

    if ($AllowConcurrentRepoEdit -or $Mode -ne "edit" -or $DryRun) {
        return ""
    }

    New-Item -ItemType Directory -Path $LockRoot -Force | Out-Null
    $lockPath = Get-RepoLockPath -RepoPath $RepoPath

    if (Test-Path -LiteralPath $lockPath) {
        $existing = $null
        try {
            $existing = Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8 | ConvertFrom-Json
        } catch {
            $existing = $null
        }

        $existingPid = 0
        if ($null -ne $existing -and $null -ne $existing.pid) {
            $existingPid = [int]$existing.pid
        }

        if (Test-ProcessAlive -ProcessId $existingPid) {
            throw "Another codex-praetor edit task appears to be active for this repo. Repo: $RepoPath. Lock: $lockPath. Existing pid: $existingPid. Wait for it to finish, verify/merge it, or rerun with -AllowConcurrentRepoEdit only when file scopes are known not to overlap."
        }

        Remove-Item -LiteralPath $lockPath -Force
    }

    $meta = [ordered]@{
        repo = (Resolve-Path -LiteralPath $RepoPath).Path
        pid = $PID
        provider = $ProviderName
        tier = $TierName
        created_at = (Get-Date).ToString("o")
        note = "Repo edit lock for codex-praetor orchestration. Prevents accidental concurrent edit dispatch from multiple Codex conversations."
    }
    $meta | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $lockPath -Encoding UTF8
    return $lockPath
}

function Release-RepoEditLock {
    param([string]$LockPath)
    if ([string]::IsNullOrWhiteSpace($LockPath)) {
        return
    }
    if (Test-Path -LiteralPath $LockPath) {
        Remove-Item -LiteralPath $LockPath -Force
    }
}

function Update-RepoEditLockHolder {
    param(
        [string]$LockPath,
        [string]$JobId,
        [int]$HolderPid,
        [string]$HolderKind
    )
    if ([string]::IsNullOrWhiteSpace($LockPath) -or -not (Test-Path -LiteralPath $LockPath)) {
        return
    }
    $lock = $null
    try {
        $lock = Get-Content -LiteralPath $LockPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        $lock = [pscustomobject]@{}
    }

    $updated = [ordered]@{}
    if ($null -ne $lock) {
        foreach ($property in $lock.PSObject.Properties) {
            $updated[$property.Name] = $property.Value
        }
    }
    $updated["pid"] = $HolderPid
    $updated["holder_pid"] = $HolderPid
    $updated["holder_kind"] = $HolderKind
    $updated["job_id"] = $JobId
    $updated["updated_at"] = (Get-Date).ToString("o")
    $updated["note"] = "Repo edit lock is held by the detached codex-praetor watcher and will be released when the worker exits."
    $updated | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $LockPath -Encoding UTF8
}

function Import-EnvFromPersistentScopes {
    param([string[]]$Names)
    foreach ($name in $Names) {
        $current = [Environment]::GetEnvironmentVariable($name, "Process")
        if (-not [string]::IsNullOrWhiteSpace($current)) {
            continue
        }

        $value = [Environment]::GetEnvironmentVariable($name, "User")
        if ([string]::IsNullOrWhiteSpace($value)) {
            $value = [Environment]::GetEnvironmentVariable($name, "Machine")
        }

        if (-not [string]::IsNullOrWhiteSpace($value)) {
            [Environment]::SetEnvironmentVariable($name, $value, "Process")
        }
    }
}

function Test-WildcardMatch {
    param(
        [string]$Pattern,
        [string]$Value
    )
    if ([string]::IsNullOrWhiteSpace($Pattern)) {
        return $false
    }
    if ($Pattern.Contains("*")) {
        return ($Value -like $Pattern)
    }
    return ($Pattern -eq $Value)
}

function Get-ProviderModelClassification {
    param(
        [object]$ProviderConfig,
        [string]$ModelName
    )

    $blocked = @($ProviderConfig.blockedModels)
    foreach ($pattern in $blocked) {
        if (Test-WildcardMatch -Pattern ([string]$pattern) -Value $ModelName) {
            return "blocked"
        }
    }

    $allowed = @($ProviderConfig.allowedModels)
    foreach ($pattern in $allowed) {
        if (Test-WildcardMatch -Pattern ([string]$pattern) -Value $ModelName) {
            return "allowed"
        }
    }

    $known = @($ProviderConfig.knownButNotDefaultModels) + @($ProviderConfig.knownSupportedModels)
    foreach ($pattern in $known) {
        if (Test-WildcardMatch -Pattern ([string]$pattern) -Value $ModelName) {
            return "known_not_default"
        }
    }

    return "unknown"
}

function Get-EffortRank {
    param([string]$Value)
    $normalized = ""
    if (-not [string]::IsNullOrWhiteSpace($Value)) {
        $normalized = $Value.ToLowerInvariant()
    }
    switch ($normalized) {
        "minimal" { return 1 }
        "low"     { return 2 }
        "medium"  { return 3 }
        "high"    { return 4 }
        "xhigh"   { return 5 }
        "max"     { return 6 }
        default   { return 0 }
    }
}

function Assert-ProviderModelPolicy {
    param(
        [object]$ProviderConfig,
        [string]$ProviderName,
        [string]$ModelName,
        [bool]$AllowAuto,
        [bool]$AllowKnownButNotDefault,
        [bool]$AllowUnknown
    )

    if ([string]::IsNullOrWhiteSpace($ModelName)) {
        return
    }

    $classification = Get-ProviderModelClassification -ProviderConfig $ProviderConfig -ModelName $ModelName

    if ($classification -eq "blocked") {
        if (($ModelName -eq "auto" -or $ModelName -eq "Auto") -and $AllowAuto) {
            return
        }
        throw "$ProviderName model '$ModelName' is blocked by policy. Use an explicit allowed model from codex-praetor-tiers.json."
    }

    if ($classification -eq "allowed") {
        return
    }

    if ($classification -eq "known_not_default") {
        if ($AllowKnownButNotDefault) {
            return
        }
        throw "$ProviderName model '$ModelName' is known but not default-routable. Use -AllowExpensiveModel only when the user explicitly accepts this fallback."
    }

    if ($AllowUnknown) {
        return
    }

    $allowed = (@($ProviderConfig.allowedModels) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) -join ", "
    throw "$ProviderName model '$ModelName' is not in the allowed model list. Allowed models: $allowed. Update codex-praetor-tiers.json with evidence or pass -AllowUnlistedModel only for an intentional manual probe."
}

function Assert-ReasoningPolicy {
    param(
        [string]$Effort,
        [bool]$AllowExtreme
    )

    if ([string]::IsNullOrWhiteSpace($Effort)) {
        return
    }

    $cap = [string]$config.policy.maxReasoningEffortWithoutApproval
    $effortRank = Get-EffortRank -Value $Effort
    $capRank = Get-EffortRank -Value $cap

    if ($effortRank -gt $capRank -and -not $AllowExtreme) {
        throw "Reasoning effort '$Effort' exceeds the default approval cap '$cap'. Use -AllowExtremeReasoning only when the user explicitly accepts the extra cost/latency."
    }
}

function Assert-KnownCodeBuddyModel {
    param(
        [object]$ProviderConfig,
        [string]$ModelName
    )

    $policyModels = @($ProviderConfig.allowedModels)
    if ($policyModels.Count -gt 0) {
        $allowedModels = @($policyModels | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
    } else {
        $knownModels = @($ProviderConfig.knownSupportedModels)
        $trustedExtraModels = @($ProviderConfig.trustedExtraModels | ForEach-Object { $_.modelCli })
        $allowedModels = @($knownModels + $trustedExtraModels | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
    }
    if ($allowedModels.Count -eq 0 -or [string]::IsNullOrWhiteSpace($ModelName)) {
        return
    }

    if ($allowedModels -notcontains $ModelName) {
        $allowed = ($allowedModels -join ", ")
        throw "CodeBuddy model '$ModelName' is not in the allowed CodeBuddy model list. Allowed models: $allowed. Use -ModelOverride with an allowed model, update codex-praetor-tiers.json after checking local/official evidence, or pass -AllowUnlistedModel if you intentionally accept provider fallback risk."
    }
}

function Assert-CodeBuddyModelPolicy {
    param(
        [object]$ProviderConfig,
        [string]$ModelName,
        [bool]$AllowAuto
    )

    if ([string]::IsNullOrWhiteSpace($ModelName)) {
        return
    }

    $blockedModels = @($ProviderConfig.blockedModels)
    if ($blockedModels -contains $ModelName) {
        if ($ModelName -eq "auto" -and $AllowAuto) {
            return
        }

        throw "CodeBuddy model '$ModelName' is blocked by policy. Use an explicit fixed model from codex-praetor-tiers.json. The 'auto' model is disabled by default because it lets CodeBuddy choose or switch the backend model."
    }
}

function Invoke-Or-StartWorker {
    param(
        [string]$Exe,
        [object[]]$ArgumentList,
        [string]$WorkingDirectory,
        [string]$ProviderName,
        [string]$TierName,
        [string]$ModelName,
        [string]$PriceNote,
        [string]$ReasoningEffortName = "",
        [string]$AgentName = "",
        [int]$ContextWindowSize = 0,
        [string]$PermissionProfileName = "",
        [string]$OutputFormatName = "",
        [string]$ProfileRoot = "",
        [string]$StructuredOutput = "",
        [string]$ModelPolicy = "",
        [string]$TaskKindName = "local_audit",
        [string]$ContractPath = "",
        [string]$ContractHash = "",
        [string]$RequestedJobId = "",
        [int]$WorkerTimeoutSeconds = 1200,
        [string]$DependencyBootstrap = "not_required"
    )

    $commandLine = Join-CommandLine $Exe $ArgumentList
    Write-Output "provider=$ProviderName"
    Write-Output "tier=$TierName"
    Write-Output "model=$ModelName"
    if (-not [string]::IsNullOrWhiteSpace($ModelPolicy)) { Write-Output "model_policy=$ModelPolicy" }
    if (-not [string]::IsNullOrWhiteSpace($ReasoningEffortName)) { Write-Output "reasoning_effort=$ReasoningEffortName" }
    if (-not [string]::IsNullOrWhiteSpace($AgentName)) { Write-Output "agent=$AgentName" }
    if ($ContextWindowSize -gt 0) { Write-Output "context_window=$ContextWindowSize" }
    if (-not [string]::IsNullOrWhiteSpace($PermissionProfileName)) { Write-Output "permission_profile=$PermissionProfileName" }
    if (-not [string]::IsNullOrWhiteSpace($OutputFormatName)) { Write-Output "output_format=$OutputFormatName" }
    if (-not [string]::IsNullOrWhiteSpace($ProfileRoot)) { Write-Output "profile_root=$ProfileRoot" }
    if (-not [string]::IsNullOrWhiteSpace($StructuredOutput)) { Write-Output "structured_output=$StructuredOutput" }
    Write-Output "continuation_disabled=true"
    Write-Output "project_artifact_root=$ProjectArtifactRoot"
    Write-Output "job_root=$JobRoot"
    Write-Output "lock_root=$LockRoot"
    Write-Output "plan_root=$PlanRoot"
    Write-Output "scratch_root=$ScratchRoot"
    Write-Output "price_note=$PriceNote"
    Write-Output "run_mode=$RunMode"
    Write-Output "task_kind=$TaskKindName"
    Write-Output "dependency_bootstrap=$DependencyBootstrap"
    Write-Output ("worker_network=" + $(if ($AllowWorkerNetwork) { "allowed_by_codex" } else { "forbidden" }))
    if (-not [string]::IsNullOrWhiteSpace($ContractHash)) { Write-Output "contract_hash=$ContractHash" }
    Write-Output "timeout_seconds=$WorkerTimeoutSeconds"
    Write-Output "command=$commandLine"

    if ($DryRun) {
        exit 0
    }

    $jobId = $RequestedJobId
    if ([string]::IsNullOrWhiteSpace($jobId)) {
        $jobId = New-WorkerJobId -ProviderName $ProviderName -TierName $TierName
    }
    $jobDir = Join-Path $JobRoot $jobId
    $jobScratch = Join-Path $ScratchRoot $jobId
    New-Item -ItemType Directory -Path $jobDir -Force | Out-Null
    New-Item -ItemType Directory -Path $jobScratch -Force | Out-Null
    $stdoutPath = Join-Path $jobDir "stdout.log"
    $stderrPath = Join-Path $jobDir "stderr.log"
    $metaPath = Join-Path $jobDir "job.json"
    $watcherStdoutPath = Join-Path $jobDir "watcher.out.log"
    $watcherStderrPath = Join-Path $jobDir "watcher.err.log"
    $completionPath = Join-Path $jobDir "completion.json"
    $argumentListPath = Join-Path $jobDir "worker-args.json"
    $storedContractPath = Join-Path $jobDir "task-contract.json"
    if (-not [string]::IsNullOrWhiteSpace($ContractPath) -and (Test-Path -LiteralPath $ContractPath -PathType Leaf)) {
        Copy-Item -LiteralPath $ContractPath -Destination $storedContractPath -Force
        $ContractPath = $storedContractPath
    }

    $meta = [ordered]@{
        job_id = $jobId
        provider = $ProviderName
        tier = $TierName
        model = $ModelName
        price_note = $PriceNote
        model_policy = $ModelPolicy
        reasoning_effort = $ReasoningEffortName
        agent = $AgentName
        context_window = $ContextWindowSize
        permission_profile = $PermissionProfileName
        output_format = $OutputFormatName
        profile_root = $ProfileRoot
        structured_output = $StructuredOutput
        repo = $Repo
        execution_repo = $WorkingDirectory
        job_root = $JobRoot
        lock_root = $LockRoot
        scratch_root = $ScratchRoot
        job_scratch = $jobScratch
        plan_id = $PlanId
        task_id = $TaskId
        depends_on = $DependsOn
        acceptance = $Acceptance
        plan_root = $PlanRoot
        mode = $Mode
        task_kind = $TaskKindName
        dependency_bootstrap = $DependencyBootstrap
        task_contract = $ContractPath
        task_contract_schema = [string]$runtimeContract.taskContractSchema
        generation_id = [string]$generation.generation_id
        runtime_contract_sha256 = $runtimeContractHash
        wrapper_protocol = [string]$runtimeContract.wrapperProtocol
        provider_tuple = [ordered]@{ provider = $ProviderName; cli_path = $Exe; model = $ModelName; permission_profile = $PermissionProfileName; output_format = $OutputFormatName; task_kind = $TaskKindName }
        contract_hash = $ContractHash
        run_mode = $RunMode
        status = "starting"
        created_at = (Get-Date).ToString("o")
        deadline_at = (Get-Date).AddSeconds($WorkerTimeoutSeconds).ToString("o")
        timeout_seconds = $WorkerTimeoutSeconds
        stdout = $stdoutPath
        stderr = $stderrPath
        completion = $completionPath
        lock_path = $repoEditLockPath
        notify_thread_id = $NotifyThreadId
        notify_workspace = $NotifyWorkspace
        notify_enabled = (-not $NoNotify -and -not [string]::IsNullOrWhiteSpace($NotifyThreadId))
        argument_list = $argumentListPath
        command = $commandLine
        events = @()
        status_note = "Durable job created. The watcher starts the worker and waits for process exit without log polling."
    }

    $meta | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $metaPath -Encoding UTF8
    $meta["watcher_stdout"] = $watcherStdoutPath
    $meta["watcher_stderr"] = $watcherStderrPath
    $ArgumentList | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $argumentListPath -Encoding UTF8
    $meta | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $metaPath -Encoding UTF8

    $watcherScript = Join-Path $scriptDir "watch-codex-praetor-job.ps1"
    if (-not (Test-Path -LiteralPath $watcherScript)) {
        throw "Missing watcher script: $watcherScript"
    }
    $watcherArgs = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $watcherScript,
        "-JobDir", $jobDir,
        "-WorkerPid", "0",
        "-StartWorker",
        "-Exe", $Exe,
        "-ArgumentListPath", $argumentListPath,
        "-WorkingDirectory", $WorkingDirectory,
        "-StdoutPath", $stdoutPath,
        "-StderrPath", $stderrPath,
        "-TimeoutSeconds", "$WorkerTimeoutSeconds"
    )
    if (-not [string]::IsNullOrWhiteSpace($repoEditLockPath)) {
        $watcherArgs += @("-LockPath", $repoEditLockPath)
    }
    if (-not [string]::IsNullOrWhiteSpace($NotifyThreadId)) {
        $watcherArgs += @("-NotifyThreadId", $NotifyThreadId)
    }
    if (-not [string]::IsNullOrWhiteSpace($NotifyWorkspace)) {
        $watcherArgs += @("-NotifyWorkspace", $NotifyWorkspace)
    }
    if ($NoNotify -or [string]::IsNullOrWhiteSpace($NotifyThreadId)) {
        $watcherArgs += "-NoNotify"
    }
    $watcherArgumentLine = ($watcherArgs | ForEach-Object { Quote-Arg ([string]$_) }) -join " "
    $watcher = Start-Process -FilePath "powershell" -ArgumentList $watcherArgumentLine -WindowStyle Hidden -RedirectStandardOutput $watcherStdoutPath -RedirectStandardError $watcherStderrPath -PassThru
    Update-RepoEditLockHolder -LockPath $repoEditLockPath -JobId $jobId -HolderPid $watcher.Id -HolderKind "watcher"
    $meta["watcher_pid"] = $watcher.Id
    $meta | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $metaPath -Encoding UTF8

    if (-not [string]::IsNullOrWhiteSpace($PlanId) -and -not [string]::IsNullOrWhiteSpace($TaskId)) {
        $planScript = Join-Path $scriptDir "manage-codex-praetor-plan.ps1"
        if (Test-Path -LiteralPath $planScript) {
            $planArgs = @(
                "-NoProfile",
                "-ExecutionPolicy", "Bypass",
                "-File", $planScript,
                "-Action", "UpsertTask",
                "-PlanId", $PlanId,
                "-PlanRoot", $PlanRoot,
                "-TaskId", $TaskId,
                "-Status", "running",
                "-JobId", $jobId,
                "-JobDir", $jobDir,
                "-Provider", $ProviderName,
                "-Tier", $TierName,
                "-Model", $ModelName,
                "-Mode", $Mode,
                "-CompletionPath", $completionPath
            )
            if (-not [string]::IsNullOrWhiteSpace($DependsOn)) {
                $planArgs += @("-DependsOn", $DependsOn)
            }
            if (-not [string]::IsNullOrWhiteSpace($Acceptance)) {
                $planArgs += @("-Acceptance", $Acceptance)
            }
            & powershell @planArgs | Out-Null
        }
    }

    Write-Output "job_id=$jobId"
    Write-Output "pid=pending"
    Write-Output "watcher_pid=$($watcher.Id)"
    Write-Output "job_dir=$jobDir"
    Write-Output "stdout=$stdoutPath"
    Write-Output "stderr=$stderrPath"
    Write-Output "completion=$completionPath"
    if ($RunMode -eq "blocking") {
        $waitMs = [Math]::Min([int64]$WorkerTimeoutSeconds * 1000 + 30000, [int64]2147483647)
        if (-not $watcher.WaitForExit([int]$waitMs)) {
            throw "Watcher did not finish before the worker timeout envelope for job $jobId."
        }
        $completion = Read-JsonOrNull -Path $completionPath
        if ($null -eq $completion) {
            throw "Blocking job exited without completion metadata: $jobId"
        }
        Write-Output "completion_status=$($completion.status)"
        if ([string]$completion.status -notin @("process_exited", "cancelled")) {
            exit 1
        }
    }
    exit 0
}

if (-not (Test-Path -LiteralPath $Repo)) {
    throw "Repo/path does not exist: $Repo"
}

if ([string]::IsNullOrWhiteSpace($TaskKind)) {
    if ($Mode -eq "edit") {
        $TaskKind = "code_change"
    } else {
        $TaskKind = "local_audit"
    }
}
if ($TaskKind -eq "external_research" -and $Mode -ne "readonly") {
    throw "external_research requires -Mode readonly. Codex/KR remains the primary evidence authority."
}
if ($TaskKind -eq "external_research" -and -not $AllowWorkerNetwork) {
    throw "external_research requires -AllowWorkerNetwork and a Codex-approved research contract."
}
$researchContract = $null
if ($TaskKind -eq "external_research") {
    if ([string]::IsNullOrWhiteSpace($ResearchContractJson)) {
        throw "external_research requires -ResearchContractJson from Codex."
    }
    try {
        $researchContract = $ResearchContractJson | ConvertFrom-Json
    } catch {
        throw "ResearchContractJson is not valid JSON."
    }
    if ([string]$researchContract.research_authority -ne "codex_kr_primary" -or [string]$researchContract.evidence_acceptance -ne "supervisor_verified") {
        throw "external_research requires codex_kr_primary authority and supervisor_verified evidence acceptance."
    }
    if (@($researchContract.claim_scope).Count -eq 0 -or @($researchContract.source_scope).Count -eq 0) {
        throw "external_research requires non-empty claim_scope and source_scope."
    }
}
if ($TaskKind -eq "code_change" -and $Mode -ne "edit") {
    throw "code_change requires -Mode edit so the worker contract cannot be mistaken for a readonly audit."
}
if ($TaskKind -eq "code_change" -and [string]::IsNullOrWhiteSpace($TaskMaterialJson)) {
    throw "code_change requires immutable task material; dispatch is blocked before worker launch."
}
if ($TaskKind -eq "test_execution" -and $Mode -ne "readonly") {
    throw "test_execution requires -Mode readonly. It may run only the declared checks and must not receive edit tools."
}

$ProjectArtifactRoot = Get-ProjectArtifactRoot -RepoPath $Repo
if ([string]::IsNullOrWhiteSpace($JobRoot)) {
    $JobRoot = Join-Path $ProjectArtifactRoot "jobs"
}
if ([string]::IsNullOrWhiteSpace($LockRoot)) {
    $LockRoot = Join-Path $ProjectArtifactRoot "locks"
}
if ([string]::IsNullOrWhiteSpace($PlanRoot)) {
    $PlanRoot = Join-Path $ProjectArtifactRoot "plans"
}
if ([string]::IsNullOrWhiteSpace($ScratchRoot)) {
    $ScratchRoot = Join-Path $ProjectArtifactRoot "scratch"
}

if (-not $DryRun -and -not $CapabilityCanary -and -not $PreflightOnly) {
    $healthScript = Join-Path $scriptDir "get-codex-praetor-health.ps1"
    if (-not (Test-Path -LiteralPath $healthScript -PathType Leaf)) {
        $healthScript = Join-Path $scriptParent "verify\get-codex-praetor-health.ps1"
    }
    if (Test-Path -LiteralPath $healthScript -PathType Leaf) {
        $healthArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $healthScript, "-Repo", $Repo, "-Channel", $RuntimeChannel, "-Json")
        if (-not [string]::IsNullOrWhiteSpace($UserProfileRoot)) {
            $healthArgs += @("-UserProfileRoot", [System.IO.Path]::GetFullPath($UserProfileRoot))
        }
        $null = & powershell @healthArgs 2>$null
        if ($LASTEXITCODE -eq 2) {
            throw "Runtime generation health is blocked. Repair the installed plugin/Skill/cache generation in the selected profile before real dispatch."
        }
    }
}

if ([string]::IsNullOrWhiteSpace($Tier)) {
    if ($Provider -eq "qoder") {
        if (Test-OffPeak) { $Tier = "qoder-night-cheap" } else { $Tier = "qoder-day-cheap" }
    } elseif ($Provider -eq "codebuddy") {
        $Tier = "codebuddy-free"
    } elseif ($PreferQoder) {
        if (Test-OffPeak) { $Tier = $config.policy.defaultNightTier } else { $Tier = $config.policy.defaultPreferQoderDayTier }
    } else {
        if (Test-OffPeak) { $Tier = $config.policy.defaultNightTier } else { $Tier = $config.policy.defaultDayTier }
    }
}

$tierConfig = $config.tiers.$Tier
if ($null -eq $tierConfig) {
    $known = ($config.tiers.PSObject.Properties.Name -join ", ")
    throw "Unknown tier '$Tier'. Known tiers: $known"
}

$resolvedProvider = [string]$tierConfig.provider
if ($Provider -ne "auto" -and $Provider -ne $resolvedProvider) {
    throw "Provider '$Provider' does not match tier '$Tier' provider '$resolvedProvider'"
}

if ($resolvedProvider -eq "qoder") {
    $gitRoot = $null
    try {
        $gitRoot = & git -C $Repo rev-parse --show-toplevel 2>$null
    } catch {
        $gitRoot = $null
    }
    if ([string]::IsNullOrWhiteSpace($gitRoot)) {
        $message = "Qoder CLI failed in prior probes outside a git worktree. Use a git repo path or choose CodeBuddy/Codex for this folder: $Repo"
        if ($DryRun) {
            Write-Warning $message
        } else {
            throw $message
        }
    }
}

$requiresWorkerWorktree = $true

$model = [string]$tierConfig.modelCli
if (-not [string]::IsNullOrWhiteSpace($ModelOverride)) {
    $model = $ModelOverride
}

$providerConfig = $config.providers.$resolvedProvider
if ($null -eq $providerConfig) {
    throw "Missing provider config for '$resolvedProvider'"
}

$modelPolicy = Get-ProviderModelClassification -ProviderConfig $providerConfig -ModelName $model
Assert-ProviderModelPolicy -ProviderConfig $providerConfig -ProviderName $resolvedProvider -ModelName $model -AllowAuto $AllowAutoModel -AllowKnownButNotDefault $AllowExpensiveModel -AllowUnknown $AllowUnlistedModel

$effectiveReasoningEffort = [string]$tierConfig.reasoningEffort
if (-not [string]::IsNullOrWhiteSpace($ReasoningEffort)) {
    $effectiveReasoningEffort = $ReasoningEffort
}
Assert-ReasoningPolicy -Effort $effectiveReasoningEffort -AllowExtreme $AllowExtremeReasoning

$effectiveContextWindow = 0
if ($null -ne $tierConfig.contextWindow) {
    $effectiveContextWindow = [int]$tierConfig.contextWindow
}
if ($ContextWindow -gt 0) {
    $effectiveContextWindow = $ContextWindow
}

$effectiveAgent = [string]$tierConfig.agent
if (-not [string]::IsNullOrWhiteSpace($Agent)) {
    $effectiveAgent = $Agent
}

$effectivePermissionProfile = [string]$tierConfig.permissionProfile
if (-not [string]::IsNullOrWhiteSpace($PermissionProfile)) {
    $effectivePermissionProfile = $PermissionProfile
} elseif ($TaskKind -eq "code_change") {
    $effectivePermissionProfile = "edit-worktree-v1"
} elseif ($TaskKind -eq "local_audit") {
    $effectivePermissionProfile = "local-audit-v1"
} elseif ($TaskKind -eq "test_execution") {
    $effectivePermissionProfile = "test-execution-v1"
} elseif ($TaskKind -eq "external_research") {
    $effectivePermissionProfile = "external-research-support-v1"
}

$effectiveOutputFormat = [string]$tierConfig.outputFormat
if ([string]::IsNullOrWhiteSpace($effectiveOutputFormat)) {
    $effectiveOutputFormat = [string]$providerConfig.defaultOutputFormat
}
if (-not [string]::IsNullOrWhiteSpace($OutputFormat)) {
    $effectiveOutputFormat = $OutputFormat
}
if ([string]::IsNullOrWhiteSpace($effectiveOutputFormat)) {
    $effectiveOutputFormat = "text"
}

$providerCliPath = ""
if ($resolvedProvider -eq "qoder") {
    $providerCliPath = [string]$config.providers.qoder.cliPath
} elseif ($resolvedProvider -eq "codebuddy") {
    $providerCliPath = [string]$config.providers.codebuddy.cliPath
}
$providerReadinessPath = if ([string]::IsNullOrWhiteSpace($ReadinessPath)) {
    Join-Path $env:USERPROFILE ".codex\codex-praetor-readiness.json"
} else {
    [System.IO.Path]::GetFullPath($ReadinessPath)
}
if (-not $DryRun -and -not $CapabilityCanary -and -not $PreflightOnly) {
    $readiness = Test-ProviderReadiness -ReadinessPath $providerReadinessPath -ProviderName $resolvedProvider -CliPath $providerCliPath -ModelName $model -PermissionProfileName $effectivePermissionProfile -TaskKindName $TaskKind
    if (-not $readiness.ok) {
        throw "Provider readiness gate blocked '$resolvedProvider': $($readiness.reason) Run test-provider-capability-canary.ps1 for the exact provider tuple first."
    }
}

$dispatchJobId = New-WorkerJobId -ProviderName $resolvedProvider -TierName $Tier
if ($requiresWorkerWorktree -and [string]::IsNullOrWhiteSpace($WorktreeName)) {
    $safeTier = $Tier -replace '[^A-Za-z0-9_-]', '-'
    $WorktreeName = "cw-$safeTier-$($dispatchJobId.Split('-')[-1])"
}

$repoEditLockPath = Acquire-RepoEditLock -RepoPath $Repo -ProviderName $resolvedProvider -TierName $Tier

$executionRepo = $Repo
try {
    if ($requiresWorkerWorktree -and -not [string]::IsNullOrWhiteSpace($WorktreeName)) {
        if ($DryRun) {
            $executionRepo = Get-WorkerWorktreePath -RepoPath $Repo -Name $WorktreeName
        } else {
            $executionRepo = Ensure-WorkerWorktree -RepoPath $Repo -Name $WorktreeName
        }
    }
    $taskMaterial = if ([string]::IsNullOrWhiteSpace($TaskMaterialJson)) { $null } else { ConvertTo-TaskMaterial -Json $TaskMaterialJson }
    $taskMaterialEvidence = $null
    if ($null -ne $taskMaterial) {
        if ($DryRun) {
            Test-TaskMaterialSource -Material $taskMaterial
            $taskMaterialEvidence = [ordered]@{ schema = [string]$taskMaterial.schema; destination = (Get-SafeRelativePath -PathValue ([string]$taskMaterial.destination)).Replace('\\', '/'); write_set = @($taskMaterial.write_set); immutable_paths = @($taskMaterial.immutable_paths); baseline_command = [string]$taskMaterial.baseline_command; baseline_exit_code = [int]$taskMaterial.baseline_exit_code; files = @($taskMaterial.files); manifest_sha256 = [string]$taskMaterial.manifest_sha256; preflight = 'validated_dry_run' }
        } else {
            $taskMaterialEvidence = Inject-TaskMaterial -Material $taskMaterial -ExecutionRoot $executionRepo
        }
    }
    $dependencyBootstrap = if ($DryRun) { if ($TaskKind -eq "code_change") { "mcp_npm_ci_if_mcp_lock_present" } else { "not_required" } } else { Initialize-WorkerDependencyBootstrap -WorkingDirectory $executionRepo -TaskKindName $TaskKind }

    $contract = [ordered]@{
        schema = [string]$runtimeContract.taskContractSchema
        job_id = $dispatchJobId
        generation_id = [string]$generation.generation_id
        runtime_contract_sha256 = $runtimeContractHash
        wrapper_protocol = [string]$runtimeContract.wrapperProtocol
        task_kind = $TaskKind
        repo = (Resolve-Path -LiteralPath $Repo).Path
        execution_worktree = $executionRepo
        provider = $resolvedProvider
        tier = $Tier
        model = $model
        permission_profile = $effectivePermissionProfile
        mode = $Mode
        allowed_paths = @($AllowedPath)
        forbidden_paths = @($ForbiddenPath)
        required_checks = @($RequiredCheck)
        budget = if ([string]::IsNullOrWhiteSpace($BudgetJson)) { $null } else { $BudgetJson | ConvertFrom-Json }
        failure_injection = $FailureInjection
        sensitivity = $Sensitivity
        task_material = $taskMaterialEvidence
        worker_network = if ($AllowWorkerNetwork) { "allowed_by_codex" } else { "forbidden" }
        research_contract = $researchContract
        acceptance = $Acceptance
        timeout_seconds = $TimeoutSeconds
        dependency_bootstrap = $dependencyBootstrap
        created_at = (Get-Date).ToString("o")
    }
    $contractJson = $contract | ConvertTo-Json -Depth 12
    $contractHash = Get-TextSha256 -Text $contractJson
    $contractPath = Join-Path $ScratchRoot "$dispatchJobId.contract.json"
    if (-not $DryRun) {
        New-Item -ItemType Directory -Path $ScratchRoot -Force | Out-Null
        Set-Content -LiteralPath $contractPath -Value $contractJson -Encoding UTF8
    }

    if ($PreflightOnly) {
        Write-Output "preflight=passed"
        Write-Output "execution_worktree=$executionRepo"
        Write-Output "contract_path=$contractPath"
        Write-Output "task_material_manifest_sha256=$($taskMaterialEvidence.manifest_sha256)"
        return
    }

    $networkRule = if ($AllowWorkerNetwork) {
        "- External network access is allowed for this task. Use existing official CLI login state when needed, but never read, print, move, or modify authentication files, tokens, cookies, caches, or provider databases."
    } else {
        "- Do not perform external network research. Codex owns KnowledgeRadar and all external evidence collection."
    }

    $supervisedTask = @"
TASK:
$Task

You are a worker agent under Codex supervision. Complete the TASK above directly.
Do not ask follow-up questions. Do not call memory, history, task, or question-style tools for this packet.
If the TASK is ambiguous, state the ambiguity in the final output instead of asking Codex or the user.

Role: worker agent. Codex is supervising this task.
Source repo: $Repo
Execution worktree: $executionRepo
Project artifact root: $ProjectArtifactRoot
Scratch root: $ScratchRoot
Mode: $Mode
Task kind: $TaskKind
Contract hash: $contractHash
Plan id: $PlanId
Task id: $TaskId
Depends on: $DependsOn
Acceptance target: $Acceptance
Allowed paths: $(@($AllowedPath) -join ', ')
Forbidden paths: $(@($ForbiddenPath) -join ', ')
Required checks: $(@($RequiredCheck) -join ' | ')
Failure injection: $FailureInjection
Task material destination: $(if ($null -eq $taskMaterialEvidence) { '' } else { [string]$taskMaterialEvidence.destination })
Declared write set: $(if ($null -eq $taskMaterialEvidence) { '' } else { @($taskMaterialEvidence.write_set) -join ', ' })

Rules:
- Complete only this task.
$networkRule
- You may read, search, edit, and run only the actions necessary for the task contract inside this worktree.
- For code_change, repair the supplied material only. Do not replace tests, alter immutable files, or create your own test harness.
- For test_execution, run only the declared required checks. Do not edit or create source files; report each check's exit code exactly.
- Do not touch auth files, application caches, internal databases, unrelated reports, or unrelated source files.
- Put scratch files, downloaded references, generated plans, and temporary outputs only under the execution worktree or the project artifact root unless Codex explicitly allowed another path.
- Do not pause for progress reports. Work autonomously until this task is complete, blocked, or unsafe.
- Keep output concise and include: what you did, files read/changed, checks run, and risks/unknowns.
"@

    if ($resolvedProvider -eq "qoder") {
        $qoder = $config.providers.qoder.cliPath
        if (-not (Test-Path -LiteralPath $qoder)) {
            throw "Qoder CLI not found: $qoder"
        }

        $cmdArgs = @("-w", $executionRepo, "--model", $model, "--max-output-tokens", "4000", "--output-format", $effectiveOutputFormat)
        if (-not [string]::IsNullOrWhiteSpace($effectiveReasoningEffort)) {
            $cmdArgs += @("--reasoning-effort", $effectiveReasoningEffort)
        }
        if ($effectiveContextWindow -gt 0) {
            $cmdArgs += @("--context-window", "$effectiveContextWindow")
        }
        if (-not [string]::IsNullOrWhiteSpace($effectiveAgent)) {
            $cmdArgs += @("--agent", $effectiveAgent)
        }
        $cmdArgs += "--permission-mode"
        if ($TaskKind -eq "test_execution") {
            $cmdArgs += @("dont_ask", "--tools", "Read", "Grep", "Glob", "Bash")
        } elseif ($Mode -eq "readonly") {
            $cmdArgs += @("dont_ask", "--tools", "Read", "Grep", "Glob")
        } else {
            $cmdArgs += @("bypass_permissions", "--tools", "Read", "Grep", "Glob", "Edit", "Write", "Bash")
        }
        $cmdArgs += @("-p", $supervisedTask)

        Invoke-Or-StartWorker -Exe $qoder -ArgumentList $cmdArgs -WorkingDirectory $executionRepo -ProviderName "qoder" -TierName $Tier -ModelName $model -PriceNote $tierConfig.creditMultiplier -ReasoningEffortName $effectiveReasoningEffort -AgentName $effectiveAgent -ContextWindowSize $effectiveContextWindow -PermissionProfileName $effectivePermissionProfile -OutputFormatName $effectiveOutputFormat -ModelPolicy $modelPolicy -TaskKindName $TaskKind -ContractPath $contractPath -ContractHash $contractHash -RequestedJobId $dispatchJobId -WorkerTimeoutSeconds $TimeoutSeconds -DependencyBootstrap $dependencyBootstrap
    }

    if ($resolvedProvider -eq "codebuddy") {
        Import-EnvFromPersistentScopes -Names @(
            "CODEBUDDY_API_KEY",
            "CODEBUDDY_AUTH_TOKEN",
            "CODEBUDDY_BASE_URL",
            "CODEBUDDY_INTERNET_ENVIRONMENT"
        )

        $node = $config.providers.codebuddy.nodePath
        $codebuddy = $config.providers.codebuddy.cliPath
        if (-not (Test-Path -LiteralPath $codebuddy)) {
            throw "CodeBuddy CLI not found: $codebuddy"
        }

        $cmdArgs = @($codebuddy, "--model", $model, "--max-turns", "$MaxTurns", "--output-format", $effectiveOutputFormat)
        if (-not [string]::IsNullOrWhiteSpace($effectiveReasoningEffort)) {
            $cmdArgs += @("--effort", $effectiveReasoningEffort)
        }
        if (-not [string]::IsNullOrWhiteSpace($effectiveAgent)) {
            $cmdArgs += @("--agent", $effectiveAgent)
        }
        if (-not [string]::IsNullOrWhiteSpace($JsonSchema)) {
            $cmdArgs += @("--json-schema", $JsonSchema)
        }
        if ($TaskKind -eq "test_execution") {
            $cmdArgs += @("-y", "--tools", "Read,Glob,Grep,Bash")
        } elseif ($Mode -eq "readonly") {
            # CodeBuddy's current CLI does not accept the historical dontAsk
            # mode. In headless runs, -y supplies the non-interactive approval
            # and --tools is the complete built-in-tool allowlist.
            $cmdArgs += @("-y", "--tools", "Read,Glob,Grep")
        } else {
            $cmdArgs += @("-y", "--tools", "Read,Glob,Grep,Edit,Write,Bash")
        }
        $cmdArgs += @("-p", $supervisedTask)

        $structured = ""
        if (-not [string]::IsNullOrWhiteSpace($JsonSchema)) { $structured = "json_schema" }
        Invoke-Or-StartWorker -Exe $node -ArgumentList $cmdArgs -WorkingDirectory $executionRepo -ProviderName "codebuddy" -TierName $Tier -ModelName $model -PriceNote $tierConfig.creditMultiplier -ReasoningEffortName $effectiveReasoningEffort -AgentName $effectiveAgent -ContextWindowSize $effectiveContextWindow -PermissionProfileName $effectivePermissionProfile -OutputFormatName $effectiveOutputFormat -StructuredOutput $structured -ModelPolicy $modelPolicy -TaskKindName $TaskKind -ContractPath $contractPath -ContractHash $contractHash -RequestedJobId $dispatchJobId -WorkerTimeoutSeconds $TimeoutSeconds -DependencyBootstrap $dependencyBootstrap
    }

} finally {
    if ($RunMode -eq "blocking" -or $DryRun) {
        Release-RepoEditLock -LockPath $repoEditLockPath
    }
}

throw "Unsupported provider: $resolvedProvider"
