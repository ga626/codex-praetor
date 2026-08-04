# Codex Praetor 0.16.25-alpha

发布日期：2026-08-04

## 本次修复

- 修复合并后的 Release On Main 误把“PR 候选提交”和“合并提交”当成必须同一个 SHA 的问题。现在只在候选阶段绑定 artifact generation commit；进入 main 后，必须以候选回执和完整 source tree 证明被提升的不可变 ZIP 与合并内容相同。
- 新增发布回归：同一内容树、不同 Git 提交必须正常发布；内容树不同必须被拒绝。这样既不会把正常 GitHub merge 误报为失败，也不会让不同内容的候选包混入 main。
- 本版本是 `0.16.24-alpha` 在创建 tag/Release 前因工作流缺陷中止后的递增恢复版本；不重打 tag、不替换资产、不手工补包。

## 用户影响

用户无需改变安装、provider 登录或派工方式。发布完成后下载到的仍是同一条由 CI 验证、远端下载复验并安装到 stable marketplace 的产品链路。

保留 Qoder Agent SDK 与 CodeBuddy ACP 的 structured progress 和 formal cancellation：Codex 仍以任务合同、隔离 worktree、完成回执和独立验收决定是否接受结果，发布流程修复不放宽这一边界。
