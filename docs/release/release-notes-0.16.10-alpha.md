# Codex Praetor 0.16.10-alpha

## 发布内容

- 派工运行目录现在锚定到 Git 的规范项目根：从 Codex Desktop 的链接 worktree 发起任务时，不会再在 C 盘来源 worktree 下嵌套创建 Praetor worker worktree。
- 默认健康检查只核验当前运行代际、安装身份、readiness 和当前维护摘要；完整历史目录盘点改为显式维护操作，不再拖慢正常派工前置检查。
- Praetor 新建的 worker worktree 会写入最小所有权记录。清理器只把“Praetor 所有、已合并且干净”的工作树列为候选；没有所有权记录的普通 Git/Codex worktree、job 和 scratch 一律保护，不会删除。
- 既有 Qoder Agent SDK、CodeBuddy ACP、structured progress 与 formal cancellation 的监督合同保持不变。

## 用户影响

- 个人开发者可继续从任意链接 worktree 发起已授权的派工，但实际 worker 一律位于项目规范根的 `.codex-praetor\worktrees`。
- 正常 health 与派工更快；需要盘点历史运行目录时，显式使用 `-IncludeRuntimeInventory`，再审阅只读结果和清理候选。
- 本次不改变 provider 路由资格、模型、认证资料边界、自动合并或生产侧不可逆动作。

## 验证

- MCP 全量确定性合同测试和插件 MCP 协议烟测。
- 链接 worktree 的真实派工夹具、健康检查快路径/显式盘点对照、所有权清理候选夹具。
- 干净隔离候选构建、最终安装包场景验证和最终 `HEAD` 与 artifact SHA 回执。

## 未包含内容

- 不清理 Codex Desktop 自己的 C 盘 worktree，也不接管用户或 Git 直接创建的 worktree。
- 不迁移、读取或输出认证资料、provider 数据库、token、cookie 或缓存。
