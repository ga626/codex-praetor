# Codex Praetor 0.6.3-alpha

本版是 `0.6.3-alpha` release incident 的恢复版本。它不覆盖旧 tag 或旧资产，而是把发布前证明、上传对象和本机收口收成同一条可验证链路。

## 主要改动

- `config/runtime-contract.json` 成为唯一可手写的运行时合同；plugin 与 Skill 副本只能由生成器派生。
- 最终 zip 启动 bundled MCP 后，工具集合、runtime contract SHA、generation manifest 和 server version 必须相同。
- 发布器只上传通过 runtime 验收并已登记 SHA 的那一份 artifact，不再隐式重新构建另一份包。
- closeout integration test 改为消费最终 zip 的真实 runtime observation；加入历史合同分叉的故障注入测试。

## 用户影响

用户仍从 GitHub Release 下载 `codex-praetor-setup-0.6.3-alpha.zip`。旧的 `0.6.3-alpha` 保留为公开 incident 证据，不能被覆盖或激活。

## 发布与验收

合并后，`Release On Main` 从精确 merge commit 构建一个 artifact、验收该 artifact、发布同一 SHA，并下载复验。随后本机必须完成 stage、fresh-context、provider readiness 和普通用户路径证明；任何外部失败都保持可见 incident/needs_user_action 状态。
