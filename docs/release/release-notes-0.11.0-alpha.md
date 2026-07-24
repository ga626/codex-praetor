# Codex Praetor 0.11.0-alpha

## 本次交付

- 真实改码评测现在会把同一份题目材料注入独立 worktree，并先确认题目原本确实失败。
- worker 只能改声明的文件；独立验收会检查题目、不可改测试、工作树改动和真实测试结果。
- 新增 `codex_praetor_verify_evaluation_task`：它只提供独立证据，最终是否接受仍由 Codex 明确决定。

## 用户可见边界

- 这不是“worker 进程正常结束就算完成”。只有题目未被篡改、改动范围正确、原测试通过，才会形成可验收结果。
- 本次不改变 provider 默认路由，也不自动启动真实 provider。
