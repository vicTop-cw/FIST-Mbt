# Goal-2 Round 7 报告 · CAF 属性测试（随机化寻虫 + 数学性质验证）

- 日期：2026-10-15
- 目标：使用 fist-mbt 全程开发，持续【寻虫-修复-验证-推进】循环轮转
- 提交：674740d（属性不变量）+（edit_distance 性质）

## 结果摘要

Round 7 两个属性测试，从「手工用例」升级到「不变量验证」：

1. **`caf_property_random_invariants`**：LCG 伪随机 push 30 条到 max_size=7 的环形缓冲，验证三条不变量：
   - `all().length() <= max_size`（FIFO 淘汰不越界）
   - `knn_search` k=0 → 空；k>count → 返回 count（不越界）
   - `caf_soft_reorder` 是候选集的置换（元素不变，仅顺序变）

2. **`caf_edit_distance_properties`**：验证 Levenshtein 的四条数学性质：
   - 自反性：d(a,a)==0
   - 对称性：d(a,b)==d(b,a)
   - 基例：d(a,"")==len(a)
   - 三角不等式：d(a,c) <= d(a,b)+d(b,c)

## 验证细节

| 阶段 | src/router 测试数 |
|---|---|
| Round 6 收口 | 129/129 |
| + edit_distance 性质 | 130/130 ✅ |

所有数学性质通过，说明 `caf_edit_distance` 实现正确（滚动数组 DP 无 off-by-one）。

## 资源消耗

| 项 | 值 |
|---|---|
| 提交 | 2 |
| 新增测试 | 2 |
| 编辑 | 2 次 |

## 遗留风险

1. P2c 接线仍未完成（pick 钩子 + 配置项 + status 展示）——`model_router_ops.mbt` WIP 未释放。
2. 属性测试覆盖有限：未测试 edit_distance 对超大字符串（O(n*m) 性能瓶颈）。

## 后续建议

1. Round 8：若并发 WIP 释放 → P2c 接线。
2. Round 8：edit_distance 性能测试（长字符串 O(n*m) 会 OOM）——可加长度上限守卫。

## 超额内容

- 无。

## 来源

- `src/router/router_caf_wbtest.mbt`（测试）
- `moon test --target js src/router` 实测
