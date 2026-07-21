param(
    [string]$ProjectRoot = "",
    [switch]$CheckRemoteActionPins
)

$ErrorActionPreference = "Stop"
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) {
    $global:PSNativeCommandUseErrorActionPreference = $false
}
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}
$root = [System.IO.Path]::GetFullPath($ProjectRoot)
$workflowRoot = Join-Path $root ".github\workflows"
$ciPath = Join-Path $workflowRoot "ci.yml"
$releasePath = Join-Path $workflowRoot "release-on-main.yml"
$pipelinePath = Join-Path $workflowRoot "release-pipeline.yml"
$publisherPath = Join-Path $root "scripts\release\publish-github-release-asset.ps1"
$intentGatePath = Join-Path $root "scripts\verify\test-release-intent.ps1"

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Get-ActionPins {
    param([string]$Path)
    $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $result = @()
    foreach ($match in [regex]::Matches($text, '(?m)^\s*uses:\s*([^\s#]+)')) {
        $reference = $match.Groups[1].Value
        if ($reference.StartsWith("./")) { continue }
        if ($reference -notmatch '^(?<owner>[^/]+)/(?<repo>[^@]+)@(?<sha>[0-9a-f]{40})$') {
            throw "Action is not pinned to a full SHA in $(Split-Path -Leaf $Path): $reference"
        }
        $result += [pscustomobject]@{
            name = "$($Matches.owner)/$($Matches.repo)"
            sha = $Matches.sha
            reference = $reference
            workflow = (Split-Path -Leaf $Path)
        }
    }
    return @($result)
}

foreach ($path in @($ciPath, $releasePath, $pipelinePath)) {
    Assert-True (Test-Path -LiteralPath $path -PathType Leaf) "Required workflow is missing: $path"
}
Assert-True (Test-Path -LiteralPath $publisherPath -PathType Leaf) "Release publisher is missing: $publisherPath"
Assert-True (Test-Path -LiteralPath $intentGatePath -PathType Leaf) "Release intent gate is missing: $intentGatePath"

$ciText = Get-Content -LiteralPath $ciPath -Raw -Encoding UTF8
$releaseText = Get-Content -LiteralPath $releasePath -Raw -Encoding UTF8
$pipelineText = Get-Content -LiteralPath $pipelinePath -Raw -Encoding UTF8
$publisherText = Get-Content -LiteralPath $publisherPath -Raw -Encoding UTF8
$intentGateText = Get-Content -LiteralPath $intentGatePath -Raw -Encoding UTF8

Assert-True ($ciText -match 'uses:\s*\./\.github/workflows/release-pipeline\.yml') "PR CI must call the shared release pipeline."
Assert-True ($ciText -match 'publish:\s*false') "PR CI must run the shared pipeline in candidate-only mode."
Assert-True ($ciText -match '(?ms)permissions:\s*\r?\n\s+contents:\s*read') "PR CI caller must use read-only contents permission."
Assert-True ($ciText -match "base_ref:\s*\$\{\{\s*github\.event\.pull_request\.base\.sha\s*\|\|\s*'origin/main'\s*\}\}") "Branch-push CI must compare the full candidate against origin/main, not only the previous branch commit."
Assert-True ($releaseText -match 'uses:\s*\./\.github/workflows/release-pipeline\.yml') "Release On Main must call the shared release pipeline."
Assert-True ($releaseText -match 'publish:\s*true') "Release On Main must run the shared pipeline in publication mode."
Assert-True ($releaseText -match '(?ms)permissions:\s*\r?\n\s+contents:\s*write') "Release On Main must explicitly request contents: write."
Assert-True ($releaseText -notmatch '(?m)^\s*workflow_dispatch:') "Release recovery must re-run the original SHA, not manually dispatch the latest branch head."
Assert-True ($releaseText -match 'release-pipeline\.yml') "Changes to the shared pipeline must trigger Release On Main on main."
Assert-True ($pipelineText -match '(?ms)on:\s*\r?\n\s+workflow_call:') "Shared release pipeline must be reusable through workflow_call."
Assert-True ($pipelineText -match 'test-release-intent\.ps1\s+@arguments') "Shared pipeline must enforce the release-intent gate."
Assert-True ($intentGateText -match 'Pipeline classification: non_release') "Release intent gate must expose the non-release classification."
Assert-True ($intentGateText -match 'if \(\$CheckRemote -and \$releaseImpact\)') "Remote immutable-tag checks must run only for release-impact candidates."
Assert-True ($pipelineText -match 'test-release-workflow-readiness\.ps1\s+-CheckRemoteActionPins') "Shared pipeline must preflight action pins before publication."
Assert-True ($pipelineText -match 'test-release-intent-classification\.ps1') "Shared pipeline must regress dependency-only classification."
Assert-True ($pipelineText -match 'publish-github-release-asset\.ps1') "Shared pipeline must own the only publication command."
Assert-True ($pipelineText -match 'ResumeExistingRelease') "A retry at the original SHA must verify an existing immutable Release instead of overwriting it."
Assert-True ($pipelineText -match 'test-release-artifact-runtime\.ps1') "Shared pipeline must execute final zip runtime acceptance before publication."
Assert-True ($pipelineText -match 'test-release-artifact-runtime\.ps1.+-MarkVerified') "Shared pipeline must mark the verified artifact before publication."
Assert-True ($pipelineText -match 'test-provider-canary-evidence\.ps1') "Shared pipeline must regress the canary clean-before and concurrent-drift contract."
Assert-True ($pipelineText -notmatch 'OutputRoot\s+"\.codex-praetor\\ci-release"') "Publication must not switch to a second ci-release build output."
Assert-True ($publisherText -match 'artifact_verified') "Publisher must require an artifact_verified manifest."
Assert-True ($publisherText -notmatch 'build-codex-praetor-release\.ps1') "Publisher must not rebuild a second upload artifact."

$pins = @(Get-ActionPins -Path $ciPath) + @(Get-ActionPins -Path $releasePath) + @(Get-ActionPins -Path $pipelinePath)
Assert-True ($pins.Count -gt 0) "No external action pins were discovered."
foreach ($group in @($pins | Group-Object name)) {
    $uniquePins = @($group.Group.sha | Sort-Object -Unique)
    Assert-True ($uniquePins.Count -eq 1) "Action $($group.Name) uses divergent pins across CI/release workflows: $($uniquePins -join ', ')"
}

if ($CheckRemoteActionPins) {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw "gh is required to resolve pinned action commits." }
    foreach ($pin in @($pins | Sort-Object name,sha -Unique)) {
        $stderrPath = [System.IO.Path]::GetTempFileName()
        try {
            $resolved = & gh api "repos/$($pin.name)/git/commits/$($pin.sha)" --jq ".sha" 2>$stderrPath
            if ($LASTEXITCODE -ne 0) {
                $stderr = Get-Content -LiteralPath $stderrPath -Raw -Encoding UTF8
                throw "Pinned action commit cannot be resolved: $($pin.reference). $stderr"
            }
            Assert-True (([string]$resolved).Trim().ToLowerInvariant() -eq $pin.sha) "Pinned action commit resolved to an unexpected SHA: $($pin.reference)"
        } finally {
            Remove-Item -LiteralPath $stderrPath -Force -ErrorAction SilentlyContinue
        }
    }
}

Write-Host "[PASS] Shared release pipeline, permissions, recovery boundary, and action pins are verified. Remote action pins checked: $CheckRemoteActionPins"
