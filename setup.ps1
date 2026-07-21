param(
    [switch]$Apply,
    [switch]$NonInteractive,
    [ValidateSet("1", "2", "3", "4", "5")]
    [string]$ProviderChoice = "",
    [switch]$ResetOnboardingState,
    [switch]$SkipMaintenance
)

$ErrorActionPreference = "Stop"
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) {
    $global:PSNativeCommandUseErrorActionPreference = $false
}
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[Console]::InputEncoding = $utf8NoBom
[Console]::OutputEncoding = $utf8NoBom
$OutputEncoding = $utf8NoBom

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$productVersion = "0.8.0-alpha"
$runtimeContractPath = Join-Path $scriptRoot "config\runtime-contract.json"
$installScript = Join-Path $scriptRoot "scripts\install\install-user.ps1"
$configTemplate = Join-Path $scriptRoot "config\codex-praetor-tiers.example.json"
$userCodexDir = Join-Path $env:USERPROFILE ".codex"
$userConfigPath = Join-Path $userCodexDir "codex-praetor.local.json"
$onboardingStatePath = Join-Path $userCodexDir "codex-praetor.onboarding-state.json"
$canaryScript = Join-Path $scriptRoot "scripts\verify\test-provider-capability-canary.ps1"
$maintenanceScript = Join-Path $scriptRoot "scripts\install\install-codex-praetor-maintenance.ps1"
$nativeHelper = Join-Path $scriptRoot "scripts\maintenance\invoke-codex-praetor-native.ps1"
. $nativeHelper

if (-not (Test-Path -LiteralPath $runtimeContractPath -PathType Leaf)) {
    throw "Codex Praetor runtime contract is missing: $runtimeContractPath"
}
$runtimeContract = Get-Content -LiteralPath $runtimeContractPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$runtimeContract.version -ne $productVersion) {
    throw "Installer version $productVersion does not match runtime contract $($runtimeContract.version)."
}

function Write-Section {
    param([string]$Text)
    Write-Host ""
    Write-Host ("=" * 64) -ForegroundColor DarkCyan
    Write-Host $Text -ForegroundColor Cyan
    Write-Host ("=" * 64) -ForegroundColor DarkCyan
}

function Write-Item {
    param(
        [string]$Label,
        [string]$Value,
        [string]$Color = "Gray"
    )
    Write-Host ("{0,-18} {1}" -f $Label, $Value) -ForegroundColor $Color
}

function Test-ObjectProperty {
    param([object]$Object, [string]$Name)
    if ($null -eq $Object) { return $false }
    return ($Object.PSObject.Properties.Name -contains $Name)
}

function Read-TrimmedHost {
    param([string]$Prompt)
    $value = Read-Host $Prompt
    if ($null -eq $value) { return "" }
    return ([string]$value).Trim()
}

function Get-IsoNow {
    return ([DateTimeOffset]::Now.ToString("o"))
}

function Get-ProviderDefinitions {
    return @(
        [pscustomobject]@{
            Id = "qoder";
            Name = "Qoder";
            Commands = @("qodercli", "qoder");
            Docs = "https://docs.qoder.com/en/cli/quick-start";
            Installers = @(
                [pscustomobject]@{
                    Label = "官方 Windows PowerShell 安装";
                    Command = "irm https://qoder.com/install.ps1 | iex";
                    NetworkHost = "qoder.com";
                    TimeoutSeconds = 600;
                    RequiresNode = $false;
                    Preferred = $true;
                },
                [pscustomobject]@{
                    Label = "官方 Windows CMD 安装";
                    Command = "curl -fsSL https://qoder.com/install.cmd -o install.cmd && install.cmd";
                    Shell = "cmd";
                    NetworkHost = "qoder.com";
                    TimeoutSeconds = 600;
                    RequiresNode = $false;
                    Preferred = $false;
                }
            );
            AuthHint = "首次使用前请在 Qoder 官方 TUI 里输入 /login。普通用户优先选浏览器登录；PAT/环境变量更适合自动化，不作为小白主路径。Windows on Arm 当前是 provider 边界。";
            AuthLaunchHint = "向导会把当前终端交给 Qoder。进入 Qoder 后输入 /login，按官方提示完成浏览器登录或 PAT；完成后退出 Qoder，向导会继续复检。";
            AuthCommand = "";
            CanaryProvider = "qoder";
            KnownBinDirs = @("%USERPROFILE%\.qoder\bin", "%USERPROFILE%\.qoder\bin\qodercli");
            ExecutablePatterns = @("qodercli.exe", "qodercli-*.exe", "qoder.exe");
        }
        [pscustomobject]@{
            Id = "codebuddy";
            Name = "CodeBuddy";
            Commands = @("codebuddy", "workbuddy");
            Docs = "https://www.codebuddy.ai/docs/cli/quickstart";
            Installers = @(
                [pscustomobject]@{
                    Label = "官方 Windows Native Installer Beta（推荐，少依赖）";
                    Command = "irm https://copilot.tencent.com/cli/install.ps1 | iex";
                    NetworkHost = "copilot.tencent.com";
                    TimeoutSeconds = 600;
                    RequiresNode = $false;
                    Preferred = $true;
                },
                [pscustomobject]@{
                    Label = "官方 Windows Native Installer 备用域名";
                    Command = "irm https://www.codebuddy.cn/cli/install.ps1 | iex";
                    NetworkHost = "www.codebuddy.cn";
                    TimeoutSeconds = 600;
                    RequiresNode = $false;
                    Preferred = $false;
                },
                [pscustomobject]@{
                    Label = "npm 全局安装";
                    Command = "npm install -g @tencent-ai/codebuddy-code";
                    NetworkHost = "registry.npmjs.org";
                    TimeoutSeconds = 600;
                    RequiresNode = $true;
                    Preferred = $false;
                }
            );
            AuthHint = "首次启动会让你选择中国站、国际站、企业域或 iOA，并打开浏览器完成认证。Codex Praetor 不替你选择站点，也不判断账号权益。";
            AuthLaunchHint = "向导会启动 CodeBuddy 官方 CLI。请按上下键选择站点或企业域，浏览器登录完成后退出 CodeBuddy，回到向导继续检测。";
            AuthCommand = "";
            CanaryProvider = "codebuddy";
            KnownBinDirs = @("%USERPROFILE%\AppData\Local\codebuddy\bin");
            ExecutablePatterns = @("codebuddy.exe", "workbuddy.exe", "codebuddy.cmd", "workbuddy.cmd");
        }
        [pscustomobject]@{
            Id = "mimo";
            Name = "MiMo";
            Commands = @("mimo", "mimo.cmd");
            Docs = "https://github.com/XiaomiMiMo/MiMo-Code";
            Installers = @(
                [pscustomobject]@{
                    Label = "官方 Windows PowerShell 安装";
                    DisplayCommand = "powershell -ep Bypass -c `"irm https://mimo.xiaomi.com/install.ps1 | iex`"";
                    Command = "irm https://mimo.xiaomi.com/install.ps1 | iex";
                    NetworkHost = "mimo.xiaomi.com";
                    TimeoutSeconds = 1200;
                    RequiresNode = $false;
                    Preferred = $true;
                },
                [pscustomobject]@{
                    Label = "npm 全局安装";
                    Command = "npm install -g @mimo-ai/cli --registry https://registry.npmjs.org";
                    NetworkHost = "registry.npmjs.org";
                    TimeoutSeconds = 600;
                    RequiresNode = $true;
                    Preferred = $false;
                },
                [pscustomobject]@{
                    Label = "Windows 平台包 fallback";
                    Command = "npm install -g @mimo-ai/mimocode-windows-x64 --registry https://registry.npmjs.org";
                    NetworkHost = "registry.npmjs.org";
                    TimeoutSeconds = 600;
                    RequiresNode = $true;
                    Preferred = $false;
                }
            );
            AuthHint = "优先尝试 mimo/mimo-auto。它是官方限时免费匿名通道；MiMo Platform、Token Plan、自定义 provider 或 API key 属于用户自己的官方账号流程。";
            AuthLaunchHint = "如果 MiMo Auto 不可用，向导会启动 mimo auth login。请在弹出的官方登录/授权流程里完成账号、余额或 Token Plan 检查。";
            AuthCommand = "auth login";
            CanaryProvider = "mimo";
            KnownBinDirs = @("%USERPROFILE%\.mimocode\bin", "%USERPROFILE%\AppData\Local\mimo\bin", "%APPDATA%\npm");
            ExecutablePatterns = @("mimo.exe", "mimo.cmd");
        }
    )
}

function New-OnboardingState {
    $providers = [ordered]@{}
    foreach ($provider in Get-ProviderDefinitions) {
        $providers[$provider.Id] = [ordered]@{
            selected = $false;
            status = "not_selected";
            commandPath = "";
            commandName = "";
            version = "";
            configWritten = $false;
            canary = "not_run";
            lastMessage = "";
            updatedAt = "";
        }
    }

    return [pscustomobject]([ordered]@{
        schemaVersion = 1;
        providerChoice = "";
        startedAt = Get-IsoNow;
        updatedAt = Get-IsoNow;
        providers = [pscustomobject]$providers;
    })
}

function Read-OnboardingState {
    if ($ResetOnboardingState -and (Test-Path -LiteralPath $onboardingStatePath -PathType Leaf)) {
        Remove-Item -LiteralPath $onboardingStatePath -Force
    }
    if (-not (Test-Path -LiteralPath $onboardingStatePath -PathType Leaf)) {
        return New-OnboardingState
    }
    try {
        $state = Get-Content -LiteralPath $onboardingStatePath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($provider in Get-ProviderDefinitions) {
            if (-not (Test-ObjectProperty -Object $state.providers -Name $provider.Id)) {
                $state.providers | Add-Member -NotePropertyName $provider.Id -NotePropertyValue ([pscustomobject]@{
                    selected = $false;
                    status = "not_selected";
                    commandPath = "";
                    commandName = "";
                    version = "";
                    configWritten = $false;
                    canary = "not_run";
                    lastMessage = "";
                    updatedAt = "";
                })
            }
        }
        return $state
    } catch {
        Write-Host "上次向导状态文件读取失败，已重新开始。旧文件不会作为成功依据。" -ForegroundColor Yellow
        return New-OnboardingState
    }
}

function Save-OnboardingState {
    param([object]$State)
    if (-not $Apply) { return }
    $State.updatedAt = Get-IsoNow
    New-Item -ItemType Directory -Path $userCodexDir -Force | Out-Null
    $json = ($State | ConvertTo-Json -Depth 20) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($onboardingStatePath, $json, $utf8NoBom)
}

function Set-ProviderState {
    param(
        [object]$State,
        [string]$ProviderId,
        [string]$Status = "",
        [object]$ProviderStatus = $null,
        [string]$Message = "",
        [string]$Canary = ""
    )

    $entry = $State.providers.$ProviderId
    if ($null -eq $entry) { return }
    if (-not [string]::IsNullOrWhiteSpace($Status)) { $entry.status = $Status }
    if ($null -ne $ProviderStatus) {
        $entry.commandPath = [string]$ProviderStatus.CommandPath
        $entry.commandName = [string]$ProviderStatus.CommandName
        $entry.version = [string]$ProviderStatus.Version
        $entry.configWritten = [bool]$ProviderStatus.ConfigWritten
    }
    if (-not [string]::IsNullOrWhiteSpace($Message)) { $entry.lastMessage = $Message }
    if (-not [string]::IsNullOrWhiteSpace($Canary)) { $entry.canary = $Canary }
    $entry.updatedAt = Get-IsoNow
    Save-OnboardingState -State $State
}

function Add-PathCandidate {
    param(
        [System.Collections.Generic.List[string]]$Parts,
        [string]$Path
    )
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    $expanded = [Environment]::ExpandEnvironmentVariables($Path)
    if ([string]::IsNullOrWhiteSpace($expanded)) { return }
    foreach ($existing in $Parts) {
        if ([string]::Equals($existing.TrimEnd("\"), $expanded.TrimEnd("\"), [StringComparison]::OrdinalIgnoreCase)) {
            return
        }
    }
    $Parts.Add($expanded)
}

function Refresh-ProcessPath {
    param([object[]]$Providers)

    $parts = [System.Collections.Generic.List[string]]::new()
    foreach ($part in (($env:PATH -split ";") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        Add-PathCandidate -Parts $parts -Path $part
    }
    foreach ($scope in @("User", "Machine")) {
        $scopePath = [Environment]::GetEnvironmentVariable("Path", $scope)
        foreach ($part in (($scopePath -split ";") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
            Add-PathCandidate -Parts $parts -Path $part
        }
    }
    foreach ($provider in $Providers) {
        foreach ($dir in $provider.KnownBinDirs) {
            Add-PathCandidate -Parts $parts -Path $dir
        }
    }
    $env:PATH = ($parts -join ";")
}

function Resolve-CommandCandidate {
    param(
        [string[]]$Names,
        [string[]]$KnownBinDirs = @(),
        [string[]]$ExecutablePatterns = @()
    )
    foreach ($name in $Names) {
        $command = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $command) {
            $path = [string]$command.Source
            if ([string]::IsNullOrWhiteSpace($path)) {
                $path = [string]$command.Path
            }
            if ([string]::IsNullOrWhiteSpace($path)) {
                $path = [string]$command.Name
            }
            return [pscustomobject]@{
                Name = $command.Name;
                Path = $path;
            }
        }
    }
    $patterns = @($ExecutablePatterns | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($patterns.Count -eq 0) {
        $patterns = @($Names | ForEach-Object {
            if ($_ -match "\.(exe|cmd|ps1|bat)$") { $_ } else { "$_.exe", "$_.cmd" }
        })
    }
    foreach ($dir in $KnownBinDirs) {
        $expanded = [Environment]::ExpandEnvironmentVariables($dir)
        if ([string]::IsNullOrWhiteSpace($expanded) -or -not (Test-Path -LiteralPath $expanded -PathType Container)) {
            continue
        }
        foreach ($pattern in $patterns) {
            $candidate = Get-ChildItem -LiteralPath $expanded -Filter $pattern -File -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTimeUtc -Descending |
                Select-Object -First 1
            if ($null -ne $candidate) {
                return [pscustomobject]@{
                    Name = $candidate.Name;
                    Path = $candidate.FullName;
                }
            }
        }
    }
    return $null
}

function Set-StatusField {
    param(
        [object]$Status,
        [string]$Name,
        [object]$Value
    )
    if ($null -eq $Status) { return }
    if (Test-ObjectProperty -Object $Status -Name $Name) {
        $Status.$Name = $Value
    } else {
        $Status | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
    }
}

function Get-ProviderStatus {
    param([object]$Provider)

    $knownBinDirs = if (Test-ObjectProperty -Object $Provider -Name "KnownBinDirs") { @($Provider.KnownBinDirs) } else { @() }
    $executablePatterns = if (Test-ObjectProperty -Object $Provider -Name "ExecutablePatterns") { @($Provider.ExecutablePatterns) } else { @() }
    $command = Resolve-CommandCandidate -Names $Provider.Commands -KnownBinDirs $knownBinDirs -ExecutablePatterns $executablePatterns
    $version = ""
    if ($null -ne $command) {
        try {
            $versionOutput = & $command.Path --version 2>$null | Select-Object -First 1
            if (-not [string]::IsNullOrWhiteSpace([string]$versionOutput)) {
                $version = ([string]$versionOutput).Trim()
            }
        } catch {
            $version = "版本读取失败，不影响继续引导"
        }
    }

    return [pscustomobject]@{
        Id = $Provider.Id;
        Name = $Provider.Name;
        Commands = ($Provider.Commands -join ", ");
        Available = ($null -ne $command);
        CommandName = if ($null -ne $command) { $command.Name } else { "" };
        CommandPath = if ($null -ne $command) { $command.Path } else { "" };
        Version = $version;
        Docs = $Provider.Docs;
        AuthHint = $Provider.AuthHint;
        AuthLaunchHint = $Provider.AuthLaunchHint;
        CanaryProvider = $Provider.CanaryProvider;
        Selected = $false;
        Rechecked = $false;
        ConfigWritten = $false;
        CanaryPreviewed = $false;
        CanaryApplied = $false;
        Skipped = $false;
        Note = "";
    }
}

function Show-ProviderStatus {
    param([object[]]$Statuses)

    foreach ($status in $Statuses) {
        if ($status.Available) {
            $versionText = if ([string]::IsNullOrWhiteSpace($status.Version)) { "" } else { "，$($status.Version)" }
            Write-Item -Label $status.Name -Value "已发现：$($status.CommandPath)$versionText" -Color "Green"
        } else {
            Write-Item -Label $status.Name -Value "未发现。可由向导执行官方安装，也可以先跳过。" -Color "DarkYellow"
        }
    }
    Write-Host "说明：这里只检查 CLI 是否可发现，不读取登录状态、token、cookie、账号数据库或余额页面。" -ForegroundColor DarkGray
}

function Read-ProviderChoice {
    param([object]$State)

    if ($NonInteractive -and -not [string]::IsNullOrWhiteSpace($ProviderChoice)) {
        return $ProviderChoice
    }
    if ($NonInteractive -and -not [string]::IsNullOrWhiteSpace($State.providerChoice)) {
        return $State.providerChoice
    }
    if ($NonInteractive) {
        return "2"
    }

    if (-not [string]::IsNullOrWhiteSpace($State.providerChoice)) {
        Write-Host ""
        Write-Host "发现上次未完成的向导状态：选择 $($State.providerChoice)，更新时间 $($State.updatedAt)。" -ForegroundColor Yellow
        $resume = Read-TrimmedHost "按 Enter 继续上次进度；输入 N 重新选择"
        if ($resume -notmatch "^n(?:o)?$" -and $State.providerChoice -in @("1", "2", "3", "4", "5")) {
            return $State.providerChoice
        }
    }

    Write-Host ""
    Write-Host "请选择 provider 配置入口："
    Write-Host "  1. 配置全部 provider"
    Write-Host "  2. 先不配置 provider，只安装并验证 Codex Praetor 本体"
    Write-Host "  3. 只配置 Qoder"
    Write-Host "  4. 只配置 CodeBuddy"
    Write-Host "  5. 只配置 MiMo"
    $choice = Read-TrimmedHost "输入选项 [默认 2]"
    if ([string]::IsNullOrWhiteSpace($choice)) {
        return "2"
    }
    if ($choice -notin @("1", "2", "3", "4", "5")) {
        Write-Host "无法识别选项，按“暂不配置 provider”继续。" -ForegroundColor Yellow
        return "2"
    }
    return $choice
}

function Get-SelectedProviderIds {
    param([string]$Choice)
    switch ($Choice) {
        "1" { return @("qoder", "codebuddy", "mimo") }
        "3" { return @("qoder") }
        "4" { return @("codebuddy") }
        "5" { return @("mimo") }
        default { return @() }
    }
}

function Wait-InstallerNetwork {
    param(
        [string]$HostName,
        [int]$TimeoutSeconds = 240
    )

    if ([string]::IsNullOrWhiteSpace($HostName)) { return }
    Write-Host "正在检查安装源网络：$HostName" -ForegroundColor Cyan
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $lastError = ""
    do {
        try {
            Resolve-DnsName -Name $HostName -ErrorAction Stop | Out-Null
            $tcpOk = Test-NetConnection -ComputerName $HostName -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue
            if ($tcpOk) { return }
            $lastError = "443 端口暂时不可达"
        } catch {
            $lastError = $_.Exception.Message
        }
        Start-Sleep -Seconds 5
    } while ((Get-Date) -lt $deadline)

    throw "安装源网络暂时不可用：$HostName。$lastError。请检查网络或代理后重试，也可以先跳过这个 provider。"
}

function Invoke-CommandWithTimeout {
    param(
        [string]$FilePath,
        [string[]]$ArgumentList,
        [int]$TimeoutSeconds
    )

    $result = Invoke-CodexPraetorNative -FilePath $FilePath -ArgumentList $ArgumentList -WorkingDirectory $scriptRoot -TimeoutSeconds $TimeoutSeconds
    if (-not [string]::IsNullOrWhiteSpace([string]$result.stdout)) { Write-Host ([string]$result.stdout).Trim() }
    if (-not [string]::IsNullOrWhiteSpace([string]$result.stderr)) { Write-Host ([string]$result.stderr).Trim() -ForegroundColor DarkGray }
    if ($result.timed_out) {
        throw "官方安装命令超过 $TimeoutSeconds 秒仍未结束。请检查网络或代理后重试，也可以先跳过这个 provider。"
    }
    if ([int]$result.exit_code -ne 0) {
        throw "官方安装命令失败，退出码：$($result.exit_code)"
    }
}

function Invoke-OfficialInstallCommand {
    param(
        [object]$Provider,
        [object]$Installer
    )

    Write-Host ""
    Write-Host "开始执行 $($Provider.Name) 官方安装：" -ForegroundColor Cyan
    $shownCommand = if (Test-ObjectProperty -Object $Installer -Name "DisplayCommand") { $Installer.DisplayCommand } else { $Installer.Command }
    Write-Host $shownCommand
    if (Test-ObjectProperty -Object $Installer -Name "NetworkHost") {
        Wait-InstallerNetwork -HostName ([string]$Installer.NetworkHost)
    }
    $timeoutSeconds = 600
    if (Test-ObjectProperty -Object $Installer -Name "TimeoutSeconds") {
        $timeoutSeconds = [int]$Installer.TimeoutSeconds
    }
    $shell = if (Test-ObjectProperty -Object $Installer -Name "Shell") { [string]$Installer.Shell } else { "powershell" }
    if ($shell -eq "cmd") {
        Invoke-CommandWithTimeout -FilePath "$env:SystemRoot\System32\cmd.exe" -ArgumentList @("/d", "/c", $Installer.Command) -TimeoutSeconds $timeoutSeconds
    } else {
        Invoke-CommandWithTimeout -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", $Installer.Command) -TimeoutSeconds $timeoutSeconds
    }
}

function Select-Installer {
    param([object]$Provider)

    $installers = @($Provider.Installers)
    if ($NonInteractive) {
        return $null
    }

    Write-Host ""
    Write-Host "$($Provider.Name) 还没有安装。向导可以替你执行官方安装命令，也可以跳过。" -ForegroundColor Yellow
    for ($i = 0; $i -lt $installers.Count; $i++) {
        $marker = if ($installers[$i].Preferred) { "（推荐）" } else { "" }
        $nodeHint = if ($installers[$i].RequiresNode) { "，需要 Node.js" } else { "" }
        Write-Host ("  {0}. {1}{2}{3}" -f ($i + 1), $installers[$i].Label, $marker, $nodeHint)
        $shownCommand = if (Test-ObjectProperty -Object $installers[$i] -Name "DisplayCommand") { $installers[$i].DisplayCommand } else { $installers[$i].Command }
        Write-Host ("     {0}" -f $shownCommand) -ForegroundColor DarkGray
    }
    Write-Host "  O. 打开官方说明"
    Write-Host "  R. 我已经自己装好了，重新检测"
    Write-Host "  S. 跳过 $($Provider.Name)"
    $answer = Read-TrimmedHost "选择 [默认 1]"
    if ([string]::IsNullOrWhiteSpace($answer)) { return $installers[0] }
    if ($answer -match "^[oO]$") {
        Start-Process $Provider.Docs | Out-Null
        return "open_docs"
    }
    if ($answer -match "^[rR]$") { return "recheck" }
    if ($answer -match "^[sS]$") { return "skip" }
    $index = 0
    if ([int]::TryParse($answer, [ref]$index) -and $index -ge 1 -and $index -le $installers.Count) {
        return $installers[$index - 1]
    }
    Write-Host "无法识别选项，按推荐官方安装方式继续。" -ForegroundColor Yellow
    return $installers[0]
}

function Ensure-ProviderInstalled {
    param(
        [object]$Provider,
        [object]$Status,
        [object]$State,
        [object[]]$AllProviders
    )

    if ($Status.Available) {
        Set-ProviderState -State $State -ProviderId $Provider.Id -Status "cli_detected" -ProviderStatus $Status -Message "CLI 已发现"
        return $Status
    }

    if (-not $Apply) {
        Write-Host ""
        Write-Host "$($Provider.Name) 未安装。实际安装模式会询问是否执行官方安装命令；预览模式不修改系统。" -ForegroundColor Yellow
        Set-ProviderState -State $State -ProviderId $Provider.Id -Status "needs_install" -Message "预览模式未执行安装"
        return $Status
    }

    if ($NonInteractive) {
        Write-Host "$($Provider.Name) 未发现；非交互模式不会自动安装第三方 provider，已标记为需要人工安装。" -ForegroundColor Yellow
        Set-ProviderState -State $State -ProviderId $Provider.Id -Status "needs_install_interactive" -Message "非交互模式未安装 provider"
        return $Status
    }

    while (-not $Status.Available) {
        $selection = Select-Installer -Provider $Provider
        if ($selection -eq "skip") {
            Set-StatusField -Status $Status -Name "Skipped" -Value $true
            Set-StatusField -Status $Status -Name "Note" -Value "用户选择跳过。"
            Set-ProviderState -State $State -ProviderId $Provider.Id -Status "skipped" -Message $Status.Note
            return $Status
        }
        if ($selection -eq "open_docs") {
            Write-Host "官方说明已打开。安装完成后回到这里选择 R 重新检测，或继续选择安装命令。" -ForegroundColor Cyan
            continue
        }
        if ($selection -ne "recheck") {
            try {
                Set-ProviderState -State $State -ProviderId $Provider.Id -Status "installing" -Message "正在执行官方安装命令"
                Invoke-OfficialInstallCommand -Provider $Provider -Installer $selection
            } catch {
                Write-Host $_.Exception.Message -ForegroundColor Red
                Set-ProviderState -State $State -ProviderId $Provider.Id -Status "install_failed" -Message $_.Exception.Message
                $retry = Read-TrimmedHost "按 Enter 重试/换安装方式，输入 S 跳过"
                if ($retry -match "^[sS]$") {
                    Set-StatusField -Status $Status -Name "Skipped" -Value $true
                    Set-ProviderState -State $State -ProviderId $Provider.Id -Status "skipped" -Message "安装失败后用户选择跳过"
                    return $Status
                }
                continue
            }
        }

        Refresh-ProcessPath -Providers $AllProviders
        $newStatus = Get-ProviderStatus -Provider $Provider
        Set-StatusField -Status $Status -Name "Available" -Value $newStatus.Available
        Set-StatusField -Status $Status -Name "CommandName" -Value $newStatus.CommandName
        Set-StatusField -Status $Status -Name "CommandPath" -Value $newStatus.CommandPath
        Set-StatusField -Status $Status -Name "Version" -Value $newStatus.Version
        Set-StatusField -Status $Status -Name "Rechecked" -Value $true
        if ($Status.Available) {
            Write-Host "复检通过：已发现 $($Provider.Name) CLI：$($Status.CommandPath)" -ForegroundColor Green
            Set-ProviderState -State $State -ProviderId $Provider.Id -Status "cli_detected" -ProviderStatus $Status -Message "安装后复检通过"
            return $Status
        }
        Write-Host "复检后仍未发现 $($Provider.Name)。常见原因是 PATH 未刷新、网络失败、权限限制或官方安装脚本异常。" -ForegroundColor Yellow
        Set-ProviderState -State $State -ProviderId $Provider.Id -Status "install_recheck_failed" -Message "安装后仍未发现 CLI"
    }

    return $Status
}

function Invoke-ProviderAuthFlow {
    param(
        [object]$Provider,
        [object]$Status,
        [object]$State
    )

    if (-not $Status.Available -or $Status.Skipped) { return $Status }
    if ($NonInteractive -or -not $Apply) {
        Set-ProviderState -State $State -ProviderId $Provider.Id -Status "auth_not_checked" -ProviderStatus $Status -Message "未进入交互授权陪跑"
        return $Status
    }

    Write-Host ""
    Write-Host "$($Provider.Name) 登录/授权陪跑" -ForegroundColor Cyan
    Write-Host $Provider.AuthHint
    Write-Host ""
    Write-Host "向导不会读取账号文件，也不会要求你把 token、cookie、PAT、API key 贴到这里。"

    while ($true) {
        Write-Host ""
        Write-Host "[L] 启动官方 CLI 登录/初始化流程"
        Write-Host "[C] 我已完成登录/授权，继续复检和 canary"
        Write-Host "[O] 打开官方说明"
        Write-Host "[S] 跳过 $($Provider.Name)"
        $answer = Read-TrimmedHost "选择 [默认 C]"
        if ([string]::IsNullOrWhiteSpace($answer) -or $answer -match "^[cC]$") {
            Set-ProviderState -State $State -ProviderId $Provider.Id -Status "auth_user_done_recheck" -ProviderStatus $Status -Message "用户声明已完成官方授权，进入复检"
            return (Get-ProviderStatus -Provider $Provider)
        }
        if ($answer -match "^[oO]$") {
            Start-Process $Provider.Docs | Out-Null
            continue
        }
        if ($answer -match "^[sS]$") {
            Set-StatusField -Status $Status -Name "Skipped" -Value $true
            Set-StatusField -Status $Status -Name "Note" -Value "用户在授权阶段选择跳过。"
            Set-ProviderState -State $State -ProviderId $Provider.Id -Status "skipped" -ProviderStatus $Status -Message "用户在授权阶段选择跳过"
            return $Status
        }
        if ($answer -match "^[lL]$") {
            Write-Host $Provider.AuthLaunchHint -ForegroundColor Cyan
            Set-ProviderState -State $State -ProviderId $Provider.Id -Status "auth_in_progress" -ProviderStatus $Status -Message "已启动官方 CLI 授权流程"
            try {
                if ([string]::IsNullOrWhiteSpace($Provider.AuthCommand)) {
                    & $Status.CommandPath
                } else {
                    $authArgs = $Provider.AuthCommand -split " "
                    & $Status.CommandPath @authArgs
                }
            } catch {
                Write-Host "官方 CLI 授权流程返回异常：$($_.Exception.Message)" -ForegroundColor Yellow
                Set-ProviderState -State $State -ProviderId $Provider.Id -Status "auth_launch_failed" -ProviderStatus $Status -Message $_.Exception.Message
            }
            Write-Host "如果你已经完成官方登录/授权，下一步选择 C 继续复检；如果官方流程还没完成，可以再次选择 L。" -ForegroundColor Cyan
            continue
        }
    }
}

function Update-ProviderConfig {
    param(
        [object[]]$Statuses,
        [object]$State
    )

    $availableSelected = @($Statuses | Where-Object { $_.Selected -and $_.Available -and -not $_.Skipped })
    if ($availableSelected.Count -eq 0) {
        return
    }
    if (-not (Test-Path -LiteralPath $configTemplate -PathType Leaf)) {
        throw "配置模板缺失：$configTemplate"
    }

    New-Item -ItemType Directory -Path $userCodexDir -Force | Out-Null

    if (Test-Path -LiteralPath $userConfigPath -PathType Leaf) {
        $config = Get-Content -LiteralPath $userConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } else {
        $config = Get-Content -LiteralPath $configTemplate -Raw -Encoding UTF8 | ConvertFrom-Json
    }

    foreach ($status in $availableSelected) {
        if ($status.Id -eq "qoder" -and $null -ne $config.providers.qoder) {
            $config.providers.qoder.cliPath = $status.CommandPath
        }
        if ($status.Id -eq "codebuddy" -and $null -ne $config.providers.codebuddy) {
            $config.providers.codebuddy.cliPath = $status.CommandPath
            $nodeCommand = Resolve-CommandCandidate -Names @("node")
            if ($null -ne $nodeCommand) {
                $config.providers.codebuddy.nodePath = $nodeCommand.Path
            }
        }
        if ($status.Id -eq "mimo" -and $null -ne $config.providers.mimo) {
            $config.providers.mimo.cliPath = $status.CommandPath
        }
        $status.ConfigWritten = $true
        Set-ProviderState -State $State -ProviderId $status.Id -Status "config_written" -ProviderStatus $status -Message "本机配置已记录 CLI 路径"
    }

    $json = ($config | ConvertTo-Json -Depth 50) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($userConfigPath, $json, $utf8NoBom)
}

function Invoke-CanaryStep {
    param(
        [object[]]$Statuses,
        [object]$State
    )

    if (-not (Test-Path -LiteralPath $canaryScript -PathType Leaf)) {
        return
    }

    $ready = @($Statuses | Where-Object { $_.Selected -and $_.Available -and -not $_.Skipped })
    if ($ready.Count -eq 0) {
        return
    }

    Write-Section "只读 canary"
    Write-Host "canary 会验证外部 agent 的当前 CLI、模型、权限合同和本地审计任务，成功后才允许真实派工。"
    Write-Host "预览不会启动真实 worker；真实 canary 可能消耗 provider 额度，所以需要你明确确认。"

    foreach ($status in $ready) {
        Write-Host ""
        Write-Host "$($status.Name) canary 命令：" -ForegroundColor Cyan
        Write-Host "powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\test-provider-capability-canary.ps1 -Provider $($status.CanaryProvider) -ConfigPath `"$userConfigPath`""

        if ($NonInteractive) {
            Set-ProviderState -State $State -ProviderId $status.Id -Status "canary_not_run" -ProviderStatus $status -Canary "not_run" -Message "非交互模式未运行 canary"
            continue
        }

        $answer = Read-TrimmedHost "选择：[P] 只预览 / [A] 运行真实只读 canary / [S] 先跳过 [默认 P]"
        if ($answer -match "^[sS]$") {
            Set-ProviderState -State $State -ProviderId $status.Id -Status "canary_skipped" -ProviderStatus $status -Canary "skipped" -Message "用户跳过 canary"
            continue
        }

        $canaryArgs = @(
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            $canaryScript,
            "-Provider",
            $status.CanaryProvider,
            "-ConfigPath",
            $userConfigPath
        )
        $mode = "preview"
        if ($answer -match "^[aA]$") {
            $canaryArgs += "-Apply"
            $mode = "apply"
        }
        try {
            $canaryResult = Invoke-CodexPraetorNative -FilePath "powershell.exe" -ArgumentList $canaryArgs -WorkingDirectory $scriptRoot -TimeoutSeconds 360
            if (-not [string]::IsNullOrWhiteSpace([string]$canaryResult.stdout)) { Write-Host ([string]$canaryResult.stdout).Trim() }
            if (-not [string]::IsNullOrWhiteSpace([string]$canaryResult.stderr)) { Write-Host ([string]$canaryResult.stderr).Trim() -ForegroundColor DarkGray }
            if ([int]$canaryResult.exit_code -eq 0 -and -not $canaryResult.timed_out) {
                if ($mode -eq "apply") {
                    $status.CanaryApplied = $true
                    Set-ProviderState -State $State -ProviderId $status.Id -Status "ready" -ProviderStatus $status -Canary "passed" -Message "真实只读 canary 通过"
                } else {
                    $status.CanaryPreviewed = $true
                    Set-ProviderState -State $State -ProviderId $status.Id -Status "canary_previewed" -ProviderStatus $status -Canary "previewed" -Message "canary 预览通过"
                }
            } else {
                Set-ProviderState -State $State -ProviderId $status.Id -Status "canary_failed" -ProviderStatus $status -Canary "failed" -Message "canary 退出码：$($canaryResult.exit_code)"
            }
        } catch {
            Write-Host "canary 未通过：$($_.Exception.Message)" -ForegroundColor Yellow
            Set-ProviderState -State $State -ProviderId $status.Id -Status "canary_failed" -ProviderStatus $status -Canary "failed" -Message $_.Exception.Message
        }
    }
}

function Invoke-ProviderOnboarding {
    param(
        [object[]]$Definitions,
        [object[]]$Statuses,
        [string[]]$SelectedIds,
        [object]$State
    )

    foreach ($id in $SelectedIds) {
        $definition = $Definitions | Where-Object { $_.Id -eq $id } | Select-Object -First 1
        $status = $Statuses | Where-Object { $_.Id -eq $id } | Select-Object -First 1
        if ($null -eq $definition -or $null -eq $status) { continue }
        $status.Selected = $true
        $State.providers.$id.selected = $true
        Save-OnboardingState -State $State

        Write-Section "$($status.Name) 配置"
        if ($status.Available) {
            Write-Host "已发现 $($status.Name)：$($status.CommandPath)" -ForegroundColor Green
        }

        $status = Ensure-ProviderInstalled -Provider $definition -Status $status -State $State -AllProviders $Definitions
        if ($status.Skipped -or -not $status.Available) {
            continue
        }

        $status = Invoke-ProviderAuthFlow -Provider $definition -Status $status -State $State
        if ($status.Skipped -or -not $status.Available) {
            continue
        }
        $latest = Get-ProviderStatus -Provider $definition
        Set-StatusField -Status $status -Name "Available" -Value $latest.Available
        Set-StatusField -Status $status -Name "CommandName" -Value $latest.CommandName
        Set-StatusField -Status $status -Name "CommandPath" -Value $latest.CommandPath
        Set-StatusField -Status $status -Name "Version" -Value $latest.Version
        Set-StatusField -Status $status -Name "Rechecked" -Value $true

        if ($status.Available) {
            Write-Host "复检通过：$($status.Name) CLI 仍然可发现。" -ForegroundColor Green
            Set-ProviderState -State $State -ProviderId $definition.Id -Status "cli_rechecked" -ProviderStatus $status -Message "授权后 CLI 复检通过"
        } else {
            Write-Host "复检后找不到 $($status.Name) CLI。可以重新运行 setup.cmd，它会从当前状态继续。" -ForegroundColor Yellow
            Set-ProviderState -State $State -ProviderId $definition.Id -Status "cli_missing_after_auth" -ProviderStatus $status -Message "授权后 CLI 复检失败"
        }
    }
}

function Show-FinalSummary {
    param(
        [object[]]$Statuses,
        [object]$State
    )

    Write-Section "最终状态总览"
    if ($Apply) {
        Write-Item -Label "Codex Praetor 本体" -Value "已安装；需要刷新正在运行的 Codex Desktop host 或重启 Codex。仅打开新任务不保证刷新插件发现。" -Color "Green"
    } else {
        Write-Item -Label "Codex Praetor 本体" -Value "预览模式未安装；加 -Apply 或双击 setup.cmd 执行。" -Color "Yellow"
    }
    Write-Item -Label "MCP 工具" -Value "随插件安装；需要 Node.js 才能启动。" -Color "Gray"

    foreach ($status in $Statuses) {
        $entry = $State.providers.$($status.Id)
        if (-not $status.Selected) {
            Write-Item -Label $status.Name -Value "未选择配置；之后可重新运行 setup.cmd。" -Color "DarkGray"
            continue
        }
        if ($status.Skipped -or $entry.status -eq "skipped") {
            Write-Item -Label $status.Name -Value "已跳过；不会影响本体 dry-run。" -Color "DarkYellow"
            continue
        }
        if ($entry.status -eq "ready") {
            Write-Item -Label $status.Name -Value "已通过真实只读 canary，可作为真实派工候选。" -Color "Green"
            continue
        }
        if ($status.Available) {
            $parts = @("CLI 已发现")
            if ($status.ConfigWritten -or $entry.configWritten) { $parts += "本机配置已记录路径" }
            if ($entry.canary -eq "previewed") { $parts += "canary 已预览" }
            if ($entry.canary -eq "failed") { $parts += "canary 未通过，需要按 provider 提示处理" }
            if ($entry.status -match "auth|config|cli") { $parts += "真实派工前仍建议完成官方授权并跑真实只读 canary" }
            Write-Item -Label $status.Name -Value ($parts -join "；") -Color "Green"
        } else {
            $message = if (-not [string]::IsNullOrWhiteSpace($entry.lastMessage)) { $entry.lastMessage } else { "CLI 未发现" }
            Write-Item -Label $status.Name -Value "$message；重新运行 setup.cmd 会从状态文件继续。" -Color "Yellow"
        }
    }

    if (Test-Path -LiteralPath $userConfigPath -PathType Leaf) {
        Write-Item -Label "本机配置" -Value $userConfigPath -Color "Green"
    } else {
        Write-Item -Label "本机配置" -Value "未写入 provider 路径；跳过 provider 时这是正常状态。" -Color "Gray"
    }
    if (Test-Path -LiteralPath $onboardingStatePath -PathType Leaf) {
        Write-Item -Label "向导状态" -Value $onboardingStatePath -Color "Gray"
    }

    Write-Host ""
    Write-Host "下一步：打开 Codex 新任务，输入：" -ForegroundColor Cyan
    Write-Host "拆分一下任务，分配给其他 agent 做 dry-run，不要真实修改文件。"
}

if (-not (Test-Path -LiteralPath $installScript -PathType Leaf)) {
    throw "安装脚本缺失：$installScript"
}

$state = Read-OnboardingState

Write-Section "Codex Praetor 安装向导"
Write-Item -Label "产品版本" -Value $productVersion -Color "Green"
Write-Host "版本：$productVersion"
Write-Host "安装范围：当前 Windows 用户插件目录，不需要管理员权限。"
Write-Host "这个向导会安装 Codex Praetor 本体，并把 Qoder、CodeBuddy、MiMo 的安装、登录陪跑、复检和 canary 串在同一个命令里。"
Write-Host "它不会替你登录账号，不会读取 token、cookie、账号数据库，也不会替你确认账单。"

Write-Section "安装前检查"
$psVersion = $PSVersionTable.PSVersion.ToString()
Write-Item -Label "PowerShell" -Value $psVersion -Color "Green"

if (Get-Command node -ErrorAction SilentlyContinue) {
    $nodeVersion = (& node --version 2>$null | Select-Object -First 1)
    Write-Item -Label "Node.js" -Value "已发现 $nodeVersion" -Color "Green"
} else {
    Write-Item -Label "Node.js" -Value "未发现。本体可先安装；CodeBuddy/MiMo 的 npm fallback 和 MCP runtime 会受影响。" -Color "Yellow"
}

if (Get-Command git -ErrorAction SilentlyContinue) {
    Write-Item -Label "Git" -Value "已发现" -Color "Green"
} else {
    Write-Item -Label "Git" -Value "未发现。本体可先安装，但真实 worker 派工和 worktree 隔离需要 Git。" -Color "Yellow"
}

$providerDefinitions = @(Get-ProviderDefinitions)
Refresh-ProcessPath -Providers $providerDefinitions
$providerStatuses = @($providerDefinitions | ForEach-Object { Get-ProviderStatus -Provider $_ })
Show-ProviderStatus -Statuses $providerStatuses

$choice = Read-ProviderChoice -State $state
$state.providerChoice = $choice
foreach ($provider in $providerDefinitions) {
    $state.providers.$($provider.Id).selected = $false
    if ($choice -eq "2") {
        $state.providers.$($provider.Id).status = "not_selected"
    }
}
Save-OnboardingState -State $state

$selectedIds = @(Get-SelectedProviderIds -Choice $choice)
if ($selectedIds.Count -eq 0) {
    Write-Section "provider 配置"
    Write-Host "你选择了先不配置 provider。Codex Praetor 本体安装、dry-run、状态查询和冲突检测仍可继续。" -ForegroundColor Cyan
} else {
    Invoke-ProviderOnboarding -Definitions $providerDefinitions -Statuses $providerStatuses -SelectedIds $selectedIds -State $state
}

if (-not $Apply) {
    Write-Section "预览结束"
    Write-Host "当前是预览模式，没有修改文件、没有安装本体、没有安装第三方 provider。"
    Write-Host "双击 setup.cmd 或运行下面命令会执行实际安装，并在需要时陪你完成 provider 官方授权："
    Write-Host "powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1 -Apply"
    Show-FinalSummary -Statuses $providerStatuses -State $state
    exit 0
}

if (-not $NonInteractive) {
    Write-Host ""
    $confirm = Read-TrimmedHost "按 Enter 开始安装 Codex Praetor 本体，输入 N 取消"
    if ($confirm -match "^n(?:o)?$") {
        Write-Host "已取消安装。重新运行 setup.cmd 会从向导状态继续。"
        Save-OnboardingState -State $state
        exit 0
    }
}

Write-Section "正在安装 Codex Praetor 本体"
$installResult = Invoke-CodexPraetorNative -FilePath "powershell.exe" -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $installScript, "-SourcePlugin", (Join-Path $scriptRoot "plugin"), "-Apply") -WorkingDirectory $scriptRoot -TimeoutSeconds 600
if (-not [string]::IsNullOrWhiteSpace([string]$installResult.stdout)) { Write-Host ([string]$installResult.stdout).Trim() }
if (-not [string]::IsNullOrWhiteSpace([string]$installResult.stderr)) { Write-Host ([string]$installResult.stderr).Trim() -ForegroundColor DarkGray }
if ($installResult.timed_out -or [int]$installResult.exit_code -ne 0) {
    throw "插件安装失败，退出码：$($installResult.exit_code)"
}

if (-not $SkipMaintenance) {
    if (-not (Test-Path -LiteralPath $maintenanceScript -PathType Leaf)) {
        throw "维护脚本缺失：$maintenanceScript"
    }
    Write-Section "安装代际自动回收维护"
    $maintenanceResult = Invoke-CodexPraetorNative -FilePath "powershell.exe" -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $maintenanceScript, "-UserProfileRoot", $env:USERPROFILE, "-SourceRoot", $scriptRoot, "-Apply") -WorkingDirectory $scriptRoot -TimeoutSeconds 120
    if (-not [string]::IsNullOrWhiteSpace([string]$maintenanceResult.stdout)) { Write-Host ([string]$maintenanceResult.stdout).Trim() }
    if (-not [string]::IsNullOrWhiteSpace([string]$maintenanceResult.stderr)) { Write-Host ([string]$maintenanceResult.stderr).Trim() -ForegroundColor DarkGray }
    if ($maintenanceResult.timed_out -or [int]$maintenanceResult.exit_code -ne 0) {
        throw "代际自动回收维护安装失败，退出码：$($maintenanceResult.exit_code)"
    }
} else {
    Write-Host "[INFO] 已跳过代际自动回收维护安装。仅允许隔离测试或开发验证使用。" -ForegroundColor Yellow
}

Update-ProviderConfig -Statuses $providerStatuses -State $state
Invoke-CanaryStep -Statuses $providerStatuses -State $state
Show-FinalSummary -Statuses $providerStatuses -State $state
