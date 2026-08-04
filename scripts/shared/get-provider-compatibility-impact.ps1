function Test-CodexPraetorProviderCompatibilityPath {
    param([string]$Path)
    return ($Path -match '(?i)(qoder|qoder-sdk|codebuddy|codebuddy-acp)' -or $Path -match '^(mcp/src/tools\.ts|scripts/dispatch/(invoke|record|watch)-codex-praetor|scripts/verify/(resolve-codex-praetor-readiness|test-provider-capability-canary)|plugin/skills/codex-praetor/scripts/(invoke|record|watch|resolve)-codex-praetor|skill/codex-praetor/scripts/(invoke|record|watch|resolve)-codex-praetor|config/(runtime-contract|codex-praetor-tiers|provider-onboarding-checklist))')
}

function Get-CodexPraetorProviderCompatibilityContent {
    param([Parameter(Mandatory = $true)][string]$Repo, [Parameter(Mandatory = $true)][string]$Path, [string]$Revision = "")
    $text = if ([string]::IsNullOrWhiteSpace($Revision)) {
        Get-Content -LiteralPath (Join-Path $Repo $Path) -Raw -Encoding UTF8
    } else {
        (& git -C $Repo show "$Revision`:$Path" | Out-String)
    }
    if ($LASTEXITCODE -ne 0) { throw "Unable to read provider compatibility path: $Path" }
    # runtime_info is an observability-only surface. Its version/generation
    # display must not consume a paid provider task. Keep the rest of tools.ts
    # in the provider surface, so dispatch semantics still invalidate evidence.
    if ($Path -eq "mcp/src/tools.ts") {
        $pattern = '(?s)export function runtimeInfoTool\(\)\s*\{.*?(?=\r?\nexport function capabilityProfilesTool)'
        if (-not [regex]::IsMatch($text, $pattern)) { throw "Unable to isolate observability-only runtimeInfoTool from $Path" }
        $text = [regex]::Replace($text, $pattern, 'export function runtimeInfoTool() { /* observability-only */ }', 1)
    }
    return $text
}

function Get-CodexPraetorProviderCompatibilitySurfaceHash {
    param([Parameter(Mandatory = $true)][string]$Repo, [string]$Revision = "")
    $paths = if ([string]::IsNullOrWhiteSpace($Revision)) { @(& git -C $Repo ls-files) } else { @(& git -C $Repo ls-tree -r --name-only $Revision) }
    if ($LASTEXITCODE -ne 0) { throw "Unable to enumerate provider compatibility surface." }
    $records = foreach ($path in @($paths | Where-Object { Test-CodexPraetorProviderCompatibilityPath -Path $_ } | Sort-Object)) {
        # The release version lives in the runtime contract but does not alter
        # a worker tuple, permission, adapter, or task contract. Hash the
        # contract's provider-relevant semantic content so an immutable
        # recovery release does not spend provider credits merely to advance a
        # version number.
        if ($path -eq "config/runtime-contract.json" -or $path -eq "mcp/src/tools.ts") {
            $text = Get-CodexPraetorProviderCompatibilityContent -Repo $Repo -Path $path -Revision $Revision
            try {
                if ($path -eq "config/runtime-contract.json") {
                    $contract = $text | ConvertFrom-Json
                    $contract.PSObject.Properties.Remove("version")
                    $normalized = $contract | ConvertTo-Json -Depth 20 -Compress
                } else { $normalized = $text }
            } catch {
                throw "Unable to normalize provider compatibility path: $path :: $($_.Exception.Message)"
            }
            $bytes = [Text.Encoding]::UTF8.GetBytes($normalized)
            $algorithm = [Security.Cryptography.SHA256]::Create()
            try { $contentHash = ([BitConverter]::ToString($algorithm.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant() } finally { $algorithm.Dispose() }
            "$path`t$contentHash"
        } else {
            $blob = if ([string]::IsNullOrWhiteSpace($Revision)) { (& git -C $Repo hash-object -- $path | Out-String).Trim() } else { (& git -C $Repo rev-parse "$Revision`:$path" | Out-String).Trim() }
            if ($LASTEXITCODE -ne 0 -or $blob -notmatch '^[0-9a-f]{40,64}$') { throw "Unable to hash provider compatibility path: $path" }
            "$path`t$blob"
        }
    }
    $bytes = [Text.Encoding]::UTF8.GetBytes(($records -join "`n") + "`n")
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try { return (([BitConverter]::ToString($algorithm.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()) } finally { $algorithm.Dispose() }
}

function Get-CodexPraetorProviderCompatibilityImpact {
    param(
        [Parameter(Mandatory = $true)][string]$Repo,
        [Parameter(Mandatory = $true)][string]$ComparisonBase,
        [string]$TargetRef = "HEAD"
    )

    if ([string]::IsNullOrWhiteSpace($ComparisonBase) -or $ComparisonBase -match '^0+$') { return @() }
    # Compare the two exact source trees. A documentation-only amend rewrites a
    # commit, so ancestry is not a safe proxy for whether provider-facing code
    # changed after a real task was accepted.
    $changed = @(& git -C $Repo diff --name-only $ComparisonBase $TargetRef)
    if ($LASTEXITCODE -ne 0) { throw "Unable to inspect provider compatibility changes against $ComparisonBase" }

    # A path name is only a cheap routing hint. It must not turn a version-only
    # edit of the runtime contract into an expensive real-worker requirement.
    # Compare the portable provider surface before deciding whether any tuple
    # needs new evidence.
    $baseSurface = Get-CodexPraetorProviderCompatibilitySurfaceHash -Repo $Repo -Revision $ComparisonBase
    $targetSurface = Get-CodexPraetorProviderCompatibilitySurfaceHash -Repo $Repo -Revision $TargetRef
    if ($baseSurface -eq $targetSurface) { return @() }

    function Test-ProviderPathSemanticChange([string]$Path) {
        if ($Path -ne "config/runtime-contract.json") { return $true }
        $baseText = Get-CodexPraetorProviderCompatibilityContent -Repo $Repo -Path $Path -Revision $ComparisonBase
        $targetText = Get-CodexPraetorProviderCompatibilityContent -Repo $Repo -Path $Path -Revision $TargetRef
        try {
            $baseContract = $baseText | ConvertFrom-Json
            $targetContract = $targetText | ConvertFrom-Json
            $baseContract.PSObject.Properties.Remove("version")
            $targetContract.PSObject.Properties.Remove("version")
            return (($baseContract | ConvertTo-Json -Depth 20 -Compress) -ne ($targetContract | ConvertTo-Json -Depth 20 -Compress))
        } catch {
            throw "Unable to compare provider-relevant runtime contract content: $($_.Exception.Message)"
        }
    }

    $affected = New-Object System.Collections.Generic.HashSet[string]
    foreach ($path in $changed) {
        $normalized = [string]$path
        if ((Test-CodexPraetorProviderCompatibilityPath -Path $normalized) -and -not (Test-ProviderPathSemanticChange -Path $normalized)) {
            continue
        }
        if ($normalized -match '(?i)(qoder|qoder-sdk)') { $null = $affected.Add("qoder") }
        if ($normalized -match '(?i)(codebuddy|codebuddy-acp)') { $null = $affected.Add("codebuddy") }
        if ((Test-CodexPraetorProviderCompatibilityPath -Path $normalized) -and $normalized -notmatch '(?i)(qoder|qoder-sdk|codebuddy|codebuddy-acp)') {
            $null = $affected.Add("qoder")
            $null = $affected.Add("codebuddy")
        }
    }
    return @($affected | Sort-Object)
}
