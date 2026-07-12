# Codex Praetor 卸载、更新和回滚

这份说明面向 Windows 用户。

## 默认安装位置

插件目录：

```text
%USERPROFILE%\plugins\codex-praetor
```

个人 marketplace 文件：

```text
%USERPROFILE%\.agents\plugins\marketplace.json
```

备份目录：

```text
%USERPROFILE%\plugins\.codex-praetor-backups
```

## 更新

下载新版 release zip 后，在解压目录里运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1 -Apply
```

安装脚本会先复制到临时目录，校验后再替换旧目录。旧目录会移动到备份目录。

## 手动卸载

1. 关闭 Codex。

2. 删除插件目录：

```powershell
Remove-Item -LiteralPath "$env:USERPROFILE\plugins\codex-praetor" -Recurse -Force
```

3. 打开个人 marketplace 文件：

```powershell
notepad "$env:USERPROFILE\.agents\plugins\marketplace.json"
```

4. 删除 `name` 为 `codex-praetor` 的插件条目。

5. 重启 Codex。

## 回滚到上一个备份

1. 关闭 Codex。

2. 查看备份：

```powershell
Get-ChildItem -LiteralPath "$env:USERPROFILE\plugins\.codex-praetor-backups" | Sort-Object LastWriteTime -Descending
```

3. 把当前插件目录改名或删除，再把备份目录移回：

```powershell
Remove-Item -LiteralPath "$env:USERPROFILE\plugins\codex-praetor" -Recurse -Force
Move-Item -LiteralPath "$env:USERPROFILE\plugins\.codex-praetor-backups\codex-praetor-<timestamp>" -Destination "$env:USERPROFILE\plugins\codex-praetor"
```

把 `<timestamp>` 换成你要恢复的备份目录名。

4. 重启 Codex。

## 目录被占用怎么办

如果 PowerShell 提示目录被占用，通常是 Codex 还在运行或插件 runtime 还没退出。

先关闭 Codex，再重试。不要强行删除未知进程正在使用的目录。
