# Codex Praetor 0.16.20-alpha

## 来源可见性与旧 checkout 防误用

- 新增只读 source provenance 检查，明确区分 `origin/main` 产品基线、候选 checkout、落后 checkout、脏 checkout、分叉 checkout 和未知来源。
- 检查只读取当前仓库的本地 Git 引用和少量源码元数据，不会自动 fetch、pull、reset、覆盖修改，也不会扫描历史 worktree。
- doctor 现在显示 source checkout 的来源分类；它是诊断信息，不会让历史 `active.json`、旧 cache 或开发 checkout 冒充当前已安装 Release。
- 增加回归覆盖：干净基线、候选提交、落后 checkout、脏 checkout 和缺失 `origin/main`。

## 保持原有边界

本版本不增加 provider、模型、认证资料访问、自动合并或生产侧不可逆动作。真实派工仍以当前安装的 Release、host runtime identity、provider readiness 和任务合同为准。
