# Codex Praetor 0.9.5-alpha

## 本次恢复修复

- 修复 `0.9.5-alpha` 已安装运行时遗漏真实评测清单的发布事故：`evaluation-suite.json` 现在随 plugin 一起安装，源码与已安装包使用同一套运行时数据解析规则。
- 最终 bundled MCP 验收会真实调用 `codex_praetor_evaluation_suite`；删除该数据文件的故障注入将阻止发布。
- 计划接口改为返回紧凑摘要，不再因历史台账变大而把截断 JSON 误当作创建计划失败；MCP 自检使用独立计划 ID，避免测试残留互相污染。

## 用户可感知到的变化

刷新到本版本后，评测工具可在正常安装的 Codex 插件中直接显示真实任务清单。较长的任务历史不会再使“创建计划”因为回执过大而失败。

## 发布与本机验收

这是针对 `0.9.5-alpha` 发布事故的新不可变版本，不覆盖已有 tag 或 Release。合并后，`Release On Main` 将从 merge SHA 自动发布 `v0.9.5-alpha`，再由同一公开包完成远端验真与 stable marketplace 自动更新。之后需要一次受支持的 Codex Desktop host 刷新，才可继续最终 canary 与真实隔离 worktree worker 验收。
