# Goal-2 Round 5 报告 · P2 决策融合核心 + 性能优化

- 日期：2026-10-15
- 目标：使用 fist-mbt 全程开发，持续【寻虫-修复-验证-推进】循环轮转
- 提交：31a3225（优化 + knn_stats）+ 5042885（caf_soft_reorder）

## 结果摘要

Round 5 推进 P2 决策融合三步：

1. **性能优化**：`CafMemory::all()` / `find()` 从 O(max_size) 优化为 O(count)——稀疏环（count << max_size）不再全扫。

2. **knn_stats()**：新增 `CafMemory::knn_stats(context, k)`，对 Top-K 邻域按模型统计成功率与平均成本，作为决策融合的数据源。复用 `caf_stats`。

3. **caf_soft_reorder()**：新增纯函数 `caf_soft_reorder(candidates, stats)`，按邻域统计软性重排候选模型——邻域内成功率占优/成本更低的提前，未在邻域的保持稳定序。**不增删模型、不破配额硬约束**。

同时 `CafModelStats` 字段公开（pub），供外部决策消费。

## 验证细节

| 阶段 | moon test src/router |
|---|---|
| Round 4 收口 | 122/122 |
| + O(count) + knn_stats 测试 | 124/124 |
| + caf_soft_reorder 测试 | 126/126 |

- `moon fmt --check` → no work to do。
- `.mbti` 未更新（router 包无独立 .mbti；src/server 的 .mbti 变更属并发 agent，不提交）。

## 计划状态更新

| 阶段 | 内容 | 状态 |
|---|---|---|
| P1 | 反馈记账与记忆表 | ✅ 已实现 |
| P2a | 相似检索（knn_search + edit_distance） | ✅ 已实现 |
| P2b | 决策融合核心（knn_stats + caf_soft_reorder） | ✅ 已实现 |
| P2c | 接线（pick 钩子 + model_router_ops + 配置项 + status） | ⏳ 待办（并发 agent WIP 收口后） |

## 资源消耗

| 项 | 值 |
|---|---|
| 提交 | 2（31a3225 / 5042885） |
| 新增测试 | 4 |
| 编辑 | 8 次 |
| 触碰并发 WIP | 0（.mbti 未提交） |

## 遗留风险

1. P2c 接线未完成：pick 内软性排序钩子、`router.use_caf_memory` 配置项、status 展示——需等 `src/server/model_router_ops.mbt` 并发 WIP 收口。
2. `caf_soft_reorder` 未在 pick 内验证集成（纯函数已测，集成未测）。
3. `src/ops/ops_pipeline.mbt:874` 编译错误仍在（并发 agent WIP）。

## 后续建议

1. Round 6：并发 WIP 收口后实施 P2c 接线（pick 钩子 + 配置项）。
2. Round 6：验证 caf_soft_reorder 端到端集成不破坏 pick 确定性决策基线。
3. Round 6：若 WIP 未收口，转寻虫（issue_scan src/router/）或探索其他 docs/ 计划。

## 超额内容

- 无。

## 来源

- `docs/2026-10-14-fist-mbt-router-caf-learning-plan.md`（P2 规格）
- `src/router/router_caf.mbt`（实现）
- `src/router/router_caf_wbtest.mbt`（测试）
- `moon test --target js src/router` 实测
