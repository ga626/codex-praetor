# Codex Praetor 0.7.1-alpha

本版修复更新后“插件已经运行、真实派工却仍被旧收据拦住”的 P0 可用性问题。

## 主要改动

- health 和 provider readiness 现在以正在运行的插件 generation 与它自己的 runtime contract 为准。
- 旧 `active.json` 只保留发布历史、诊断和回收用途；它不再提供当前 provider readiness 的判断依据。
- health 会汇总当前 generation 的有效 readiness tuple；真正派工仍会逐项校验所选 provider、模型、权限、任务类型、CLI 路径、CLI hash 与有效期。
- 修复源码 generation JSON 被合同同步提示污染的问题，开发态 health/验收脚本可稳定解析。
- 增加“旧收据 + 新运行 generation + 新 readiness”回归测试，防止同类问题再次让新版本无法真实派工。

## 用户影响

更新插件并完成 Desktop 刷新后，如果 provider 已安装且登录，只需对当前版本真实运行一次只读 capability canary。canary 通过后即可真实派工；旧 `active.json`、旧缓存或旧发布回执不会再把新运行版本错误判成不可用。

## 发布与验收

合并后，`Release On Main` 会从该 merge commit 自动构建、验证、发布并下载复验同一份不可变 zip。验收依次确认：`runtime_info` 为 `0.7.1-alpha`、health 的 `running_generation` 与 `provider_readiness` 正确、dry-run 成功、一次真实只读派工成功且主工作树保持干净。
