# Codex Praetor 0.16.16-alpha

## 发布内容

- 修复 `0.16.16-alpha` 的 Release On Main 事故：PR CI 上传候选 ZIP 与主分支提升候选 ZIP 现在共用一个 artifact 名称生成器，不会分别手写名称。
- 增加确定性回归：固定版本、PR 编号和完整 SHA 必须生成唯一的规范名称；PR CI 和主分支提升都必须调用同一生成器。
- `0.16.16-alpha` 在创建 tag 前停止，没有 Release 或公开下载包；本版是新的不可变事故恢复版本，不会修改、覆盖或补发旧版本。

## 用户影响

- 本版不新增 provider、模型、认证访问、自动合并或生产侧不可逆动作；既定的 structured progress 与 formal cancellation 合同保持不变。
- 发布仍只提升 PR 阶段已经验收的同一 ZIP；主分支不重新构建或替换安装包。

## 验证

- 发布前会验证候选 artifact 命名合同、候选收据、内容树、ZIP SHA256、artifact manifest、provenance 与远端下载。
- 任一合同不一致仍会在创建 tag 前停止，保留可审计的失败证据。
