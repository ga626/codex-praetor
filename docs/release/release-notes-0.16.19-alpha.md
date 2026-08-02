# Codex Praetor 0.16.19-alpha

## 派工基线可核验

- 只读审计和测试任务现在与真实改码任务一样，都会把调用方声明的 Git 提交传到隔离 worker worktree。
- 系统会把该提交同时写入任务合同、job、completion 和 ledger attempt，并在登记时重新核对实际 worktree HEAD。
- 已存在但指向不同提交的同名 worker branch 会在启动前被拒绝，避免静默复用旧工作目录。

## 保持原有边界

本版本不增加 provider、模型、认证资料访问、自动合并或生产侧不可逆动作。Codex 仍负责验收，worker 仍只能在隔离 worktree 中执行其合同范围内的任务。

## 进展与停止

派工继续提供 `structured progress`，让 Codex 根据 worker 的结构化状态判断启动、执行、完成或失败。用户停止任务时仍走 `formal cancellation`：系统保存取消请求和最终回执，取消、超时或无验收结论的工作不会被当作已完成。
