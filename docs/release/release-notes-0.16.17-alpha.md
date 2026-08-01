# Codex Praetor 0.16.17-alpha

## 发布内容

- 修复 `0.16.17-alpha` 的 Release On Main 事故：main 已成功提升 PR 的同一候选 ZIP，但最终 ZIP 运行时验收缺少 MCP 测试依赖而停止。
- 主分支发布现在会在提升后的最终包验收前调用受控的 MCP 依赖安装脚本；该脚本保持 Qoder SDK 的隐式 CLI 下载关闭。
- 增加工作流回归，确保主分支发布不能再假定 PR CI 的 `node_modules` 会跨作业存在。
- `0.16.17-alpha` 没有创建 tag、Release 或公开下载包；本版是新的不可变恢复版本，不会修改、覆盖或补发旧版本。

## 用户影响

- 本版不新增 provider、模型、认证访问、自动合并或生产侧不可逆动作；既定的 structured progress 与 formal cancellation 合同保持不变。
- 发布仍只提升 PR 阶段已经验收的同一 ZIP；主分支不重新构建或替换安装包。

## 验证

- 发布前会验证候选 artifact 命名、主分支依赖准备、候选收据、内容树、ZIP SHA256、artifact manifest、provenance 与远端下载。
- 任一合同不一致仍会在创建 tag 前停止，保留可审计的失败证据。
