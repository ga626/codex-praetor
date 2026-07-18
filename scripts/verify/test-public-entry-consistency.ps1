param(
    [string]$Version = "0.5.0-alpha",
    [string]$Repository = "ga626/codex-praetor",
    [string]$ProjectRoot = "",
    [switch]$SkipRemoteRelease
)

$ErrorActionPreference = "Stop"
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) {
    $global:PSNativeCommandUseErrorActionPreference = $false
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
}
$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)

$tag = "v$Version"
$assetName = "codex-praetor-setup-$Version.zip"
$releaseUrl = "https://github.com/$Repository/releases/tag/$tag"
$assetUrl = "https://github.com/$Repository/releases/download/$tag/$assetName"
$shaAssetName = "$assetName.sha256"

$failures = New-Object System.Collections.Generic.List[string]

function Add-Pass {
    param([string]$Message)
    Write-Host "[PASS] $Message"
}

function Add-Fail {
    param([string]$Message)
    $script:failures.Add($Message)
    Write-Host "[FAIL] $Message"
}

function Read-Text {
    param([string]$RelativePath)
    $path = Join-Path $ProjectRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-Fail "Public entry file missing: $RelativePath"
        return ""
    }
    return Get-Content -LiteralPath $path -Raw -Encoding UTF8
}

function Assert-Contains {
    param([string]$Text, [string]$Needle, [string]$Label)
    if ($Text.Contains($Needle)) {
        Add-Pass "$Label contains $Needle"
    } else {
        Add-Fail "$Label is missing $Needle"
    }
}

function Assert-NotContains {
    param([string]$Text, [string]$Needle, [string]$Label)
    if ($Text.Contains($Needle)) {
        Add-Fail "$Label still contains stale marker: $Needle"
    } else {
        Add-Pass "$Label does not contain stale marker: $Needle"
    }
}

if (-not $SkipRemoteRelease) {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        Add-Fail "GitHub CLI is required to verify the public Release."
    } else {
        $releaseJson = & gh release view $tag --repo $Repository --json tagName,isDraft,isPrerelease,assets 2>&1
        if ($LASTEXITCODE -ne 0) {
            Add-Fail "Unable to read GitHub Release $Repository@$tag. Output: $releaseJson"
        } else {
            $release = $releaseJson | ConvertFrom-Json
            if ($release.tagName -eq $tag) {
                Add-Pass "GitHub Release exists: $tag"
            } else {
                Add-Fail "GitHub Release tag mismatch: $($release.tagName)"
            }
            $assetNames = @($release.assets | ForEach-Object { $_.name })
            if ($assetNames -contains $assetName) {
                Add-Pass "GitHub Release has asset: $assetName"
            } else {
                Add-Fail "GitHub Release is missing asset: $assetName"
            }
            if ($assetNames -contains $shaAssetName) {
                Add-Pass "GitHub Release has asset: $shaAssetName"
            } else {
                Add-Fail "GitHub Release is missing asset: $shaAssetName"
            }
        }
    }
}

$readme = Read-Text "README.md"
$readmeEn = Read-Text "README.en.md"
$installZh = Read-Text "docs\user\installation.zh.md"
$roadmap = Read-Text "docs\roadmap.md"
$releaseNotesPath = "docs\release\release-notes-$Version.md"
$releaseNotes = Read-Text $releaseNotesPath
$security = Read-Text "SECURITY.md"
$setup = Read-Text "setup.ps1"
$mcpPackage = Read-Text "mcp\package.json"
$mcpServer = Read-Text "mcp\src\server.ts"
$pluginManifest = Read-Text "plugin\.codex-plugin\plugin.json"
$pluginMcpPackage = Read-Text "plugin\mcp\package.json"
$releaseBuilder = Read-Text "scripts\release\build-codex-praetor-release.ps1"
$releasePublisher = Read-Text "scripts\release\publish-github-release-asset.ps1"
$releaseVerifier = Read-Text "scripts\release\verify-github-release-asset.ps1"

Assert-Contains -Text $readme -Needle $releaseUrl -Label "README.md"
Assert-Contains -Text $readme -Needle $assetUrl -Label "README.md"
Assert-Contains -Text $readme -Needle $assetName -Label "README.md"
Assert-Contains -Text $readmeEn -Needle $releaseUrl -Label "README.en.md"
Assert-Contains -Text $readmeEn -Needle $assetUrl -Label "README.en.md"
Assert-Contains -Text $installZh -Needle $releaseUrl -Label "docs/user/installation.zh.md"
Assert-Contains -Text $installZh -Needle $assetUrl -Label "docs/user/installation.zh.md"
Assert-Contains -Text $roadmap -Needle $tag -Label "docs/roadmap.md"
Assert-Contains -Text $releaseNotes -Needle $Version -Label $releaseNotesPath
Assert-Contains -Text $security -Needle $Version -Label "SECURITY.md"
Assert-Contains -Text $setup -Needle $Version -Label "setup.ps1"
Assert-Contains -Text $mcpPackage -Needle ('"version": "' + $Version + '"') -Label "mcp/package.json"
Assert-Contains -Text $mcpServer -Needle ('version: "' + $Version + '"') -Label "mcp/src/server.ts"
Assert-Contains -Text $pluginManifest -Needle ('"version":  "' + $Version + '"') -Label "plugin/.codex-plugin/plugin.json"
Assert-Contains -Text $pluginMcpPackage -Needle ('"version": "' + $Version + '"') -Label "plugin/mcp/package.json"
Assert-Contains -Text $releaseBuilder -Needle ('[string]$Version = "' + $Version + '"') -Label "release package builder"
Assert-Contains -Text $releasePublisher -Needle ('[string]$Version = "' + $Version + '"') -Label "GitHub Release publisher"
Assert-Contains -Text $releaseVerifier -Needle ('[string]$Version = "' + $Version + '"') -Label "GitHub Release verifier"

$staleMarkers = @(
    'releases/tag/v0.1.1-alpha',
    'releases/download/v0.1.1-alpha',
    'codex-praetor-setup-0.1.1-alpha.zip',
    '0.1.1-alpha',
    'releases/tag/v0.1.2-alpha',
    'releases/download/v0.1.2-alpha',
    'codex-praetor-setup-0.1.2-alpha.zip',
    'latest user-downloadable GitHub Release is still **0.1.1-alpha**',
    'after merge',
    'release notes draft'
)

$publicTexts = @{
    "README.md" = $readme
    "README.en.md" = $readmeEn
    "docs/user/installation.zh.md" = $installZh
    "docs/roadmap.md" = $roadmap
    $releaseNotesPath = $releaseNotes
}
foreach ($entry in $publicTexts.GetEnumerator()) {
    foreach ($marker in $staleMarkers) {
        Assert-NotContains -Text $entry.Value -Needle $marker -Label $entry.Key
    }
}

Write-Host ""
Write-Host "Failures: $($failures.Count)"
if ($failures.Count -gt 0) {
    exit 1
}
exit 0
