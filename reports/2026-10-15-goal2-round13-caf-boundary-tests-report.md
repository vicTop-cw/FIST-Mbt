# Goal-2 Round 13 报告 · CAF 边界用例补测

- 日期：2026-10-15
- 目标：使用 fist-mbt 全程开发，持续【寻虫-修复-验证-推进】循环轮转
- 交付：src/router/router_caf_wbtest.mbt +4 测试

## 结果摘要

补充 4 个 CAF 边界用例测试，覆盖排序稳定性和检索边界：

| 测试名 | 目的 |
|---|---|
| `caf_soft_reorder_tie_stable` | 相同 rate+cost 保持原序（严格弱排序最后一格） |
| `caf_soft_reorder_mixed_neighborhood` | 混合邻域：邻域优先 + 非邻域保持原序 |
| `caf_knn_search_k_greater_than_records` | k>记录数返回全部；k=0/负防御 |
| `caf_knn_stats_empty_neighborhood` | 空记忆 → 空 stats + 零回归 |

**测试计数**：131 → **135**，全部通过。

## 验证输出

```
Total tests: 135, passed: 135, failed: 0.
```

## 资源消耗

| 项 | 值 |
|---|---|
| 新增测试 | 4 |
| 测试通过 | 135/135 |
| 新增文件 | 0（修改已有测试文件） |
| 提交 | 1 |

## 遗留风险

1. P2c 接线仍被并发 agent WIP 阻塞（model_router_ops.mbt，27 文件）。
2. 并发 agent WIP 中 star_gate_wbtest.mbt 有 4 个 deprecation warnings（非阻塞）。

## 后续建议

1. Round 14：若 WIP 释放 → P2c 接线。
2. Round 14：若仍占用 → 考虑冷启动启发式或 knn 前缀索引优化。

## 超额内容

- 无。

## 来源

- `src/router/router_caf_wbtest.mbt`（末尾追加）
