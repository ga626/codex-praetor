param(
    [switch]$Apply,
    [switch]$NonInteractive,
    [ValidateSet("1", "2", "3", "4", "5")]
    [string]$ProviderChoice = ""
)

$ErrorActionPreference = "Stop"
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$installScript = Join-Path $scriptRoot "scripts\install\install-user.ps1"

function Write-Section {
    param([string]$Text)
    Write-Host ""
    Write-Host ("=" * 64) -ForegroundColor DarkCyan
    Write-Host $Text -ForegroundColor Cyan
    Write-Host ("=" * 64) -ForegroundColor DarkCyan
}

function Test-CommandAvailable {
    param([string[]]$Names)
    foreach ($name in $Names) {
        if (Get-Command $name -ErrorAction SilentlyContinue) {
            return $true
        }
    }
    return $false
}

function Get-ProviderStatus {
    param(
        [string]$Name,
        [string[]]$Commands
    )

    $available = Test-CommandAvailable -Names $Commands
    [pscustomobject]@{
        Name = $Name
        Available = $available
        Commands = ($Commands -join ", ")
    }
}

function Show-ProviderStatus {
    param([object[]]$Statuses)

    foreach ($status in $Statuses) {
        $label = if ($status.Available) { "已发现" } else { "未发现" }
        $color = if ($status.Available) { "Green" } else { "DarkYellow" }
        Write-Host ("{0,-10} {1,-4}  可执行文件：{2}" -f $status.Name, $label, $status.Commands) -ForegroundColor $color
    }
    Write-Host "说明：这里仅检查 CLI 是否可发现，不读取登录状态、token 或账号数据库。" -ForegroundColor DarkGray
}

function Read-ProviderChoice {
    if ($NonInteractive -and -not [string]::IsNullOrWhiteSpace($ProviderChoice)) {
        return $ProviderChoice
    }

    Write-Host ""
    Write-Host "请选择 provider 配置入口："
    Write-Host "  1. 查看全部 provider"
    Write-Host "  2. 暂不配置 provider，先安装 Codex Praetor"
    Write-Host "  3. 只查看并配置 Qoder"
    Write-Host "  4. 只查看并配置 CodeBuddy"
    Write-Host "  5. 只查看并配置 MiMo"
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

function Show-ProviderGuidance {
    param(
        [string]$Choice,
        [object[]]$Statuses
    )

    $selected = switch ($Choice) {
        "1" { @("Qoder", "CodeBuddy", "MiMo") }
        "3" { @("Qoder") }
        "4" { @("CodeBuddy") }
        "5" { @("MiMo") }
        default { @() }
    }
    if ($selected.Count -eq 0) {
        return
    }

    Write-Section "provider 配置提示"
    foreach ($name in $selected) {
        $status = $Statuses | Where-Object { $_.Name -eq $name } | Select-Object -First 1
        if ($status.Available) {
            if ($name -eq "MiMo") {
                Write-Host "$name：已在 PATH 中发现 CLI。请优先尝试 mimo/mimo-auto 只读 canary；失败或指定模型时再按 MiMo 文档连接 provider。" -ForegroundColor Green
            } else {
                Write-Host "$name：已在 PATH 中发现 CLI。请在 Codex Praetor 安装后按对应文档完成官方登录/授权和只读 canary。" -ForegroundColor Green
            }
        } else {
            if ($name -eq "MiMo") {
                Write-Host "$name：当前未发现 CLI。请先按 MiMo 官方安装方式安装；首次可优先尝试 mimo/mimo-auto。" -ForegroundColor Yellow
            } else {
                Write-Host "$name：当前未发现 CLI。请先按 provider 官方流程安装并登录，再配置 Codex Praetor。" -ForegroundColor Yellow
            }
        }
    }
    Write-Host ""
    Write-Host "对应文档：" -ForegroundColor Cyan
    if ($selected -contains "Qoder") { Write-Host "  docs\provider-notes\qoder.md" }
    if ($selected -contains "CodeBuddy") { Write-Host "  docs\provider-notes\codebuddy.md" }
    if ($selected -contains "MiMo") { Write-Host "  docs\provider-notes\mimo.md" }
}

if (-not (Test-Path -LiteralPath $installScript -PathType Leaf)) {
    throw "安装脚本缺失：$installScript"
}

Write-Section "Codex Praetor 安装向导"
Write-Host "版本：0.1.0-alpha"
Write-Host "安装范围：当前用户插件目录，不需要管理员权限。"
Write-Host "本向导不会安装 provider，不会替你登录，也不会读取 token、cookie 或账号数据库。"

Write-Section "安装前检查"
$psVersion = $PSVersionTable.PSVersion.ToString()
Write-Host "PowerShell：$psVersion" -ForegroundColor Green

if (Get-Command node -ErrorAction SilentlyContinue) {
    $nodeVersion = (& node --version 2>$null | Select-Object -First 1)
    Write-Host "Node.js：已发现 $nodeVersion" -ForegroundColor Green
} else {
    Write-Host "Node.js：未发现。安装插件仍可继续，但 MCP runtime 需要 Node.js。" -ForegroundColor Yellow
}

if (Get-Command git -ErrorAction SilentlyContinue) {
    Write-Host "Git：已发现" -ForegroundColor Green
} else {
    Write-Host "Git：未发现。插件安装仍可继续，但真实 worker 派工需要 Git worktree。" -ForegroundColor Yellow
}

$providerStatuses = @(
    Get-ProviderStatus -Name "Qoder" -Commands @("qodercli", "qoder")
    Get-ProviderStatus -Name "CodeBuddy" -Commands @("codebuddy", "workbuddy")
    Get-ProviderStatus -Name "MiMo" -Commands @("mimo", "mimo.cmd")
)
Show-ProviderStatus -Statuses $providerStatuses

$choice = Read-ProviderChoice
Show-ProviderGuidance -Choice $choice -Statuses $providerStatuses

if (-not $Apply) {
    Write-Section "预览结束"
    Write-Host "当前是预览模式。双击 setup.cmd 会执行实际安装。"
    exit 0
}

if (-not $NonInteractive) {
    Write-Host ""
    $confirm = Read-Host "按 Enter 开始安装，输入 N 取消"
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

Write-Section "安装完成"
Write-Host "Codex Praetor 已安装到：$env:USERPROFILE\plugins\codex-praetor" -ForegroundColor Green
Write-Host "下一步：重启 Codex，或打开一个新任务让插件被发现。"
Write-Host "首次使用建议：拆分一下任务，分配给其他 agent 做 dry-run，不要真实修改文件。"
Write-Host "provider 配置模板：config\codex-praetor.local.json"
Write-Host "验收命令：powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\doctor-codex-praetor.ps1"
