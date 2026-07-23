# Codex Praetor 0.9.9-alpha

发布日期：2026-07-23

## 本次修复

- 修复已安装插件中 capability-canary 启动时无法解析哈希 helper 的路径错误。
- 首次 provider 验证现在能从发布包内的 Skill 脚本正常启动，并在成功后写入当前 generation 的 readiness 回执。
- 新增针对插件镜像 canary 脚本的实际执行回归，防止源码目录可用、发布包却无法首次派工的情况再次进入 Release。

## 用户影响

升级后，Qoder 与 CodeBuddy 可以在新版本首次安装后通过真实 capability canary 建立自己的当前 generation 证据；不会再因包内 helper 缺失而被普通派工前置门禁卡住。

## 验收与发布

这是针对 `0.9.8-alpha` 公开 Release incident 的新不可变修复版本。`Release On Main` 会从合并 SHA 构建并发布唯一 zip；同一公开包完成远端验真、稳定安装自动更新和 host 刷新后的最终真实派工验收。
