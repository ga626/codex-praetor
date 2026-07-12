@echo off
setlocal
chcp 65001 >nul
title Codex Praetor 安装向导
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1" -Apply
set "exit_code=%ERRORLEVEL%"
echo.
if not "%exit_code%"=="0" (
    echo 安装未完成，退出码：%exit_code%
) else (
    echo 安装向导已完成。
)
pause
exit /b %exit_code%
