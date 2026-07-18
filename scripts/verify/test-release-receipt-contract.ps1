param(
    [string]$ProjectRoot = ""
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $ProjectRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
}

$schemaPath = Join-Path ([System.IO.Path]::GetFullPath($ProjectRoot)) "config\release-receipt.schema.json"
if (-not (Test-Path -LiteralPath $schemaPath -PathType Leaf)) { throw "Release receipt schema is missing: $schemaPath" }
$schema = Get-Content -LiteralPath $schemaPath -Raw -Encoding UTF8 | ConvertFrom-Json

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

Assert-True ([string]$schema.properties.schema.const -eq "codex-praetor-release-receipt/v2") "Receipt schema constant is incorrect."
Assert-True (@($schema.properties.status.enum) -contains "staged") "Receipt schema must allow staged status."
Assert-True (@($schema.properties.status.enum) -contains "active") "Receipt schema must allow active status."
Assert-True (@($schema.properties.channel.enum) -contains "stable" -and @($schema.properties.channel.enum) -contains "dev") "Receipt schema must allow stable and dev channels."
Assert-True (@($schema.properties.delivery.properties.state.enum) -contains "awaiting_host_refresh") "Receipt schema must model host refresh gating."
Assert-True (@($schema.properties.delivery.properties.state.enum) -contains "active") "Receipt schema must model active state."
Assert-True (@($schema.properties.delivery.properties.state.enum) -contains "delivered") "Receipt schema must model delivered state."
Assert-True (@($schema.properties.delivery.properties.user_path.properties.status.enum) -contains "pending") "Receipt schema must model pending user path proof."
Assert-True (@($schema.properties.delivery.properties.user_path.properties.status.enum) -contains "passed") "Receipt schema must model passed user path proof."

$required = @($schema.required)
foreach ($name in @("schema", "status", "channel", "generation", "delivery")) {
    Assert-True ($required -contains $name) "Receipt schema is missing required top-level field: $name"
}

Write-Host "[PASS] Release receipt contract schema is present and covers staged, active, and delivered states."
