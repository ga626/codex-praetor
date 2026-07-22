# Codex Praetor 0.9.0-alpha

本版先把“谁适合做什么工作”从印象判断变成可追溯的事实层。它不会擅自改变默认派工，也不会因为某个 provider 有一份配置文件就自动把任务交给它。

## 主要改动

- 新增只读 MCP 工具 `codex_praetor_capability_profiles`：从项目内不可变任务尝试和 Codex 的验收结论，按“具体 provider、模型、权限、任务类型和运行时代际”生成能力画像。
- 能力画像用 `observed`、`provisional`、`qualified`、`cooling_down`、`blocked` 等明确状态表达证据强度和失败边界；当前登录、权限、预算、隔离和 canary 等硬门始终优先。
- 为 Qoder、CodeBuddy 和 MiMo 建立公开的 Provider Adapter 合同，明确允许模型、权限语义、启动/结束解析、故障分类和所需 canary 证据，不包含本机路径、账号或 token。
- 对每次 attempt 绑定 Codex 的验收结论，避免一个任务有多次尝试时，把后来的验收错误地算到较早的尝试上。
- 新增合同回归测试，验证画像是只读投影、adapter 存在不代表可自动派工，并覆盖观察、暂定、合格、冷却和阻断状态。

## 用户影响

你会多一个“看清证据”的只读工具，而不是一个会擅自选人的黑箱。后续版本才会基于这些证据提供可解释的路由建议；在此之前，现有默认 tier 和派工结果保持不变。

## 发布与验收

合并后 `Release On Main` 必须从精确 merge commit 自动构建并发布新的不可变 zip。发布资产经远端下载验真后，自动本机激活会安装同一 zip。此轮四个 PR 完成后，再由用户一次刷新 Codex Desktop host，并依次验证 `runtime_info`、provider canary 和真实 worker。
