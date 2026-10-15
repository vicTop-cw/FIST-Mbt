# Goal-2 Round 1 报告 · C-A-F 学习路由寻虫 + BUG-173/174 上报

- 日期：2026-10-15
- 目标：使用 fist-mbt 全程开发，持续【寻虫-修复-验证-推进】循环轮转（Goal-2 Round 1/256）
- 方向：docs/2026-10-14-fist-mbt-router-caf-learning-plan.md（C-A-F 学习路由，唯一未实现计划）
- 提交：无（bug 上报 publish_task=true 已在 ns=bugs 生成 T0r612/613）

## 结果摘要

### 1. 方向确定：C-A-F 学习路由

`docs/` 下最新未实现计划 = `2026-10-14-fist-mbt-router-caf-learning-plan.md`（P1/P2 均标 ⬜ 未开始）。Router enhancement plan 三项已实现（P1.1/P1.3/P2）。

### 2. 并发 agent 已提交实现

`src/router/router_caf.mbt`（211 行）+ 2 个测试文件（`router_caf_wbtest.mbt` / `router_caf_bug188_wbtest.mbt`）+ BUG-168/172/188 修复。`git status -- src/router/` 空 = 已提交。

### 3. 我的分工：寻虫（不触碰 src/router/）

用 `boundary_probe` + 手工代码阅读发现 **2 个真实 bug**：

### 4. BUG-173（medium, OPEN, T0r612）

**caf_stats 的 sort_by 比较器违反严格弱序**（src/router/router_caf.mbt:151-173）

```
if rate_a != rate_b {
  if rate_a > rate_b { -1 } else { 1 }
} else if a.avg_cost < b.avg_cost {
  -1
} else {
  1   // ← 相等时恒返回 1（非 0）
}
```

- `cmp(a, a)` 恒返回 1 ≠ 0 —— 违反自反性。
- `cmp(a, b) == 1` 且 `cmp(b, a) == 1`（相等时）—— 违反反对称性。
- 后果：sort_by 可能不终止/退化 O(n²)/结果不稳定，`model_router_status` 展示错序。

### 5. BUG-174（low, OPEN, T0r613）

**caf_feature_hash 的 h\*31+c 无检查溢出 + h.abs() 未定义**（src/router/router_caf.mbt:179-188）

- `h = h * 31 + c` 对 Int64 无检查，约 14 字符以上必然溢出（31^14 ≈ 1e20 > 2^63）。
- `h.abs()` 在 `h == Int64.min_value()` 时 MoonBit 未定义（panic）。
- 概率低（约 1/2^64），但属真实缺陷类。

### 6. 处置边界

- 只读 src/router/，**不修改源码**（并发 agent 职责）。
- 通过 `report_bug(publish_task=true)` 上报，已生成修复单 T0r612/613（ns=bugs）。

## 资源消耗

| 项 | 值 |
|---|---|
| 工具调用 | glob × 2、read × 2、pwsh × 2、bug_list × 1、read(router_caf.mbt) × 1、boundary_probe × 2、report_bug × 2 |
| 提交 | 无（bug 上报生成 T0r612/613） |
| 触碰并发 WIP | 无 |

## 任务分配记录

- 本会话 Goal-2 Round 1 完成：方向确定 + C-A-F 寻虫 + 2 bug 上报。

## 遗留风险

1. BUG-173/174 已 OPEN，等待并发 agent 修复。
2. 内建 compat 的 protocolVersion 回写缺陷——已归档为 DGM 资产。
3. BUG-155 假绿持续——HEAD 仍含 stale dist。

## 后续建议

1. Round 2 建议：验证 BUG-173/174 是否被修复（若并发 agent 已修则标 FIXED + evidence）。
2. 持续【寻虫-修复-验证-推进】循环：可扩展到 `src/router/router_caf_wbtest.mbt` 测试覆盖审查 + `src/server/model_router_ops.mbt` 接线面。
3. 推进方向：`docs/` 下唯一未实现计划已找到（C-A-F），后续若并发 agent 完成 P2（相似检索 + 决策融合）则验证闭环。

## 超额内容

- 无（严格限于 C-A-F 寻虫 + bug 上报）。

## 来源

- `docs/2026-10-14-fist-mbt-router-caf-learning-plan.md` → 唯一未实现计划
- `src/router/router_caf.mbt` → 211 行 C-A-F 实现
- `report_bug` → BUG-173（medium）/ BUG-174（low）
- `boundary_probe` → sort-comparator / int-overflow-abs 两个规则
