$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$gateScript = Join-Path $projectRoot "scripts\dispatch\test-codex-praetor-capability-evidence.ps1"
$root = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-praetor-capability-gate-" + [guid]::NewGuid().ToString("N"))
$evidenceRoot = Join-Path $root "evidence"

function Assert-Equal {
    param([object]$Actual, [object]$Expected, [string]$Message)
    if ($Actual -ne $Expected) { throw "$Message Expected '$Expected', got '$Actual'." }
}

function Write-Receipt {
    param([string]$Id, [string]$Model = "fixture-model", [string]$AcceptedAt = ((Get-Date).ToUniversalTime().ToString("o")))
    New-Item -ItemType Directory -Path $evidenceRoot -Force | Out-Null
    [ordered]@{
        schema = "codex-praetor-capability-evidence/v1"
        evidence_id = $Id
        accepted_at = $AcceptedAt
        task_family = "bounded_code_change"
        provider_tuple = [ordered]@{
            provider = "fixture"
            cli_path = "C:\fixture\worker.exe"
            cli_hash = "a" * 64
            model = $Model
            permission_profile = "fixture-edit-v1"
            task_kind = "code_change"
            connection_mode = "codebuddy_acp"
            runner_identity = "codebuddy_acp:fixture-runner-v1"
        }
        supervisor_verdict = "accepted"
        contract_sha256 = "c" * 64
        job_sha256 = "d" * 64
        completion_sha256 = "e" * 64
        required_checks = @("fixture")
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $evidenceRoot "$Id.json") -Encoding UTF8
}

function Invoke-Gate {
    $raw = & powershell -NoProfile -ExecutionPolicy Bypass -File $gateScript -TaskFamily bounded_code_change -Provider fixture -CliPath "C:\fixture\worker.exe" -CliHash ("a" * 64) -Model fixture-model -PermissionProfile fixture-edit-v1 -TaskKind code_change -ConnectionMode codebuddy_acp -RunnerIdentity codebuddy_acp:fixture-runner-v1 -EvidenceRoot $evidenceRoot
    if ($LASTEXITCODE -ne 0) { throw "Capability evidence gate failed: $($raw -join ' ')" }
    return ($raw -join "`n") | ConvertFrom-Json
}

try {
    Assert-Equal (Invoke-Gate).allowed $true "A complete real task must not be blocked because it has no warm-up receipts."
    Write-Receipt -Id "accepted-1"
    Write-Receipt -Id "accepted-2"
    Assert-Equal (Invoke-Gate).well_observed $false "Two receipts are observations, not a release gate."
    Write-Receipt -Id "accepted-3"
    Assert-Equal (Invoke-Gate).well_observed $true "Three fresh exact receipts must mark a worker identity well observed."

    Write-Receipt -Id "wrong-model" -Model "other-model"
    Assert-Equal (Invoke-Gate).accepted_count 3 "A different model must not borrow another tuple's evidence."
    Set-Content -LiteralPath (Join-Path $evidenceRoot "malformed.json") -Value "not json" -Encoding UTF8
    Assert-Equal (Invoke-Gate).allowed $true "A malformed receipt must not become evidence or block a real task."

    Remove-Item -LiteralPath $evidenceRoot -Recurse -Force
    Write-Receipt -Id "stale-1" -AcceptedAt "2025-01-01T00:00:00.000Z"
    Write-Receipt -Id "stale-2" -AcceptedAt "2025-01-01T00:00:00.000Z"
    Write-Receipt -Id "stale-3" -AcceptedAt "2025-01-01T00:00:00.000Z"
    Assert-Equal (Invoke-Gate).well_observed $false "Stale evidence must not be shown as well observed."
    Write-Output "codex-praetor capability evidence gate test ok"
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
