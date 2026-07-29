# Codex Praetor 0.16.8-alpha

## 发布内容

- Release On Main 现在会先复用发布影响分类；只有真正改变公开运行时、安装包或发布合同的 main 合并才会创建新的不可变 Release。
- 更新 `actions/checkout` 到 7.0.1 的固定提交，保持 CI 与发布工作流使用同一经过固定的 action 版本。
- 已有的 structured progress 与 formal cancellation 合同保持不变，并继续由同一 runtime contract 约束。

## 用户影响

普通依赖或工作流维护合并不再错误尝试复用已有版本标签；已发布的稳定安装包和 worker 授权边界不变。

## 验证

- 发布影响分类和共享工作流合同回归。
- 干净隔离候选构建、安装包验收和远端下载复验。
