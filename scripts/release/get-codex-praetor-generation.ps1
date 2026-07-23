param(
    [string]$ProjectRoot = "",
    [string]$ContentRoot = "",
    [string]$Commit = "",
    [switch]$Json
)

$ErrorActionPreference = "Stop"
. (Join-Path (Split-Path -Parent $PSScriptRoot) "shared\ensure-file-hash.ps1")

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $ProjectRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
}

$projectPath = [System.IO.Path]::GetFullPath($ProjectRoot)
$contentPath = if ([string]::IsNullOrWhiteSpace($ContentRoot)) { $projectPath } else { [System.IO.Path]::GetFullPath($ContentRoot) }
$syncScript = Join-Path $projectPath "scripts\release\sync-codex-praetor-runtime-contract.ps1"
if ($contentPath -eq $projectPath -and (Test-Path -LiteralPath $syncScript -PathType Leaf)) {
    $null = & $syncScript -ProjectRoot $projectPath 6>$null
    if ($LASTEXITCODE -ne 0) { throw "Runtime contract surfaces are not generated from the canonical source." }
}
$contractPath = Join-Path $contentPath "config\runtime-contract.json"
if (-not (Test-Path -LiteralPath $contractPath -PathType Leaf)) {
    $contractPath = Join-Path $contentPath "plugin\runtime-contract.json"
}
$pluginRoot = Join-Path $contentPath "plugin"
$skillRoot = Join-Path $pluginRoot "skills\codex-praetor"
$pluginManifestPath = Join-Path $pluginRoot ".codex-plugin\plugin.json"
$mcpPackagePath = Join-Path $pluginRoot "mcp\package.json"

foreach ($path in @($contractPath, $pluginManifestPath, $mcpPackagePath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Generation input is missing: $path"
    }
}
if (-not (Test-Path -LiteralPath $skillRoot -PathType Container)) {
    throw "Bundled plugin Skill root is missing: $skillRoot"
}

$contract = Get-Content -LiteralPath $contractPath -Raw -Encoding UTF8 | ConvertFrom-Json
$manifest = Get-Content -LiteralPath $pluginManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$mcpPackage = Get-Content -LiteralPath $mcpPackagePath -Raw -Encoding UTF8 | ConvertFrom-Json
$version = [string]$contract.version
if ([string]::IsNullOrWhiteSpace($version) -or [string]$manifest.version -ne $version -or [string]$mcpPackage.version -ne $version) {
    throw "Runtime contract, plugin manifest, and MCP package must have one version."
}

function Get-TreeManifest {
    param([string]$Root, [string]$Label)

    $files = @(
        Get-ChildItem -LiteralPath $Root -Recurse -File -Force |
            Sort-Object FullName |
            ForEach-Object {
                $relative = $_.FullName.Substring($Root.Length).TrimStart("\\") -replace "\\", "/"
                [pscustomobject]@{
                    path = $relative
                    sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
                }
            }
    )
    $canonical = (($files | ForEach-Object { "$($_.path)|$($_.sha256)" }) -join "`n")
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($canonical)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $digest = ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
    return [pscustomobject]@{
        label = $Label
        sha256 = $digest
        files = $files
    }
}

$commit = $Commit.Trim().ToLowerInvariant()
if ([string]::IsNullOrWhiteSpace($commit)) {
    try {
        $commit = ((& git -C $projectPath rev-parse HEAD 2>$null) | Out-String).Trim().ToLowerInvariant()
    } catch {
        $commit = ""
    }
}
if ($commit -notmatch "^[0-9a-f]{40}$") {
    throw "Generation requires a git commit SHA from the project root."
}

$skillTree = Get-TreeManifest -Root $skillRoot -Label "skill"
$pluginTree = Get-TreeManifest -Root $pluginRoot -Label "plugin"
$contractHash = (Get-FileHash -LiteralPath $contractPath -Algorithm SHA256).Hash.ToLowerInvariant()
$combined = "skill|$($skillTree.sha256)`nplugin|$($pluginTree.sha256)`ncontract|$contractHash"
$combinedBytes = [System.Text.Encoding]::UTF8.GetBytes($combined)
$combinedSha = [System.Security.Cryptography.SHA256]::Create()
try {
    $contentHash = ([System.BitConverter]::ToString($combinedSha.ComputeHash($combinedBytes))).Replace("-", "").ToLowerInvariant()
} finally {
    $combinedSha.Dispose()
}

$result = [ordered]@{
    schema = "codex-praetor-release-generation/v2"
    product = "codex-praetor"
    version = $version
    commit = $commit
    content_manifest_sha256 = $contentHash
    generation_id = "$version--$($commit.Substring(0, 12))--$($contentHash.Substring(0, 12))"
    runtime_contract_sha256 = $contractHash
    wrapper_protocol = [string]$contract.wrapperProtocol
    task_contract_schema = [string]$contract.taskContractSchema
    required_mcp_tools = @($contract.requiredMcpTools)
    trees = [ordered]@{
        skill = $skillTree
        plugin = $pluginTree
    }
}

if ($Json) {
    $result | ConvertTo-Json -Depth 12
} else {
    $result
}
