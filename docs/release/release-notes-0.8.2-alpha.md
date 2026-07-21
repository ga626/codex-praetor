# Codex Praetor 0.8.2-alpha

本版修复了已公开版本在本机完成安装后，健康检查仍错误拒绝当前 generation 的问题，并把发布后的本机激活固化为一个可执行、可复验的入口。

## 主要改动

- health 与 capability canary 统一从运行中的 bundled plugin 解析 Release generation；不会再把正确的当前 canary proof 误判为旧合同的 synthetic generation。
- 发布后可执行 `scripts/release/activate-published-codex-praetor-release.ps1`：下载并验真同一公开 Release zip，运行包内安装器，调用官方 `codex plugin add codex-praetor@personal`，安装 maintenance，并明确停在 `needs_host_restart` 或 `needs_canary`。
- 外部 worker 的隔离 worktree 支持 detached HEAD：以当前 commit 创建新的隔离分支，不再因验收 checkout 没有分支而失败。
- 新增打包态正反 generation proof、自动激活 fixture 和 detached HEAD worktree 的回归，防止相同链路再次漂移。

## 用户影响

公开 Release 下载验真通过后，Codex 可自动安装该同一 zip 到稳定 marketplace；用户不再需要手动下载、解压或安装。若输出为 `needs_host_restart`，只需按受支持方式刷新或重启一次 Codex Desktop；之后先验证 `runtime_info`，再做 canary 和真实 worker。

## 发布与验收

合并后 `Release On Main` 从精确 merge commit 自动构建、发布并复验不可变 zip。公开交付与本机 host 是否已刷新仍是两个独立观察：前者通过远端 artifact 证明，后者通过安装身份、host runtime 和 canary 顺序证明。
