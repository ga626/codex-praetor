# Codex Praetor 0.16.31-alpha

## 修复

- 修复首次派工在合同预检阶段被错误拒绝后只能看到 PowerShell 原始错误的问题。
- 为未知 tier、缺失或冻结基线错误、绝对路径、目录路径和不存在的不可变文件返回结构化失败分类与下一步动作。
- 让任务材料的写入范围和不可变范围只能引用已声明的相对叶文件，认证目录和其他禁止范围继续由 `forbidden_paths` 表达。
- 补充三类历史失败的回归测试，确保合同问题不会消耗 worker 额度。

本版本不改变 Qoder 中国版 `stream-json` 和 CodeBuddy ACP 的连接路线；取消仍是受控进程取消（controlled process cancellation），不新增 provider 或认证能力。
