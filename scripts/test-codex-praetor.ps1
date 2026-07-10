param(
    [string]$Repo = "",
    [switch]$SkipDryRun,
    [switch]$SkipInstalledSkillCheck,
    [switch]$SkipGlobalRuleCheck,
    [switch]$SkipMcpTest,
    [switch]$SkipPluginMcpPackageCheck
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
if ([string]::IsNullOrWhiteSpace($Repo)) {
    $Repo = $projectRoot
}

$failures = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

function Add-Pass {
    param([string]$Message)
    Write-Host "[PASS] $Message"
}

function Add-Warn {
    param([string]$Message)
    $script:warnings.Add($Message)
    Write-Host "[WARN] $Message"
}

function Add-Fail {
    param([string]$Message)
    $script:failures.Add($Message)
    Write-Host "[FAIL] $Message"
}

function Assert-Path {
    param([string]$Path, [string]$Label)
    if (Test-Path -LiteralPath $Path) {
        Add-Pass "$Label exists"
    } else {
        Add-Fail "$Label missing: $Path"
    }
}

function Get-RelativeHashMap {
    param([string]$Root)
    $map = @{}
    Get-ChildItem -LiteralPath $Root -Recurse -File -Force |
        Sort-Object FullName |
        ForEach-Object {
            $relative = $_.FullName.Substring($Root.Length).TrimStart("\")
            $map[$relative] = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
        }
    return $map
}

function Compare-HashMaps {
    param(
        [hashtable]$Expected,
        [hashtable]$Actual,
        [string]$ActualLabel
    )

    $allKeys = @($Expected.Keys + $Actual.Keys | Sort-Object -Unique)
    $diffs = @()
    foreach ($key in $allKeys) {
        if (-not $Expected.ContainsKey($key)) {
            $diffs += "extra: $key"
        } elseif (-not $Actual.ContainsKey($key)) {
            $diffs += "missing: $key"
        } elseif ($Expected[$key] -ne $Actual[$key]) {
            $diffs += "changed: $key"
        }
    }

    if ($diffs.Count -eq 0) {
        Add-Pass "$ActualLabel matches source skill"
    } else {
        Add-Fail "$ActualLabel differs from source skill: $($diffs -join '; ')"
    }
}

function Test-JsonFile {
    param([string]$Path)
    try {
        $null = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
        Add-Pass "JSON parses: $Path"
    } catch {
        Add-Fail "JSON parse failed: $Path :: $($_.Exception.Message)"
    }
}

function Test-PowerShellFile {
    param([string]$Path)
    $tokens = $null
    $errors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    if ($errors.Count -eq 0) {
        Add-Pass "PowerShell parses: $Path"
    } else {
        Add-Fail "PowerShell parse failed: $Path :: $($errors[0].Message)"
    }
}

$sourceSkill = Join-Path $projectRoot "skill\codex-praetor"
$pluginSkill = Join-Path $projectRoot "plugin\skills\codex-praetor"
$installedSkill = Join-Path $env:USERPROFILE ".codex\skills\codex-praetor"
$globalAgents = Join-Path $env:USERPROFILE ".codex\AGENTS.md"
$pluginManifest = Join-Path $projectRoot "plugin\.codex-plugin\plugin.json"
$pluginMcpConfig = Join-Path $projectRoot "plugin\.mcp.json"
$pluginMcpRuntime = Join-Path $projectRoot "plugin\mcp\dist\server.js"
$pluginMcpPackage = Join-Path $projectRoot "plugin\mcp\package.json"
$sourceInvoke = Join-Path $projectRoot "scripts\invoke-codex-praetor.ps1"

Assert-Path $sourceSkill "Source skill"
Assert-Path $pluginSkill "Plugin skill"
Assert-Path (Join-Path $projectRoot "scripts") "Source scripts"
Assert-Path (Join-Path $projectRoot "mcp") "MCP source directory"
Assert-Path $pluginManifest "Plugin manifest"
Assert-Path $pluginMcpConfig "Plugin MCP config"
Assert-Path $sourceInvoke "Dry-run entrypoint"

$skillText = Get-Content -LiteralPath (Join-Path $sourceSkill "SKILL.md") -Raw
if ($skillText -match "(?m)^name:\s*codex-praetor\s*$") {
    Add-Pass "Source skill frontmatter name is codex-praetor"
} else {
    Add-Fail "Source skill frontmatter name is not codex-praetor"
}

if (-not $SkipGlobalRuleCheck) {
    if (Test-Path -LiteralPath $globalAgents) {
        $globalAgentsText = Get-Content -LiteralPath $globalAgents -Raw
        if ($globalAgentsText -match "## Codex Praetor Delegation" -and $globalAgentsText -match "Codex subagents are a different Codex-token route") {
            Add-Pass "Global AGENTS has Codex Praetor delegation route"
        } else {
            Add-Fail "Global AGENTS is missing the Codex Praetor delegation route"
        }
    } else {
        Add-Warn "Global AGENTS not found on this machine: $globalAgents"
    }
}

$jsonPaths = @(
    $pluginManifest,
    $pluginMcpConfig,
    (Join-Path $projectRoot "config\codex-praetor-tiers.example.json"),
    (Join-Path $sourceSkill "scripts\codex-praetor-tiers.json"),
    (Join-Path $pluginSkill "scripts\codex-praetor-tiers.json"),
    $pluginMcpPackage
)
foreach ($path in $jsonPaths) {
    if (Test-Path -LiteralPath $path) {
        Test-JsonFile $path
    } else {
        Add-Fail "JSON file missing: $path"
    }
}

try {
    $manifest = Get-Content -LiteralPath $pluginManifest -Raw | ConvertFrom-Json
    if ($manifest.name -eq "codex-praetor") {
        Add-Pass "Plugin manifest name is codex-praetor"
    } else {
        Add-Fail "Plugin manifest name is $($manifest.name)"
    }

    $mcpConfig = Get-Content -LiteralPath $pluginMcpConfig -Raw | ConvertFrom-Json
    $server = $mcpConfig.mcpServers.'codex-praetor'
    if ($null -ne $server) {
        Add-Pass "Plugin MCP server is present"
    } else {
        Add-Fail "Plugin MCP server is missing"
    }

    if ($null -ne $server -and ($server.PSObject.Properties.Name -notcontains "enabled")) {
        Add-Pass "Plugin MCP config does not carry install-state enabled flag"
    } else {
        Add-Fail "Plugin MCP config should not contain an enabled flag"
    }

    $expectedMcpArg = "./mcp/dist/server.js"
    if ($null -ne $server -and $server.args -contains $expectedMcpArg) {
        Add-Pass "Plugin MCP config points to bundled runtime"
    } else {
        Add-Fail "Plugin MCP config does not point to $expectedMcpArg"
    }

    if ($null -ne $server -and $server.cwd -eq ".") {
        Add-Pass "Plugin MCP config sets cwd to plugin root"
    } else {
        Add-Fail "Plugin MCP config must set cwd to '.' so relative runtime paths resolve from the plugin root"
    }
} catch {
    Add-Fail "Manifest or MCP semantic check failed: $($_.Exception.Message)"
}

$psRoots = @(
    (Join-Path $projectRoot "scripts"),
    (Join-Path $sourceSkill "scripts"),
    (Join-Path $pluginSkill "scripts"),
    (Join-Path $projectRoot "examples")
)
Get-ChildItem -LiteralPath $psRoots -Filter "*.ps1" -File -Recurse |
    Sort-Object FullName |
    ForEach-Object { Test-PowerShellFile $_.FullName }

try {
    $sourceMap = Get-RelativeHashMap $sourceSkill
    $pluginMap = Get-RelativeHashMap $pluginSkill
    Compare-HashMaps -Expected $sourceMap -Actual $pluginMap -ActualLabel "Plugin skill"

    $rootProjectOnlyScripts = @(
        "test-codex-praetor.ps1",
        "doctor-codex-praetor.ps1",
        "build-codex-praetor-release.ps1",
        "set-codex-praetor-public-metadata.ps1",
        "install-codex-praetor-hooks.ps1",
        "publish-codex-praetor-skill.ps1",
        "publish-codex-praetor-plugin.ps1",
        "publish-codex-praetor-personal-marketplace.ps1",
        "publish-codex-praetor-personal-cache.ps1"
    )
    $rootScriptFiles = Get-ChildItem -LiteralPath (Join-Path $projectRoot "scripts") -File |
        Where-Object { $rootProjectOnlyScripts -notcontains $_.Name }
    $rootScriptDiffs = @()
    foreach ($rootScriptFile in $rootScriptFiles) {
        $sourceScriptPath = Join-Path (Join-Path $sourceSkill "scripts") $rootScriptFile.Name
        if (-not (Test-Path -LiteralPath $sourceScriptPath)) {
            $rootScriptDiffs += "missing in source skill: $($rootScriptFile.Name)"
            continue
        }
        $rootHash = (Get-FileHash -LiteralPath $rootScriptFile.FullName -Algorithm SHA256).Hash
        $sourceHash = (Get-FileHash -LiteralPath $sourceScriptPath -Algorithm SHA256).Hash
        if ($rootHash -ne $sourceHash) {
            $rootScriptDiffs += "changed: $($rootScriptFile.Name)"
        }
    }
    if ($rootScriptDiffs.Count -eq 0) {
        Add-Pass "Root scripts match source skill script copies"
    } else {
        Add-Fail "Root scripts differ from source skill script copies: $($rootScriptDiffs -join '; ')"
    }

    if (-not $SkipInstalledSkillCheck) {
        if (Test-Path -LiteralPath $installedSkill) {
            $installedItem = Get-Item -LiteralPath $installedSkill -Force
            if (($installedItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) {
                Add-Pass "Installed skill is a real directory, not a link"
            } else {
                Add-Fail "Installed skill is a reparse point/link: $installedSkill"
            }

            $installedMap = Get-RelativeHashMap $installedSkill
            Compare-HashMaps -Expected $sourceMap -Actual $installedMap -ActualLabel "Installed skill"
        } else {
            Add-Warn "Installed skill not found on this machine: $installedSkill"
        }
    }
} catch {
    Add-Fail "Skill comparison failed: $($_.Exception.Message)"
}

$oldNamePattern = "cheap-worker-orchestrator|WorkerLane|workerlane|invoke-cheap-worker|watch-cheap-worker|manage-cheap-worker|\.cheap-worker"
$allowedOldNameFiles = @(
    "AGENTS.md",
    "scripts\test-codex-praetor.ps1"
)
$skipDirectoryNames = @(".git", ".release", "handoff", "node_modules", "dist", "build", "coverage", "__pycache__")
$oldNameHits = @()
Get-ChildItem -LiteralPath $projectRoot -Recurse -File -Force |
    Where-Object {
        $full = $_.FullName
        foreach ($dirName in $skipDirectoryNames) {
            if ($full -like "*\$dirName\*") { return $false }
        }
        if ($full -like "*.codex-praetor\*") { return $false }
        return $true
    } |
    ForEach-Object {
        $relative = $_.FullName.Substring($projectRoot.Length).TrimStart("\")
        if ($allowedOldNameFiles -contains $relative) { return }
        if ($relative -like "docs\evidence-register.md") { return }
        if ($relative -like "skill\*\references\evidence-register.md") { return }
        if ($relative -like "plugin\*\references\evidence-register.md") { return }

        $matches = Select-String -LiteralPath $_.FullName -Pattern $oldNamePattern -AllMatches -ErrorAction SilentlyContinue
        foreach ($match in $matches) {
            $oldNameHits += "${relative}:$($match.LineNumber): $($match.Line.Trim())"
        }
    }
if ($oldNameHits.Count -eq 0) {
    Add-Pass "No active old product names found"
} else {
    Add-Fail "Active old product names found: $($oldNameHits -join '; ')"
}

if (-not $SkipDryRun) {
    try {
        $dryRunOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $sourceInvoke `
            -Provider mimo `
            -Tier mimo-auto-readonly `
            -Repo $Repo `
            -Task "Dry run only. Verify Codex Praetor current project baseline." `
            -Mode readonly `
            -DryRun `
            -NoNotify

        $dryRunText = ($dryRunOutput | Out-String)
        if ($LASTEXITCODE -eq 0 -and $dryRunText -match "provider=mimo" -and $dryRunText -match "project_artifact_root=" -and $dryRunText -match "CodexPraetor\.codex-praetor") {
            Add-Pass "MiMo readonly dry-run succeeds and resolves project-local artifact root"
        } else {
            Add-Fail "MiMo readonly dry-run returned unexpected output"
        }
    } catch {
        Add-Fail "MiMo readonly dry-run failed: $($_.Exception.Message)"
    }
}

if (-not $SkipMcpTest) {
    $mcpRoot = Join-Path $projectRoot "mcp"
    $mcpPackage = Join-Path $mcpRoot "package.json"
    if (Test-Path -LiteralPath $mcpPackage) {
        try {
            Push-Location -LiteralPath $mcpRoot
            try {
                $mcpOutput = & npm test 2>&1
                if ($LASTEXITCODE -eq 0 -and (($mcpOutput | Out-String) -match "codex-praetor-mcp self-test ok")) {
                    Add-Pass "MCP package builds and self-test passes"
                } else {
                    Add-Fail "MCP package self-test returned unexpected output: $($mcpOutput | Out-String)"
                }
            } finally {
                Pop-Location
            }
        } catch {
            Add-Fail "MCP package self-test failed: $($_.Exception.Message)"
        }
    } else {
        Add-Warn "MCP package.json not found; skipping MCP self-test"
    }
}

if (-not $SkipPluginMcpPackageCheck) {
    if (Test-Path -LiteralPath $pluginMcpRuntime -PathType Leaf) {
        Add-Pass "Plugin MCP bundled runtime exists"
    } else {
        Add-Fail "Plugin MCP bundled runtime missing: $pluginMcpRuntime"
    }

    $pluginMcpNodeModules = Join-Path $projectRoot "plugin\mcp\node_modules"
    if (Test-Path -LiteralPath $pluginMcpNodeModules) {
        Add-Fail "Plugin MCP package should be bundled without node_modules: $pluginMcpNodeModules"
    } else {
        Add-Pass "Plugin MCP package has no bundled node_modules"
    }

    if (Test-Path -LiteralPath $pluginMcpRuntime -PathType Leaf) {
        try {
            $importOutput = & node -e "import('node:url').then(({pathToFileURL})=>import(pathToFileURL(process.argv[1]).href)).then(m=>{if(typeof m.createServer!=='function'){console.error('missing createServer');process.exit(2)}console.log('plugin mcp import ok')})" $pluginMcpRuntime 2>&1
            if ($LASTEXITCODE -eq 0 -and (($importOutput | Out-String) -match "plugin mcp import ok")) {
                Add-Pass "Plugin MCP bundled runtime imports successfully"
            } else {
                Add-Fail "Plugin MCP bundled runtime import failed: $($importOutput | Out-String)"
            }
        } catch {
            Add-Fail "Plugin MCP bundled runtime import failed: $($_.Exception.Message)"
        }
    }

    $pluginMcpSmoke = Join-Path $projectRoot "mcp\scripts\smoke-plugin-mcp.js"
    if (Test-Path -LiteralPath $pluginMcpSmoke -PathType Leaf) {
        try {
            Push-Location -LiteralPath (Join-Path $projectRoot "mcp")
            try {
                $smokeOutput = & node $pluginMcpSmoke $pluginMcpRuntime $Repo 2>&1
                if ($LASTEXITCODE -eq 0 -and (($smokeOutput | Out-String) -match "plugin mcp protocol smoke ok")) {
                    Add-Pass "Plugin MCP protocol smoke passes"
                } else {
                    Add-Fail "Plugin MCP protocol smoke failed: $($smokeOutput | Out-String)"
                }
            } finally {
                Pop-Location
            }
        } catch {
            Add-Fail "Plugin MCP protocol smoke failed: $($_.Exception.Message)"
        }
    } else {
        Add-Fail "Plugin MCP protocol smoke script missing: $pluginMcpSmoke"
    }
}

Write-Host ""
Write-Host "Warnings: $($warnings.Count)"
Write-Host "Failures: $($failures.Count)"

if ($failures.Count -gt 0) {
    exit 1
}

exit 0
