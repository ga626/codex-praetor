# Codex Praetor 0.16.14-alpha

## 发布内容

- 修复发布链路：PR 候选阶段构建、运行时验收并证明一份 ZIP；合并到 `main` 后只下载、核对并发布该 ZIP，不再重新打包第二份。
- Release generation 现在同时记录候选提交和不可变的源码内容树。最终 tag 可以有不同的 Git 提交 SHA，但其内容树必须与已验收候选完全一致；否则在创建 tag 前失败。
- 为候选 ZIP 增加 GitHub Actions artifact、候选收据和 provenance attestation；发布阶段会核对 PR、内容树、SHA256、manifest 和远端下载结果。
- pre-push 的完整本地检查保留，但发布控制面会以明确阶段输出显示进度，避免把本机验收误判为网络卡住。

## 用户影响

- 用户下载到的 Release ZIP 与 PR 阶段已经验收的 ZIP 是同一份文件，可用 SHA256 与 provenance 追溯。
- 本版不新增 provider、模型、认证访问、自动合并或生产侧不可逆动作。

## 验证

- 候选 ZIP、main promotion ZIP 与远端下载 ZIP 的 SHA256 必须一致。
- 任意候选收据、内容树、generation 或 digest 不一致都会在 tag/Release 前失败。
- 发布后仍完成 stable 安装、host 刷新、`runtime_info`、canary 和真实 worker 任务验收。
