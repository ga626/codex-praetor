param(
    [Parameter(Mandatory = $true)]
    [string]$RepositoryUrl,

    [switch]$Apply
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
$manifestPath = Join-Path $projectRoot "plugin\.codex-plugin\plugin.json"

function Normalize-GitHubRepositoryUrl {
    param([string]$Value)

    $trimmed = $Value.Trim().TrimEnd("/")
    if ($trimmed.EndsWith(".git", [System.StringComparison]::OrdinalIgnoreCase)) {
        $trimmed = $trimmed.Substring(0, $trimmed.Length - 4)
    }

    $uri = $null
    if (-not [System.Uri]::TryCreate($trimmed, [System.UriKind]::Absolute, [ref]$uri)) {
        throw "RepositoryUrl must be an absolute HTTPS GitHub repository URL."
    }
    if ($uri.Scheme -ne "https" -or $uri.Host -ne "github.com") {
        throw "RepositoryUrl must start with https://github.com/."
    }

    $parts = @($uri.AbsolutePath.Trim("/").Split("/", [System.StringSplitOptions]::RemoveEmptyEntries))
    if ($parts.Count -ne 2) {
        throw "RepositoryUrl must have exactly owner and repo path segments, for example https://github.com/OWNER/codex-praetor."
    }

    foreach ($part in $parts) {
        if ($part -notmatch "^[A-Za-z0-9_.-]+$") {
            throw "RepositoryUrl owner and repo may only contain letters, numbers, underscore, dot, or hyphen."
        }
    }

    if ($trimmed -match "YOUR_GITHUB_OWNER|YOUR_REPO|PLACEHOLDER|TODO_PUBLIC_URL") {
        throw "RepositoryUrl still contains a draft placeholder."
    }

    return "https://github.com/$($parts[0])/$($parts[1])"
}

if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Plugin manifest not found: $manifestPath"
}

$normalizedUrl = Normalize-GitHubRepositoryUrl -Value $RepositoryUrl
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json

Write-Host "Codex Praetor public metadata update"
Write-Host "Manifest: $manifestPath"
Write-Host "Repository URL: $normalizedUrl"
Write-Host "Mode: $(if ($Apply) { 'apply' } else { 'dry-run' })"

if (-not $Apply) {
    Write-Host "Dry run only. Re-run with -Apply after the final GitHub owner/repo is confirmed."
    exit 0
}

$manifest.homepage = $normalizedUrl
$manifest.repository = $normalizedUrl
if ($null -eq $manifest.interface) {
    throw "Plugin manifest is missing interface metadata."
}
$manifest.interface.websiteURL = $normalizedUrl

$json = $manifest | ConvertTo-Json -Depth 20
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($manifestPath, $json + [Environment]::NewLine, $utf8NoBom)

Write-Host "[PASS] Plugin public metadata URLs updated."
