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
$candidateArtifactNamePath = Join-Path $root "scripts\release\get-release-candidate-artifact-name.ps1"
$resolverPath = Join-Path $root "scripts\release\resolve-release-promotion-artifact.ps1"
$candidateHostReceiptGatePath = Join-Path $root "scripts\verify\test-candidate-host-receipt.ps1"
$candidateHostReceiptWriterPath = Join-Path $root "scripts\release\write-candidate-host-receipt.ps1"
$intentGatePath = Join-Path $root "scripts\verify\test-release-intent.ps1"
$preflightPath = Join-Path $root "scripts\verify\invoke-release-candidate-preflight.ps1"

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
Assert-True (Test-Path -LiteralPath $candidateArtifactNamePath -PathType Leaf) "Candidate artifact naming helper is missing: $candidateArtifactNamePath"
Assert-True (Test-Path -LiteralPath $resolverPath -PathType Leaf) "Release promotion resolver is missing: $resolverPath"
Assert-True (Test-Path -LiteralPath $candidateHostReceiptGatePath -PathType Leaf) "Candidate host receipt gate is missing: $candidateHostReceiptGatePath"
Assert-True (Test-Path -LiteralPath $candidateHostReceiptWriterPath -PathType Leaf) "Candidate host receipt writer is missing: $candidateHostReceiptWriterPath"
Assert-True (Test-Path -LiteralPath $intentGatePath -PathType Leaf) "Release intent gate is missing: $intentGatePath"
Assert-True (Test-Path -LiteralPath $preflightPath -PathType Leaf) "Candidate preflight is missing: $preflightPath"

$ciText = Get-Content -LiteralPath $ciPath -Raw -Encoding UTF8
$releaseText = Get-Content -LiteralPath $releasePath -Raw -Encoding UTF8
$pipelineText = Get-Content -LiteralPath $pipelinePath -Raw -Encoding UTF8
$publisherText = Get-Content -LiteralPath $publisherPath -Raw -Encoding UTF8
$resolverText = Get-Content -LiteralPath $resolverPath -Raw -Encoding UTF8
$intentGateText = Get-Content -LiteralPath $intentGatePath -Raw -Encoding UTF8
$preflightText = Get-Content -LiteralPath $preflightPath -Raw -Encoding UTF8

$candidateArtifactName = (& $candidateArtifactNamePath -Version "0.16.16-alpha" -PullRequestNumber 74 -HeadSha "0123456789abcdef0123456789abcdef01234567" | Out-String).Trim()
Assert-True ($candidateArtifactName -eq "codex-praetor-candidate-0.16.16-alpha-pr74-0123456789abcdef0123456789abcdef01234567") "Candidate artifact naming helper must produce the canonical version, PR, and full-SHA name."

Assert-True ($ciText -match 'uses:\s*\./\.github/workflows/release-pipeline\.yml') "PR CI must call the shared release pipeline."
Assert-True ($ciText -match 'publish:\s*false') "PR CI must run the shared pipeline in candidate-only mode."
Assert-True ($ciText -match '(?ms)permissions:\s*\r?\n\s+contents:\s*read') "PR CI caller must use read-only contents permission."
Assert-True ($ciText -match '(?ms)attestations:\s*write') "PR CI must grant only the attestation permission needed to attest its verified candidate."
Assert-True ($ciText -match '(?ms)id-token:\s*write') "PR CI must grant an OIDC token for candidate provenance attestation."
Assert-True ($ciText -notmatch '(?ms)^\s*push:') "PR candidates must not trigger duplicate branch-push CI."
Assert-True ($ciText -match "base_ref:\s*\$\{\{\s*github\.event\.pull_request\.base\.sha\s*\|\|\s*'origin/main'\s*\}\}") "PR CI must compare the full candidate against its target branch."
Assert-True ($releaseText -match 'uses:\s*\./\.github/workflows/release-pipeline\.yml') "Release On Main must call the shared release pipeline."
Assert-True ($releaseText -match 'publish:\s*true') "Release On Main must run the shared pipeline in publication mode."
Assert-True ($releaseText -match '(?ms)permissions:\s*\r?\n\s+contents:\s*write') "Release On Main must explicitly request contents: write."
Assert-True ($releaseText -match '(?ms)actions:\s*read') "Release On Main must read the verified candidate artifact."
Assert-True ($releaseText -notmatch '(?m)^\s*workflow_dispatch:') "Release recovery must re-run the original SHA, not manually dispatch the latest branch head."
Assert-True ($releaseText -match 'release-pipeline\.yml') "Changes to the shared pipeline must trigger Release On Main on main."
Assert-True ($releaseText -match '"mcp/\*\*"') "Release On Main must include MCP dependency manifest changes."
Assert-True ($releaseText -notmatch '!mcp/package\.json' -and $releaseText -notmatch '!mcp/package-lock\.json') "Release On Main must not exclude MCP dependency manifests."
Assert-True ($pipelineText -match '(?ms)on:\s*\r?\n\s+workflow_call:') "Shared release pipeline must be reusable through workflow_call."
Assert-True ($pipelineText -match 'invoke-release-candidate-preflight\.ps1\s+@arguments') "Shared pipeline must use the one candidate preflight entry."
Assert-True ($pipelineText -match 'write-release-candidate-receipt\.ps1') "PR CI must bind its artifact to the PR candidate receipt."
Assert-True ($pipelineText -match 'actions/upload-artifact@[0-9a-f]{40}') "PR CI must upload the verified candidate artifact with a pinned action."
Assert-True ($pipelineText -match 'get-release-candidate-artifact-name\.ps1') "PR CI must derive its retained candidate artifact name from the shared helper."
Assert-True ($pipelineText -match 'steps\.candidate_artifact\.outputs\.name') "PR CI upload must use the shared candidate artifact name output."
Assert-True ($pipelineText -match 'actions/attest-build-provenance@[0-9a-f]{40}') "PR CI must attest the verified candidate ZIP with a pinned action."
Assert-True ($pipelineText -match 'resolve-release-promotion-artifact\.ps1') "Main publication must resolve the previously verified candidate artifact."
Assert-True ($pipelineText -match 'codex-praetor-candidate-host-receipt') "Main publication must materialize the candidate host receipt from the release PR."
Assert-True ($pipelineText -match 'test-candidate-host-receipt\.ps1[\s\S]*-PromotionMainCommit\s+"\$\{\{ github\.sha \}\}"') "Main promotion must require a candidate host receipt bound to the promoted main tree."
Assert-True ($pipelineText -match 'test-provider-release-evidence\.ps1[\s\S]*-PromotionMainCommit\s+"\$\{\{ github\.sha \}\}"') "Main promotion must compare the promoted main tree without requiring its merge commit SHA to equal the PR artifact commit."
Assert-True ((Get-Content -LiteralPath (Join-Path $root "scripts\verify\test-provider-release-evidence.ps1") -Raw -Encoding UTF8) -match 'candidate artifact source tree does not match the promoted main tree') "Provider evidence validation must accept only a promoted main tree equal to the verified candidate tree."
Assert-True ($resolverText -match 'get-release-candidate-artifact-name\.ps1') "Main publication must resolve the same candidate artifact name through the shared helper."
Assert-True ($pipelineText -notmatch 'name:\s*codex-praetor-candidate-\$\{\{ github\.event\.pull_request\.number \}\}') "PR CI must not keep an independent legacy candidate artifact naming rule."
Assert-True ($pipelineText -match '(?ms)- name: Validate release control plane on main\s*\r?\n\s*if:.*\r?\n\s*shell: pwsh\s*\r?\n\s*env:\s*\r?\n\s*GH_TOKEN:\s*\$\{\{ github\.token \}\}') "Main release-control validation must pass GitHub Actions token to gh."
Assert-True ($intentGateText -match 'Pipeline classification: non_release') "Release intent gate must expose the non-release classification."
Assert-True ($intentGateText -match 'if \(\$CheckRemote -and \$releaseImpact\)') "Remote immutable-tag checks must run only for release-impact candidates."
Assert-True ($preflightText -match 'test-release-workflow-readiness\.ps1') "Candidate preflight must validate workflow readiness."
Assert-True ($preflightText -match 'test-release-intent-classification\.ps1') "Candidate preflight must regress dependency-only classification."
Assert-True ($pipelineText -match 'id:\s*release_impact') "Shared pipeline must classify mainline changes before publication."
Assert-True ($pipelineText -match "steps\.release_impact\.outputs\.publish\s*==\s*'true'") "Mainline publication must run only for release-impact changes."
Assert-True ($pipelineText -match '(?ms)- name: Install MCP dependencies for promoted artifact verification\s*\r?\n\s*if:.*steps\.release_impact\.outputs\.publish.*\r?\n\s*shell: pwsh\s*\r?\n\s*run:.*install-mcp-dependencies\.ps1') "Main promotion must install the controlled MCP test dependencies before final artifact runtime verification."
Assert-True ($pipelineText -match 'publish-github-release-asset\.ps1') "Shared pipeline must own the only publication command."
Assert-True ($pipelineText -match 'ResumeExistingRelease') "A retry at the original SHA must verify an existing immutable Release instead of overwriting it."
Assert-True ($preflightText -match 'test-release-artifact-runtime\.ps1') "Candidate preflight must execute final zip runtime acceptance."
Assert-True ($preflightText -match 'test-release-artifact-runtime\.ps1.*-MarkVerified') "Candidate preflight must mark the verified artifact."
Assert-True ($preflightText -match 'test-provider-canary-evidence\.ps1') "Candidate preflight must regress canary evidence."
Assert-True ($pipelineText -notmatch 'OutputRoot\s+"\.codex-praetor\\ci-release"') "Publication must not switch to a second ci-release build output."
Assert-True ($pipelineText -notmatch '(?ms)if:\s*\$\{\{\s*inputs\.publish\s*\}\}\s*\r?\n\s*shell:\s*pwsh\s*\r?\n\s*env:\s*\r?\n\s*GH_TOKEN.*invoke-release-candidate-preflight') "Main publication must not invoke the candidate preflight and rebuild a second ZIP."
Assert-True ($publisherText -match 'artifact_verified') "Publisher must require an artifact_verified manifest."
Assert-True ($publisherText -notmatch 'build-codex-praetor-release\.ps1') "Publisher must not rebuild a second upload artifact."
Assert-True ($publisherText -match 'verify-github-release-asset\.ps1.*-AllowDraft') "Publisher must download-verify the draft artifact before it becomes public."
Assert-True ($publisherText -match 'Draft GitHub Release verification failed') "Draft verification failure must leave the original draft for incident recovery."
Assert-True ($publisherText -match 'branch --show-current\s*\|\s*Out-String') "Publisher must normalize an empty detached-HEAD branch result before calling Trim()."
Assert-True ($publisherText -match 'AllowDetachedHead.*GITHUB_ACTIONS') "Publisher must permit the known detached-HEAD release-runner context only when explicitly requested by the workflow."

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
