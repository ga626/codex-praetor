param(
    [string]$Repo = "",
    [string]$ConfigPath = "",
    [switch]$RequireHead,
    [switch]$PublicRelease,
    [switch]$StagedOnly,
    [switch]$AllowDraftMetadataPlaceholders,
    [switch]$Json
)

$ErrorActionPreference = "Stop"
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) {
    $global:PSNativeCommandUseErrorActionPreference = $false
}
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $utf8NoBom
$OutputEncoding = $utf8NoBom

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
if ([string]::IsNullOrWhiteSpace($Repo)) {
    $Repo = $projectRoot
}

$checks = New-Object System.Collections.Generic.List[object]

function Add-Check {
    param(
        [string]$Name,
        [string]$Status,
        [string]$Message,
        [string]$Next = ""
    )
    $script:checks.Add([ordered]@{
        name = $Name
        status = $Status
        message = $Message
        next = $Next
    })
}

function Test-CommandExists {
    param([string]$Command)
    $cmd = Get-Command $Command -ErrorAction SilentlyContinue
    return ($null -ne $cmd)
}

function Invoke-Quick {
    param(
        [string]$Exe,
        [string[]]$Args,
        [string]$WorkingDirectory = $projectRoot,
        [int]$TimeoutSeconds = 20
    )
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $Exe
        $quotedArgs = @()
        foreach ($arg in $Args) {
            if ($arg -match '[\s"]') {
                $quotedArgs += ('"' + ($arg -replace '"', '\"') + '"')
            } else {
                $quotedArgs += $arg
            }
        }
        $psi.Arguments = ($quotedArgs -join " ")
        $psi.WorkingDirectory = $WorkingDirectory
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $p = [System.Diagnostics.Process]::Start($psi)
        if (-not $p.WaitForExit($TimeoutSeconds * 1000)) {
            try { $p.Kill() } catch {}
            return @{ returncode = 124; stdout = ""; stderr = "timeout" }
        }
        return @{
            returncode = $p.ExitCode
            stdout = $p.StandardOutput.ReadToEnd().Trim()
            stderr = $p.StandardError.ReadToEnd().Trim()
        }
    } catch {
        return @{ returncode = 999; stdout = ""; stderr = $_.Exception.Message }
    }
}

function Resolve-CodexPraetorConfig {
    $candidates = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) { $candidates.Add($ConfigPath) }
    if (-not [string]::IsNullOrWhiteSpace($env:CODEX_PRAETOR_CONFIG)) { $candidates.Add($env:CODEX_PRAETOR_CONFIG) }
    $candidates.Add((Join-Path $projectRoot "config\codex-praetor.local.json"))
    $candidates.Add((Join-Path $env:USERPROFILE ".codex\codex-praetor.local.json"))
    $candidates.Add((Join-Path $projectRoot "config\codex-praetor-tiers.example.json"))

    foreach ($candidate in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return $candidate
        }
    }
    return ""
}

function Test-GitHead {
    param([string]$Path)
    $oldErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $null = & git -C $Path rev-parse --verify HEAD 2>$null
        return ($LASTEXITCODE -eq 0)
    } finally {
        $ErrorActionPreference = $oldErrorActionPreference
    }
}

function Test-PublicReleaseScanPath {
    param([string]$RelativePath)

    if ([string]::IsNullOrWhiteSpace($RelativePath)) {
        return $false
    }

    $normalized = $RelativePath -replace "/", "\"
    if ($normalized -like "handoff\*") { return $false }
    if ($normalized -like "docs\internal\*") { return $false }
    if ($normalized -like "docs\development\*") { return $false }
    if ($normalized -like "docs\github-alpha-release-productization-plan-*.md") { return $false }
    if ($normalized -like "docs\github-repository-and-user-experience-audit-*.md") { return $false }
    if ($normalized -like "docs\productization-*.md") { return $false }
    if ($normalized -like "docs\mcp-tool-handle-transport-closed-research-*.md") { return $false }
    if ($normalized -like "docs\productization-execution-map-*.md") { return $false }
    if ($normalized -like "docs\release-readiness-audit-*.md") { return $false }
    if ($normalized -like "plugin\skills\*") { return $false }
    if ($normalized -eq "scripts\doctor-codex-praetor.ps1") { return $false }
    if ($normalized -like "*\node_modules\*") { return $false }
    if ($normalized -like "*\dist\server.js") { return $false }
    return $true
}

function Test-DraftMetadataPlaceholder {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    return ($Value -match "YOUR_GITHUB_OWNER|YOUR_REPO|PLACEHOLDER|TODO_PUBLIC_URL")
}

function Get-ProviderSetupDoc {
    param([string]$Provider)
    return "docs/provider-notes/$Provider.md"
}

function Test-Provider {
    param(
        [string]$Provider,
        [object]$ProviderConfig
    )

    if ($null -eq $ProviderConfig) {
        Add-Check "provider:$Provider" "disabled" "Optional provider is not configured: $Provider. Real dispatch for this provider is disabled." "Add providers.$Provider to an ignored local config after installing the provider. See $(Get-ProviderSetupDoc -Provider $Provider)."
        return
    }

    $nodePath = ""
    if ($Provider -eq "codebuddy") {
        $nodePath = [string]$ProviderConfig.nodePath
        if ([string]::IsNullOrWhiteSpace($nodePath)) { $nodePath = "node" }
        if (-not (Test-CommandExists $nodePath)) {
            Add-Check "provider:codebuddy:node" "disabled" "CodeBuddy provider is disabled because Node is not available for the configured entrypoint." "Install Node or set providers.codebuddy.nodePath in an ignored local config. See $(Get-ProviderSetupDoc -Provider 'codebuddy')."
            return
        }
        Add-Check "provider:codebuddy:node" "ready" "Node is available for CodeBuddy." ""
    }

    $cliPath = [string]$ProviderConfig.cliPath
    if ([string]::IsNullOrWhiteSpace($cliPath) -or $cliPath -like "C:\Path\To\*") {
        Add-Check "provider:${Provider}:cli" "disabled" "$Provider provider is optional and currently disabled because cliPath is still a template value." "Install $Provider, then set providers.$Provider.cliPath in an ignored local config. See $(Get-ProviderSetupDoc -Provider $Provider)."
        return
    }

    $exists = $false
    if (Test-Path -LiteralPath $cliPath -PathType Leaf) {
        $exists = $true
    } elseif (Test-CommandExists $cliPath) {
        $exists = $true
    }

    if (-not $exists) {
        Add-Check "provider:${Provider}:cli" "disabled" "$Provider provider is disabled because the configured CLI was not found: $cliPath" "Install this provider, put it on PATH, or fix providers.$Provider.cliPath in an ignored local config. See $(Get-ProviderSetupDoc -Provider $Provider)."
        return
    }

    Add-Check "provider:${Provider}:cli" "ready" "$Provider CLI path exists." ""

    if ($StagedOnly) {
        Add-Check "provider:${Provider}:capability" "info" "$Provider capability probe is skipped in staged-only commit guard mode." "Run doctor without -StagedOnly before release or before using this provider for real dispatch."
        return
    }

    $versionCommand = @($ProviderConfig.versionCommand)
    if ($versionCommand.Count -eq 0) {
        Add-Check "provider:${Provider}:version" "info" "$Provider has no versionCommand configured." "Add a versionCommand to the provider config so doctor can check CLI compatibility."
    } else {
        if ($Provider -eq "codebuddy") {
            $codebuddyVersionArgs = @($cliPath) + [string[]]$versionCommand
            $versionProbe = Invoke-Quick -Exe $nodePath -Args $codebuddyVersionArgs -TimeoutSeconds 15
        } else {
            $versionProbe = Invoke-Quick -Exe $cliPath -Args ([string[]]$versionCommand) -TimeoutSeconds 15
        }

        if ($versionProbe.returncode -eq 0) {
            $versionText = (($versionProbe.stdout, $versionProbe.stderr) -join " ").Trim()
            if ($versionText.Length -gt 120) { $versionText = $versionText.Substring(0, 120) + "..." }
            Add-Check "provider:${Provider}:version" "ready" "$Provider version probe succeeded. $versionText" ""
        } else {
            Add-Check "provider:${Provider}:version" "info" "$Provider version probe did not prove compatibility. Exit code: $($versionProbe.returncode)." "Run the provider CLI manually if you plan to use this provider, then run a readonly canary before real dispatch. See $(Get-ProviderSetupDoc -Provider $Provider)."
        }
    }

    Add-Check "provider:${Provider}:auth" "info" "$Provider CLI presence is checked, but login/account state is intentionally not inspected by doctor." "Complete the provider's normal login flow outside Codex Praetor, then run a readonly dry-run or canary before real dispatch. See $(Get-ProviderSetupDoc -Provider $Provider)."
}

if (Test-CommandExists "git") {
    Add-Check "git" "ready" "Git is available." ""
} else {
    Add-Check "git" "fail" "Git is not available." "Install Git for Windows."
}

if (Test-Path -LiteralPath $Repo) {
    Add-Check "repo" "ready" "Repository path exists: $Repo" ""
} else {
    Add-Check "repo" "fail" "Repository path does not exist: $Repo" "Fix -Repo."
}

$insideGitOutput = (& git -C $Repo rev-parse --is-inside-work-tree 2>&1 | Out-String).Trim()
$insideGitExit = $LASTEXITCODE
$gitRootOutput = (& git -C $Repo rev-parse --show-toplevel 2>&1 | Out-String).Trim()
$gitRootExit = $LASTEXITCODE
if ($insideGitExit -eq 0 -and $insideGitOutput -eq "true") {
    $rootText = if ($gitRootExit -eq 0) { $gitRootOutput } else { $Repo }
    Add-Check "git-root" "ready" "Git root: $rootText" ""
} else {
    $detail = if (-not [string]::IsNullOrWhiteSpace($insideGitOutput)) { $insideGitOutput } else { "git rev-parse failed" }
    Add-Check "git-root" "fail" "The current path is not a Git repository." "Run git init or switch to the project root. Detail: $detail"
}

$headOk = Test-GitHead -Path $Repo
if ($headOk) {
    Add-Check "git-head" "ready" "HEAD exists, so external workers can create worktrees." ""
} else {
    $status = if ($RequireHead) { "fail" } else { "warn" }
    Add-Check "git-head" $status "This repository has no initial commit; real worker worktree creation will be blocked." "Finish redaction and checks, then create a clean initial commit."
}

if (Test-CommandExists "node") {
    $nodeVersion = (& node --version 2>$null)
    Add-Check "node" "ready" "Node is available: $nodeVersion" ""
} else {
    Add-Check "node" "fail" "Node is not available, so MCP cannot start." "Install Node.js."
}

if (Test-CommandExists "npm") {
    Add-Check "npm" "ready" "npm is available." ""
} else {
    Add-Check "npm" "warn" "npm is not available, so MCP tests cannot run." "Install Node.js/npm."
}

$resolvedConfigPath = Resolve-CodexPraetorConfig
if ([string]::IsNullOrWhiteSpace($resolvedConfigPath)) {
    Add-Check "config" "fail" "Codex Praetor config was not found." "Copy config/codex-praetor-tiers.example.json to config/codex-praetor.local.json, or set CODEX_PRAETOR_CONFIG."
    $config = $null
} else {
    try {
        $config = Get-Content -LiteralPath $resolvedConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $configStatus = if ($resolvedConfigPath -like "*codex-praetor-tiers.example.json") { "warn" } else { "ready" }
        $configNext = if ($configStatus -eq "warn") { "Create a local config before real dispatch; do not depend on the public template." } else { "" }
        Add-Check "config" $configStatus "Config parsed: $resolvedConfigPath" $configNext
    } catch {
        $config = $null
        Add-Check "config" "fail" "Config could not be parsed: $resolvedConfigPath" $_.Exception.Message
    }
}

if ($null -ne $config) {
    Test-Provider -Provider "qoder" -ProviderConfig $config.providers.qoder
    Test-Provider -Provider "codebuddy" -ProviderConfig $config.providers.codebuddy
    Test-Provider -Provider "mimo" -ProviderConfig $config.providers.mimo
}

$testScript = Join-Path $projectRoot "scripts\test-codex-praetor.ps1"
if (Test-Path -LiteralPath $testScript -PathType Leaf) {
    Add-Check "self-test" "ready" "Self-test script exists." "Run scripts/test-codex-praetor.ps1 before committing."
} else {
    Add-Check "self-test" "fail" "Self-test script is missing." ""
}

if ($PublicRelease) {
    if (Test-CommandExists "gh") {
        Add-Check "github-cli" "ready" "GitHub CLI is available for publication workflows." "Run gh auth status before creating the public repository or release."
    } else {
        Add-Check "github-cli" "warn" "GitHub CLI is not available. Codex cannot create the repository or GitHub release from this machine yet." "Install GitHub CLI and use gh auth login. Do not use pasted Personal Access Tokens as a substitute."
    }

    $publicRoots = @(
        "README.md",
        "AGENTS.md",
        ".gitignore",
        ".githooks",
        "config",
        "mcp",
        "scripts",
        "skill",
        "docs",
        "plugin\.codex-plugin",
        "plugin\.mcp.json",
        "plugin\mcp"
    )
    $privateUserProfile = [Environment]::GetFolderPath('UserProfile')
    $patterns = @(
        $projectRoot,
        $privateUserProfile,
        ('.codex' + '\\plugins\\cache'),
        ('AppData' + '\\Roaming\\QoderWork')
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    $hits = New-Object System.Collections.Generic.List[string]
    $secretHits = New-Object System.Collections.Generic.List[string]
    $filesToScan = New-Object System.Collections.Generic.List[string]
    $secretPatterns = @(
        "ghp_[A-Za-z0-9_]{20,}",
        "github_pat_[A-Za-z0-9_]{20,}",
        "gho_[A-Za-z0-9_]{20,}",
        "ghu_[A-Za-z0-9_]{20,}",
        "ghs_[A-Za-z0-9_]{20,}",
        "ghr_[A-Za-z0-9_]{20,}"
    )
    if ($StagedOnly) {
        $staged = & git -C $projectRoot -c core.quotePath=false diff --cached --name-only 2>$null
        foreach ($path in $staged) {
            if ([string]::IsNullOrWhiteSpace($path)) { continue }
            if (-not (Test-PublicReleaseScanPath -RelativePath $path)) { continue }
            $full = Join-Path $projectRoot $path
            if (Test-Path -LiteralPath $full -PathType Leaf) {
                $filesToScan.Add((Resolve-Path -LiteralPath $full).Path)
            }
        }
    } else {
        foreach ($root in $publicRoots) {
            $rootPath = Join-Path $projectRoot $root
            if (-not (Test-Path -LiteralPath $rootPath)) { continue }
            if (Test-Path -LiteralPath $rootPath -PathType Leaf) {
                $resolved = (Resolve-Path -LiteralPath $rootPath).Path
                $relative = $resolved.Substring($projectRoot.Length).TrimStart("\")
                if (Test-PublicReleaseScanPath -RelativePath $relative) {
                    $filesToScan.Add($resolved)
                }
                continue
            }
            Get-ChildItem -LiteralPath $rootPath -Recurse -File -Force |
                ForEach-Object {
                    $relative = $_.FullName.Substring($projectRoot.Length).TrimStart("\")
                    if (Test-PublicReleaseScanPath -RelativePath $relative) {
                        $filesToScan.Add($_.FullName)
                    }
                }
        }
    }

    foreach ($file in ($filesToScan | Sort-Object -Unique)) {
        $relative = $file.Substring($projectRoot.Length).TrimStart("\")
        $text = Get-Content -LiteralPath $file -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
        foreach ($pattern in $patterns) {
            if ($text -like "*$pattern*") {
                $hits.Add("$relative :: $pattern")
            }
        }
        foreach ($secretPattern in $secretPatterns) {
            if ($text -match $secretPattern) {
                $secretHits.Add("$relative :: GitHub token-shaped secret")
            }
        }
    }

    if ($hits.Count -eq 0) {
        Add-Check "public-release-scan" "ready" "No blocking local path or account markers were found in the public release scan." ""
    } else {
        Add-Check "public-release-scan" "fail" "Found $($hits.Count) blocking public release markers." (($hits | Select-Object -First 12) -join "; ")
    }

    if ($secretHits.Count -eq 0) {
        Add-Check "public-secret-scan" "ready" "No GitHub token-shaped secrets were found in the public release scan." ""
    } else {
        Add-Check "public-secret-scan" "fail" "Found $($secretHits.Count) token-shaped public release secrets." (($secretHits | Select-Object -First 12) -join "; ")
    }

    $manifestPath = Join-Path $projectRoot "plugin\.codex-plugin\plugin.json"
    if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
        try {
            $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $metadataValues = @(
                [string]$manifest.homepage,
                [string]$manifest.repository,
                [string]$manifest.interface.websiteURL
            )
            $placeholderValues = @($metadataValues | Where-Object { Test-DraftMetadataPlaceholder -Value $_ })
            if ($placeholderValues.Count -eq 0) {
                Add-Check "public-metadata-url" "ready" "Plugin public metadata URLs do not contain draft placeholders." ""
            } elseif ($AllowDraftMetadataPlaceholders) {
                Add-Check "public-metadata-url" "warn" "Plugin public metadata URLs still contain draft placeholders." "Replace final GitHub owner/repo URLs before publishing a public release."
            } else {
                Add-Check "public-metadata-url" "fail" "Plugin public metadata URLs still contain draft placeholders." "Use -AllowDraftMetadataPlaceholders only for CI or draft package checks; final public release must use real URLs."
            }
        } catch {
            Add-Check "public-metadata-url" "fail" "Could not inspect plugin public metadata URLs." $_.Exception.Message
        }
    } else {
        Add-Check "public-metadata-url" "fail" "Plugin manifest is missing, so public metadata URLs cannot be inspected." $manifestPath
    }
}

$statusRank = @{ ready = 0; info = 0; disabled = 0; warn = 1; missing = 1; missing_config = 1; fail = 2 }
$maxRank = 0
foreach ($check in $checks) {
    $rank = $statusRank[[string]$check.status]
    if ($null -eq $rank) { $rank = 1 }
    if ($rank -gt $maxRank) { $maxRank = $rank }
}
$overall = if ($maxRank -eq 0) { "PASS" } elseif ($maxRank -eq 1) { "WARN" } else { "FAIL" }

$payload = [ordered]@{
    schema = "codex-praetor-doctor/v1"
    status = $overall
    repo = (Resolve-Path -LiteralPath $Repo -ErrorAction SilentlyContinue).Path
    config = $resolvedConfigPath
    checks = $checks
}

if ($Json) {
    $payload | ConvertTo-Json -Depth 8
} else {
    Write-Host "Codex Praetor doctor: $overall"
    foreach ($check in $checks) {
        Write-Host ("[{0}] {1}: {2}" -f $check.status, $check.name, $check.message)
        if (-not [string]::IsNullOrWhiteSpace([string]$check.next)) {
            Write-Host ("      Next: {0}" -f $check.next)
        }
    }
}

if ($overall -eq "FAIL") {
    exit 1
}
exit 0
