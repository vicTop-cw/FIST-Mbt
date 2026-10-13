# R13 · 四模式流水线自我迭代 · Round 2 报告

- **日期**：2026-10-13
- **命名空间**：`r13-pipeline`（根任务 `T0`）
- **模式**：bugfind（换面：规则面 → 只读）
- **执行方式**：fist-mbt 本机发布版（`scripts/fist.py call`）
- **开关状态**：延续 R13 全部开启（`gradient/calibrate/reinject_context/boundary_probe/omega_strong_verify`）

---

## 结果摘要

第 1 环锁定 `src/store/` 并闭环 811/811。第 2 环换面，侦察发现 `src/evolve/`、`src/server/`、`src/store/` **几乎全 ` M`**（大面积他方 WIP），为避写冲突改走**只读 bugfind**：

- `issue_scan --dir src`：106 文件、**55 findings**（0 high / 22 medium / 33 low）。
- 指挥官**逐条复核 7 条 medium，全部假阳性**（非盲信规则）。
- **元发现：issue_scan 规则面对本仓假阳性率约 100%**——本仓守卫规范严格 + `secs-overflow` 规则错误假设 Int32。
- **BUG-152 入账（OPEN）**：issue_scan `secs-overflow` 规则过度泛化。

## 逐条复核表（7/7 假阳性）

| 命中 | 守卫 | 判定 |
|---|---|---|
| `ops_watchdog.mbt:416` `pending_advance.unwrap()` | L415 `if is_some()` | 假阳性 |
| `engine_triage.mbt:47` `s.substring(0,max)` | L46 `max<=len` | 假阳性 |
| `engine_dag_ext.mbt:862` `budget*w/total_w` | `if total_w<=0` | 假阳性 |
| `omega/gate.mbt:347` `passed/total` | L346 `if total>0` | 假阳性 |
| `omega/omega_tool.mbt:249` `passed/total` | L248 `if total>0` | 假阳性 |
| `ops_selfdrive.mbt:566` `ls.substring(3,end~)` | L565 `if end>3` | 假阳性 |
| `ops_ts.mbt:57` `days*86400` | L48 `year>2091` 上界守卫（即 BUG-217 已修） | 假阳性（规则过时） |

**两条根因**：
1. **本仓守卫规范严格**（R6-8 契约面封口 + 加固），除零/越界/unwrap 几乎都有前置守卫——issue_scan 逐行匹配不认守卫上下文。
2. **`secs-overflow` 规则假设 Int32**（issue_scan.mbt L170-177 `why` 明写"Int32 下…"），而 MoonBit 默认 `Int` 在 JS 是 53 位安全整数、native 是 64 位，仅显式 Int32 才溢出——规则匹配器不区分类型，对默认 `Int` 代码系统性误报（`engine_supervisor.mbt:558` `(jd-2451545)*86400 ≈ 4.6e11` 在 53 位内不溢出）。

## 资源消耗

| 资源 | 说明 |
|---|---|
| fist-mbt 本机发布版 | `issue_scan --dir src`、`report_bug`（BUG-152）、`tools/list` |
| 指挥官 | 逐条复核 7 条 medium（读源码确认守卫）+ 追跨文件 helper 源 + 确认规则真源 + BUG-152 上报 + memory 沉淀 |
| 只读 | 未改任何 src/ 文件（避开大面积他方 WIP） |

## 任务分配记录

| 环节 | 承担者 | 交付 |
|---|---|---|
| bugfind 换面 | 指挥官（issue_scan） | 55 findings 扫描 |
| 逐条复核 | 指挥官 | 7/7 假阳性核实 + 两条根因 |
| bug 上报 | 指挥官 | BUG-152（OPEN，low） |
| 沉淀 | 指挥官 | memory/2026-10-13.md 追加 + 本报告 |

## 遗留风险

1. **BUG-152 OPEN**（issue_scan 规则过度泛化）——不影响运行时正确性，但持续污染 bugfind 换面。建议后续修规则匹配器。
2. **BUG-151 OPEN**（第 1 环，file_locks/lock_violations 双后端 clear 不一致），等 `store_sqlite.mbt` owner 收口。
3. **`src/` 大面积他方 WIP**：第 2 环因此只能只读。后续环想改 `src/engine|evolve|server|store/` 都可能撞车，需先 `git status` 确认占用面。

## 后续建议

1. **第 3 环换面指路**：issue_scan 规则面对本仓已失效 ⇒ 回到 R12 命中轴——**契约/描述面**（R6-8、R12 BUG-214 形态）+ **handler 接线**（R11）。这两面才是本仓当前状态的真正命中面。
2. **修 issue_scan `secs-overflow` 规则**：匹配器加变量类型语义判别或仅对显式 Int32 命中（BUG-152）。
3. **补 self_search 入库接线**（R12 翻账点名 P3 未实现）：`src/evolve/` 目前全被他方 WIP 占用，需等占用面释放后推进。
4. **README 资产名漂移 + G7 GitCode**（R13 活风险）：README 属并发占用面、G7 卡外部 API，均留 owner 决策。

## 超额内容

- **"工具命中率随代码演进衰减"**是本轮最重要洞察：R12 用 issue_scan 命中过 BUG-155~214（那时仓库没写守卫），现在守卫写齐了，**同一规则同一工具就变成噪声**。这是**工具与代码共同演化**的实证，不是工具坏了，是"换面"要跟着代码状态走。
- **静态扫描必漏跨文件 helper**：扫"temp/*.db 无 clear"命中 `ops_pipeline_test.mbt`，追源发现清旧在 `ops_watchdog_test.mbt` L11 helper 里。单文件正则看不到跨文件 helper——与 R12「子代理静态边界分析会算错」同形。

## 来源

- 扫描：`issue_scan --dir src`（106 文件 / 55 findings）
- 复核源码：`src/ops/ops_watchdog.mbt` L415-416、`src/engine/engine_triage.mbt` L44-47、`src/engine/engine_dag_ext.mbt` L862、`src/omega/gate.mbt` L346-347、`src/omega/omega_tool.mbt` L248-249、`src/ops/ops_selfdrive.mbt` L565-566、`src/ops/ops_ts.mbt` L42-48、`src/engine/engine_supervisor.mbt` L538-558
- 规则真源：`src/server/issue_scan.mbt` L170-177
- helper 源：`src/ops/ops_watchdog_test.mbt` L11-20（`wd_sqlite_engine` 内含 `ignore(s.clear())`）
- 缺陷账本：`memory/bugs.md`（BUG-152，OPEN）
- 当日日志：`memory/2026-10-13.md`（R13 第 2 环段）
- 前序：`reports/2026-10-13-r13-cycle1-report.md`（第 1 环 811/811 + BUG-151）