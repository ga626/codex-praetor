$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\compute.ps1"
if ((& $PSScriptRoot\compute.ps1 -Left 2 -Right 3) -ne 5) { throw 'Expected sum 5.' }
Write-Output 'bounded-test-fix passed'
