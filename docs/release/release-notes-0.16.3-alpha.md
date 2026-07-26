# Codex Praetor 0.16.3-alpha

## 本版交付

- 修复能力画像读取 Windows PowerShell 写出的 UTF-8 BOM ledger 时，把有效 JSON 误判为 `malformed` 的问题。
- 能力画像现在能只读投影同一份 ledger；不会重写、迁移或清理历史 plan 文件。
- 新增回归：带 BOM 的 ledger 仍可参与只读画像，且原始字节内容保持不变。

## 未扩大承诺

本版不把任何历史、canary、夹具或 marker 提升为 provider 能力，也不新增 provider、任务族、自动路由或连接层。真正的能力仍须由当前 generation、真实任务、独立验收和 Codex `accepted` 回执共同证明。

## 发布后验收

Release On Main 必须从合并 SHA 构建同一不可变 zip、上传并远端下载复验。stable 安装和 host 刷新后，Codex 会先核对 `runtime_info`，再确认能力画像不再把带 BOM 的有效 ledger 误报为损坏；这项解析修复本身不改变任何能力 verdict。
