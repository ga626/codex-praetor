param(
    [ValidateSet("auto", "qoder", "codebuddy", "mimo")]
    [string]$Provider = "auto",

    [string]$Tier = "",

    [string]$ConfigPath = "",

    [Parameter(Mandatory = $true)]
    [string]$Repo,

    [Parameter(Mandatory = $true)]
    [string]$Task,

    [ValidateSet("readonly", "edit")]
    [string]$Mode = "readonly",

    [ValidateSet("", "local_audit", "code_change", "external_research")]
    [string]$TaskKind = "",

    [ValidateSet("blocking", "background")]
    [string]$RunMode = "blocking",

    [switch]$DryRun,

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

    [string]$DependsOn = "",

    [string]$Acceptance = "",

    [string]$PlanRoot = "",

    [string]$ScratchRoot = "",

    [switch]$NoNotify,

    [string[]]$AllowedPath = @(),

    [string[]]$ForbiddenPath = @(".git/**", ".env*", "auth/**", "node_modules/**"),

    [switch]$AllowWorkerNetwork,

    [switch]$CapabilityCanary
)

$ErrorActionPreference = "Stop"
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
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
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

    $state = Read-JsonOrNull -Path $ReadinessPath
    if ($null -eq $state -or $null -eq $state.entries) {
        return [ordered]@{ ok = $false; reason = "No capability canary record exists."; cli_hash = (Get-FileSha256OrEmpty -Path $CliPath) }
    }

    $cliHash = Get-FileSha256OrEmpty -Path $CliPath
    $now = Get-Date
    foreach ($entry in @($state.entries)) {
        if ([string]$entry.status -ne "passed") { continue }
        if ([string]$entry.provider -ne $ProviderName) { continue }
        if ([string]$entry.cli_path -ne $CliPath) { continue }
        if ([string]$entry.cli_hash -ne $cliHash) { continue }
        if ([string]$entry.model -ne $ModelName) { continue }
        if ([string]$entry.permission_profile -ne $PermissionProfileName) { continue }
        if ([string]$entry.task_kind -ne $TaskKindName) { continue }
        if ([string]::IsNullOrWhiteSpace([string]$entry.expires_at)) { continue }
        if ([DateTime]::Parse([string]$entry.expires_at) -le $now) { continue }
        return [ordered]@{ ok = $true; reason = "Matching capability canary is current."; cli_hash = $cliHash; entry = $entry }
    }
    return [ordered]@{ ok = $false; reason = "No current canary matches this provider tuple."; cli_hash = $cliHash }
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
    if ([string]::IsNullOrWhiteSpace($baseBranch)) {
        throw "Cannot create worker worktree from a detached HEAD or non-branch checkout: $RepoPath"
    }

    $worktreePath = Get-WorkerWorktreePath -RepoPath $RepoPath -Name $Name
    if (Test-Path -LiteralPath $worktreePath) {
        throw "Worker worktree path already exists: $worktreePath"
    }

    $branchName = "cw-$Name"
    $existingBranch = & git -C $RepoPath branch --list $branchName 2>$null
    New-Item -ItemType Directory -Path (Split-Path -Parent $worktreePath) -Force | Out-Null

    if ([string]::IsNullOrWhiteSpace($existingBranch)) {
        & git -C $RepoPath worktree add -b $branchName $worktreePath $baseBranch | Out-Null
    } else {
        & git -C $RepoPath worktree add $worktreePath $branchName | Out-Null
    }

    if ($LASTEXITCODE -ne 0) {
        throw "git worktree add failed for $worktreePath"
    }

    return $worktreePath
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
        [int]$WorkerTimeoutSeconds = 1200
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
        task_contract = $ContractPath
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
        if ([string]$completion.status -ne "completed") {
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
if ($TaskKind -eq "external_research") {
    throw "external_research must stay with Codex and KnowledgeRadar. Do not dispatch external network research to a provider worker."
}
if ($TaskKind -eq "code_change" -and $Mode -ne "edit") {
    throw "code_change requires -Mode edit so the worker contract cannot be mistaken for a readonly audit."
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

if (-not $DryRun -and -not $CapabilityCanary) {
    $healthScript = Join-Path $scriptDir "get-codex-praetor-health.ps1"
    if (-not (Test-Path -LiteralPath $healthScript -PathType Leaf)) {
        $healthScript = Join-Path $scriptParent "verify\get-codex-praetor-health.ps1"
    }
    if (Test-Path -LiteralPath $healthScript -PathType Leaf) {
        $null = & powershell -NoProfile -ExecutionPolicy Bypass -File $healthScript -Repo $Repo -Json 2>$null
        if ($LASTEXITCODE -eq 2) {
            throw "Runtime generation health is blocked. Repair the installed plugin/Skill/cache generation before real dispatch."
        }
    }
}

if ([string]::IsNullOrWhiteSpace($Tier)) {
    if ($Provider -eq "qoder") {
        if (Test-OffPeak) { $Tier = "qoder-night-cheap" } else { $Tier = "qoder-day-cheap" }
    } elseif ($Provider -eq "codebuddy") {
        $Tier = "codebuddy-free"
    } elseif ($Provider -eq "mimo") {
        if ($Mode -eq "edit") { $Tier = "mimo-auto-edit" } else { $Tier = "mimo-isolated-audit" }
    } elseif ($PreferQoder) {
        if (Test-OffPeak) { $Tier = $config.policy.defaultNightTier } else { $Tier = $config.policy.defaultPreferQoderDayTier }
    } else {
        if (Test-OffPeak) { $Tier = $config.policy.defaultNightTier } else { $Tier = $config.policy.defaultDayTier }
    }
}

if ($Tier -eq "mimo-auto-readonly") {
    Write-Warning "Tier 'mimo-auto-readonly' is deprecated. Using 'mimo-isolated-audit'; MiMo audit is isolated, not advertised as filesystem-readonly."
    $Tier = "mimo-isolated-audit"
}

$tierConfig = $config.tiers.$Tier
if ($null -eq $tierConfig -and $Tier -eq "mimo-isolated-audit" -and $null -ne $config.tiers."mimo-auto-readonly") {
    Write-Warning "Local config still uses the legacy MiMo tier key. Reusing its model settings under the new isolated-audit contract."
    $tierConfig = $config.tiers."mimo-auto-readonly"
}
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
} elseif ($TaskKind -eq "code_change" -and $resolvedProvider -ne "mimo") {
    $effectivePermissionProfile = "edit-worktree-v1"
} elseif ($TaskKind -eq "local_audit" -and $resolvedProvider -ne "mimo") {
    $effectivePermissionProfile = "local-audit-v1"
} elseif ($TaskKind -eq "local_audit" -and $resolvedProvider -eq "mimo") {
    $effectivePermissionProfile = "mimo-isolated-audit-v1"
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
} elseif ($resolvedProvider -eq "mimo") {
    $providerCliPath = [string]$config.providers.mimo.cliPath
}
$providerReadinessPath = Join-Path $env:USERPROFILE ".codex\codex-praetor-readiness.json"
if (-not $DryRun -and -not $CapabilityCanary) {
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

    $contract = [ordered]@{
        schema = "codex-praetor-task-contract/v2"
        job_id = $dispatchJobId
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
        worker_network = if ($AllowWorkerNetwork) { "allowed_by_codex" } else { "forbidden" }
        acceptance = $Acceptance
        timeout_seconds = $TimeoutSeconds
        created_at = (Get-Date).ToString("o")
    }
    $contractJson = $contract | ConvertTo-Json -Depth 12
    $contractHash = Get-TextSha256 -Text $contractJson
    $contractPath = Join-Path $ScratchRoot "$dispatchJobId.contract.json"
    if (-not $DryRun) {
        New-Item -ItemType Directory -Path $ScratchRoot -Force | Out-Null
        Set-Content -LiteralPath $contractPath -Value $contractJson -Encoding UTF8
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

Rules:
- Complete only this task.
- Do not perform external network research. Codex owns KnowledgeRadar and all external evidence collection.
- You may read, search, edit, and run only the actions necessary for the task contract inside this worktree.
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
        if ($Mode -eq "readonly") {
            $cmdArgs += @("dont_ask", "--tools", "Read", "Grep", "Glob")
        } else {
            $cmdArgs += @("bypass_permissions", "--tools", "Read", "Grep", "Glob", "Edit", "Write", "Bash")
        }
        $cmdArgs += @("-p", $supervisedTask)

        Invoke-Or-StartWorker -Exe $qoder -ArgumentList $cmdArgs -WorkingDirectory $executionRepo -ProviderName "qoder" -TierName $Tier -ModelName $model -PriceNote $tierConfig.creditMultiplier -ReasoningEffortName $effectiveReasoningEffort -AgentName $effectiveAgent -ContextWindowSize $effectiveContextWindow -PermissionProfileName $effectivePermissionProfile -OutputFormatName $effectiveOutputFormat -ModelPolicy $modelPolicy -TaskKindName $TaskKind -ContractPath $contractPath -ContractHash $contractHash -RequestedJobId $dispatchJobId -WorkerTimeoutSeconds $TimeoutSeconds
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
        if ($Mode -eq "readonly") {
            $cmdArgs += @("--permission-mode", "dontAsk", "--allowedTools", "Read,Glob,Grep", "--disallowedTools", "Bash,Edit,Write,WebFetch")
        } else {
            $cmdArgs += @("--permission-mode", "dontAsk", "--allowedTools", "Read,Glob,Grep,Edit,Write,Bash", "--disallowedTools", "WebFetch")
        }
        $cmdArgs += @("-p", $supervisedTask)

        $structured = ""
        if (-not [string]::IsNullOrWhiteSpace($JsonSchema)) { $structured = "json_schema" }
        Invoke-Or-StartWorker -Exe $node -ArgumentList $cmdArgs -WorkingDirectory $executionRepo -ProviderName "codebuddy" -TierName $Tier -ModelName $model -PriceNote $tierConfig.creditMultiplier -ReasoningEffortName $effectiveReasoningEffort -AgentName $effectiveAgent -ContextWindowSize $effectiveContextWindow -PermissionProfileName $effectivePermissionProfile -OutputFormatName $effectiveOutputFormat -StructuredOutput $structured -ModelPolicy $modelPolicy -TaskKindName $TaskKind -ContractPath $contractPath -ContractHash $contractHash -RequestedJobId $dispatchJobId -WorkerTimeoutSeconds $TimeoutSeconds
    }

    if ($resolvedProvider -eq "mimo") {
        $mimo = $config.providers.mimo.cliPath
        if (-not (Test-Path -LiteralPath $mimo)) {
            throw "MiMo CLI not found: $mimo"
        }

        $mimoProfileRoot = [string]$config.providers.mimo.profileRoot
        if (-not [string]::IsNullOrWhiteSpace($mimoProfileRoot)) {
            [Environment]::SetEnvironmentVariable("MIMOCODE_HOME", $mimoProfileRoot, "Process")
        }

        $mimoOutputFormat = $effectiveOutputFormat
        if ($mimoOutputFormat -eq "text") {
            $mimoOutputFormat = "default"
        }
        if ($mimoOutputFormat -eq "stream-json") {
            $mimoOutputFormat = "json"
        }

        $cmdArgs = @("run", "--model", $model, "--format", $mimoOutputFormat, "--dir", $executionRepo)
        if (-not [string]::IsNullOrWhiteSpace($effectiveAgent)) {
            $cmdArgs += @("--agent", $effectiveAgent)
        }
        if (-not [string]::IsNullOrWhiteSpace($effectiveReasoningEffort)) {
            $cmdArgs += @("--variant", $effectiveReasoningEffort)
        }
        $mimoTaskPacket = ($supervisedTask -replace "\r?\n", " ").Trim()
        $cmdArgs += @($mimoTaskPacket)

        Invoke-Or-StartWorker -Exe $mimo -ArgumentList $cmdArgs -WorkingDirectory $executionRepo -ProviderName "mimo" -TierName $Tier -ModelName $model -PriceNote $tierConfig.creditMultiplier -ReasoningEffortName $effectiveReasoningEffort -AgentName $effectiveAgent -ContextWindowSize $effectiveContextWindow -PermissionProfileName $effectivePermissionProfile -OutputFormatName $mimoOutputFormat -ProfileRoot $mimoProfileRoot -StructuredOutput "json_event_stream" -ModelPolicy $modelPolicy -TaskKindName $TaskKind -ContractPath $contractPath -ContractHash $contractHash -RequestedJobId $dispatchJobId -WorkerTimeoutSeconds $TimeoutSeconds
    }
} finally {
    if ($RunMode -eq "blocking" -or $DryRun) {
        Release-RepoEditLock -LockPath $repoEditLockPath
    }
}

throw "Unsupported provider: $resolvedProvider"
