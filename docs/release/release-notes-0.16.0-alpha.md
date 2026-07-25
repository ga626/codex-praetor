# Codex Praetor 0.16.0-alpha

## 本版交付

- 真实 `code_change` 改为从冻结 commit 创建隔离 Git worktree；worker 的可接受结果必须是该 worktree 中可审查的源码 diff。
- 每项真实改码任务必须声明允许路径、禁止路径、不可修改的已跟踪文件、独立复跑检查和 base commit。
- Codex 验收会拒绝空 diff、越界 diff、不可修改文件变化、缺少 stdout/stderr 或复制材料改码；worker 的退出码和自述不能单独构成成功。
- 复制 task material 仅保留为旧 canary/回归夹具，不再可被记录为真实源码改码能力。

## 未扩大承诺

本版没有新增可公开路由的 provider 改码能力，也没有接入 ACP、JSON stream、SDK 或 daemon。Qoder 与 CodeBuddy 的真实任务资格仍以之后阶段 1 的独立 accepted 事实记录为准。

## 发布后验收

Release On Main 必须从合并 SHA 构建同一不可变 zip，上传并远端下载复验。stable 安装与 host 刷新后，Codex 还会复核 `runtime_info`、canary 和一项已经证实的真实 worker 任务；任何失败都按 release incident 处理，不重发同版本包。
