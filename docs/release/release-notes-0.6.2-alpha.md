# Codex Praetor 0.6.2-alpha

本版把发布验收从“源码和中间构建通过”收紧为“最终用户下载包真实启动通过”。它不会覆盖 `0.6.2-alpha`；将由 `Release On Main` 从本次合并 commit 构建新的不可变 Release。

## 主要变化

- `npm test` 和发布器都会重建 `plugin/mcp/dist/server.js`，不再允许 bundled MCP 由手工维护的旧生成物决定。
- 新增最终 artifact runtime gate：解压生成的 zip 后启动其中的 MCP，校验 handshake 版本、runtime contract、必需工具和 generation manifest。
- PR candidate、main 发布和远端 Release 下载复验使用同一份 bundled runtime smoke，源码与实际用户入口版本分叉会在合并前失败。
- generation manifest 改为根据最终 stage 计算，同时保留精确 Git commit 作为来源证明。
- 项目规则明确：合并后只能进入“产品已交付”或“代码已合并、产品未交付（release incident）”；禁止同一版本的收口补丁 PR。

## 用户影响

用户下载 `codex-praetor-setup-0.6.2-alpha.zip` 后启动的 MCP 与公开版本声明一致。若 GitHub 发布、网络或 Desktop host 刷新失败，系统会给出明确阻断状态和恢复动作，而不会把失败伪装成已交付。

## 验证

- `npm test --prefix .\mcp`
- `scripts/verify/test-public-entry-consistency.ps1 -SkipRemoteRelease`
- `scripts/verify/test-release-package-determinism.ps1`
- `scripts/verify/test-release-artifact-runtime.ps1`
- `scripts/verify/test-release-closeout.ps1`
- bundled runtime 版本故障注入：故意将临时 artifact 改回 `0.6.0-alpha`，runtime smoke 以版本不匹配失败。

## 发布计划

合并后，受保护的 `Release On Main` 从精确 merge commit 自动构建、创建 `v0.6.2-alpha` draft、上传 zip 和 SHA256、公开发布并下载复验。随后按 release receipt 完成 stage、fresh-context、provider readiness、activate 和普通用户路径证明；任何外部失败都作为 incident 处理，不以同版本补丁绕过。
