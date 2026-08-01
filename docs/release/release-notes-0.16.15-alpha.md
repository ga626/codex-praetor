# Codex Praetor 0.16.15-alpha

## 发布内容

- 修复 `0.16.14-alpha` 的 Release On Main 控制面事故：主分支发布前的远端 action-pin 核验现在把 GitHub Actions 的短期令牌明确传给 `gh`。
- 增加回归合同，确保任何以后调用 `gh` 的主分支发布前检查都不会遗漏 `GH_TOKEN`。
- `0.16.14-alpha` 没有创建 tag、Release 或公开下载包；本版是新的不可变恢复版本，不会修改、覆盖或补发旧版本。
- 既定 Qoder Agent SDK 与 CodeBuddy ACP 的 structured progress、formal cancellation 和 Codex 验收边界保持不变；本版只修复发布控制面。

## 用户影响

- 本版不新增 provider、模型、认证访问、自动合并或生产侧不可逆动作。
- 修复后，发布流程仍只提升 PR 阶段已验证的同一 ZIP；不会在 `main` 重新打包第二份。

## 验证

- Release On Main 会先通过远端 action-pin 核验，再校验候选收据、内容树、ZIP SHA256、artifact manifest、provenance 与远端下载。
- 若任一核验失败，流程仍会 formal cancellation：在创建 tag 前停止，不覆盖现有 Release，并保留失败证据。
