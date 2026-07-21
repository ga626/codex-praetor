param(
    [string]$Repo = "",
    [switch]$IncludeDeveloperEnvironment,
    [switch]$SkipDryRun,
    [switch]$SkipInstalledSkillCheck,
    [switch]$SkipGlobalRuleCheck,
    [switch]$SkipMcpTest,
    [switch]$SkipPluginMcpPackageCheck,
    [switch]$SkipUserInstallSmoke
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
if ([string]::IsNullOrWhiteSpace($Repo)) {
    $Repo = $projectRoot
}

if (-not $IncludeDeveloperEnvironment) {
    $SkipDryRun = $true
    $SkipInstalledSkillCheck = $true
    $SkipGlobalRuleCheck = $true
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

if ($IncludeDeveloperEnvironment) {
    Write-Host "Validation mode: product + developer environment"
} else {
    Write-Host "Validation mode: product only"
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

function Get-NormalizedText {
    param([string]$Path)
    $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    return (($text -replace "`r`n", "`n") -replace "`r", "`n")
}

function Test-JsonFile {
    param([string]$Path)
    try {
        $null = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
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
$runtimeContract = Join-Path $projectRoot "config\runtime-contract.json"
$sourceInvoke = Join-Path $projectRoot "scripts\dispatch\invoke-codex-praetor.ps1"
$userInstallScript = Join-Path $projectRoot "scripts\install\install-user.ps1"
$setupCmd = Join-Path $projectRoot "setup.cmd"
$setupScript = Join-Path $projectRoot "setup.ps1"

Assert-Path $sourceSkill "Source skill"
Assert-Path $pluginSkill "Plugin skill"
Assert-Path (Join-Path $projectRoot "scripts") "Source scripts"
Assert-Path (Join-Path $projectRoot "mcp") "MCP source directory"
Assert-Path $pluginManifest "Plugin manifest"
Assert-Path $pluginMcpConfig "Plugin MCP config"
Assert-Path $sourceInvoke "Dry-run entrypoint"
Assert-Path $setupCmd "Double-click setup entrypoint"
Assert-Path $setupScript "Setup wizard script"
Assert-Path $runtimeContract "Runtime contract"

$setupCmdText = Get-Content -LiteralPath $setupCmd -Raw -Encoding UTF8
if ($setupCmdText -match "setup\.ps1" -and $setupCmdText -match "pause") {
    Add-Pass "Double-click setup entrypoint delegates to setup.ps1 and keeps the window visible"
} else {
    Add-Fail "Double-click setup entrypoint is missing setup.ps1 delegation or pause"
}

$setupCmdBytes = [System.IO.File]::ReadAllBytes($setupCmd)
$setupCmdLfCount = 0
$setupCmdCrlfCount = 0
for ($i = 0; $i -lt $setupCmdBytes.Length; $i++) {
    if ($setupCmdBytes[$i] -eq 10) {
        $setupCmdLfCount += 1
        if ($i -gt 0 -and $setupCmdBytes[$i - 1] -eq 13) {
            $setupCmdCrlfCount += 1
        }
    }
}
if ($setupCmdLfCount -gt 0 -and $setupCmdLfCount -eq $setupCmdCrlfCount) {
    Add-Pass "Double-click setup entrypoint uses CRLF line endings for cmd.exe"
} else {
    Add-Fail "Double-click setup entrypoint must use CRLF line endings for cmd.exe"
}

$skillText = Get-Content -LiteralPath (Join-Path $sourceSkill "SKILL.md") -Raw -Encoding UTF8
if ($skillText -match "(?m)^name:\s*codex-praetor\s*$") {
    Add-Pass "Source skill frontmatter name is codex-praetor"
} else {
    Add-Fail "Source skill frontmatter name is not codex-praetor"
}

if (-not $SkipGlobalRuleCheck) {
    if (Test-Path -LiteralPath $globalAgents) {
        $globalAgentsText = Get-Content -LiteralPath $globalAgents -Raw -Encoding UTF8
        $hasPraetorRoute = [regex]::IsMatch($globalAgentsText, '(?i)codex[- ]praetor|\u6267\u653f\u5b98')
        $hasExternalProviderRoute = [regex]::IsMatch($globalAgentsText, '(?i)qoder|codebuddy|mimo')
        $hasNativeSubagentBoundary = [regex]::IsMatch($globalAgentsText, '(?i)subagent|\u5b50\u4ee3\u7406|\u539f\u751f\s*Codex')
        if ($hasPraetorRoute -and $hasExternalProviderRoute -and $hasNativeSubagentBoundary) {
            Add-Pass "Global AGENTS has Codex Praetor delegation route"
        } else {
            Add-Fail "Global AGENTS is missing the semantic Codex Praetor delegation route"
        }
    } else {
        Add-Warn "Global AGENTS not found on this machine: $globalAgents"
    }
}

$jsonPaths = @(
    $pluginManifest,
    $pluginMcpConfig,
    (Join-Path $projectRoot "config\codex-praetor-tiers.example.json"),
    (Join-Path $projectRoot ".agents\plugins\marketplace.json"),
    (Join-Path $sourceSkill "scripts\codex-praetor-tiers.json"),
    (Join-Path $pluginSkill "scripts\codex-praetor-tiers.json"),
    (Join-Path $projectRoot "config\task-governance.schema.json"),
    (Join-Path $projectRoot "config\release-receipt.schema.json"),
    (Join-Path $projectRoot "config\release-intent.json"),
    (Join-Path $projectRoot "config\release-intent.schema.json"),
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
    $manifest = Get-Content -LiteralPath $pluginManifest -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($manifest.name -eq "codex-praetor") {
        Add-Pass "Plugin manifest name is codex-praetor"
    } else {
        Add-Fail "Plugin manifest name is $($manifest.name)"
    }

    $mcpConfig = Get-Content -LiteralPath $pluginMcpConfig -Raw -Encoding UTF8 | ConvertFrom-Json
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
Test-PowerShellFile $setupScript

try {
    $sourceMap = Get-RelativeHashMap $sourceSkill
    $pluginMap = Get-RelativeHashMap $pluginSkill
    Compare-HashMaps -Expected $sourceMap -Actual $pluginMap -ActualLabel "Plugin skill"

    $rootScriptFiles = Get-ChildItem -LiteralPath (Join-Path $projectRoot "scripts\dispatch") -File
    $rootScriptDiffs = @()
    foreach ($rootScriptFile in $rootScriptFiles) {
        $sourceScriptPath = Join-Path (Join-Path $sourceSkill "scripts") $rootScriptFile.Name
        if (-not (Test-Path -LiteralPath $sourceScriptPath)) {
            $rootScriptDiffs += "missing in source skill: $($rootScriptFile.Name)"
            continue
        }
        $rootText = Get-NormalizedText -Path $rootScriptFile.FullName
        $sourceText = Get-NormalizedText -Path $sourceScriptPath
        if ($rootText -ne $sourceText) {
            $rootScriptDiffs += "changed: $($rootScriptFile.Name)"
        }
    }
    if ($rootScriptDiffs.Count -eq 0) {
        Add-Pass "Root dispatch scripts match source skill script copies"
    } else {
        Add-Fail "Root dispatch scripts differ from source skill script copies: $($rootScriptDiffs -join '; ')"
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
    "scripts\verify\test-codex-praetor.ps1"
)
$skipDirectoryNames = @(".git", ".release", ".release-live", ".release-remote-check", "handoff", "development", "node_modules", "dist", "build", "coverage", "__pycache__")
$oldNameHits = @()
Get-ChildItem -LiteralPath $projectRoot -Recurse -File -Force |
    Where-Object {
        $full = $_.FullName
        if ($full -match "\\\.release[^\\]*\\") { return $false }
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
            -Tier mimo-isolated-audit `
            -Repo $Repo `
            -Task "Dry run only. Verify Codex Praetor current project baseline." `
            -Mode readonly `
            -DryRun `
            -NoNotify

        $dryRunText = ($dryRunOutput | Out-String)
        if ($LASTEXITCODE -eq 0 -and $dryRunText -match "provider=mimo" -and $dryRunText -match "project_artifact_root=" -and $dryRunText -match "CodexPraetor[\\\/]\.codex-praetor" -and $dryRunText -match "CodexPraetor[\\\/]\.codex-praetor[\\\/]worktrees") {
            Add-Pass "MiMo isolated-audit dry-run succeeds and resolves in-project artifact and worktree roots"
        } else {
            Add-Fail "MiMo isolated-audit dry-run returned unexpected output"
        }
    } catch {
        Add-Fail "MiMo isolated-audit dry-run failed: $($_.Exception.Message)"
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
            $nodeProbe = @'
import('node:url').then(({pathToFileURL})=>import(pathToFileURL(process.argv[1]).href)).then(m=>{if(typeof m.createServer!=='function'){console.error('missing createServer');process.exit(2)}console.log('plugin mcp import ok')})
'@
            $importOutput = & node -e $nodeProbe $pluginMcpRuntime 2>&1
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
                $smokeArgs = @($pluginMcpRuntime, $Repo)
                if ($SkipDryRun) {
                    $smokeArgs += "--skip-dry-run"
                }
                $smokeOutput = & node $pluginMcpSmoke @smokeArgs 2>&1
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

$dynamicFactsTest = Join-Path $projectRoot "scripts\verify\test-dynamic-health-facts.ps1"
if (Test-Path -LiteralPath $dynamicFactsTest -PathType Leaf) {
    try {
        $dynamicOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $dynamicFactsTest -ProjectRoot $projectRoot 2>&1
        if ($LASTEXITCODE -eq 0 -and (($dynamicOutput | Out-String) -match "Dynamic readiness")) {
            Add-Pass "Dynamic readiness and maintenance adapter regression passes"
        } else {
            Add-Fail "Dynamic readiness/maintenance regression failed: $($dynamicOutput | Out-String)"
        }
    } catch { Add-Fail "Dynamic readiness/maintenance regression failed: $($_.Exception.Message)" }
} else {
    Add-Fail "Dynamic readiness regression script missing: $dynamicFactsTest"
}

$runningGenerationHealthTest = Join-Path $projectRoot "scripts\verify\test-running-generation-health-proof.ps1"
if (Test-Path -LiteralPath $runningGenerationHealthTest -PathType Leaf) {
    try {
        $healthAuthorityOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $runningGenerationHealthTest -ProjectRoot $projectRoot 2>&1
        if ($LASTEXITCODE -eq 0 -and (($healthAuthorityOutput | Out-String) -match "Running generation")) {
            Add-Pass "Running-generation health authority regression passes"
        } else {
            Add-Fail "Running-generation health authority regression failed: $($healthAuthorityOutput | Out-String)"
        }
    } catch { Add-Fail "Running-generation health authority regression failed: $($_.Exception.Message)" }
} else {
    Add-Fail "Running-generation health authority regression script missing: $runningGenerationHealthTest"
}

$receiptContractTest = Join-Path $projectRoot "scripts\verify\test-release-receipt-contract.ps1"
if (Test-Path -LiteralPath $receiptContractTest -PathType Leaf) {
    try {
        $receiptOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $receiptContractTest -ProjectRoot $projectRoot 2>&1
        if ($LASTEXITCODE -eq 0 -and (($receiptOutput | Out-String) -match "Release receipt contract")) { Add-Pass "Release receipt contract regression passes" } else { Add-Fail "Release receipt contract regression failed: $($receiptOutput | Out-String)" }
    } catch { Add-Fail "Release receipt contract regression failed: $($_.Exception.Message)" }
} else { Add-Fail "Release receipt contract script missing: $receiptContractTest" }

$releaseIntentTest = Join-Path $projectRoot "scripts\verify\test-release-intent.ps1"
if (Test-Path -LiteralPath $releaseIntentTest -PathType Leaf) {
    try {
        $intentOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $releaseIntentTest -ProjectRoot $projectRoot 2>&1
        if ($LASTEXITCODE -eq 0 -and (($intentOutput | Out-String) -match "Release intent is valid")) { Add-Pass "Release intent contract regression passes" } else { Add-Fail "Release intent contract regression failed: $($intentOutput | Out-String)" }
    } catch { Add-Fail "Release intent contract regression failed: $($_.Exception.Message)" }
} else { Add-Fail "Release intent contract script missing: $releaseIntentTest" }

$devIsolationTest = Join-Path $projectRoot "scripts\verify\test-dev-channel-isolation.ps1"
if (Test-Path -LiteralPath $devIsolationTest -PathType Leaf) {
    try {
        $devOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $devIsolationTest -ProjectRoot $projectRoot 2>&1
        if ($LASTEXITCODE -eq 0 -and (($devOutput | Out-String) -match "Retired multi-surface release commands are absent")) { Add-Pass "Plugin-only installation boundary regression passes" } else { Add-Fail "Plugin-only installation boundary regression failed: $($devOutput | Out-String)" }
    } catch { Add-Fail "Dev channel isolation regression failed: $($_.Exception.Message)" }
} else { Add-Fail "Dev channel isolation script missing: $devIsolationTest" }

$supplyChainTest = Join-Path $projectRoot "scripts\verify\test-supply-chain-controls.ps1"
if (Test-Path -LiteralPath $supplyChainTest -PathType Leaf) {
    try {
        $supplyOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $supplyChainTest -ProjectRoot $projectRoot 2>&1
        if ($LASTEXITCODE -eq 0 -and (($supplyOutput | Out-String) -match "Supply-chain")) { Add-Pass "Supply-chain controls regression passes" } else { Add-Fail "Supply-chain controls regression failed: $($supplyOutput | Out-String)" }
    } catch { Add-Fail "Supply-chain controls regression failed: $($_.Exception.Message)" }
} else { Add-Fail "Supply-chain regression script missing: $supplyChainTest" }

if (-not $SkipUserInstallSmoke) {
    $installSmokeRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-praetor-install-smoke-" + [System.Guid]::NewGuid().ToString("N"))
    $installSmokePlugin = Join-Path $installSmokeRoot "plugins\codex-praetor"
    $installSmokeMarketplace = Join-Path $installSmokeRoot ".agents\plugins\marketplace.json"
    try {
    $installOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $userInstallScript `
            -SourcePlugin (Join-Path $projectRoot "plugin") `
            -InstallRoot $installSmokePlugin `
            -MarketplacePath $installSmokeMarketplace `
            -Apply 2>&1
        if ($LASTEXITCODE -ne 0) {
            Add-Fail "User install smoke failed: $($installOutput | Out-String)"
        } elseif (-not (Test-Path -LiteralPath (Join-Path $installSmokePlugin ".codex-plugin\plugin.json") -PathType Leaf)) {
            Add-Fail "User install smoke did not copy plugin manifest"
        } elseif (-not (Test-Path -LiteralPath $installSmokeMarketplace -PathType Leaf)) {
            Add-Fail "User install smoke did not write marketplace"
        } else {
            $marketplace = Get-Content -LiteralPath $installSmokeMarketplace -Raw -Encoding UTF8 | ConvertFrom-Json
            $entry = @($marketplace.plugins | Where-Object { $_.name -eq "codex-praetor" } | Select-Object -First 1)
            if ($entry.Count -eq 1 -and [string]$entry[0].source.path -eq "./plugins/codex-praetor") {
                Add-Pass "User install smoke writes plugin and marketplace entry in a clean temp root"
            } else {
                Add-Fail "User install smoke marketplace entry is missing or malformed"
            }
        }
    } catch {
        Add-Fail "User install smoke failed: $($_.Exception.Message)"
    } finally {
        if (Test-Path -LiteralPath $installSmokeRoot) {
            Remove-Item -LiteralPath $installSmokeRoot -Recurse -Force
        }
    }
}

if (-not $SkipUserInstallSmoke) {
    $setupSmokeRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-praetor-setup-smoke-" + [System.Guid]::NewGuid().ToString("N"))
    $setupSmokeHome = Join-Path $setupSmokeRoot "home"
    $setupSmokeInstall = Join-Path $setupSmokeHome "plugins\codex-praetor"
    $setupSmokeMarketplace = Join-Path $setupSmokeHome ".agents\plugins\marketplace.json"
    try {
        New-Item -ItemType Directory -Path $setupSmokeHome -Force | Out-Null
        $oldUserProfile = $env:USERPROFILE
        $env:USERPROFILE = $setupSmokeHome
        $setupOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $setupScript `
            -Apply `
            -NonInteractive `
            -ProviderChoice 2 `
            -SkipMaintenance 2>&1
        if ($LASTEXITCODE -ne 0) {
            Add-Fail "Setup wizard smoke failed: $($setupOutput | Out-String)"
        } elseif (-not (Test-Path -LiteralPath (Join-Path $setupSmokeInstall ".codex-plugin\plugin.json") -PathType Leaf)) {
            Add-Fail "Setup wizard smoke did not install plugin manifest"
        } elseif (-not (Test-Path -LiteralPath $setupSmokeMarketplace -PathType Leaf)) {
            Add-Fail "Setup wizard smoke did not write marketplace"
        } else {
            Add-Pass "Setup wizard smoke installs the plugin in a clean temporary user root"
        }
    } catch {
        Add-Fail "Setup wizard smoke failed: $($_.Exception.Message)"
    } finally {
        if ($null -ne $oldUserProfile) {
            $env:USERPROFILE = $oldUserProfile
        }
        if (Test-Path -LiteralPath $setupSmokeRoot) {
            Remove-Item -LiteralPath $setupSmokeRoot -Recurse -Force
        }
    }
}

if (-not $SkipUserInstallSmoke) {
    $setupCmdSmokeRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-praetor-setup-cmd-smoke-" + [System.Guid]::NewGuid().ToString("N"))
    $setupCmdSmokeHome = Join-Path $setupCmdSmokeRoot "home"
    $setupCmdSmokeInstall = Join-Path $setupCmdSmokeHome "plugins\codex-praetor"
    $setupCmdSmokeMarketplace = Join-Path $setupCmdSmokeHome ".agents\plugins\marketplace.json"
    try {
        New-Item -ItemType Directory -Path $setupCmdSmokeHome -Force | Out-Null
        $setupCmdLine = "set `"USERPROFILE=$setupCmdSmokeHome`" && set `"HOME=$setupCmdSmokeHome`" && set `"CODEX_PRAETOR_SKIP_MAINTENANCE=1`" && cd /d `"$projectRoot`" && (echo 2&echo.) | setup.cmd"
        $setupCmdOutput = & cmd.exe /d /c $setupCmdLine 2>&1
        $setupCmdOutputText = $setupCmdOutput | Out-String
        if ($LASTEXITCODE -ne 0) {
            Add-Fail "setup.cmd smoke failed: $setupCmdOutputText"
        } elseif ($setupCmdOutputText -match "not recognized") {
            Add-Fail "setup.cmd smoke was parsed incorrectly by cmd.exe: $setupCmdOutputText"
        } elseif (-not (Test-Path -LiteralPath (Join-Path $setupCmdSmokeInstall ".codex-plugin\plugin.json") -PathType Leaf)) {
            Add-Fail "setup.cmd smoke did not install plugin manifest"
        } elseif (-not (Test-Path -LiteralPath $setupCmdSmokeMarketplace -PathType Leaf)) {
            Add-Fail "setup.cmd smoke did not write marketplace"
        } else {
            Add-Pass "setup.cmd runs through cmd.exe and installs in a clean temporary user root"
        }
    } catch {
        Add-Fail "setup.cmd smoke failed: $($_.Exception.Message)"
    } finally {
        if (Test-Path -LiteralPath $setupCmdSmokeRoot) {
            Remove-Item -LiteralPath $setupCmdSmokeRoot -Recurse -Force
        }
    }
}

if (-not $SkipUserInstallSmoke) {
    $providerSetupSmokeRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-praetor-provider-setup-smoke-" + [System.Guid]::NewGuid().ToString("N"))
    $providerSetupHome = Join-Path $providerSetupSmokeRoot "home"
    $providerSetupBin = Join-Path $providerSetupSmokeRoot "bin"
    $providerSetupConfig = Join-Path $providerSetupHome ".codex\codex-praetor.local.json"
    $providerSetupState = Join-Path $providerSetupHome ".codex\codex-praetor.onboarding-state.json"
    try {
        New-Item -ItemType Directory -Path $providerSetupHome -Force | Out-Null
        New-Item -ItemType Directory -Path $providerSetupBin -Force | Out-Null
        $fakeMimo = Join-Path $providerSetupBin "mimo.cmd"
        "@echo off`r`necho 0.0.0-test`r`n" | Set-Content -LiteralPath $fakeMimo -Encoding ASCII

        $oldUserProfile = $env:USERPROFILE
        $oldPath = $env:PATH
        $env:USERPROFILE = $providerSetupHome
        $env:PATH = "$providerSetupBin;$oldPath"
        $providerSetupOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $setupScript `
            -Apply `
            -NonInteractive `
            -ProviderChoice 5 `
            -SkipMaintenance 2>&1
        if ($LASTEXITCODE -ne 0) {
            Add-Fail "Provider setup wizard smoke failed: $($providerSetupOutput | Out-String)"
        } elseif (-not (Test-Path -LiteralPath $providerSetupConfig -PathType Leaf)) {
            Add-Fail "Provider setup wizard smoke did not write user config: $providerSetupConfig"
        } elseif (-not (Test-Path -LiteralPath $providerSetupState -PathType Leaf)) {
            Add-Fail "Provider setup wizard smoke did not write resumable onboarding state: $providerSetupState"
        } else {
            $providerConfig = Get-Content -LiteralPath $providerSetupConfig -Raw -Encoding UTF8 | ConvertFrom-Json
            $providerStateText = Get-Content -LiteralPath $providerSetupState -Raw -Encoding UTF8
            $providerState = $providerStateText | ConvertFrom-Json
            $secretPattern = "token|cookie|api[_-]?key|personal[_-]?access[_-]?token|secret"
            if ([string]$providerConfig.providers.mimo.cliPath -ne $fakeMimo) {
                Add-Fail "Provider setup wizard wrote unexpected MiMo path: $($providerConfig.providers.mimo.cliPath)"
            } elseif ($providerState.providerChoice -ne "5" -or $providerState.providers.mimo.status -notin @("canary_not_run", "config_written", "auth_not_checked", "cli_rechecked")) {
                Add-Fail "Provider setup wizard wrote unexpected onboarding state for MiMo: $($providerState.providers.mimo.status)"
            } elseif ($providerStateText -match $secretPattern) {
                Add-Fail "Provider setup wizard state contains a secret-like field name"
            } else {
                Add-Pass "Provider setup wizard writes provider path and resumable non-secret onboarding state"
            }
        }
    } catch {
        Add-Fail "Provider setup wizard smoke failed: $($_.Exception.Message)"
    } finally {
        if ($null -ne $oldUserProfile) {
            $env:USERPROFILE = $oldUserProfile
        }
        if ($null -ne $oldPath) {
            $env:PATH = $oldPath
        }
        if (Test-Path -LiteralPath $providerSetupSmokeRoot) {
            Remove-Item -LiteralPath $providerSetupSmokeRoot -Recurse -Force
        }
    }
}

Write-Host ""
Write-Host "Warnings: $($warnings.Count)"
Write-Host "Failures: $($failures.Count)"

if ($failures.Count -gt 0) {
    exit 1
}

exit 0
