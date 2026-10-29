# warning 收口（BUG-478 · Lane DO）

> 司令-γ · 2026-10-29
> **本单最重要的产出不是「消了几个 warning」，而是「发现判据的三次系统性误判」。**

---

## ① 分类纠正记录（三次误判同一盲区）

`unused_value` 14 个里，我**错了三次**，全部是同一个根因：

| # | 符号 | 初判 | 改判 | 依据 |
|---|---|---|---|---|
| 1 | `server.mbt:3738` `flush_bug_queue` | **③ 本该用**（静默丢弃调用方参数，BUG-472 同族） | **① 真死**（`let` 死绑定） | 参数在 `:3776` **被第二次读取**并用于 `:3779` / `:3880` / `:3883`；`:3738` 赋值后从未被读 |
| 2 | `server.mbt:1122` `laya_client_budget_ms` | **① 真死** | **② 预留** | 被 `pipeline_r2_wbtest.mbt:137` **断言** |
| 3 | `issue_scan.mbt:489` `scan_outside_literal` | **① 真死** | **② 预留** | 被 `issue_scan_wbtest.mbt:16/17/19` **断言** |

### 🔴 三次误判的**同一个根因**

**MoonBit 的 `unused_*` 系列只扫「被检查的那个面」。**

- `unused_value` 报 = **产品代码**未用（**不看测试**）
- `unused_package` 报 = **产品代码**未 import（**不看测试**）

**⇒ 只看编译器给的那一个面，会把「只被测试用」误判成「真死」。**

**⇒ 硬要求**：判「真死」必须 grep **三个面**：
1. 产品代码
2. 白盒测试（`_wbtest.mbt`）
3. 黑盒测试（`_test.mbt`）

**⚠️ 多一层教训**：「同一参数被读两次」≠「第一次读了没用」——要看第二次有没有用。
判「③ 本该用」的判据应是「这个值最终有没有影响任何输出/状态」，不是「它有没有被 `let` 过」。
**若按初判去给 `:3738` 补 flush 逻辑 ⇒ flush 会执行两次。**

---

## ② 已知 warning 台账（27 个，**已知且有意保留**）

| 类型 | 数 | 位置 | 为什么保留 | 复审条件 |
|---|---|---|---|---|
| `result_error_return` | **4** | `server.mbt:109/128/1277/1332` | `Result` 是**刻意的结构约束**；改 `raise` 会让「忘了检查」重新可能（`raise` 可被 `catch` 吞，`Result` 必须 `match`）⇒ **倒退已修复的缺陷类型**。`to_result`/`to_unit_result` 职责**就是** Result→Result 映射 | 变成纯 handler 再评 |
| `unused_constructor` | **9** | `ops_loop.mbt:33-37`(5)·`atgc-old/codon.mbt:56/58/60`(3)·`atgc/vm.mbt:33`(1) | ②预留 API 面。`ops_loop.mbt:21` 注释：「无生产构造点（生产 0 / 测试 5）」 | 90 天无构造再评 |
| `struct_never_constructed` | **3** | `constraint.mbt:32/43/55` | ②预留 API 面（注释：生产消费 5/2/6）⇒ 删了引擎就没了 API 面 | 同上 |
| `unused_package` | **4** | `consistency/moon.pkg:2/3` · `core/moon.pkg:13` · `engine/moon.pkg:10` | ① `consistency` 包唯一文件是 `_test.mbt`，测试用 `@store.`/`@constraint.` **4 处**；② `core` 那份注释明写「生产代码不使用它，告警属预期」（BUG-427 接线格需要）；③ `engine` 产品 0 处、**测试 26 处** | 包内出现产品调用时再评 |
| `deprecated_syntax` | **1** | `router/star_gate.mbt:33` | `derive(Show)` 是 `:44` `pub extend StarVerdict with Show::{to_string, output}` 的**前提**；删 ⇒ `[4018] does not implement trait Show` **连锁破坏** | MoonBit 支持 `extend` 不带 `derive` 时再评 |
| `unused_value`（②预留） | **6** | `json_get.mbt:15` `jget` · `upgrade_core.mbt:182` `should_upgrade` · `engine.mbt:98/1161` `by~` · `engine_dag_ext.mbt:1218/1414` `ns~` · `evolve.mbt:140` `lam~` · `omega_tool.mbt:285` `max_rounds~` | ①`jget` 15 包各一份（BUG-361 作用域定律），store 内调用都在 `_test`/`_wbtest`；②`should_upgrade` 被 `upgrade_wbtest.mbt:92` 引用；③其余是 **pub 契约形参**（删会动 `.mbti` 与调用点），`lam~` docstring 明写「BUG-354 历史残留」 | — |
| **合计** | **27** | | | |

---

## ③ 本单做了什么

| 项 | 文件 | 结果 |
|---|---|---|
| **`action` 插值 bug 修复** | `engine_rsv.mbt` | 单花括号 `{action}` → `\{action}`，`action` 参数重新生效 |
| **S1b 新锁格** | `engine_bug476_strict_wbtest.mbt` | 断言 `msg.contains(act)` + **反脱锚**断言不残留字面量 `{action}`（可变异） |
| **`implicit_impl_as_method` 5 → 0** | `auth_mode.mbt` / `engine.mbt` | `AuthMode` / `DepsState` / `DepsReport` 各加 `pub extend ... with Eq::{not_equal, equal}` 与 `Debug::{to_repr}` |
| **`core_package_not_imported` 2 → 0** | `engine/moon.pkg` | 加 `"moonbitlang/core/env"` |
| **`unused_value` ①真死删 2 个** | `server_bug469_no_challenge_wbtest.mbt` / `ops/audit_test.mbt` | 删 `cw_count_code` 整函数；`let agent` → `let _agent` |

### 本单未做项
| 项 | 分类 | 状态 |
|---|---|---|
| `server.mbt:3738` `flush_bug_queue` | ①真死 | **不删**（并发在途），留待 BUG-480 收口 |
| `server.mbt:230` `AclIdentity`→`priv` | `missing_priv` | **已改未提交**（同文件） |

---

## ④ 缺口与风险

- **R1** 上表两项在 `server.mbt`，**未提交** —— 该文件 72 行 diff 中 71 行是 Lane DN 的 BUG-480 改动。
- **R2** 本单**未跑全量 `moon test`** —— 全仓恒有 Beta WIP 的编译错误
  （`server.mbt:10664/10665` `.to_int()`），出不了汇总行。已跑的是**各包 `moon check` = 0 errors**。
- **R3** `deprecated` 25 个**未动** —— `substring` → 切片涉及**边界语义**（负数/越界），多在测试文件里属纯噪音。**建议单独一轮。**
- **R4** `unused_async` 1（`server.mbt:10580`）未动 —— 同在 `server.mbt`。

---

## ⑤ 建议入档位置

- 本报告：`reports/2026-10-29-warning-final-report.md`
- **判例**（建议）：**「编译器只懂语法形态，不懂设计意图」** ——
  `result_error_return` / `deprecated_syntax` / `unused_package` 三类都是**警告建议会倒退**：
  前者会让「忘了检查」重新可能，后者会连锁破坏 `Show` trait 实现。
- **判例**（建议）：**「`unused_*` 只扫一个面」** —— 判「真死」须 grep 产品+白盒+黑盒三面。
