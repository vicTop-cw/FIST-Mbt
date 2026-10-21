# Marvis Unsafe 扫描报告 — engine_dag_ext / issue_scan / issue_scan_wbtest

**扫描日期**：2026-10-17  
**扫描范围**：`src/engine/engine_dag_ext.mbt`、`src/server/issue_scan.mbt`、`src/server/issue_scan_wbtest.mbt`  
**方法**：全文件逐行读取 + 精确正则搜索（区分裸调用 / `unwrap_or` / 字符串字面量 / 注释）  
**结论先行**：三文件**均无裸 `.unwrap()` / `unsafe_get()` / `.expect()` 运行时调用**；风险甄别聚焦 `unwrap_or` 默认值误用（共 3 处中高风险）。

---

## 一、前提修正

| 用户前提 | 实测 |
|---|---|
| "unsafe_get/unwrap/expect 调用最密集" | `engine_dag_ext.mbt` 有 32 处 `unwrap_or()` 调用，**0 处裸 `.unwrap()`**；`issue_scan.mbt` 与 `issue_scan_wbtest.mbt` 的 `unwrap`/`unsafe_get` 全部是**字符串字面量**（规则 pattern、doc 注释、测试夹具），不产生运行时调用 |
| `.expect()` 存在 | **全项目 0 处**（`grep \.expect\( → No matches`） |

---

## 二、风险甄别（`unwrap_or` 默认值误用 Top 3）

| # | 文件:行号 | 调用链 | 风险 | 修复建议 |
|---|---|---|---|---|
| 1 | `engine_dag_ext.mbt:360-363` | `dag_topo_order` → Kahn 拓扑排序内循环：`deps_of.get(cur).unwrap_or([])` → `indeg.get(nxt).unwrap_or(0)` → `if indeg.get(nxt).unwrap_or(0) == 0 { … }` | **中** | 循环内 `deps_of` / `indeg` 已在 L334-337 对全部 `ids` 显式 `.set(id, [])` / `.set(id, 0)` 初始化，所以 `unwrap_or` 默认值理论上不会命中；但若后续重构有 id 漏初始化（如 `deps_of.set(d, …)` 的 `d` 不在 `ids` 中），`unwrap_or([])` 会**静默跳过**该后继，导致拓扑序不完整、`cycle` 误判。建议：将 `unwrap_or` 改为 `unwrap_or_else(|| { abort("Kahn: 未初始化的后继 " + cur) })` 或 `match .get(cur) { Some(v) => v  None => unreachable!("Kahn invariant broken") }`，让 invariant 违背显式 crash 而非静默吞掉。 |
| 2 | `engine_dag_ext.mbt:910` | `budget_split_by_dag` → `if not(in_scope.get(t.get_id()).unwrap_or(false)) { continue }` | **高** | `in_scope` 仅对 `scope_ids` 显式 `.set(id, true)`（L906-908），`scope_ids` 之外的任务 `in_scope.get()` 返回 `None` → `unwrap_or(false)` → `not(false)=true` → `continue` 跳过——**语义正确**。但若 `scope_ids` 为空（L969 分支），`in_scope` 仍空，所有任务被 `not(unwrap_or(false))=true` 跳过，返回 `verdict="insufficient"`（已在 L969-981 兜底）。风险在于：若未来有人在 L909 之前给 `in_scope` 追加了 `false` 条目，`unwrap_or(false)` 会**误判成 false→continue 跳过**，逻辑静默反转。建议改为 `if in_scope.get(t.get_id()) != Some(true) { continue }`，明确区分"未登记(false)"与"显式排除(false)"。 |
| 3 | `engine_dag_ext.mbt:260-270` | `dag_reaches` → BFS 传递环检测：`visited.get(cur).unwrap_or(false)` / `visited.get(d).unwrap_or(false)` | **低** | `visited` 纯由本函数 `visited.set(cur, true)` 写入，无外部污染；BFS 循环中 `visited.get(cur)` 在第一次迭代时返回 `None` → `unwrap_or(false)` → `continue` 跳过——**语义正确且安全**。唯一理论风险：`cur` 被并发修改（多线程场景），但 MoonBit 单线程模型下不成立。建议保留现状，可加一行注释说明不变量。 |

---

## 三、`issue_scan.mbt` 与 `issue_scan_wbtest.mbt` — 零运行时风险

| 文件 | `unwrap` 出现次数 | 性质 |
|---|---|---|
| `issue_scan.mbt` | 7 处 | 5 处为**规则 pattern 字符串**（`".unwrap()"`、`"unsafe_get"`），2 处为 **doc 注释散文**（L358、L873-874）。**无运行时调用**。 |
| `issue_scan_wbtest.mbt` | 14 处 | 全部位于 `assert_eq(scan_unwrap_receiver("….unwrap()"), "…")` / `assert_true(scan_outside_literal(…, ".unwrap()"))` 的**字符串夹具**中，用作被测函数的输入。**无运行时 `.unwrap()` 调用**。 |

> 这两份文件是"扫描器+测试"：它们的职责是**检测别人的** `.unwrap()`，自身被 `scan_is_rules_table`（L1215-1221）排除在扫描范围之外。代码实现全部基于 `match` / `find` / `contains`，**无 panic 路径**。

---

## 四、`unwrap_or` 之外：`engine_dag_ext.mbt` 的潜在 panic 向量（补充）

虽不在"unwrap/unsafe_get/expect" 范围内，但以下模式在 DAG 运算中因空值导致运行时 panic 的概率高于 `unwrap_or`：

| 文件:行号 | 模式 | 风险 |
|---|---|---|
| `engine_dag_ext.mbt:899` | `code.substring(start~, end=idx)`（`scan_unwrap_receiver` 中的 `String` 操作，实际在 `issue_scan.mbt`） | 若 `idx = 0`（`code` 以 `.unwrap(` 开头），`start~` 从 0 开始 → `end=0` → 空字符串返回（MoonBit 不 panic），但 `scan_unwrap_receiver` L880-881 已用 `idx == 0` 提前返回 `""`。安全。 |
| `engine_dag_ext.mbt:196` | `dag_ascii` → `self.store.list_tasks_in(target)` | 若 `target` 命名空间不存在，`list_tasks_in` 行为由 store 决定（SQLite 返回空数组、内存版返回空数组）→ `tasks` 空 → 返回 `""`。**不 panic**，但需注意 store 实现是否在 ns 不存在时返回 `None` 而非空数组。 |

---

## 五、结论

1. **无裸 `.unwrap()` / `unsafe_get()` / `.expect()` 调用**——三文件在"裸调用"维度零风险。
2. **32 处 `unwrap_or()` 构成主要风险面**：#2（`budget_split_by_dag` L910）语义反转隐患最值得修，#1（`dag_topo_order` L360-363）次之。
3. `issue_scan.mbt` / `issue_scan_wbtest.mbt` 作为扫描器+测试，自身代码无 panic 路径，`unwrap` 仅作为字符串输入出现。
4. 用户前提"unsafe_get/unwrap/expect 最密集"需修正——实际最密集的是 `unwrap_or`（安全变体），而非裸调用。

> **建议优先级**：P1 → #2（L910），P2 → #1（L360-363），P3 → 加注释说明 #3 的不变量。issue_scan 两份文件无需改动。
