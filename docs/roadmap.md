# Codex Praetor 路线图

## 当前状态：2026-07-15

`v0.1.2-alpha` 是当前已发布给普通用户下载的版本。它把 Codex Praetor 从“安装和 dry-run 可用”推进到“Codex 可以真实派发外部 worker、收集结果、记录验收结论，并按计划继续下一步”。

已经完成：

- Skill、脚本、MCP 薄封装和插件包结构。
- 意图识别、dry-run、任务列表、状态查询、计划、lane 查询和冲突检测。
- 真实 worker 派发 MCP 工具。
- worker 结果摘要读取和失败分类。
- 计划中的 ready task 查询、计划任务派发和 Codex 验收记录。
- worker 完成后进入 `awaiting_verification`，只有 Codex 验收通过才解锁依赖任务。
- Qoder、CodeBuddy、MiMo 三类 provider 路线的只读 canary。
- 中文首页、安装指南、排错指南、隐私边界、卸载回滚和用户验收清单。
- GitHub issue 模板和 pull request 模板。
- provider 只读 canary 的统一预览/执行入口。
- Windows 安装向导的 5 选项 provider 引导：全部配置、全部跳过、只配置 Qoder、只配置 CodeBuddy、只配置 MiMo。
- 安装向导中的官方安装执行、人工授权陪跑、断点恢复、复检、本机配置写入、可选只读 canary 和最终状态总览。

## 近期目标

1. 让新鲜 Codex 工具上下文能看到真实 dispatch、result、next-ready、dispatch-plan-task 和 verify-task 工具。
2. 让 Codex 在大任务开始时先声明分工：哪些交给 worker，哪些 Codex 自己保留，原因是什么。
3. 让 worker 失败进入统一分类：超轮数、provider 缺失、未登录、权限拒绝、测试失败、无有效产出、需要人工处理。
4. 让计划任务只有经过 Codex 验收后才推进依赖任务。
5. 保持公开文档中文优先，英文只作为切换页或补充。
6. Release 页面、README、安装说明和插件展示信息保持同一套口径。
7. 公开包不包含内部交接材料、本机配置、provider 缓存、运行态任务、个人截图或账号信息。

## 下一版候选方向

- 发布收口自动化：让 Release、README、安装指南、路线图和远端 zip 在同一套公开入口一致性检查里保持同步。
- 发布包确定性：固定 zip 文件顺序、时间戳和元数据，让相同内容构建出稳定 SHA256。
- 更友好的插件缓存清理和恢复提示。
- 更完整的 GitHub Release 校验信息，例如 zip 摘要和安装后检查步骤。
- 持续跟进 Codex 插件和 MCP 加载机制变化，减少用户手动操作。
- 清理发布后遗留的已合并分支、过期 worker worktree 和本地运行态归档说明。

## 不做什么

- 不做通用多 Agent 平台。
- 不在未经用户确认时安装 Qoder、CodeBuddy、MiMo；用户确认后只执行官方安装命令，不替用户登录或确认账单。
- 不读取 token、cookie、账号数据库、余额页或个人截图。
- 不默认创建 Codex 原生 subagent。
- 不把源码目录和本机安装目录做软链接或自动同步。
