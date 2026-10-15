# Goal-2 Round 19 报告 · 发现 BUG-193 + 新增锁测试

- 日期：2026-10-15
- 目标：使用 fist-mbt 全程开发，持续【寻虫-修复-验证-推进】循环轮转
- 交付：BUG-193 上报 + 2 条 caf_stats 锁测试（代码就位但被阻塞）

## 结果摘要

### 1. 发现 BUG-193（critical）

**问题**：并发 agent 在 `src/router/router_config.mbt` 的 WIP diff 中引入 `n.is_finite()` 调用（3 处：line 133、148、220），但 MoonBit 的 `Double` 类型**没有** `is_finite` 方法。

**影响**：`moon check src/router` → **3 errors，全仓编译失败**（连 `moon test` 也无法运行）。

**上报**：`report_bug` → **BUG-193**（critical），修复任务 **T0r615** 发布到 bugs 命名空间。

**建议修复**：
```moonbit
// 错误（不可用）
if n.is_finite() && n >= -2_000_000_000.0 && n <= 2_000_000_000.0 {

// 正确（等价）
if n == n && n >= -2_000_000_000.0 && n <= 2_000_000_000.0 {
```
（`n == n` 为 true 表示不是 NaN；NaN 与任何数比较都是 false，`n >= X` 已经自然排除 NaN）

### 2. 新增 2 条 caf_stats 锁测试（代码就位但被阻塞）

**目的**：锁住并发 agent R17 加的 `total>0` 防御守卫。

**测试**：
- `caf_stats_zero_total_guard_safety`：验证任何合法输入下 `caf_stats` 不 panic 且 `avg_cost` 有限
- `caf_stats_high_frequency_single_model`：单模型高频（100 条）不 panic 且排序稳定

**状态**：代码已写入 `src/router/router_caf_wbtest.mbt`（+34 行），但被 router_config.mbt 编译错误阻塞无法运行。

### 3. 我的测试代码无错误

`moon check src/router/router_caf_wbtest.mbt` 的 3 errors **全在 router_config.mbt**（line 133/148/220），我的测试代码本身语法正确。

## 验证细节

```
Error: [4015] × 3
  router_config.mbt:133  Type Double has no method is_finite
  router_config.mbt:148  Type Double has no method is_finite
  router_config.mbt:220  Type Double has no method is_finite
```

## 资源消耗

| 项 | 值 |
|---|---|
| FIST MCP 工具调用 | 1（report_bug） |
| 修改文件 | 1（src/router/router_caf_wbtest.mbt，+34 行） |
| BUG 编号 | BUG-193（critical） |

## 遗留风险

1. **全仓编译失败**（router_config.mbt 并发 agent WIP 未提交修复）——所有测试无法运行。
2. 我的 2 条新测试待编译错误解除后验证。
3. 并发 agent 仍持有 router_caf.mbt 的 WIP（R17 加的守卫未提交）。

## 后续建议

1. 并发 agent 修复 BUG-193 后：跑 `moon test --target js src/router` 验证我的 2 条新测试。
2. 并发 agent 修复后：跑全仓回归（基线 1112/1112）确认零回归。
3. P2c 接线仍受阻塞，但 BUG-193 修复是**更紧迫**的路径（阻断所有工作）。

## 超额内容

- 无。

## 来源

- `git diff src/router/router_config.mbt`（并发 agent WIP，3 处 is_finite）
- `moon check src/router` → 3 errors (Error [4015])
- `mcp__fist-mbt__report_bug` → BUG-193, task T0r615
- `src/router/router_caf_wbtest.mbt`（+2 测试，待验证）
