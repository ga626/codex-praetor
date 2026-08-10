function Resolve-CodexPraetorCodeBuddyAdmissionOutput {
    param(
        [Parameter(Mandatory = $true)][string]$ModelName,
        [string]$Stdout = "",
        [string]$Stderr = "",
        [int]$ExitCode = 0
    )

    # This is deliberately a small, non-secret classification.  Do not return
    # the CLI transcript: it can contain account or workspace details and it
    # is not needed to decide whether creating a paid worker job is safe.
    $combined = "$Stdout`n$Stderr"
    $result = [ordered]@{
        schema = "codex-praetor-codebuddy-admission/v1"
        provider = "codebuddy"
        model = $ModelName
        status = "ready"
        failure_class = ""
        advisory_class = ""
        next_action = ""
        cli_exit_code = $ExitCode
        model_advertised = $false
    }
    if ($combined -match '(?i)session\s+expired|automatically\s+logged\s+out|\blogin\s+required\b|please\s+log\s*in') {
        $result.status = "blocked"
        $result.failure_class = "provider_auth_required"
        $result.next_action = "Complete /login in the official CodeBuddy CLI, then rerun dispatch readiness."
        return [pscustomobject]$result
    }
    if ($ExitCode -ne 0) {
        $result.status = "blocked"
        $result.failure_class = "provider_cli_probe_failed"
        $result.next_action = "Check that CodeBuddy CLI launches with the current account and network, then rerun dispatch readiness."
        return [pscustomobject]$result
    }
    $modelPattern = '(?i)(?<![\p{L}\p{N}_-])' + [regex]::Escape($ModelName) + '(?![\p{L}\p{N}_-])'
    if ($combined -match $modelPattern) {
        $result.model_advertised = $true
        return [pscustomobject]$result
    }
    # CodeBuddy's own historic logs show that a custom fixed model may be sent
    # even when its static --help catalogue does not advertise it.  Therefore
    # catalogue absence is evidence to retain for final acceptance, not an
    # authorization failure that would incorrectly prevent the only reliable
    # test: a bounded ACP task whose trace and outcome are independently
    # checked.  Authentication and launcher failures above remain hard stops.
    $result.advisory_class = "configured_model_not_advertised"
    $result.next_action = "The static CLI catalogue does not advertise fixed model $ModelName; verify the bounded ACP task's fixed-model launch and accepted outcome before granting capability evidence."
    return [pscustomobject]$result
}

function Invoke-CodexPraetorCodeBuddyAdmissionProbe {
    param(
        [Parameter(Mandatory = $true)][string]$LauncherPath,
        [Parameter(Mandatory = $true)][string]$CliPath,
        [Parameter(Mandatory = $true)][string]$ModelName,
        [int]$TimeoutSeconds = 30
    )

    if ([string]::IsNullOrWhiteSpace($LauncherPath) -or [string]::IsNullOrWhiteSpace($CliPath) -or -not (Test-Path -LiteralPath $CliPath -PathType Leaf)) {
        return [pscustomobject]@{ schema = "codex-praetor-codebuddy-admission/v1"; provider = "codebuddy"; model = $ModelName; status = "blocked"; failure_class = "provider_cli_probe_failed"; next_action = "Check CodeBuddy CLI path and launcher configuration, then rerun dispatch readiness."; cli_exit_code = -1; model_advertised = $false }
    }
    $stdoutPath = [IO.Path]::GetTempFileName()
    $stderrPath = [IO.Path]::GetTempFileName()
    try {
        $process = Start-Process -FilePath $LauncherPath -ArgumentList @($CliPath, "--help") -NoNewWindow -PassThru -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            try { $process.Kill() } catch { }
            return [pscustomobject]@{ schema = "codex-praetor-codebuddy-admission/v1"; provider = "codebuddy"; model = $ModelName; status = "blocked"; failure_class = "provider_cli_probe_timeout"; next_action = "Check CodeBuddy CLI startup state and network, then rerun dispatch readiness."; cli_exit_code = -1; model_advertised = $false }
        }
        $stdout = Get-Content -LiteralPath $stdoutPath -Raw -Encoding UTF8
        $stderr = Get-Content -LiteralPath $stderrPath -Raw -Encoding UTF8
        return Resolve-CodexPraetorCodeBuddyAdmissionOutput -ModelName $ModelName -Stdout $stdout -Stderr $stderr -ExitCode $process.ExitCode
    } catch {
        return [pscustomobject]@{ schema = "codex-praetor-codebuddy-admission/v1"; provider = "codebuddy"; model = $ModelName; status = "blocked"; failure_class = "provider_cli_probe_failed"; next_action = "Check that CodeBuddy CLI launches with the current account and network, then rerun dispatch readiness."; cli_exit_code = -1; model_advertised = $false }
    } finally {
        foreach ($path in @($stdoutPath, $stderrPath)) { if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue } }
    }
}
