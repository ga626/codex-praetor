# Codex Praetor 0.9.4-alpha

## 本次修复

- 修复 `0.9.3-alpha` 的发布后功能缺陷：已安装插件现在自带三家 provider 的 adapter 合同和 onboarding 清单，不再依赖只存在于发布压缩包根目录的 `config/`。
- `codex_praetor_provider_operations` 在真实已安装运行时能展示三家 provider 的合同状态和准入清单。
- 最终发布物验收现在会真正调用该工具；若插件内缺少运营数据，构建在发布前失败。

## 用户可感知到的变化

刷新到本版本后，运营面板不再把三个 provider 都误显示为“只有可小范围验证、没有合同和清单”。它仍不会读取认证信息，也不会因为展示合同而自动扩大派工权限。

## 发布与本机验收

这是针对 `0.9.3-alpha` 的不可变版本修复，不会覆盖旧 tag 或旧 Release。合并后，`Release On Main` 会从本次 merge SHA 自动发布 `v0.9.4-alpha`，验真远端包并自动更新 stable marketplace。之后需要一次受支持的 Codex Desktop host 刷新，再验证新 runtime、provider canary 和真实隔离 worktree worker。
