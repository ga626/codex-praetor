# Codex Praetor 0.16.1-alpha

## 本版交付

- 任务账本与长期能力回执会把 worker completion 中已有的 `contract_hash` 规范写入 `contract_sha256`，不再因字段名差异丢失任务合同证据。
- 只读任务没有写集合时，账本会明确记录空数组，而不是含义不明的 `null`。
- 结果分类器不再把普通成功文本中的 `auth` 一词误判为要求登录；明确的“需要登录/认证失败/令牌失效”等信号仍会被正确拦截。

## 未扩大承诺

本版没有新增 provider、任务族或自动路由资格。Qoder 与 CodeBuddy 的真实任务资格仍只能由 Codex 验收的独立真实记录取得；canary、夹具和 marker 仍不是该证据。

## 发布后验收

Release On Main 必须从合并 SHA 构建同一不可变 zip、上传并远端下载复验。stable 安装和 host 刷新后，Codex 会先核对 `runtime_info`，再重跑受本修复影响的真实 Qoder 只读任务；只有账本、回执、结果分类、独立复跑和 Codex 验收全部一致，才会把它们记为 `accepted`。
