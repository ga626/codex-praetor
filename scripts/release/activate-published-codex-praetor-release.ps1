param(
    [string]$Version = "0.16.38-alpha",
    [string]$Tag = "",
    [string]$Repository = "ga626/codex-praetor",
    [string]$ReleaseZip = "",
    [string]$ReleaseSha256 = "",
    [string]$CandidateReceiptPath = "",
    [string]$UserProfileRoot = $env:USERPROFILE,
    [string]$CodexCommand = "codex",
    [string]$HostRuntimeInfoPath = "",
    [switch]$AllowExplicitFixture,
    [switch]$DeferPluginCacheRefresh,
    # Default to a durable wait. The helper must not miss a legitimate host
    # restart merely because the maintainer did not exit within 15 minutes.
    [int]$DeferredCacheRefreshWaitSeconds = 0,
    [switch]$SkipMaintenance,
    [switch]$Json
)

$ErrorActionPreference = "Stop"
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) {
    $global:PSNativeCommandUseErrorActionPreference = $false
}
. (Join-Path (Split-Path -Parent $PSScriptRoot) "shared\ensure-file-hash.ps1")
if ([string]::IsNullOrWhiteSpace($Tag)) { $Tag = "v$Version" }
$releaseName = "codex-praetor-setup-$Version"
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-praetor-activate-" + [Guid]::NewGuid().ToString("N"))

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Read-ReleaseGeneration([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Release generation is missing: $Path" }
    $generation = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($name in @("product", "version", "generation_id", "commit", "source_tree", "runtime_contract_sha256")) {
        if ([string]::IsNullOrWhiteSpace([string]$generation.$name)) { throw "Release generation lacks ${name}: $Path" }
    }
    if ([string]$generation.product -ne "codex-praetor") { throw "Unexpected release product: $($generation.product)" }
    if ([string]$generation.version -ne $Version) { throw "Release generation version differs from requested version: $($generation.version)" }
    return $generation
}

function Read-SidecarHash([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Release SHA256 sidecar is missing: $Path" }
    $text = (Get-Content -LiteralPath $Path -Raw -Encoding UTF8).Trim()
    if ($text -notmatch '^(?<hash>[0-9A-Fa-f]{64})(?:\s+\*?.*)?$') { throw "Release SHA256 sidecar is invalid: $Path" }
    return $Matches.hash.ToLowerInvariant()
}

function Invoke-CodexCommandInProfile {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    # Codex CLI resolves its marketplace and cache from the user environment.
    # Keep a candidate activation inside its supplied profile; never let a
    # release fixture silently use the developer's stable Codex state.
    $previous = @{
        USERPROFILE = $env:USERPROFILE
        HOME = $env:HOME
        CODEX_HOME = $env:CODEX_HOME
    }
    try {
        $env:USERPROFILE = $profileRoot
        $env:HOME = $profileRoot
        $env:CODEX_HOME = Join-Path $profileRoot ".codex"
        New-Item -ItemType Directory -Path $env:CODEX_HOME -Force | Out-Null
        $stderrPath = [IO.Path]::GetTempFileName()
        try {
            # A nonzero CLI exit is evidence we must classify below.  The
            # PowerShell shim can otherwise turn its stderr into a terminating
            # NativeCommandError before we can recognize a cache lock.
            $previousErrorActionPreference = $ErrorActionPreference
            $ErrorActionPreference = "Continue"
            try {
                $output = & $CodexCommand @Arguments 2> $stderrPath
                $exitCode = $LASTEXITCODE
            } finally {
                $ErrorActionPreference = $previousErrorActionPreference
            }
            $stderr = if (Test-Path -LiteralPath $stderrPath) { Get-Content -LiteralPath $stderrPath -Raw -Encoding UTF8 } else { "" }
        } finally {
            if (Test-Path -LiteralPath $stderrPath) { Remove-Item -LiteralPath $stderrPath -Force -ErrorAction SilentlyContinue }
        }
    } finally {
        foreach ($name in $previous.Keys) {
            if ($null -eq $previous[$name]) { Remove-Item -LiteralPath ("Env:" + $name) -ErrorAction SilentlyContinue }
            else { Set-Item -LiteralPath ("Env:" + $name) -Value $previous[$name] }
        }
    }
    return [pscustomobject]@{ output = @($output); stderr = $stderr; exit_code = $exitCode }
}

function Resolve-GitHubTagCommit([string]$Repo, [string]$ReleaseTag) {
    $ref = (& gh api "repos/$Repo/git/ref/tags/$ReleaseTag" | ConvertFrom-Json).object
    if ([string]$ref.type -eq "tag") { $ref = (& gh api "repos/$Repo/git/tags/$($ref.sha)" | ConvertFrom-Json).object }
    if ([string]$ref.type -ne "commit" -or [string]$ref.sha -notmatch '^[0-9a-f]{40}$') { throw "GitHub tag $Repo@$ReleaseTag does not resolve to a commit." }
    return ([string]$ref.sha).ToLowerInvariant()
}

function Resolve-GitHubCommitTree([string]$Repo, [string]$Commit) {
    $tree = ((& gh api "repos/$Repo/git/commits/$Commit" | ConvertFrom-Json).tree.sha).ToLowerInvariant()
    if ($tree -notmatch '^[0-9a-f]{40}$') { throw "GitHub commit $Commit does not expose a content tree." }
    return $tree
}

try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    $zipPath = ""
    $shaPath = ""
    $sourceKind = "published_release"
    if (-not [string]::IsNullOrWhiteSpace($ReleaseZip)) {
        if ([string]::IsNullOrWhiteSpace($CandidateReceiptPath) -and -not $AllowExplicitFixture) {
            throw "Explicit local ZIP activation is blocked. Use activate-pr-candidate.ps1 with a PR CI candidate receipt, or pass -AllowExplicitFixture only from a deterministic test fixture."
        }
        $zipPath = [System.IO.Path]::GetFullPath($ReleaseZip)
        $shaPath = if ([string]::IsNullOrWhiteSpace($ReleaseSha256)) { "$zipPath.sha256" } else { [System.IO.Path]::GetFullPath($ReleaseSha256) }
        $sourceKind = "explicit_release_fixture"
    } else {
        if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw "GitHub CLI is required to activate a published Release." }
        $release = (& gh release view $Tag --repo $Repository --json isDraft,assets | ConvertFrom-Json)
        if ([bool]$release.isDraft) { throw "GitHub Release $Tag is still a draft." }
        $assets = @($release.assets | ForEach-Object { [string]$_.name })
        if ($assets -notcontains "$releaseName.zip" -or $assets -notcontains "$releaseName.zip.sha256") { throw "GitHub Release $Tag is missing its immutable zip or SHA256 sidecar." }
        & gh release download $Tag --repo $Repository --pattern "$releaseName.zip" --dir $tempRoot
        if ($LASTEXITCODE -ne 0) { throw "Failed to download the published Release zip." }
        & gh release download $Tag --repo $Repository --pattern "$releaseName.zip.sha256" --dir $tempRoot
        if ($LASTEXITCODE -ne 0) { throw "Failed to download the published Release SHA256 sidecar." }
        $zipPath = Join-Path $tempRoot "$releaseName.zip"
        $shaPath = Join-Path $tempRoot "$releaseName.zip.sha256"
    }
    if (-not (Test-Path -LiteralPath $zipPath -PathType Leaf)) { throw "Release zip is missing: $zipPath" }
    $candidateReceipt = $null
    if (-not [string]::IsNullOrWhiteSpace($CandidateReceiptPath)) {
        if ($sourceKind -ne "explicit_release_fixture") { throw "Candidate activation requires an explicit candidate ZIP and SHA256 sidecar." }
        $CandidateReceiptPath = [System.IO.Path]::GetFullPath($CandidateReceiptPath)
        if (-not (Test-Path -LiteralPath $CandidateReceiptPath -PathType Leaf)) { throw "Candidate receipt is missing: $CandidateReceiptPath" }
        $candidateReceipt = Get-Content -LiteralPath $CandidateReceiptPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([string]$candidateReceipt.schema -ne "codex-praetor-release-candidate/v1" -or [string]$candidateReceipt.status -ne "artifact_verified") { throw "Candidate receipt is not an artifact_verified v1 receipt." }
        if ([string]$candidateReceipt.candidate.version -ne $Version) { throw "Candidate receipt version differs from requested activation version." }
        $sourceKind = "verified_pr_candidate"
    }
    if ($SkipMaintenance -and $sourceKind -eq "published_release") { throw "Published Release activation may not skip generation maintenance installation." }
    $expectedHash = Read-SidecarHash -Path $shaPath
    $actualHash = Get-Sha256 -Path $zipPath
    if ($actualHash -ne $expectedHash) { throw "Release zip hash differs from its SHA256 sidecar." }
    if ($null -ne $candidateReceipt -and $actualHash -ne ([string]$candidateReceipt.artifact.zip_sha256).ToLowerInvariant()) { throw "Candidate ZIP hash differs from its verified candidate receipt." }

    $stage = Join-Path $tempRoot "stage"
    Expand-Archive -LiteralPath $zipPath -DestinationPath $stage -Force
    $generationPath = Join-Path $stage "codex-praetor-release-generation.json"
    $generation = Read-ReleaseGeneration -Path $generationPath
    if ($null -ne $candidateReceipt) {
        if ([string]$generation.generation_id -ne [string]$candidateReceipt.generation.id -or [string]$generation.source_tree -ne [string]$candidateReceipt.generation.source_tree -or [string]$generation.runtime_contract_sha256 -ne [string]$candidateReceipt.generation.runtime_contract_sha256) {
            throw "Candidate bundle generation does not match the verified candidate receipt."
        }
    }
    if ($sourceKind -eq "published_release") {
        $tagCommit = Resolve-GitHubTagCommit -Repo $Repository -ReleaseTag $Tag
        $tagTree = Resolve-GitHubCommitTree -Repo $Repository -Commit $tagCommit
        if ([string]$generation.source_tree -ne $tagTree) { throw "Downloaded Release generation does not match the immutable GitHub tag content tree." }
    }

    $installScript = Join-Path $stage "scripts\install\install-user.ps1"
    $maintenanceScript = Join-Path $stage "scripts\install\install-codex-praetor-maintenance.ps1"
    $stateScript = Join-Path $stage "scripts\verify\get-codex-praetor-installation-state.ps1"
    $deferredRefreshSource = Join-Path $stage "scripts\release\refresh-codex-praetor-plugin-cache-after-exit.ps1"
    foreach ($path in @($installScript, $maintenanceScript, $stateScript, $deferredRefreshSource)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Release bundle is missing required activation script: $path" }
    }

    $profileRoot = [System.IO.Path]::GetFullPath($UserProfileRoot)
    $installRoot = Join-Path $profileRoot "plugins\codex-praetor"
    $marketplacePath = Join-Path $profileRoot ".agents\plugins\marketplace.json"
    $backupRoot = Join-Path (Split-Path -Parent $installRoot) ".codex-praetor-backups"
    $codexHomeRoot = Join-Path $profileRoot ".codex"
    $cachedGenerationPath = Join-Path $codexHomeRoot (Join-Path "plugins" (Join-Path "cache" (Join-Path "personal" (Join-Path "codex-praetor" (Join-Path $Version "release-generation.json")))))
    if (Test-Path -LiteralPath $cachedGenerationPath -PathType Leaf) {
        try { $cachedGeneration = Get-Content -LiteralPath $cachedGenerationPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { throw "Existing Codex plugin cache generation is unreadable: $cachedGenerationPath" }
        if ([string]$cachedGeneration.generation_id -and [string]$cachedGeneration.generation_id -ne [string]$generation.generation_id) {
            throw "Plugin version $Version already has a different cached generation. Bump the product version before activating new content."
        }
    }
    $backupsBefore = if (Test-Path -LiteralPath $backupRoot) { @(Get-ChildItem -LiteralPath $backupRoot -Directory | Select-Object -ExpandProperty FullName) } else { @() }
    $installOutput = (& powershell -NoProfile -ExecutionPolicy Bypass -File $installScript -SourcePlugin (Join-Path $stage "plugin") -ExpectedGenerationPath $generationPath -InstallRoot $installRoot -MarketplacePath $marketplacePath -Apply | Out-String)
    if ($LASTEXITCODE -ne 0) { throw "Bundled user installer failed." }
    if (-not $Json -and -not [string]::IsNullOrWhiteSpace($installOutput)) { Write-Host $installOutput.TrimEnd() }

    if (-not $SkipMaintenance) {
        $maintenanceOutput = (& powershell -NoProfile -ExecutionPolicy Bypass -File $maintenanceScript -UserProfileRoot $profileRoot -SourceRoot $stage -Apply | Out-String)
        if ($LASTEXITCODE -ne 0) { throw "Generation maintenance installation failed." }
        if (-not $Json -and -not [string]::IsNullOrWhiteSpace($maintenanceOutput)) { Write-Host $maintenanceOutput.TrimEnd() }
    }

    $stableProfile = ([IO.Path]::GetFullPath($profileRoot) -eq [IO.Path]::GetFullPath($env:USERPROFILE))
    $hostProcessesBeforeActivation = @(Get-Process -Name "codex" -ErrorAction SilentlyContinue | ForEach-Object {
        [ordered]@{ id = [int]$_.Id; started_at = $_.StartTime.ToUniversalTime().ToString("o") }
    })
    if ($stableProfile -and $hostProcessesBeforeActivation.Count -gt 0) {
        # The managed cache is known to be locked while Desktop is alive. Enter
        # the durable wait state directly instead of performing a doomed add.
        $DeferPluginCacheRefresh = $true
        $pluginAdd = [pscustomobject]@{ output = @(); stderr = "codex Desktop is still running; defer plugin cache refresh."; exit_code = 1 }
    } else {
        $pluginAdd = Invoke-CodexCommandInProfile -Arguments @("plugin", "add", "codex-praetor@personal")
    }
    $pluginAddOutput = (($pluginAdd.output | Out-String) + [string]$pluginAdd.stderr)
    if ([int]$pluginAdd.exit_code -ne 0) {
        $cacheLock = ($hostProcessesBeforeActivation.Count -gt 0 -and $stableProfile) -or ($pluginAddOutput -match '(?i)failed to back up plugin cache entry|access is denied|拒绝访问')
        if (-not $DeferPluginCacheRefresh -or -not $cacheLock) { throw "Official 'codex plugin add codex-praetor@personal' failed." }
        $deferredRoot = Join-Path $profileRoot (".codex\codex-praetor-deferred-activation\" + [string]$generation.generation_id)
        New-Item -ItemType Directory -Path $deferredRoot -Force | Out-Null
        $deferredScript = Join-Path $deferredRoot "refresh-plugin-cache-after-exit.ps1"
        $deferredState = Join-Path $deferredRoot "result.json"
        $deferredPendingState = Join-Path $deferredRoot "pending.json"
        $deferredStdout = Join-Path $deferredRoot "stdout.log"
        $deferredStderr = Join-Path $deferredRoot "stderr.log"
        if (Test-Path -LiteralPath $deferredState -PathType Leaf) {
            $existingState = Get-Content -LiteralPath $deferredState -Raw -Encoding UTF8 | ConvertFrom-Json
            $existingStatus = [string]$existingState.status
            if ($existingStatus -eq "completed") {
                $payload = [ordered]@{
                    schema = "codex-praetor-published-activation/v1"
                    status = "needs_host_restart"
                    source_kind = $sourceKind
                    version = $Version
                    tag = $Tag
                    generation = $generation
                    release_sha256 = $actualHash
                    candidate_receipt_sha256 = if ($null -eq $candidateReceipt) { "" } else { (Get-Sha256 -Path $CandidateReceiptPath) }
                    deferred_refresh_state = $deferredState
                    deferred_pending_state = $deferredPendingState
                    next_action = "helper 已完成缓存刷新；完全退出并重新打开 Codex Desktop，然后在新任务中核对 runtime_info。"
                }
                if ($Json) { $payload | ConvertTo-Json -Depth 14 } else { Write-Host ('Activation status: ' + [string]$payload.status); Write-Host ('Next: ' + [string]$payload.next_action) }
                return
            }
            if ($existingStatus -eq "failed") { throw "Deferred plugin cache refresh already failed: $($existingState.reason). Inspect $deferredState before retrying." }
        }
        if ((Test-Path -LiteralPath $deferredPendingState -PathType Leaf) -and -not (Test-Path -LiteralPath $deferredState -PathType Leaf)) {
            $payload = [ordered]@{
                schema = "codex-praetor-published-activation/v1"
                status = "awaiting_host_exit"
                source_kind = $sourceKind
                version = $Version
                tag = $Tag
                generation = $generation
                release_sha256 = $actualHash
                candidate_receipt_sha256 = if ($null -eq $candidateReceipt) { "" } else { (Get-Sha256 -Path $CandidateReceiptPath) }
                deferred_refresh_state = $deferredState
                deferred_pending_state = $deferredPendingState
                observed_host_processes = $hostProcessesBeforeActivation
                next_action = "该候选已有 helper 在等待宿主退出；不要重复启动或重复重启。状态完成后再核对 runtime_info。"
            }
            if ($Json) { $payload | ConvertTo-Json -Depth 14 } else { Write-Host ('Activation status: ' + [string]$payload.status); Write-Host ('Next: ' + [string]$payload.next_action) }
            return
        }
        $pendingPayload = [ordered]@{
            schema = "codex-praetor-deferred-plugin-cache-refresh/v1"
            status = "pending"
            reason = "waiting_for_host_exit"
            expected_version = $Version
            expected_generation_id = [string]$generation.generation_id
            expected_runtime_contract_sha256 = [string]$generation.runtime_contract_sha256
            expected_zip_sha256 = $actualHash
            observed_host_processes = $hostProcessesBeforeActivation
            updated_at = [DateTime]::UtcNow.ToString("o")
            next_action = "等待 Codex Desktop 完全退出；不要重复启动 helper 或重复请求刷新。"
        }
        $pendingTemporaryPath = "$deferredPendingState.$([Guid]::NewGuid().ToString('N')).tmp"
        [IO.File]::WriteAllText($pendingTemporaryPath, (($pendingPayload | ConvertTo-Json -Depth 12) + [Environment]::NewLine), (New-Object Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $pendingTemporaryPath -Destination $deferredPendingState -Force
        Copy-Item -LiteralPath $deferredRefreshSource -Destination $deferredScript -Force
        $processArguments = @(
            "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $deferredScript,
            "-UserProfileRoot", $profileRoot, "-CodexCommand", $CodexCommand,
            "-ExpectedVersion", $Version, "-StatusPath", $deferredState,
            "-PendingStatusPath", $deferredPendingState,
            "-ExpectedGenerationId", [string]$generation.generation_id,
            "-ExpectedRuntimeContractSha256", [string]$generation.runtime_contract_sha256,
            "-ExpectedZipSha256", $actualHash,
            "-WaitTimeoutSeconds", [string]$DeferredCacheRefreshWaitSeconds
        )
        Start-Process -FilePath "powershell.exe" -ArgumentList $processArguments -WindowStyle Hidden -RedirectStandardOutput $deferredStdout -RedirectStandardError $deferredStderr
        $payload = [ordered]@{
            schema = "codex-praetor-published-activation/v1"
            status = "awaiting_host_exit"
            source_kind = $sourceKind
            version = $Version
            tag = $Tag
            generation = $generation
            release_sha256 = $actualHash
            candidate_receipt_sha256 = if ($null -eq $candidateReceipt) { "" } else { (Get-Sha256 -Path $CandidateReceiptPath) }
             deferred_refresh_state = $deferredState
             deferred_pending_state = $deferredPendingState
             observed_host_processes = $hostProcessesBeforeActivation
            next_action = '完全退出 Codex Desktop；后台 helper 会在宿主退出后运行官方 codex plugin add，随后重新打开 Codex。'
        }
        if ($Json) {
            $payload | ConvertTo-Json -Depth 14
        } else {
            Write-Host ('Activation status: ' + [string]$payload.status)
            Write-Host ('Next: ' + [string]$payload.next_action)
        }
        return
    }
    if (-not $Json -and -not [string]::IsNullOrWhiteSpace($pluginAddOutput)) { Write-Host $pluginAddOutput.TrimEnd() }
    $pluginListResult = Invoke-CodexCommandInProfile -Arguments @("plugin", "list")
    $pluginList = $pluginListResult.output | Out-String
    if ([int]$pluginListResult.exit_code -ne 0) { throw "Official 'codex plugin list' failed after installation." }
    $pluginListPattern = "(?m)^\s*" + [regex]::Escape("codex-praetor@personal") + "\s+.*?\s+" + [regex]::Escape($Version) + "(?:\s|$)"
    if ($pluginList -notmatch $pluginListPattern) { throw "codex plugin list does not show an installed codex-praetor@personal $Version row." }

    $stateArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $stateScript, "-ExpectedGenerationPath", $generationPath, "-InstallRoot", $installRoot, "-MarketplacePath", $marketplacePath, "-Json")
    if (-not [string]::IsNullOrWhiteSpace($HostRuntimeInfoPath)) { $stateArgs += @("-HostRuntimeInfoPath", [System.IO.Path]::GetFullPath($HostRuntimeInfoPath)) }
    $state = (& powershell @stateArgs | Out-String | ConvertFrom-Json)
    if ([string]$state.status -eq "needs_install") { throw "Stable marketplace identity does not match the verified Release after activation." }
    $backupsAfter = if (Test-Path -LiteralPath $backupRoot) { @(Get-ChildItem -LiteralPath $backupRoot -Directory | Select-Object -ExpandProperty FullName) } else { @() }
    $createdBackup = @($backupsAfter | Where-Object { $_ -notin $backupsBefore } | Sort-Object -Descending | Select-Object -First 1)
    $payload = [ordered]@{
        schema = "codex-praetor-published-activation/v1"
        status = [string]$state.status
        source_kind = $sourceKind
        version = $Version
        tag = $Tag
        generation = $generation
        release_sha256 = $actualHash
        candidate_receipt_sha256 = if ($null -eq $candidateReceipt) { "" } else { (Get-Sha256 -Path $CandidateReceiptPath) }
        previous_stable_backup = if ($createdBackup.Count -eq 1) { [string]$createdBackup[0] } else { "" }
        installation_state = $state
        next_action = [string]$state.next_action
    }
    if ($Json) { $payload | ConvertTo-Json -Depth 14 } else { Write-Host "Activation status: $($payload.status)"; Write-Host "Next: $($payload.next_action)" }
} finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
