# Codex Praetor 0.8.0-alpha

本版把“真实 provider 能力证明、worker 生命周期、发布 CI”三条链路统一成可观察、可回归的产品边界。

## 主要改动

- capability canary 现在要求开始前仓库干净；运行期间发现并发仓库变动时，会记录 `external_repo_drift_observed`，不会抹掉已经获得的真实 provider 证明。
- canary 的 worker 提示词缩短为一条自然语言任务；权限、网络限制、版本、marker、日志和仓库观察由外围验收协议执行。
- `process_exited`、超时、watcher 异常和未知终态不再显示为 active lane。进程退出后会明确显示“等待 Codex 验收”，不会虚假占用编辑 lane。
- 修复 MCP 对分段 UTF-8 管道输出的解码，中文健康信息不会因字符恰好跨 pipe chunk 而变成乱码。
- 共享 GitHub Actions pipeline 会把 dependency-only PR 统一分类为 non-release：仍执行构建和测试，但不再错误要求复用或新建不可变产品 tag。
- 增加并发 drift、dirty-before、dependency-only CI 分流、终态 lane 和 UTF-8 分段解码回归测试。

## 用户影响

更新并刷新 Codex 后，已登录的 provider 仍需要为当前 generation 做一次真实只读 canary。开始前请使用干净仓库；若其他人或其他流程在 canary 运行中改动仓库，系统会保留 provider 结果并标记这次仓库观察，随后请先审查该改动再开始编辑任务。

worker 进程退出不等于任务已完成。它只表示外部执行已经结束；Codex 仍需读取结果、检查证据并记录采信结论。

## 发布与验收

合并后，`Release On Main` 从该 merge commit 自动构建、验证、发布并下载复验同一份不可变 zip。公开 Release 下载复验通过即为产品交付；本机 Desktop 刷新、provider 登录和当前 generation canary 属于单机验收状态，不会形成同版本的“收口修复发布”。
