# Release incident: Release On Main bootstrap failure

日期：2026-07-19

## 事实

- 受影响候选：`0.6.0-alpha`，合并提交 `6b3cfe30ae6838f6a64a293ad89b50ef6d1bf52c`。
- 失败 run：[Release On Main #29677178250](https://github.com/ga626/codex-praetor/actions/runs/29677178250)。
- 失败阶段：runner 初始化 action 时；`actions/setup-node` 被固定到不存在的 SHA `...0021`。
- 影响：没有创建 `v0.6.0-alpha` tag、GitHub Release、zip 或 `.sha256`；因此没有可恢复的已发布交付物，也没有本机 activation。

## 根因

PR CI 与合并后发布 workflow 各自维护 action 固定 SHA。CI 使用可解析的 SHA，而发布 workflow 使用了末位错误的 SHA。原有检查只验证“40 位十六进制格式”，没有实际向 GitHub 解析 SHA，也没有让两条路径运行同一份 pipeline。

## 处置

本事故不通过人工运行发布脚本处理。恢复 PR 发布为 `0.6.1-alpha`，并：

1. 将 PR 候选验证与 main 发布改为同一份 reusable workflow；
2. 在 PR 中实际解析每个外部 action 固定 SHA；
3. 强制 release intent 版本相对目标分支递增；
4. 移除从最新分支头部手工触发发布的入口；
5. 把“已创建 tag/Release 的失败只能重跑原 run”写入验证、发布说明和 runbook。

## 关闭条件

只有 `v0.6.1-alpha` 由 `Release On Main` 从合并提交自动创建、远端下载复验成功，并完成独立的本机交付链路后，本事故才可标记为已关闭。
