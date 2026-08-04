# Codex Praetor 0.16.23-alpha

发布日期：2026-08-04

## 本次修复

- 修复 `Release On Main` 在 GitHub Actions 的 detached HEAD 环境中发布时，因空分支名被直接调用 `Trim()` 而中断的问题。
- 发布脚本现在把原生 Git 输出显式归一化为空字符串；仍只允许在本地 `main` 或 GitHub Actions 明确授权的 detached main SHA 上发布。
- 增加发布控制面回归断言，防止该空输出路径再次绕过检查后在创建 Release 前失败。

## 用户影响

本次不改变 Qoder 或 CodeBuddy 的派工合同、模型选择、权限范围或认证处理。它确保已经通过候选 CI 的不可变 ZIP 能在 main 发布阶段继续完成 GitHub Release、远端下载复验和稳定安装。

本版本继续保留 **structured progress** 与 **formal cancellation** 合同：发布控制面修复不会把“进程结束”误写成成功，也不会改变 Codex 对 worker completion、取消、超时和 accepted 的判定边界。

## 验收与发布

候选包仍须在隔离环境完成 MCP 合同测试、最终 artifact 运行验收，以及 Qoder 和 CodeBuddy 各自的当前 generation canary 与真实任务验收。发布流程必须从同一候选 artifact 提升，不能在 main 重新构建或用手工上传替代。
