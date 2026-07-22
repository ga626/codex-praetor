# 能力画像与 Provider Adapter 合同

这份合同解决一个很具体的问题：不要因为某个 worker 曾经“看起来能用”，就把它当成任何任务都可靠。Codex 仍是唯一的规划者、派工审批者和最终验收者；外部 CLI worker 只完成边界明确的工作包。

## 一句话模型

能力画像不是人员打分表，而是对不可变尝试记录的可重建投影：

```text
真实 attempt + Codex 验收结论
  → provider tuple + 任务族
  → observed / provisional / qualified / cooling_down / blocked
```

一个画像的键同时包含 provider、CLI 身份、模型、权限配置、任务类型、运行时代际和合同 hash。这样 Qoder 的只读成功，不能自动证明 MiMo 的写代码也可靠；同一 provider 换模型、换 CLI 或换权限后也不会错误继承旧结论。

## 状态的简单含义

- `observed`：只有一次被 Codex 采信的真实结果；只可观察，不能作为默认派工依据。
- `provisional`：有两次采信；只能在低风险工作包中保守建议。
- `qualified`：至少三次采信；仍必须通过当前的登录、版本、权限、预算和隔离等硬门。
- `cooling_down`：刚发生超时、限流、网络或服务不可用；等待并重新 canary，不能盲目重试。
- `blocked`：发生风控、认证、CLI 缺失、解析失败或权限拒绝；先解决原因，不能自动派工。
- `unknown` / `stale`：没有足够的、或已不再适用的证据。

硬门永远优先于画像。画像只提供可解释的建议，不会在本阶段改变默认 tier 或路由结果。

## Provider Adapter 是什么

`config/provider-adapters/` 中每个公开 JSON 描述一个 provider 的稳定合同：如何发现 CLI、允许哪些模型、每种权限在对方 CLI 中到底意味着什么、怎样记录结束状态、怎样清理，以及最少要拿到什么 fixture 和真实 canary 证据。

它不保存本机 CLI 路径、账号、token 或 provider 数据库。真实配置仍只存在本机私有配置中。

MiMo 的边界尤其明确：Build agent 可以在 disposable worktree 写文件。因此 `mimo-isolated-audit-v1` 表示“只在隔离项目内做审计”，不是承诺整个文件系统只读。worktree 保护主项目，不是操作系统沙箱。

## 新 provider 的准入清单

1. 新增并通过 adapter 合同；模型和权限语义必须明确，不能写“自动”。
2. 通过 fixture，确认失败分类和结束状态能稳定解析。
3. 在隔离 worktree 通过当前运行时代际的只读和受控改码 canary。
4. 让 Codex 审核实际 diff、测试和成本/风控边界，积累画像证据。
5. 只有后续路由阶段把这些证据解释为建议；不能因为 adapter 文件存在就自动可派工。

PR 1 仅建立上述事实层和合同。真实任务基线、路由建议与三家 provider 的运营闭环分别在后续 PR 完成。
