# Codex Praetor 0.12.0-alpha

## 本次交付

- Qoder 与 CodeBuddy 都已在隔离工作树中完成一项小型真实改码任务；结果必须经 Codex 的独立材料、改动范围和测试验收后才能被接受。
- 修正了 watcher：worker 在 stdout 中解释“provider 被拒绝”等失败情形时，不再被误判为该 worker 本身失败。
- 真实评测题改为不可变材料与独立验收，避免只凭标记文本把“能够跑测试”误判为已证实能力。
- 发布前检查收敛为一个候选包预检入口：同一份最终 zip、同一份 SHA 和当前提交回执贯穿本地验证、PR CI 与 main 发布。

## 用户可见边界

- CodeBuddy 当前可以完成经过隔离与独立验收的小型改码任务；它不能在现有 Bash 沙箱中执行 PowerShell 测试，因此产品不会把它宣传成通用测试执行器。
- Qoder 的 provider 拒绝、超时、取消和部分工作树都不是成功；系统会保留证据，等待新的 canary 或人工决定，不会自动合并或盲目重试。
- 本版仍只支持 Qoder 和 CodeBuddy；不会读取账号材料，也不会自动登录或更改 provider 设置。
