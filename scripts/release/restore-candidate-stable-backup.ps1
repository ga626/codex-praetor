param(
    [Parameter(Mandatory = $true)][string]$BackupPath,
    [string]$UserProfileRoot = $env:USERPROFILE,
    [switch]$Apply
)

$ErrorActionPreference = "Stop"
$profileRoot = [IO.Path]::GetFullPath($UserProfileRoot)
$installRoot = Join-Path $profileRoot "plugins\codex-praetor"
$backupRoot = [IO.Path]::GetFullPath((Join-Path $profileRoot "plugins\.codex-praetor-backups"))
$BackupPath = [IO.Path]::GetFullPath($BackupPath)
if (-not ($BackupPath.StartsWith($backupRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase))) { throw "Backup path is outside the Codex Praetor managed backup root." }
if (-not (Test-Path -LiteralPath $BackupPath -PathType Container)) { throw "Candidate backup does not exist: $BackupPath" }
Write-Host "Candidate stable restore plan"
Write-Host "Backup:  $BackupPath"
Write-Host "Stable:  $installRoot"
Write-Host "Mode:    $(if ($Apply) { 'apply' } else { 'dry-run' })"
if (-not $Apply) { exit 0 }
$recovery = Join-Path (Split-Path -Parent $installRoot) (".codex-praetor.failed-candidate-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
if (Test-Path -LiteralPath $installRoot) { Move-Item -LiteralPath $installRoot -Destination $recovery }
Move-Item -LiteralPath $BackupPath -Destination $installRoot
if (-not (Test-Path -LiteralPath (Join-Path $installRoot ".codex-plugin\plugin.json") -PathType Leaf)) { throw "Restored stable plugin manifest is missing." }
Write-Host "[PASS] Previous stable plugin restored. Restart Codex Desktop before using it."
