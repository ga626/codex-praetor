# Codex Praetor 路线图

## 当前状态：2026-07-21

`v0.9.0-alpha` 是当前已公开交付的基线。候选 `v0.9.1-alpha` 建立真实任务评测实验场：把四类工作、隔离边界、验收、预算和失败注入变成可复跑合同，准备任务不等于能力证据，也不改变默认派工。合并后仍只由 Release On Main 创建、发布和复验不可变 Release；本机验证严格区分隔离开发 profile 与已安装用户 runtime。

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
- canary 的 clean-before 与 drift-during 分层证据；并发仓库变动不会再伪装成 provider 失败。
- `process_exited` 等执行终态与“等待 Codex 验收”分层展示，不再错误占用 active lane。
- Windows 安装向导的 5 选项 provider 引导：全部配置、全部跳过、只配置 Qoder、只配置 CodeBuddy、只配置 MiMo。
- 安装向导中的官方安装执行、人工授权陪跑、断点恢复、复检、本机配置写入、可选只读 canary 和最终状态总览。
- 发布包确定性构建：固定 zip 条目顺序和时间戳，让相同发布内容构建出稳定 SHA256。
- 本地运行态清理预览：识别已合并且干净的 worker worktree、过期完成任务和 scratch 内容，默认只预览，确认后才删除或归档。
- 产品验收与开发者本机检查分离，PR 和发布门禁不再被全局规则、本机 skill 副本或 provider 登录状态误伤。
- 公开入口一致性检查，确保首页、安装说明、路线图、发布说明和 GitHub Release 指向同一版本。
- release intent、版本面一致性和 main 合并后自动发布 workflow。
- 真实 worktree 实验：Qoder fail-to-pass、background job、旧安装 CodeBuddy 拒绝与恢复源码 CodeBuddy 真实写入均已有独立证据；实验产物不合入主线。

## 近期目标

- 将“合并 -> 自动 Release -> 远端复验”作为唯一公开发布路径，禁止合并后的人工补发版。
- 将本机 stable 更新与 Desktop host refresh 明确为独立投影；自动发布成功后，不能伪称当前对话已热更新。

本大 PR 一次完成：

- logical task、immutable attempt、artifact/evidence 状态和 supervisor verdict 的本地账本；`completed` 只代表 accepted outcome，绝不代表一次进程退出。
- 默认顺序派工；只有明确不重叠的 write set 才允许并行 edit attempt，并保留 base commit、预算与 stop-loss。
- 用新账本执行 maintenance、动态 health、runtime inventory、供应链与用户文档这些产品真值工作流。
- 代际感知的 readiness、统一 job/completion 终态、不可复用 release tag、隔离收口烟测和旧 generation 延迟回收。

1. 让新鲜 Codex 工具上下文能看到真实 dispatch、result、next-ready、dispatch-plan-task 和 verify-task 工具。
2. 让 Codex 在大任务开始时先声明分工：哪些交给 worker，哪些 Codex 自己保留，原因是什么。
3. 让 worker 失败进入统一分类：超轮数、provider 缺失、未登录、权限拒绝、测试失败、无有效产出、需要人工处理。
4. 让计划任务只有经过 Codex 验收后才推进依赖任务。
5. 让开发验证把 readiness 写入隔离 profile，不能污染稳定安装或其 provider 准入记录。
6. 保持公开文档中文优先，英文只作为切换页或补充。
7. Release 页面、README、安装说明和插件展示信息保持同一套口径。
8. 公开包不包含内部交接材料、本机配置、provider 缓存、运行态任务、个人截图或账号信息。

## 下一版候选方向

- Desktop host runtime identity、刷新状态和恢复提示。
- 持续跟进 Codex 插件和 MCP 加载机制变化，减少用户手动操作。
- 清理工具和用户向导之间的提示联动，例如什么时候建议运行清理、哪些内容永远不应清理。
- 为运行态清理增加更直观的空间占用摘要和保留期说明。

## 不做什么

- 不做通用多 Agent 平台。
- 不在未经用户确认时安装 Qoder、CodeBuddy、MiMo；用户确认后只执行官方安装命令，不替用户登录或确认账单。
- 不读取 token、cookie、账号数据库、余额页或个人截图。
- 不默认创建 Codex 原生 subagent。
- 不把源码目录和本机安装目录做软链接或自动同步。
