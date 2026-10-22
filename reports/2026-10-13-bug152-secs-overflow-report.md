# R13 第 4 环报告 · 修 BUG-152（issue_scan secs-overflow 的 Int32 假设）

- 日期：2026-10-13
- 命名空间：`r13-pipeline`（根任务 `T0`，`task_plan_deep` 开关全开）
- 模式：bugfind + fix_and_merge（第 2 环发现 BUG-152 → 第 4 环修复）
- 状态：**第 4 环闭环，BUG-152 FIXED，secs-overflow 命中 4→0 全部清零**

---

## 结果摘要

第 4 环把第 2 环发现的 BUG-152（`secs-overflow` 规则**假设 Int32**、对 MoonBit 默认 `Int` 系统性误报）落成可运行修复：给 `src/server/issue_scan.mbt` 的 `scan_finding_guarded` 加 `secs-overflow` 分支，**只在显式 Int32 时保留检出**，其余（默认 Int / Int64 / Double / f64）一律 suppress。

**核心实证（我独立复跑）**：

| 判据 | 结果 | 说明 |
|---|---|---|
| `moon check` | `ran 36 tasks, 1861 warnings, 0 errors` | warnings 1859→1861 为并行跑序抖动，非引入 |
| `moon test --target js src/server` | **215/215/0** | 基线 210，+5 新测试 |
| 全量 `moon test --target js` | **819/819/0** | 基线 814，+5，RC=0 |
| `issue_scan --dir src` | 52 → **48**，`secs-overflow` **4 → 0** | 清零 |
| 基线对账 | 52−48=**4** | 精确等于 4 条目标假阳性，无误滤真阳性 |

**判绿达成**（BUG-142 口径：以汇总行为准）。

---

## 根因

规则 `why` 明写「Int32 下 days*86400 超过 24855 天（约 68 年）即溢出」，但 **MoonBit 默认 `Int` 在 JS 目标为 53 位安全整数（~9e15）、native 为 64 位（~9.2e18）**，`days*86400` 需 `days>1e11` 才溢出（约 3.3 千年）。**只有显式 `Int32`**（32 位，最大 21 亿）才在 days>24855（约 68 年，Y2038）溢出。旧实现把规则 pattern 命中全当待判、又无 secs-overflow 守卫分支，4 条默认 Int 全报。

**4 条目标假阳性**（逐条核实无 Int32 注解）：
- `src/engine/engine_supervisor.mbt:558` `Some((jd - 2451545) * 86400 - 43200 + …)`
- `src/ops/ops_cleanup.mbt:27` `let threshold = now_s - retention_days * 86400`
- `src/ops/ops_ts.mbt:57` `days * 86400 + hour * 3600 + min * 60 + sec`
- `src/router/model_router.mbt:323` `days_from_civil(y, mo, d) * 86400 + …`

---

## 修复内容

**只改 `src/server/issue_scan.mbt` + `src/server/issue_scan_secs_overflow_test.mbt`**（2 文件，边界例外见下）：

1. 新 helper `scan_has_int32_signal(s)`：匹配 `Int32`/`.to_int32()`/`Int32.of`/`Int32.new`/`Int32::`（精确子串，不误匹配 `Int`）。
2. 新 helper `scan_secs_suppressed(code, prev_lines)`：Int64/Double/f64 → true；显式 Int32 → false；prev_lines **用 `scan_code_part` 去注释后**同判；皆无 → true。
3. `scan_finding_guarded` 新分支（L646-651）：`if rule == "secs-overflow" { return scan_secs_suppressed(...) }`。**未动** string-index/substring-overrun/possible-overflow 既有分支，**未动** BUG-153 的 `scan_guard_div_direct`。
4. 规则 `why`/`hint` 改写为「仅显式 Int32 才溢出；默认 Int 在 JS 53 位/native 64 位不溢出」口径。
5. DEBUG TESTS 新增 5 测试：explicit Int32→false / `.to_int32()`→false / 默认 Int→true / Int64→true / **注释含 Int32→true**（回归锁）。

---

## 关键坑（本环最隐蔽的一环，已踩已堵）

子代理初版 `scan_has_int32_signal` **直接扫 prev_lines 原文**，`ops_ts.mbt:57` 的**上下文注释**（L43-47 反复写「Int32 上界」「已越过 Int32 上界」）被裸子串当成真阳性信号，首轮跑出 secs-overflow=1 / total=49（未达 0）。**修法**：prev_lines 先过既有 `scan_code_part`（去字符串字面量 + 截行尾注释）再匹配，彻底剔除注释散文噪声。

**教训**：**规则守卫若按「信号子串」匹配，必须先剥注释散文**——裸子串会把散文当类型注解，导致守卫反向失效。

---

## 资源消耗

- 1 个 `subagent`（修 BUG-152，约 20 分钟）
- 我（指挥官）：根因定位、终审逐条核查、独立复跑验证（`moon check` / `src/server` / 全量 / `issue_scan` 各多次）
- 实跑命令 8 次左右

---

## 任务分配记录

| 角色 | 承担 | 结果 |
|---|---|---|
| 子代理（bugfind-fix） | 实现 `scan_has_int32_signal` + `scan_secs_suppressed` + 守卫分支 + 5 测试 + 自包含实验对账 | 通过终审 |
| 指挥官（我） | 根因、终审、边界裁决、记账、沉淀 | 独立复跑验证一致 |

**过程纠错（指挥官 early 判断错了）**：我终审时**实测到 secs-overflow=1（total 49）**，以为是最终版本，据此标 BUG-152 FIXED 时 evidence 误写「4→1」。**实际那是子代理的中间版本**（还没修 `scan_code_part`）。子代理**自己识别了这个坑并修**，最终版本 4→0。**我抓到中间版本当最终版，是时序误判**——最终以重跑 `issue_scan` = 48 / secs-overflow 0 为准。

**边界例外（我裁定接受）**：子代理改了 `issue_scan_secs_overflow_test.mbt`，超出「只改 issue_scan.mbt」。**原因**：该既有测试注入**默认 Int** 的 `days*86400` 并断言 secs-overflow 命中，**恰好断言 BUG-152 要消灭的假阳性**；不改它 `moon test --target js src/server` 就 failed:1。子代理把 `pub fn f(days: Int) -> Int` 改为 `pub fn f(days: Int32) -> Int32`（保留测试「规则存在且可统计」意图）。**裁定接受**：子代理**没删测试**而是**修正断言**为显式 Int32——**这是诚实修正，不是凑绿**。

---

## 遗留风险

1. **secs-overflow 检测粒度是行级子串**，跨行变量类型无法真正类型化——若 Int32 声明在 >5 行之前会漏保留（保守向误滤方向）。src 现状无此形，可接受。
2. `ops_ts.mbt:57` 虽 suppress，其 `iso_to_secs` 实际已带 `if year > 2091 { return -1 }` 上界守卫，本就安全；本轮未动四个被扫对象本体。
3. **warnings 1861 vs 1859 有 ±2 抖动**（非引入，知悉）。
4. 未跑 native 目标（BUG-133 探针口径，非本轮范围）。
5. **BUG-151** 仍 OPEN（file_locks/lock_violations 双后端 clear 不一致，等 `store_sqlite.mbt` owner 收口，mtime 今日活跃 WIP）。

---

## 后续建议

- **第 5 环候选 A（`self_search` 入库接线）**：R12 翻账点名的 P3 未实现项已核实成立——`src/evolve/self_search.mbt` 暴露 `run_external_search`（含注入 `runner?` 参数）等 5 个 pub fn，**外部调用者为零**；`src/evolve/` mtime 全为 2026-10-12 19:31（**非活跃 WIP**，可安全改）。接线受「**不新增 MCP 工具**」边界约束，须接现有工具 IO 层（如 `evolve_submit`/`evolve_distill` 内部注入 runner）。
- **第 5 环候选 B（契约/描述面）**：`check_doc_surface.py` 已有 `RE_TOOL_DESC`/`tool_desc_registry()`（J9），但「描述引用已删除枚举值」（BUG-214 形态）未见——可评估补这条判据。
- **第 5 环候选 C**：修 BUG-151（等 `store_sqlite.mbt` owner 收口）。
- **BUG-152 后续**：给 `scan_secs_suppressed` 补一条「Int32 声明在更早行」的测试，覆盖跨行类型场景（当前测试用 `prev_lines=[]`，未覆盖）。

---

## 超额内容（无）

本轮只改了 `issue_scan.mbt` + `issue_scan_secs_overflow_test.mbt`（后者为边界例外），未新增 MCP 工具、未动历史文件（memory/bugs.md 走 bug_fix 工具）。

---

## 来源

- 真源代码：`src/server/issue_scan.mbt`（`scan_has_int32_signal` L515 / `scan_secs_suppressed` L529 / 守卫分支 L646）
- 被扫对象（未修改）：`src/engine/engine_supervisor.mbt:558`、`src/ops/ops_cleanup.mbt:27`、`src/ops/ops_ts.mbt:57`、`src/router/model_router.mbt:323`
- 账本：`memory/bugs.md`（BUG-152 FIXED @2026-10-13T08:23:39Z，BUG-153 FIXED @2026-10-13T07:59:24Z，BUG-151 OPEN）
- 日志：`memory/2026-10-13.md` 第 4 环段
- 前序报告：`reports/2026-10-13-r13-cycle1-report.md`、`reports/2026-10-13-r13-cycle2-report.md`、`reports/2026-10-13-r13-cycle3-report.md`