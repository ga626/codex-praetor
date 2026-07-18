# Codex Praetor 0.4.1-alpha

## 这版解决什么

这一版修正了发布验收中“工具名相同就等于新 runtime 已加载”的错误假设。插件、cache、MCP 进程和 Codex Desktop host 是不同层：磁盘已经安装新版本，不代表常驻 Desktop host 已经从新路径启动 MCP server。

## 主要变化

- `codex_praetor_runtime_info` 现在返回 runtime contract SHA256、实际根目录、MCP PID 和启动时间。
- fresh-context proof 必须绑定这些运行时身份字段；旧版本或同名旧工具不能再为新 generation 签署通过。
- release activation 与 health gate 会拒绝缺少 runtime identity 的 proof。
- `reload-codex-praetor-mcp.ps1` 现在明确是独立 app-server 诊断，不能再被当成常驻 Desktop host 的刷新动作。

## 用户影响

更新插件后，如果 Desktop 内的 `runtime_info` 仍显示旧版本、旧 SHA256 或旧路径，反复新建任务不会修复。需要先通过 Codex 支持的刷新动作或完全退出并重新启动 Desktop，让常驻 host 重建插件发现状态；随后只做一次 native canary。

## 发布验收

合并后将发布 `v0.4.1-alpha` 的安装 zip 与 `.sha256`。stage 后先验证实际 Desktop runtime identity，再写 fresh-context proof、provider readiness 和 active receipt。只有普通用户下载、安装、重新启动并看到匹配 runtime identity 后，才算产品交付。
