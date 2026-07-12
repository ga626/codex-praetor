# Codex Praetor 运行目录收敛报告

## 结论

这次要解决的不是“D 盘多了几个文件夹看着不舒服”，而是 Codex Praetor 的默认运行目录策略不符合项目根目录管理方式。`D:\Projects` 应该只放一个个独立项目，不应该出现 `CodexPraetor.codex-praetor`、`CodexPraetor.worktrees`、`CodexPraetor.tools` 这种看起来像项目、实际是运行产物的同级目录。

本次方案把 Codex Praetor 的运行产物统一收进项目内部的隐藏目录：

```text
<项目根>\
  .codex-praetor\
    jobs\
    plans\
    locks\
    scratch\
    worktrees\
    tools\
```

源码、文档、MCP、插件仍然留在原来的项目目录里；worker 的任务记录、临时文件、隔离 worktree 和本地工具缓存进入 `.codex-praetor`。这个目录已被 `.gitignore` 忽略，不会进入 GitHub 仓库，也不会和 GitHub 上的项目目录结构冲突。

## 这四个目录为什么会出现

当前看到的四个目录分别代表四类东西。

`<项目根>` 是真正的项目源码仓库。它有 `.git`，当前分支从这里提交、推送、发 PR。这个目录必须保留。

`<项目根>.codex-praetor` 是旧策略下的运行状态目录。里面放 worker job、MCP plan、自测 plan、scratch。它不是源码，也不是应该单独出现在项目总目录里的项目。

`<项目根>.worktrees` 是旧策略下的 worker Git worktree 集合。它不是普通复制目录，而是 Git 正式登记过的 linked worktree。它的出现不是因为普通提交、推送或创建分支，而是因为 Codex Praetor 为 MiMo 等外部 worker 创建隔离执行目录。

`<项目根>.tools` 是本地工具缓存。当前里面主要是 GitHub CLI 的 zip 和解压后的 `gh.exe`。它不属于项目源码，也不应该占用项目总目录的项目层级。

根因在旧实现里：脚本和 MCP 会先取项目父目录，再拼出 `<project>.codex-praetor` 和 `<project>.worktrees`。这个设计原本是想避免把运行产物写进源码树，但结果是污染了更上一级的项目总目录。

## 什么操作会触发它

普通 Git 操作不会触发这些目录。创建分支、提交、推送本身不会创建 `CodexPraetor.codex-praetor` 或 `CodexPraetor.worktrees`。

会触发的是 Codex Praetor 自己的运行入口：

- 真实 worker 派工会创建 job、scratch 和必要的 worktree。
- background worker 会写入 `jobs`，并由 watcher 写入 completion。
- blocking worker 会写入 `scratch\blocking-*`。
- MCP plan/self-test 会写入 `plans`。
- 需要本地发布工具时，可能留下 `tools` 缓存。

所以修复点不能只靠“以后少点点按钮”，而要改默认路径策略。

## 本次代码修复

本次修复把默认路径从项目同级改成项目内部隐藏运行区。

PowerShell wrapper 现在使用：

```text
<project>\.codex-praetor
<project>\.codex-praetor\worktrees\<worker-worktree>
```

MCP path helper 现在也使用同一个项目内部路径。这样脚本入口、MCP 工具卡、自测和真实 worker 派工不会再认不同的根目录。

测试断言同步更新：dry-run 必须解析到 `CodexPraetor\.codex-praetor` 和 `CodexPraetor\.codex-praetor\worktrees`。如果以后有人把路径策略改回项目同级，测试会失败。

插件副本和 skill 文案也同步更新。这样不是只修开发源码，打包到 Codex 插件里的版本也不会继续使用旧路径。

## GitHub 目录冲突判断

这套新目录不会和 GitHub 上的项目目录冲突。

原因有三点。

第一，`.codex-praetor/` 是本机运行态，已经在 `.gitignore` 里。它不会被 `git add` 默认加入，也不会进入 PR。

第二，项目源码目录仍然保持原结构：`skill/`、`scripts/`、`mcp/`、`plugin/`、`docs/` 等目录没有被塞进运行日志或 worker 输出。

第三，Git linked worktree 可以放在项目内部的忽略目录下。本次已用临时仓库验证，`git worktree add` 可以创建类似 `<repo>\.codex-praetor\worktrees\<name>` 的 nested worktree。它依然是 Git 管理的隔离工作区，但不会在资源管理器里伪装成项目总目录下的另一个项目。

## 开发目录和运行目录如何隔离

不需要再额外创建一个同级开发目录，也不应该在项目总目录下再造 `CodexPraetor-dev`、`CodexPraetor-runtime` 这类并列目录。

正确隔离方式是在同一个项目目录内分层：

```text
CodexPraetor\
  skill\       # 产品源 skill
  scripts\     # 产品源脚本
  mcp\         # MCP 源码
  plugin\      # 插件打包形态
  docs\        # 可提交文档
  .codex-praetor\  # 本机运行态，不提交
```

这样读者打开项目总目录时只会看到一个项目；开发者打开项目内部时，也能清楚区分“可提交源码”和“本机运行态”。

## 当前本机遗留目录的处理步骤

本次新增迁移脚本：

```powershell
scripts\migrate-codex-praetor-runtime-root.ps1
```

执行顺序如下。

第一步，确认没有正在运行的 Codex Praetor worker。正在运行的 job 不应该迁移。

第二步，先做 dry-run：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\migrate-codex-praetor-runtime-root.ps1
```

它会显示将要迁移的旧目录和新目录，但不移动任何东西。

第三步，确认 dry-run 只涉及这三个旧目录：

```text
<项目根>.codex-praetor
<项目根>.worktrees
<项目根>.tools
```

第四步，执行迁移：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\migrate-codex-praetor-runtime-root.ps1 -Apply
```

脚本会把旧的 `jobs`、`plans`、`locks`、`scratch` 收进 `<项目根>\.codex-praetor`；把旧 worktree 通过 `git worktree move` 移到 `<项目根>\.codex-praetor\worktrees`；把旧工具缓存移到 `<项目根>\.codex-praetor\tools`。如果新旧运行目录里已有同名 plan 或 job，脚本不会覆盖，会给旧项追加 `legacy-时间戳` 后缀保留下来。

第五步，验收：

```powershell
git worktree list --porcelain
git status --short --branch
Get-ChildItem <项目总目录> -Directory | Where-Object { $_.Name -like '<项目名>*' }
```

预期结果是：worktree 仍被 Git 识别，主仓库没有新增可提交的运行文件，项目总目录下不再出现旧的同级运行目录。

## 本次 PR 的完成标准

这次 PR 必须同时满足四件事。

第一，新的 worker 路径和 MCP 路径都指向项目内部 `.codex-praetor`。

第二，测试不再接受 `CodexPraetor.codex-praetor` 这种同级路径。

第三，文档告诉用户运行产物在哪里、为什么不进 GitHub、怎么迁移旧目录。

第四，本地验证必须证明 dry-run、自测、MCP build 和发布前检查仍然可跑。

这套方案解决的是产品默认行为，不只是清理当前电脑上的几个文件夹。清理脚本负责当前本机遗留目录；路径策略负责以后不再复发。
