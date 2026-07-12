param(
    [string]$Version = "0.1.0-alpha",
    [string]$OutputRoot = ".release",
    [switch]$Apply,
    [switch]$AllowDraftMetadataPlaceholders
)

$ErrorActionPreference = "Stop"
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) {
    $global:PSNativeCommandUseErrorActionPreference = $false
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
$outputRootPath = [System.IO.Path]::GetFullPath((Join-Path $projectRoot $OutputRoot))
$releaseName = "codex-praetor-setup-$Version"
$stagePath = Join-Path $outputRootPath $releaseName
$zipPath = Join-Path $outputRootPath "$releaseName.zip"
$sha256Path = Join-Path $outputRootPath "$releaseName.zip.sha256"

function Assert-UnderProject {
    param([string]$Path)
    $full = [System.IO.Path]::GetFullPath($Path)
    $projectFull = [System.IO.Path]::GetFullPath($projectRoot)
    $projectPrefix = $projectFull.TrimEnd("\") + "\"
    if (($full -ne $projectFull) -and (-not $full.StartsWith($projectPrefix, [System.StringComparison]::OrdinalIgnoreCase))) {
        throw "Refusing to operate outside project root: $full"
    }
}

function Copy-ReleaseItem {
    param([string]$RelativePath)
    $source = Join-Path $projectRoot $RelativePath
    if (-not (Test-Path -LiteralPath $source)) {
        throw "Release item missing: $RelativePath"
    }
    if (Test-Path -LiteralPath $source -PathType Container) {
        Get-ChildItem -LiteralPath $source -Recurse -File -Force | ForEach-Object {
            $sourceRelative = $_.FullName.Substring($projectRoot.Length).TrimStart("\")
            if (Test-BlockedReleasePath -RelativePath $sourceRelative) { return }
            $target = Join-Path $stagePath $sourceRelative
            $targetParent = Split-Path -Parent $target
            New-Item -ItemType Directory -Path $targetParent -Force | Out-Null
            Copy-Item -LiteralPath $_.FullName -Destination $target -Force
        }
    } else {
        $target = Join-Path $stagePath $RelativePath
        $targetParent = Split-Path -Parent $target
        New-Item -ItemType Directory -Path $targetParent -Force | Out-Null
        Copy-Item -LiteralPath $source -Destination $target -Force
    }
}

function Test-BlockedReleasePath {
    param([string]$RelativePath)
    $normalized = $RelativePath -replace "/", "\"
    if ($normalized -like "handoff\*") { return $true }
    if ($normalized -like "docs\internal\*") { return $true }
    if ($normalized -like "docs\development\*") { return $true }
    if ($normalized -like "docs\github-alpha-release-productization-plan-*.md") { return $true }
    if ($normalized -like "docs\github-repository-and-user-experience-audit-*.md") { return $true }
    if ($normalized -like "docs\productization-*.md") { return $true }
    if ($normalized -like "docs\mcp-tool-handle-transport-closed-research-*.md") { return $true }
    if ($normalized -like "docs\productization-execution-map-*.md") { return $true }
    if ($normalized -like "docs\release-readiness-audit-*.md") { return $true }
    if ($normalized -like "*\node_modules\*") { return $true }
    if ($normalized -like "mcp\dist\*") { return $true }
    if ($normalized -like "*.local.json") { return $true }
    if ($normalized -like ".env*") { return $true }
    if ($normalized -like "scripts\publish-codex-praetor-personal-*") { return $true }
    if ($normalized -match "(?i)(auth|token|secret)") { return $true }
    return $false
}

function Assert-PublicReleaseTree {
    param([string]$Root)
    $blocked = New-Object System.Collections.Generic.List[string]
    $markerHits = New-Object System.Collections.Generic.List[string]
    $secretHits = New-Object System.Collections.Generic.List[string]
    $privateUserProfile = [Environment]::GetFolderPath('UserProfile')
    $markers = @(
        $projectRoot,
        $privateUserProfile,
        ('.codex' + '\plugins\cache'),
        ('AppData' + '\Roaming\QoderWork')
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    $secretPatterns = @(
        "ghp_[A-Za-z0-9_]{20,}",
        "github_pat_[A-Za-z0-9_]{20,}",
        "gho_[A-Za-z0-9_]{20,}",
        "ghu_[A-Za-z0-9_]{20,}",
        "ghs_[A-Za-z0-9_]{20,}",
        "ghr_[A-Za-z0-9_]{20,}"
    )

    Get-ChildItem -LiteralPath $Root -Recurse -File -Force |
        ForEach-Object {
            $relative = $_.FullName.Substring($Root.Length).TrimStart("\")
            if (Test-BlockedReleasePath -RelativePath $relative) {
                $blocked.Add($relative)
            }
            $text = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
            foreach ($marker in $markers) {
                if ($text -like "*$marker*") {
                    $markerHits.Add("$relative :: $marker")
                }
            }
            foreach ($pattern in $secretPatterns) {
                if ($text -match $pattern) {
                    $secretHits.Add("$relative :: GitHub token-shaped secret")
                }
            }
        }

    if ($blocked.Count -gt 0) {
        throw "Release package contains blocked paths: $($blocked -join '; ')"
    }
    if ($markerHits.Count -gt 0) {
        throw "Release package contains local/private markers: $($markerHits -join '; ')"
    }
    if ($secretHits.Count -gt 0) {
        throw "Release package contains token-shaped secrets: $($secretHits -join '; ')"
    }
}

function Test-DraftMetadataPlaceholder {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    return ($Value -match "YOUR_GITHUB_OWNER|YOUR_REPO|PLACEHOLDER|TODO_PUBLIC_URL")
}

function Assert-PublicMetadataUrls {
    param([string]$Root)

    $manifestPath = Join-Path $Root "plugin\.codex-plugin\plugin.json"
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "Release package is missing plugin manifest: $manifestPath"
    }

    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $metadataValues = @(
        [string]$manifest.homepage,
        [string]$manifest.repository,
        [string]$manifest.interface.websiteURL
    )
    $placeholderValues = @($metadataValues | Where-Object { Test-DraftMetadataPlaceholder -Value $_ })
    if ($placeholderValues.Count -eq 0) {
        Write-Host "[PASS] Plugin public metadata URLs do not contain draft placeholders."
        return
    }

    if ($AllowDraftMetadataPlaceholders) {
        Write-Host "[WARN] Draft package contains placeholder public metadata URLs. Replace them before public publication."
        return
    }

    throw "Release package contains placeholder public metadata URLs. Re-run with real GitHub owner/repo URLs, or use -AllowDraftMetadataPlaceholders only for draft checks."
}

$include = @(
    "README.md",
    "README.en.md",
    "setup.cmd",
    "setup.ps1",
    "LICENSE",
    "CHANGELOG.md",
    "SECURITY.md",
    "CONTRIBUTING.md",
    ".gitignore",
    ".agents",
    ".githooks",
    ".github",
    "config",
    "docs",
    "examples",
    "mcp\package.json",
    "mcp\package-lock.json",
    "mcp\scripts",
    "mcp\src",
    "mcp\tsconfig.json",
    "plugin",
    "scripts",
    "skill"
)

Write-Host "Codex Praetor release package plan"
Write-Host "Version: $Version"
Write-Host "Stage:   $stagePath"
Write-Host "Zip:     $zipPath"
Write-Host "SHA256:  $sha256Path"
Write-Host "Mode:    $(if ($Apply) { 'apply' } else { 'dry-run' })"
Write-Host "Draft metadata placeholders allowed: $(if ($AllowDraftMetadataPlaceholders) { 'yes' } else { 'no' })"

foreach ($item in $include) {
    $path = Join-Path $projectRoot $item
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required release input missing: $item"
    }
}

if (-not $Apply) {
    Write-Host ""
    Write-Host "Dry run only. Re-run with -Apply to create the release zip."
    exit 0
}

Assert-UnderProject -Path $outputRootPath
Assert-UnderProject -Path $stagePath
Assert-UnderProject -Path $zipPath

New-Item -ItemType Directory -Path $outputRootPath -Force | Out-Null
if (Test-Path -LiteralPath $stagePath) {
    Remove-Item -LiteralPath $stagePath -Recurse -Force
}

New-Item -ItemType Directory -Path $stagePath -Force | Out-Null
foreach ($item in $include) {
    Copy-ReleaseItem -RelativePath $item
}

Assert-PublicReleaseTree -Root $stagePath
Assert-PublicMetadataUrls -Root $stagePath
if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}
Compress-Archive -Path (Join-Path $stagePath "*") -DestinationPath $zipPath -Force
$zipHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
[System.IO.File]::WriteAllText($sha256Path, "$zipHash  $releaseName.zip$([Environment]::NewLine)", (New-Object System.Text.UTF8Encoding($false)))

$zipItem = Get-Item -LiteralPath $zipPath
Write-Host "[PASS] Release package created: $($zipItem.FullName)"
Write-Host "[PASS] Size bytes: $($zipItem.Length)"
Write-Host "[PASS] SHA256: $zipHash"
Write-Host "[PASS] Release tree passed blocked-path and private-marker checks."
