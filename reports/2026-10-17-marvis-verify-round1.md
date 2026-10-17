# Marvis 验证轮 Round 1 — 汇总报告

**验证日期**：2026-10-17  
**当前分支**：`marvis-verify-20261017`  
**关联报告**：`reports/2026-10-17-marvis-unsafe-scan.md`（前置 Unsafe 扫描）  
**验证目标**：确认 Unsafe 扫描发现的风险不破坏 engine 核心逻辑，回归测试全绿

---

## 一、前置扫描结论（引用 unsafe-scan 报告）

| 维度 | 结论 |
|---|---|
| 裸 `.unwrap()` | **0 处**（三文件全零） |
| `unsafe_get()` | **0 处**（全零） |
| `.expect()` | **0 处**（全项目零命中） |
| `unwrap_or()` 中高风险 | **3 处**（#1 `dag_topo_order` L360-363 中 / #2 `budget_split_by_dag` L910 高 / #3 `dag_reaches` L260-270 低） |
| 扫描器自身（issue_scan） | 零运行时风险 |

> **P1 建议**：`budget_split_by_dag` L910 `unwrap_or(false)` 存在语义反转隐患（未来若 `in_scope` 追加 `false` 条目，逻辑静默反转）。  
> **P2 建议**：`dag_topo_order` L360-363 `unwrap_or` 改为显式 `abort` 防 invariant 违背。  
> **P3 建议**：`dag_reaches` L260-270 加注释说明不变量（现状安全）。

---

## 二、Engine 全量回归测试

| 命令 | 结果 |
|---|---|
| `moon test --target js src/engine` | **162/162 全绿** |

### 覆盖范围

`src/engine` 目录下全部测试文件：
- `dag_ext_test.mbt` — DAG 拓扑排序 / 传递闭包 / 关键路径 / 松弛分析
- `engine_circuit_wbtest.mbt` — 熔断器状态机
- `engine_dag_mc_wbtest.mbt` — Monte Carlo 完工预测
- `engine_doctor_closed_loop_test.mbt` — 医生闭环自检
- `engine_eval.mbt` — Evaluator-Optimizer
- `engine_saga.mbt` — Saga 补偿
- `engine_supervisor.mbt` — 超级管家工具
- `engine_triage.mbt` — 任务推荐
- `omega_strong_test.mbt` — Omega 强验证
- `engine.mbt` — 核心生命周期

### 验证意义

Unsafe 扫描发现的 3 处 `unwrap_or` 风险均位于 `engine_dag_ext.mbt`（DAG 核心运算）。本轮 162/162 全绿表明：
1. 当前代码路径下 `unwrap_or` 默认值**不会被异常输入触发**（拓扑排序 / 预算拆分 / BFS 传递闭包均按初始化不变量运行）
2. 扫描结论中"语义反转隐患"属于**未来重构风险**，而非当前 panic 风险
3. engine 核心 DAG 逻辑（Kahn 拓扑、关键路径、Monte Carlo、松弛分析）经得起回归

---

## 三、综合评估

| 项 | 状态 |
|---|---|
| Unsafe 裸调用 | ✅ 零命中 |
| Engine 回归 | ✅ 162/162 全绿 |
| 语义隐患（P1） | ⚠️ `budget_split_by_dag` L910 待修 |
| 不变量违背（P2） | ⚠️ `dag_topo_order` L360-363 待修 |

**结论**：验证轮 Round 1 通过。engine 核心逻辑在当前输入域下零 panic，Unsafe 扫描发现的 `unwrap_or` 风险为**防御性加固项**，不阻塞回归。建议下一轮按 P1→P2 顺序修复并追加对应白盒测试。

---

## 四、后续建议

1. **P1 修复**：`engine_dag_ext.mbt:910` 将 `unwrap_or(false)` 改为 `!= Some(true)` 明确区分"未登记"与"显式排除"
2. **P2 修复**：`engine_dag_ext.mbt:360-363` 将 `unwrap_or` 改为 `match` + `unreachable!` 或 `abort`，让 invariant 违背显式 crash
3. **白盒加固**：为修复后的逻辑追加 `engine_dag_ext_wbtest.mbt` 用例，覆盖"scope_ids 为空"与"漏初始化 id"分支
4. **合入主线**：修复完成后合入 `main`，进入下一验证轮
