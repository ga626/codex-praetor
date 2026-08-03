# 发布 CI 连续失败：根因、历史统计与防再犯机制

日期：2026-08-04  
范围：PR #80 `codex/qoder-session-write-resilience`，以及 2026-07-29 至 2026-08-03 的人工产品 PR CI 记录。  
结论状态：已定位共同流程缺口；本报告提出的修复在提交前必须经过本地定向验证，再由 PR CI 独立复核。

## 一句话结论

这不是 Qoder 或 CodeBuddy 派工失败，也不是“CI 偶尔不稳定”。PR #80 的最后两次失败，是本机和 GitHub Runner 为同一候选源码生成了不同 SHA 的 ZIP；现有测试只证明了“同一台机器连做几次相同”，没有证明“本机和 CI 的安装包是同一字节”。此外，工作流名称写着“检出精确候选”，实际却依赖 `pull_request` 的默认合并引用，未来会让 CI 构建输入和 PR head/evidence 脱钩。

正确修复不是再改一遍 evidence SHA，而是：CI 显式检出 PR head；ZIP 写入器直接写入受限、无压缩、所有头字段固定的规范 ZIP；测试检查 ZIP 的真实二进制头字段。

## PR #80 的证据链

| 事项 | 本机最终候选 | GitHub Actions run `30829981386` |
| --- | --- | --- |
| PR head | `d42a654f2f389d9287feaeddeab8b64c74e79ea3` | run 元数据也记录该 head |
| 构建 ZIP 大小 | `3106509` bytes | `3106509` bytes |
| ZIP SHA-256 | `0128cb7b5ad49df5ec19f75786204169c0ab2cd5d17c527ae7384d96390b05b2` | `389f60415c0a554edab7b4c2cbe4facbddc1b4d2ddac95d0b922deb687bb1d13` |
| 失败位置 | 本地运行时验收通过 | provider evidence hard gate：artifact SHA 不一致 |

两个 SHA 不同，故 CI 拒绝把旧本机 evidence 绑定到不同的云端 ZIP。这一拒绝是正确的安全行为，错在它之前的“确定性”承诺不够严格。

已排除的猜测：

- 不是两个 provider 任务失败：Qoder 与 CodeBuddy 均有 `report_valid`、退出码 `0`、干净工作树的真实回执。
- 不是 PR 未推送：远端 head 已确认是 `d42a654`。
- 不足以归因于 Node 主版本：本机分别用 Node `v25.2.1` 与 CI 同款 Node `v22.23.1` 重建，ZIP SHA 均为本机的 `0128...`。
- PR #80 当前 base 与 head 的 tree 合并没有内容差异，但 CI 日志证明默认检出了 synthetic merge commit `fd512...`，所以流程仍有未来风险。

无法从失败 run 取得其 ZIP 文件本身（hard gate 失败在 artifact upload 前），因此不能诚实断言“某一个具体 ZIP 头字段已经变了”。可以证明的是：系统 ZIP 实现仍有未由脚本控制的输出字节；新写入器会直接固定所有会影响本项目 ZIP 的字段，不依赖猜测具体字段。

## 连续失败的时间线

| Run | PR #80 提交 | 实际失败 | 处理结论 |
| --- | --- | --- | --- |
| `30815859166` | `0da434c` | 通过 | 初始候选通过，当时尚未包含后续修复提交 |
| `30821462120` | `1faf04e` | evidence head 与 artifact generation commit 不一致 | 提交与 evidence 绑定顺序问题 |
| `30824676635` | `04730a2` | evidence SHA 与 CI ZIP SHA 不一致 | 首次暴露跨机器 artifact 差异 |
| `30829981386` | `d42a654` | 同一 SHA 不一致再次出现 | 证明“改成无压缩”没有覆盖根因；不应再盲目重试 |

## 历史产品 PR 统计

统计口径：仅人工产品 PR，排除 Dependabot；窗口内共 8 个有失败 run 的产品 PR（#60、#61、#62、#67、#76、#78、#79、#80）。其中 #60/#61/#62/#67/#76/#78/#79 后续 CI 已通过并合并；#80 仍开放。

| 类别 | 失败 run 数 | 案例 | 当时被修复的方向 |
| --- | ---: | --- | --- |
| 运行时/隔离验收 | 2 | #60 包内 MCP 超时与 evaluation contract；#79 isolated release closeout | 补齐包内运行时与隔离收口条件 |
| 静态合同或公开入口 | 4 | #61 job lifecycle；#62 release intent；#76 release notes；#78 public entry consistency | 把遗漏的合同面补入实现和检查 |
| MCP 行为合同 | 2 | #67 两次 assertion | 修正 SDK/协议实现与对应断言 |
| 发布 artifact 绑定 | 3 | #80 一次 generation head、两次 SHA | 本次统一修复检出身份与 ZIP 字节身份 |

这 11 次失败不说明“CI 不可靠”；相反，它说明此前流程缺少把本地候选、CI 检出、包字节和证据同时锁定的前置环节。以后不能用“本地绿了”代替这四项的同一性证明。

## 外部证据如何支持修复

- Reproducible Builds 的 archive metadata 指南说明：归档可能带入文件时间、排序、权限等环境信息；ZIP 还可以写入 extra fields，推荐显式排除这些字段。<https://reproducible-builds.org/docs/archives/>
- Microsoft 的 `ZipArchive.CreateEntry` 文档只说明它创建 ZIP entry、默认写入当前时间且可设置压缩级别；它没有承诺跨 runtime 的二进制一致输出。<https://learn.microsoft.com/en-us/dotnet/api/system.io.compression.ziparchive.createentry>
- .NET runtime 的 ZIP 源码展示中央目录有 version made by、compatibility platform、general purpose flag、extra field、external attributes 等独立字段。这正是不能只靠“无压缩 + 固定时间”就宣称跨环境相同的原因。<https://github.com/dotnet/runtime/blob/main/src/libraries/System.IO.Compression/src/System/IO/Compression/ZipArchiveEntry.cs>

## 本次实现与验证顺序

1. 工作流把候选 checkout 固定为 PR head，并在 CI 日志断言实际 HEAD。
2. 将 release ZIP 改为规范 stored-ZIP 写入器：固定 UTF-8 标志、DOS 日期时间、version made by/needed、属性、排序、零 extra 和零 comment，不使用默认 `ZipArchive` 输出。
3. 扩展确定性测试：除了三次重建 SHA 相同，还逐个读取中央目录并验证上述固定字段。
4. 重新构建最终 artifact；由于 PR #80 改变了 Qoder 运行时代码，最终提交仍要在隔离候选上各完成一次 Qoder 和 CodeBuddy 真实任务，更新 PR evidence 为最终 head/generation/artifact SHA。
5. 仅当本地定向链和 PR CI 都通过，才合并；main 后仍按同一 immutable artifact 发布、下载复验、stable 安装与新任务验收。

## 已写入的长期流程规则

项目 `AGENTS.md` 已增加三条：候选 CI 必须检出并断言 PR head；ZIP 字节身份必须固定所有 ZIP 元数据并做二进制结构验收；同一 PR 失败后必须先汇总全部失败 run、用本地针对性证据覆盖共同根因，禁止只改 evidence SHA 重试。
