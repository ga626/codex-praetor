# Codex Praetor 0.7.0-alpha

本版收敛 Codex Praetor 的插件安装与发布边界：产品只有一个插件包，Skill 和 MCP 都从该包运行；GitHub Release 的同一 artifact 是发布事实，本机缓存和旧收据只用于诊断，不能反向阻断新版插件。

## 主要改动

- Release zip 只携带 `plugin/` 中的 bundled Skill，不再携带第二套根目录 Skill。
- 精确 release generation manifest 同时写入插件本体，已安装 Skill 的 provider canary 不再退化成 `--packaged--` generation。
- 全局 Skill 不再是运行前提；健康检查不再因旧 active receipt 或旧全局 Skill 阻断真实派工。
- 保留不可变 tag、同一 artifact 验收、远端下载复验和 runtime contract 证明；缓存由 Codex Desktop 管理，不由发布器手工制造“活动版本”。

## 用户影响

用户仍从 GitHub Release 下载 `codex-praetor-setup-0.7.0-alpha.zip`。安装器只更新 personal marketplace 的插件来源目录；重启 Codex Desktop 并在新对话中使用插件，即可让宿主创建和加载新的版本缓存。

## 发布与验收

合并后，`Release On Main` 从精确 merge commit 构建、验收、上传并下载复验同一份 zip。最终用户验收只需确认新 Desktop context 的 `runtime_info` 与插件内 generation manifest 一致；旧版本缓存可以延迟回收，不影响新版本可用性。
