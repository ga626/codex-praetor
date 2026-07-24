$ErrorActionPreference = 'Stop'
$text = Get-Content -LiteralPath "$PSScriptRoot\README.md" -Raw -Encoding UTF8
if ($text -notmatch 'Codex must independently accept') { throw 'Required lifecycle statement is absent.' }
Write-Output 'bounded-contract-doc passed'
