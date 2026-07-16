function Get-CodexPraetorRetirementPath {
    param(
        [string]$UserProfileRoot,
        [ValidateSet("stable", "dev")][string]$Channel = "stable"
    )
    return Join-Path ([System.IO.Path]::GetFullPath($UserProfileRoot)) ".codex\codex-praetor-releases\$Channel\retirement.json"
}

function New-CodexPraetorRetirementState {
    param([string]$Channel)
    return [pscustomobject]@{
        schema = "codex-praetor-generation-retirement/v1"
        channel = $Channel
        updated_at = ""
        entries = @()
    }
}

function Read-CodexPraetorRetirementState {
    param(
        [string]$Path,
        [string]$Channel = "stable"
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return New-CodexPraetorRetirementState -Channel $Channel
    }
    try {
        $state = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -eq $state.entries) { $state.entries = @() }
        return $state
    } catch {
        throw "Retirement manifest is invalid: $Path :: $($_.Exception.Message)"
    }
}

function Write-CodexPraetorRetirementState {
    param(
        [string]$Path,
        [object]$State
    )
    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $State.updated_at = [DateTime]::UtcNow.ToString("o")
    $temp = "$Path.tmp-$([Guid]::NewGuid().ToString('N'))"
    $json = ($State | ConvertTo-Json -Depth 20) + [Environment]::NewLine
    [IO.File]::WriteAllText($temp, $json, (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $temp -Destination $Path -Force
}

function Add-CodexPraetorRetirementEntry {
    param(
        [object]$State,
        [string]$Path,
        [string]$Kind,
        [string]$GenerationId = ""
    )
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $entries = @($State.entries)
    $existing = @($entries | Where-Object { [string]$_.path -ieq $fullPath } | Select-Object -First 1)
    if ($existing.Count -gt 0) {
        if (-not [string]::IsNullOrWhiteSpace($GenerationId) -and [string]::IsNullOrWhiteSpace([string]$existing[0].generation_id)) {
            $existing[0].generation_id = $GenerationId
        }
        return $existing[0]
    }

    $entry = [pscustomobject]@{
        path = $fullPath
        kind = $Kind
        generation_id = $GenerationId
        status = "pending"
        first_seen_at = [DateTime]::UtcNow.ToString("o")
        last_attempt_at = ""
        next_attempt_at = ""
        attempts = 0
        last_error = ""
    }
    $State.entries = @($entries + $entry)
    return $entry
}
