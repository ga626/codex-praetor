# Codex Praetor 0.8.3-alpha

本版是对 `0.8.2-alpha` 发布事故的恢复版本。上一版已经成功发布，但真实 CodeBuddy 编辑 worker 因权限参数与本机 CLI 不兼容而不能写入隔离 worktree，因此不能宣称产品已交付；该历史 Release 保持不变。

## 主要改动

- CodeBuddy headless 派工改用本机 CLI 已验证的 `-y --tools` 协议，不再传入已不被当前 CLI 支持的 `--permission-mode dontAsk`。
- 只读任务仅开放 `Read,Glob,Grep`；编辑任务仅在 Codex 创建的隔离 worktree 中开放 `Read,Glob,Grep,Edit,Write,Bash`。两类任务都不开放网络工具。
- 新增可重复的权限故障注入回归：用严格的模拟 CLI 实际运行只读和编辑派工，历史 `dontAsk`、`allowedTools` 或 `disallowedTools` 参数会被拒绝，错误协议不能再进入发布候选。
- 同步修正 bundled Skill 的权限政策和证据登记，以本机 CLI 支持的语法为准，并明确 worktree 只隔离文件冲突，不是安全沙箱。

## 用户影响

升级后，CodeBuddy 的真实编辑任务可以在 disposable worktree 内获得所需的写入与命令权限，Codex 仍负责检查 diff、测试和是否合并。用户不需要手动修改 CodeBuddy 配置、缓存或权限数据库。

## 发布与验收

合并后 `Release On Main` 必须从精确 merge commit 自动构建并发布新的不可变 zip。公开 artifact 验真、本机安装身份、host 刷新、`runtime_info`、两类 capability canary 和真实编辑 worker 将依次复验；任一步失败即维持“代码已合并，产品未交付（release incident）”，先重跑同一 SHA 或修自动发布路径，不为同一版本补包。
