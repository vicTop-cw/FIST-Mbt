# Goal-2 Round 4 报告 · C-A-F P2 核心算法 + 测试覆盖缺口闭合

- 日期：2026-10-15
- 目标：使用 fist-mbt 全程开发，持续【寻虫-修复-验证-推进】循环轮转
- 提交：0e85be8（3 覆盖测试）+ 2b612ca（P2 核心算法）

## 结果摘要

Round 4 推进了两件事：

1. **补 3 个测试覆盖缺口**（Round 2 识别的）：
   - `caf_memory_wraparound_order`：环形回绕后 FIFO 顺序
   - `caf_memory_single_slot`：max_size=1 单元素退化
   - `caf_memory_full_buffer_eviction`：满缓冲覆盖不增长 count

2. **实施 P2 相似检索核心算法**：
   - `caf_edit_distance(a, b)`：Levenshtein 编辑距离（O(n*m) DP）
   - `CafMemory::knn_search(context, k)`：按编辑距离取 Top-K 历史记录

## 验证细节

| 阶段 | moon test src/router |
|---|---|
| Round 3 收口 | 116/116 |
| + 3 覆盖测试 | 119/119 |
| + P2 算法 | 122/122 |

- `moon fmt --check` → no work to do。
- 全仓 moon test 仍被 `src/ops/ops_pipeline.mbt:874` 编译错误阻断（并发 agent WIP）。

## 计划状态更新（文档即实现）

| 阶段 | 内容 | 状态 |
|---|---|---|
| P1 | 反馈记账与记忆表 | ✅ 已实现（2026-10-15） |
| P2 | 相似检索与决策融合 | 🔄 进行中（核心算法已实现，接线与 pick 软性排序待办） |

## 资源消耗

| 项 | 值 |
|---|---|
| 提交 | 2（0e85be8 / 2b612ca） |
| 新增测试 | 6 |
| 编辑 | 8 次 |
| 触碰并发 WIP | 0 |

## 遗留风险

1. `CafMemory::all()`/`find()`/`knn_search()` 均 O(max_size)，非 O(count) —— 大数据量时性能退化（不是正确性）。
2. P2 尚未接线：`model_router_ops.mbt`（并发 WIP）未接入 `knn_search`，pick 软性排序未实现。
3. `src/ops/ops_pipeline.mbt:874` 编译错误仍在（并发 agent WIP）。

## 后续建议

1. Round 5：P2 决策融合 —— 在 pick 决策内加入软性排序钩子（默认关闭零回归）。
2. Round 5：`all()` 性能优化（遍历 count 而非 max_size）。
3. Round 5：验证 knn_search 编辑距离是否对语义近似有意义（当前是数字串编辑距离，非语义距离）。

## 超额内容

- 无。

## 来源

- `docs/2026-10-14-fist-mbt-router-caf-learning-plan.md`（P2 规格）
- `src/router/router_caf.mbt`（实现）
- `src/router/router_caf_wbtest.mbt`（测试）
- `moon test --target js src/router` 实测
