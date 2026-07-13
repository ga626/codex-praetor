param(
    [switch]$Apply,
    [switch]$NonInteractive,
    [ValidateSet("1", "2", "3", "4", "5")]
    [string]$ProviderChoice = ""
)

$ErrorActionPreference = "Stop"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[Console]::InputEncoding = $utf8NoBom
[Console]::OutputEncoding = $utf8NoBom
$OutputEncoding = $utf8NoBom

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$installScript = Join-Path $scriptRoot "scripts\install\install-user.ps1"
$configTemplate = Join-Path $scriptRoot "config\codex-praetor-tiers.example.json"
$userConfigPath = Join-Path $env:USERPROFILE ".codex\codex-praetor.local.json"
$canaryScript = Join-Path $scriptRoot "scripts\verify\test-provider-readonly-canary.ps1"

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

function Get-ProviderDefinitions {
    return @(
        [pscustomobject]@{
            Id = "qoder";
            Name = "Qoder";
            Commands = @("qodercli", "qoder");
            Docs = "https://docs.qoder.com/en/cli/quick-start";
            InstallHint = "Windows PowerShell: irm https://qoder.com/install.ps1 | iex";
            AuthHint = "首次使用前请按 Qoder 官方流程完成交互登录。PAT/环境变量更适合自动化，不作为普通用户主路径。Windows on Arm 当前是 provider 边界。";
            CanaryProvider = "qoder";
        }
        [pscustomobject]@{
            Id = "codebuddy";
            Name = "CodeBuddy";
            Commands = @("codebuddy", "workbuddy");
            Docs = "https://www.codebuddy.ai/docs/cli/quickstart";
            InstallHint = "npm: npm install -g @tencent-ai/codebuddy-code；Windows native beta: irm https://www.codebuddy.cn/cli/install.ps1 | iex";
            AuthHint = "首次启动会让你选择中国站、国际站、企业域或 iOA，并打开浏览器完成认证。Codex Praetor 不替你选择站点。";
            CanaryProvider = "codebuddy";
        }
        [pscustomobject]@{
            Id = "mimo";
            Name = "MiMo";
            Commands = @("mimo", "mimo.cmd");
            Docs = "https://github.com/XiaomiMiMo/MiMo-Code";
            InstallHint = "Windows PowerShell: powershell -ep Bypass -c `"irm https://mimo.xiaomi.com/install.ps1 | iex`"；npm: npm install -g @mimo-ai/cli";
            AuthHint = "优先尝试 mimo/mimo-auto。它是官方限时免费匿名通道；MiMo Platform、Token Plan、自定义 provider 或 API key 属于用户自己的官方账号流程。";
            CanaryProvider = "mimo";
        }
    )
}

function Resolve-CommandCandidate {
    param([string[]]$Names)
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
    return $null
}

function Get-ProviderStatus {
    param([object]$Provider)

    $command = Resolve-CommandCandidate -Names $Provider.Commands
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
        InstallHint = $Provider.InstallHint;
        AuthHint = $Provider.AuthHint;
        CanaryProvider = $Provider.CanaryProvider;
        Selected = $false;
        Rechecked = $false;
        ConfigWritten = $false;
        CanaryPreviewed = $false;
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
            Write-Item -Label $status.Name -Value "未发现。可稍后安装，不影响 Codex Praetor 本体。" -Color "DarkYellow"
        }
    }
    Write-Host "说明：这里仅检查 CLI 是否可发现，不读取登录状态、token、cookie、账号数据库或余额页面。" -ForegroundColor DarkGray
}

function Read-ProviderChoice {
    if ($NonInteractive -and -not [string]::IsNullOrWhiteSpace($ProviderChoice)) {
        return $ProviderChoice
    }

    Write-Host ""
    Write-Host "请选择 provider 配置入口："
    Write-Host "  1. 配置全部 provider"
    Write-Host "  2. 先不配置 provider，只安装并验证 Codex Praetor 本体"
    Write-Host "  3. 只配置 Qoder"
    Write-Host "  4. 只配置 CodeBuddy"
    Write-Host "  5. 只配置 MiMo"
    $choice = Read-Host "输入选项 [默认 2]"
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

function Wait-ForProviderUserAction {
    param([object]$Status)

    if ($NonInteractive) {
        if ($Status.Available) {
            return "continue"
        }
        return "skip"
    }

    Write-Host ""
    Write-Host "$($Status.Name) 需要你在官方流程里处理的事：" -ForegroundColor Cyan
    Write-Host $Status.AuthHint
    Write-Host ""
    Write-Host "[Enter] 我已完成安装/登录，继续检测"
    Write-Host "[O] 打开官方说明"
    Write-Host "[S] 跳过 $($Status.Name)"
    $answer = Read-Host "选择"
    if ($answer -match "^[oO]$") {
        Start-Process $Status.Docs | Out-Null
        Write-Host "已打开官方说明。完成后回到这里按 Enter 继续检测，或输入 S 跳过。"
        $answer = Read-Host "选择"
    }
    if ($answer -match "^[sS]$") {
        return "skip"
    }
    return "continue"
}

function Invoke-ProviderOnboarding {
    param(
        [object[]]$Statuses,
        [string[]]$SelectedIds
    )

    foreach ($id in $SelectedIds) {
        $status = $Statuses | Where-Object { $_.Id -eq $id } | Select-Object -First 1
        if ($null -eq $status) { continue }
        $status.Selected = $true

        Write-Section "$($status.Name) 配置"
        if ($status.Available) {
            Write-Host "已发现 $($status.Name)：$($status.CommandPath)" -ForegroundColor Green
        } else {
            Write-Host "当前没有发现 $($status.Name) CLI。" -ForegroundColor Yellow
            Write-Host "官方安装入口：" -ForegroundColor Cyan
            Write-Host "  $($status.Docs)"
            Write-Host "官方安装方式：" -ForegroundColor Cyan
            Write-Host "  $($status.InstallHint)"
        }

        $action = Wait-ForProviderUserAction -Status $status
        if ($action -eq "skip") {
            $status.Skipped = $true
            $status.Note = "用户选择跳过，之后可以重新运行 setup.cmd。"
            continue
        }

        $definition = Get-ProviderDefinitions | Where-Object { $_.Id -eq $id } | Select-Object -First 1
        $newStatus = Get-ProviderStatus -Provider $definition
        $status.Available = $newStatus.Available
        $status.CommandName = $newStatus.CommandName
        $status.CommandPath = $newStatus.CommandPath
        $status.Version = $newStatus.Version
        $status.Rechecked = $true

        if ($status.Available) {
            Write-Host "复检通过：已发现 $($status.Name) CLI。" -ForegroundColor Green
        } else {
            Write-Host "复检后仍未发现 $($status.Name)。这不影响本体安装，只表示真实派工暂不可用。" -ForegroundColor Yellow
            $status.Note = "未发现 CLI。"
        }
    }
}

function Update-ProviderConfig {
    param([object[]]$Statuses)

    $availableSelected = @($Statuses | Where-Object { $_.Selected -and $_.Available -and -not $_.Skipped })
    if ($availableSelected.Count -eq 0) {
        return
    }
    if (-not (Test-Path -LiteralPath $configTemplate -PathType Leaf)) {
        throw "配置模板缺失：$configTemplate"
    }

    $parent = Split-Path -Parent $userConfigPath
    New-Item -ItemType Directory -Path $parent -Force | Out-Null

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
    }

    $json = ($config | ConvertTo-Json -Depth 50) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($userConfigPath, $json, $utf8NoBom)
}

function Invoke-CanaryPreview {
    param([object[]]$Statuses)

    if ($NonInteractive -or -not (Test-Path -LiteralPath $canaryScript -PathType Leaf)) {
        return
    }

    $ready = @($Statuses | Where-Object { $_.Selected -and $_.Available -and -not $_.Skipped })
    if ($ready.Count -eq 0) {
        return
    }

    Write-Section "只读 canary"
    Write-Host "只读 canary 的作用：让外部 agent 只读固定文件并返回标记，证明 Codex Praetor 能调用它。"
    Write-Host "现在可以先预览命令，不启动真实 worker；登录完成后你也可以按提示加 -Apply。"

    foreach ($status in $ready) {
        Write-Host ""
        Write-Host "$($status.Name) canary 预览命令：" -ForegroundColor Cyan
        Write-Host "powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\test-provider-readonly-canary.ps1 -Provider $($status.CanaryProvider)"
        $answer = Read-Host "现在运行预览吗？[y/N]"
        if ($answer -match "^[yY]") {
            & powershell -NoProfile -ExecutionPolicy Bypass -File $canaryScript -Provider $status.CanaryProvider -ConfigPath $userConfigPath
            if ($LASTEXITCODE -eq 0) {
                $status.CanaryPreviewed = $true
            }
        }
    }
}

function Show-FinalSummary {
    param([object[]]$Statuses)

    Write-Section "最终状态总览"
    Write-Item -Label "Codex Praetor 本体" -Value "已安装；重启 Codex 或打开新任务后应能发现插件。" -Color "Green"
    Write-Item -Label "MCP 工具" -Value "随插件安装；需要 Node.js 才能启动。" -Color "Gray"

    foreach ($status in $Statuses) {
        if (-not $status.Selected) {
            Write-Item -Label $status.Name -Value "未选择配置；之后可重新运行 setup.cmd。" -Color "DarkGray"
            continue
        }
        if ($status.Skipped) {
            Write-Item -Label $status.Name -Value "已跳过；不会影响本体 dry-run。" -Color "DarkYellow"
            continue
        }
        if ($status.Available) {
            $parts = @("CLI 已发现")
            if ($status.ConfigWritten) { $parts += "本机配置已记录路径" }
            if ($status.CanaryPreviewed) { $parts += "canary 预览已通过" }
            $parts += "真实派工前请确认官方登录/授权和只读 canary"
            Write-Item -Label $status.Name -Value ($parts -join "；") -Color "Green"
        } else {
            Write-Item -Label $status.Name -Value "CLI 未发现；先按官方说明安装和登录，再重新运行向导。" -Color "Yellow"
        }
    }

    if (Test-Path -LiteralPath $userConfigPath -PathType Leaf) {
        Write-Item -Label "本机配置" -Value $userConfigPath -Color "Green"
    } else {
        Write-Item -Label "本机配置" -Value "未写入 provider 路径；跳过 provider 时这是正常状态。" -Color "Gray"
    }

    Write-Host ""
    Write-Host "下一步：打开 Codex 新任务，输入：" -ForegroundColor Cyan
    Write-Host "拆分一下任务，分配给其他 agent 做 dry-run，不要真实修改文件。"
}

if (-not (Test-Path -LiteralPath $installScript -PathType Leaf)) {
    throw "安装脚本缺失：$installScript"
}

Write-Section "Codex Praetor 安装向导"
Write-Host "版本：0.1.1-alpha"
Write-Host "安装范围：当前 Windows 用户插件目录，不需要管理员权限。"
Write-Host "这个向导会安装 Codex Praetor 本体，并帮助你检查或配置 Qoder、CodeBuddy、MiMo。"
Write-Host "它不会替你登录账号，不会读取 token、cookie、账号数据库，也不会替你确认账单。"

Write-Section "安装前检查"
$psVersion = $PSVersionTable.PSVersion.ToString()
Write-Item -Label "PowerShell" -Value $psVersion -Color "Green"

if (Get-Command node -ErrorAction SilentlyContinue) {
    $nodeVersion = (& node --version 2>$null | Select-Object -First 1)
    Write-Item -Label "Node.js" -Value "已发现 $nodeVersion" -Color "Green"
} else {
    Write-Item -Label "Node.js" -Value "未发现。本体可先安装，但 MCP runtime 和部分 provider 安装方式需要 Node.js。" -Color "Yellow"
}

if (Get-Command git -ErrorAction SilentlyContinue) {
    Write-Item -Label "Git" -Value "已发现" -Color "Green"
} else {
    Write-Item -Label "Git" -Value "未发现。本体可先安装，但真实 worker 派工和 worktree 隔离需要 Git。" -Color "Yellow"
}

$providerDefinitions = Get-ProviderDefinitions
$providerStatuses = @($providerDefinitions | ForEach-Object { Get-ProviderStatus -Provider $_ })
Show-ProviderStatus -Statuses $providerStatuses

$choice = Read-ProviderChoice
$selectedIds = @(Get-SelectedProviderIds -Choice $choice)
if ($selectedIds.Count -eq 0) {
    Write-Section "provider 配置"
    Write-Host "你选择了先不配置 provider。Codex Praetor 本体安装、dry-run、状态查询和冲突检测仍可继续。" -ForegroundColor Cyan
} else {
    Invoke-ProviderOnboarding -Statuses $providerStatuses -SelectedIds $selectedIds
}

if (-not $Apply) {
    Write-Section "预览结束"
    Write-Host "当前是预览模式，没有修改文件。"
    Write-Host "双击 setup.cmd 或运行下面命令会执行实际安装："
    Write-Host "powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1 -Apply"
    exit 0
}

if (-not $NonInteractive) {
    Write-Host ""
    $confirm = Read-Host "按 Enter 开始安装 Codex Praetor 本体，输入 N 取消"
    if ($confirm -match "^n(?:o)?$") {
        Write-Host "已取消安装。"
        exit 0
    }
}

Write-Section "正在安装"
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installScript -SourcePlugin (Join-Path $scriptRoot "plugin") -Apply
if ($LASTEXITCODE -ne 0) {
    throw "插件安装失败，退出码：$LASTEXITCODE"
}

Update-ProviderConfig -Statuses $providerStatuses
Invoke-CanaryPreview -Statuses $providerStatuses
Show-FinalSummary -Statuses $providerStatuses
