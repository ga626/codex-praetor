## 修改内容

- 

## 验证

- [ ] `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\doctor-codex-praetor.ps1 -RequireHead -PublicRelease`
- [ ] `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-codex-praetor.ps1`
- [ ] `npm test --prefix .\mcp`
- [ ] 已完成一次不修改文件的 dry-run。
- [ ] 如果改动安装或发布流程，已验证安装、更新或回滚路径。

## 安全检查

- [ ] 没有提交 token、cookie、API key、provider 账号数据库、个人截图或本机私有配置。
- [ ] 没有把 D 盘开发源和 C 盘安装版做软链接或自动同步。
- [ ] 没有把外部 worker 派工替换成 Codex 原生 subagent。

## 用户影响

- [ ] 不需要用户重新理解 provider 账号、token 或本机数据库边界。
- [ ] 文档或命令失败时，用户能看出下一步该做什么。
