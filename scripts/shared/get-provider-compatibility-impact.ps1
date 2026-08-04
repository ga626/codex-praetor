function Test-CodexPraetorProviderCompatibilityPath {
    param([string]$Path)
    return ($Path -match '(?i)(qoder|qoder-sdk|codebuddy|codebuddy-acp)' -or $Path -match '^(mcp/src/tools\.ts|scripts/dispatch/(invoke|record|watch)-codex-praetor|scripts/verify/(resolve-codex-praetor-readiness|test-provider-capability-canary)|plugin/skills/codex-praetor/scripts/(invoke|record|watch|resolve)-codex-praetor|skill/codex-praetor/scripts/(invoke|record|watch|resolve)-codex-praetor|config/(runtime-contract|codex-praetor-tiers|provider-onboarding-checklist))')
}

function Get-CodexPraetorProviderCompatibilitySurfaceHash {
    param([Parameter(Mandatory = $true)][string]$Repo, [string]$Revision = "")
    $paths = if ([string]::IsNullOrWhiteSpace($Revision)) { @(& git -C $Repo ls-files) } else { @(& git -C $Repo ls-tree -r --name-only $Revision) }
    if ($LASTEXITCODE -ne 0) { throw "Unable to enumerate provider compatibility surface." }
    $records = foreach ($path in @($paths | Where-Object { Test-CodexPraetorProviderCompatibilityPath -Path $_ } | Sort-Object)) {
        $blob = if ([string]::IsNullOrWhiteSpace($Revision)) { (& git -C $Repo hash-object -- $path | Out-String).Trim() } else { (& git -C $Repo rev-parse "$Revision`:$path" | Out-String).Trim() }
        if ($LASTEXITCODE -ne 0 -or $blob -notmatch '^[0-9a-f]{40,64}$') { throw "Unable to hash provider compatibility path: $path" }
        "$path`t$blob"
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

    $affected = New-Object System.Collections.Generic.HashSet[string]
    foreach ($path in $changed) {
        $normalized = [string]$path
        if ($normalized -match '(?i)(qoder|qoder-sdk)') { $null = $affected.Add("qoder") }
        if ($normalized -match '(?i)(codebuddy|codebuddy-acp)') { $null = $affected.Add("codebuddy") }
        if (Test-CodexPraetorProviderCompatibilityPath -Path $normalized) {
            $null = $affected.Add("qoder")
            $null = $affected.Add("codebuddy")
        }
    }
    return @($affected | Sort-Object)
}
