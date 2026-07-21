# Codex Praetor 0.8.1-alpha

本版把发布后的本机更新验收改为可观察的身份链，避免把“公开 Release 已交付”和“这台 Desktop 仍加载旧插件”混成一次发布事故。

## 主要改动

- 安装器写入无敏感安装回执，并核对插件内的 release generation；开发源码安装会明确标为非公开 Release。
- 新增安装身份观察器：只会给出 `needs_install`、`needs_host_restart` 或 `needs_canary`，不会修改 cache、readiness、provider 或认证数据。
- 安装向导不再在 host 身份未知时运行真实 canary；正确顺序是安装身份一致、刷新 host、`runtime_info` 一致、再 canary。
- GitHub Release 校验分为 CI 的同一 artifact 模式和发布后的公开 artifact 模式。本地候选旧时标记 `local_candidate_stale`，不再误称远端 Release 过期。
- 产品验证会拒绝含非 ASCII 文本但缺少 UTF-8 BOM 的 PowerShell 脚本，避免本机与 GitHub Windows runner 的代码页差异。

## 用户影响

更新后先安装目标 Release，再刷新 Codex Desktop host。仅打开新任务不能刷新 host；新任务中的 `codex_praetor_runtime_info` 与安装版本一致后，才可运行一次真实只读 canary 和后续派工。

## 发布与验收

合并后 `Release On Main` 继续从精确 merge commit 自动构建、发布并下载复验同一不可变 zip。公开下载复验通过即为产品交付；单机更新状态由安装身份观察器单独说明，不会制造同版本收口补丁。
