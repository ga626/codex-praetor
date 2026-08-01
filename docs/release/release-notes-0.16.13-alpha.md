# Codex Praetor 0.16.13-alpha

## 发布内容

- 修复“开启 Codex 执行官模式”在 Codex Desktop 中被 MCP 对话 ID 阻塞的问题。模式现由插件 Skill 作为当前对话的工作规范维护，不再依赖 `CODEX_THREAD_ID`、不写入项目状态，也不会错误继承到新对话。
- MCP 保留实际派工、状态、取消和验收工具；取消某个正在运行的 worker 必须显式指定 `job_id` 并读取终态，产品不再猜测某个 worker 属于当前对话。
- 既有的 structured progress（结构化进展）和 formal cancellation（正式取消）合同保持不变：worker 的进度、取消请求与终态仍由实际任务记录和 `completion.json` 证明。
- 公开能力合同改为声明 Skill 工作流，而不是一个实际上无法在宿主中可靠工作的模式开关工具。

## 用户影响

- 用户在一个任务中说“开启 Codex 执行官模式”后，Codex 会在后续实质任务先评估是否适合交给 Qoder 或 CodeBuddy；新任务不会继承。
- 本版不新增 provider、模型、认证访问、自动合并或生产侧不可逆动作。

## 验证

- 构建后的 MCP 工具面不再包含三项错误的模式状态工具，运行时合同和插件内 Skill 镜像保持一致。
- 最终 artifact 仍须完成安装、fresh-context、canary 和真实 worker 任务验收。
