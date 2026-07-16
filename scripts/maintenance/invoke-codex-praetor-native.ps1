function ConvertTo-CodexPraetorNativeArgument {
    param([AllowNull()][string]$Value)

    if ($null -eq $Value -or $Value.Length -eq 0) {
        return '""'
    }
    if ($Value -notmatch '[\s"]') {
        return $Value
    }

    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append([char]34)
    $slashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq [char]92) {
            $slashes++
            continue
        }
        if ($character -eq [char]34) {
            for ($index = 0; $index -lt (($slashes * 2) + 1); $index++) {
                [void]$builder.Append([char]92)
            }
            [void]$builder.Append([char]34)
            $slashes = 0
            continue
        }
        for ($index = 0; $index -lt $slashes; $index++) {
            [void]$builder.Append([char]92)
        }
        [void]$builder.Append($character)
        $slashes = 0
    }
    for ($index = 0; $index -lt ($slashes * 2); $index++) {
        [void]$builder.Append([char]92)
    }
    [void]$builder.Append([char]34)
    return $builder.ToString()
}

function Invoke-CodexPraetorNative {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [string]$WorkingDirectory = "",
        [int]$TimeoutSeconds = 0
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
        $psi.WorkingDirectory = $WorkingDirectory
    }
    $psi.Arguments = (@($ArgumentList | ForEach-Object {
        ConvertTo-CodexPraetorNativeArgument -Value ([string]$_)
    }) -join " ")

    $displayArguments = $psi.Arguments
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    $startedAt = [DateTimeOffset]::UtcNow
    try {
        if (-not $process.Start()) {
            return [pscustomobject]@{
                started = $false
                timed_out = $false
                exit_code = 9009
                stdout = ""
                stderr = "Process did not start."
                duration_ms = 0
                file_path = $FilePath
                arguments = $displayArguments
            }
        }
    } catch {
        return [pscustomobject]@{
            started = $false
            timed_out = $false
            exit_code = 9009
            stdout = ""
            stderr = $_.Exception.Message
            duration_ms = [int](([DateTimeOffset]::UtcNow - $startedAt).TotalMilliseconds)
            file_path = $FilePath
            arguments = $displayArguments
        }
    }

    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $timedOut = $false
    if ($TimeoutSeconds -gt 0 -and -not $process.WaitForExit($TimeoutSeconds * 1000)) {
        $timedOut = $true
        try { $process.Kill() } catch { }
        $process.WaitForExit()
    } else {
        $process.WaitForExit()
    }

    $stdout = $stdoutTask.Result
    $stderr = $stderrTask.Result
    $exitCode = if ($timedOut) { 124 } else { $process.ExitCode }
    $duration = [int](([DateTimeOffset]::UtcNow - $startedAt).TotalMilliseconds)
    $process.Dispose()

    return [pscustomobject]@{
        started = $true
        timed_out = $timedOut
        exit_code = $exitCode
        stdout = $stdout
        stderr = $stderr
        duration_ms = $duration
        file_path = $FilePath
        arguments = $displayArguments
    }
}
