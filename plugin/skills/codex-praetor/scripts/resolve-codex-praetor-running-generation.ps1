. (Join-Path $PSScriptRoot "ensure-file-hash.ps1")

function Resolve-CodexPraetorRunningGeneration {
    param(
        [Parameter(Mandatory = $true)][string]$RuntimeContractPath,
        [string]$ProjectRoot = "",
        [string]$ScriptDirectory = ""
    )

    if (-not (Test-Path -LiteralPath $RuntimeContractPath -PathType Leaf)) {
        throw "Runtime contract is missing: $RuntimeContractPath"
    }
    $contract = Get-Content -LiteralPath $RuntimeContractPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $contractHash = (Get-FileHash -LiteralPath $RuntimeContractPath -Algorithm SHA256).Hash.ToLowerInvariant()

    $manifestPaths = New-Object 'System.Collections.Generic.List[string]'
    if (-not [string]::IsNullOrWhiteSpace($ScriptDirectory) -and (Test-Path -LiteralPath $ScriptDirectory -PathType Container)) {
        $cursor = (Resolve-Path -LiteralPath $ScriptDirectory).Path
        for ($index = 0; $index -lt 6; $index++) {
            $manifestPaths.Add((Join-Path $cursor "release-generation.json"))
            $parent = Split-Path -Parent $cursor
            if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $cursor) { break }
            $cursor = $parent
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($ProjectRoot)) {
        $manifestPaths.Add((Join-Path $ProjectRoot "release-generation.json"))
        $manifestPaths.Add((Join-Path $ProjectRoot "plugin\release-generation.json"))
    }

    foreach ($manifestPath in @($manifestPaths | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { continue }
        try {
            $generation = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ([string]$generation.product -eq "codex-praetor" -and
                [string]$generation.version -eq [string]$contract.version -and
                [string]$generation.runtime_contract_sha256 -eq $contractHash -and
                [string]$generation.task_contract_schema -eq [string]$contract.taskContractSchema -and
                -not [string]::IsNullOrWhiteSpace([string]$generation.generation_id)) {
                return $generation
            }
        } catch {
            continue
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($ProjectRoot)) {
        $generationScript = Join-Path $ProjectRoot "scripts\release\get-codex-praetor-generation.ps1"
        if (Test-Path -LiteralPath $generationScript -PathType Leaf) {
            try {
                $generation = & $generationScript -ProjectRoot $ProjectRoot -Json | ConvertFrom-Json
                if ([string]$generation.product -eq "codex-praetor" -and
                    [string]$generation.version -eq [string]$contract.version -and
                    [string]$generation.runtime_contract_sha256 -eq $contractHash -and
                    [string]$generation.task_contract_schema -eq [string]$contract.taskContractSchema -and
                    -not [string]::IsNullOrWhiteSpace([string]$generation.generation_id)) {
                    return $generation
                }
            } catch {
                # Fall through to the runtime-only identity below.
            }
        }
    }

    return [pscustomobject]@{
        generation_id = "$( [string]$contract.version )--runtime-contract--$($contractHash.Substring(0, 12))"
        version = [string]$contract.version
        runtime_contract_sha256 = $contractHash
        task_contract_schema = [string]$contract.taskContractSchema
    }
}
