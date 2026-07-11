## 修改内容

- 

## 验证

- [ ] `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\doctor-codex-praetor.ps1 -RequireHead -PublicRelease`
- [ ] `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-codex-praetor.ps1`
- [ ] `npm test --prefix .\mcp`

## 安全检查

- [ ] 没有提交 token、cookie、API key、provider 账号数据库、个人截图或本机私有配置。
- [ ] 没有把 D 盘开发源和 C 盘安装版做软链接或自动同步。
- [ ] 没有把外部 worker 派工替换成 Codex 原生 subagent。

