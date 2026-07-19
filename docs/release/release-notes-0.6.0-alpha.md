# Codex Praetor 0.6.0-alpha

本版本把发布流程从“合并后人工补发布”改为同一条可验证的合并即发布流水线。

## 主要变化

- 发布影响 PR 必须在同一个 PR 内提交 `config/release-intent.json` 和完整版本面。
- PR CI 会阻断缺少发布意图、复用已有不可变 tag 或版本面不一致的变更。
- `main` 合并后由 `Release On Main` 自动完成构建、测试、创建 draft Release、上传 zip 与 `.sha256`、发布和远端复验。
- 版本、runtime contract、Plugin、Skill、MCP、安装入口和公开文档通过统一版本脚本保持一致。
- 保留 `awaiting_host_refresh`、provider readiness 和 user-path proof 等运行态门禁；自动 Release 成功不等于本机已激活。

## 发布边界

GitHub Release 是不可变交付物。旧 tag 不会被覆盖；新的用户可见变更必须使用新的版本和 tag。Codex Desktop 当前对话不能承诺无感热替换，开发验证仍使用隔离 dev profile 和 fresh context。

## 验证

- `scripts/verify/test-release-intent.ps1`
- `scripts/verify/test-codex-praetor.ps1`
- `npm test --prefix .\mcp`
- `scripts/verify/test-release-package-determinism.ps1`
- `scripts/verify/test-release-closeout.ps1`
