param(
    [string]$Repo = "",
    [switch]$SkipDryRun,
    [switch]$SkipInstalledSkillCheck,
    [switch]$SkipGlobalRuleCheck,
    [switch]$SkipMcpTest,
    [switch]$SkipPluginMcpPackageCheck,
    [switch]$SkipUserInstallSmoke
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$testScript = Join-Path $scriptDir "test-codex-praetor.ps1"

$argsList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $testScript, "-IncludeDeveloperEnvironment")
if (-not [string]::IsNullOrWhiteSpace($Repo)) {
    $argsList += @("-Repo", $Repo)
}
if ($SkipDryRun) { $argsList += "-SkipDryRun" }
if ($SkipInstalledSkillCheck) { $argsList += "-SkipInstalledSkillCheck" }
if ($SkipGlobalRuleCheck) { $argsList += "-SkipGlobalRuleCheck" }
if ($SkipMcpTest) { $argsList += "-SkipMcpTest" }
if ($SkipPluginMcpPackageCheck) { $argsList += "-SkipPluginMcpPackageCheck" }
if ($SkipUserInstallSmoke) { $argsList += "-SkipUserInstallSmoke" }

& powershell @argsList
exit $LASTEXITCODE
