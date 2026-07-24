## 修改内容

- 

## 发布意图

- [ ] 本 PR 不改变用户入口、安装包、Skill、Plugin、MCP、provider wrapper 或发布流程。
- [ ] 本 PR 属于发布影响变更，已在同一个 PR 更新 `config/release-intent.json`、版本面和发布说明；合并到 `main` 后会由 Release On Main 自动发布。
- [ ] 已确认版本/tag 不复用已有不可变 Release。

## 验证

- [ ] 已从当前候选 HEAD 的干净隔离 worktree 运行 `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\invoke-release-candidate-preflight.ps1 -BaseRef origin/main -CheckRemote -AllowDraftMetadataPlaceholders`。
- [ ] 已取得该 HEAD 与候选 zip SHA 对应的通过回执；PR CI 只作同一入口的独立复核。
- [ ] 如果改本机 Codex 安装、已安装 skill、provider dry-run 或全局规则联动，已另跑 `scripts\verify\test-codex-praetor-dev-env.ps1`。

## 安全检查

- [ ] 没有提交 token、cookie、API key、provider 账号数据库、个人截图或本机私有配置。
- [ ] 没有把 D 盘开发源和 C 盘安装版做软链接或自动同步。
- [ ] 没有把外部 worker 派工替换成 Codex 原生 subagent。

## 用户影响

- [ ] 不需要用户重新理解 provider 账号、token 或本机数据库边界。
- [ ] 文档或命令失败时，用户能看出下一步该做什么。
