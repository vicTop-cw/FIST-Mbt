# Goal-2 Round 12 报告 · CAF 离线回放验证（验收标准 1）

- 日期：2026-10-15
- 目标：使用 fist-mbt 全程开发，持续【寻虫-修复-验证-推进】循环轮转
- 交付：scripts/caf_offline_replay.py（Python 验证脚本）

## 结果摘要

写 Python 脚本模拟 MoonBit CAF 算法语义（feature_hash / edit_distance / knn_stats / soft_reorder），验证 ACRouter C-A-F 学习路由的**验收标准 1**。

**构造**：
- 4 个模型（m_free/m_cheap/m_mid/m_premium）
- 2 类任务特征（简单/复杂）
- 每类 200 条记录，成功率按人工标注（简单任务 m_free=0.9；复杂任务 m_premium=0.95）
- 200+200=400 条记录混合，用特征哈希 knn 检索

**结果**：

| 查询类型 | Top-1 | 模型统计（rate/cost） | 人工标注预期 | 结果 |
|---|---|---|---|---|
| 简单任务 | `m_free` | 0.93 / 0.01 | 低成本高成功率优先 | ✅ |
| 复杂任务 | `m_premium` | 1.0 / 0.5 | 高成功率优先 | ✅ |

**额外验证**：
- 置换性：soft_reorder 只置换不增删候选集 ✅
- 空记忆零回归：soft_reorder 返回原序 ✅

## 验证细节

```
简单任务邻域 Top 排序: ['m_free', 'm_premium', 'm_mid', 'm_cheap']
  模型统计: [('m_free', 0.93, 0.01), ('m_premium', 0.92, 0.5), ('m_mid', 0.91, 0.1)]
复杂任务邻域 Top 排序: ['m_premium', 'm_mid', 'm_cheap', 'm_free']
  模型统计: [('m_premium', 1.0, 0.5), ('m_mid', 0.91, 0.1), ('m_cheap', 0.52, 0.05)]
```

## 资源消耗

| 项 | 值 |
|---|---|
| 新增脚本 | 1（~130 行） |
| 测试通过 | 3/3 |
| FIST MCP 工具调用 | 0 |

## 遗留风险

1. 本脚本用 Python 模拟，不是 MoonBit 真源；后续可考虑用 `run_check` 跑 MoonBit 编译产物做等价验证。
2. P2c 接线仍被并发 WIP 阻塞（model_router_ops.mbt）。

## 后续建议

1. Round 13：若 WIP 释放 → P2c 接线。
2. Round 13：若仍占用 → 可用 `run_check` 把本脚本接入 CI（scripts/ 面允许）。

## 超额内容

- 无。

## 来源

- `scripts/caf_offline_replay.py`
- `docs/2026-10-14-fist-mbt-router-caf-learning-plan.md` 验收标准 1
