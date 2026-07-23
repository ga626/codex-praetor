$ErrorActionPreference = "Stop"

# Windows Server images can expose a PowerShell host without the FileHash cmdlet.
# Keep the public Get-FileHash shape for legacy callers, but compute SHA-256 with
# .NET so every supported Windows PowerShell host has the same behavior.
if ($env:CODEX_PRAETOR_FORCE_PORTABLE_FILE_HASH -eq "1" -or $null -eq (Get-Command Get-FileHash -ErrorAction SilentlyContinue)) {
    function Get-FileHash {
        param(
            [Parameter(Mandatory = $true, Position = 0)]
            [Alias("LiteralPath")]
            [string]$Path,
            [ValidateSet("SHA256")]
            [string]$Algorithm = "SHA256"
        )

        $stream = [System.IO.File]::OpenRead($Path)
        try {
            $sha256 = [System.Security.Cryptography.SHA256]::Create()
            try {
                $hash = ([System.BitConverter]::ToString($sha256.ComputeHash($stream))).Replace("-", "").ToUpperInvariant()
            } finally {
                $sha256.Dispose()
            }
        } finally {
            $stream.Dispose()
        }
        return [pscustomobject]@{ Algorithm = "SHA256"; Hash = $hash; Path = $Path }
    }
}
