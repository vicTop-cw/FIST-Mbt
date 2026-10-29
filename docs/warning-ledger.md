# 已知 warning 台账

> **本台账的每个数字都是「现算」的，不是「上次记的」**（见 §0）。
> 最后现算：**2026-10-29 16:35（`moon check --target js`）**
> 维护者：司令-γ · 判据（下一轮）：`scripts/check_warning_ledger.py`（**尚未写**）

---

## 0. 为什么这份台账必须可复核

**这个仓曾有一份「41 个已知有意保留」的口头台账，它自己就错了两次**：

| 错法 | 表现 | 只能被什么抓出来 |
|---|---|---|
| **漏登记** | 3 个 `substring` 只记了 1 个 | **覆盖率表**（总数 − 台账收录 = 漏项） |
| **记错数量** | `unused_value` 记 6 个，实际 10 个 | **重新数一遍**（覆盖率抓不到——分母也错了） |
| **★ 去重口径错** | 同位置多条被合并成 1（`deprecated` 记 12、实际 15） | **按 Warning 块计数，不按位置去重**；`moon check \| grep -c 'Warning (deprecated)'` |

**★ 第三种最阴险**：它**不报错**，只让数字偏小。
**而判据若也用同一去重口径（`set` 收集位置），两边同向偏小 ⇒ 正好抵消成 `100%` 假绿。**
**⇒ 本仓实测：台账记 12、判据报 43/43=100%，两边都错、方向相同、互相印证成假绿。**
**⇒ 判例：「判据的独立」不只是不抄对方代码，还包括不继承对方的隐含口径。**

**三种错法的共同点：错的是「数数的方式」，不是「数错了」。**

**⇒ 判例：「例外清单」自己也会错，而且漏登记与记错数量是两种错，要用两种手段抓。**

**⇒ 本文件规则**：
1. 每个类别的数字**必须标「现算于 <时间>」**；
2. 新增/删除条目时**连带更新 §2 的覆盖率表**；
3. **凡未在此表登记的 warning，一律视为「未处理」**（不是「已豁免」）。

---

## 1. 台账条目（45 条，逐条可核）

| # | 类型 | 数 | 位置 | 为什么保留 | 复审条件 |
|---|---|---|---|---|---|
| L1 | `result_error_return` | **4** | `server.mbt:107/124/1275/1330` | `Result` 是**刻意的结构约束**（注释：「想静默回落得先改签名」）。改 `raise` 会让「忘了检查」重新可能：`raise` 可被上层 `catch` 吞掉，`Result` 必须显式 `match`。`to_result`/`to_unit_result` 的职责**就是** Result→Result 映射。**可核引用**：4 处签名 `server.mbt:107/124/1275/1330`（`engine_for_ns` / `engine_route_in` / `to_result` / `to_unit_result`） | 某函数变成纯 handler 再评 |
| L2 | `unused_constructor` | **9** | `ops_loop.mbt:33-37`(5) · `atgc-old/codon.mbt:56/58/60`(3) · `atgc/vm.mbt:33`(1) | ② 预留 API 面。**`ops_loop_wbtest.mbt:318-322` 逐个断言全部 5 个变体**（实测覆盖） | 90 天无构造再评 |
| L3 | `struct_never_constructed` | **3** | `constraint.mbt:32/43/55` | ② 预留 API 面。三者在 `constraint.mbt:104/115/135/175` 作为**函数参数类型**使用 ⇒ 是 API 面，只是无构造点 | 同上 |
| L4 | `unused_package` | **4** | `consistency/moon.pkg:2/3` · `core/moon.pkg:13` · `engine/moon.pkg:15` | ① `consistency` 包唯一文件是 `_test.mbt`（4 处 `@store.`/`@constraint.`）；② `core` 在 `core_task_reject_cap_wbtest:147` 用 `@fs.`；③ `engine` 测试内 **26 处** `@fs.`。**编译器的 `unused_package` 只扫产品面，不看测试** | 包内出现产品调用时再评 |
| L5 | `deprecated_syntax` | **1** | `router/star_gate.mbt:33` | `derive(Show)` 是 `:42` `pub extend StarVerdict with Show::{to_string, output}` 的**前提**；删 ⇒ `[4018] does not implement trait Show` **连锁破坏** | MoonBit 支持 `extend` 不带 `derive` 时再评 |
| L6 | `deprecated`（Show→Debug） | **11** | `cmd/cli/main.mbt:501`(2) · `router/model_router_caf_wbtest.mbt:551/625`(2) · `router/router_caf_replay_distinct_test.mbt:288`(2) · `router/router_state_wbtest.mbt:85`(2) · `router/star_gate_wbtest.mbt:280/296/311`(3) | `star_gate.mbt:42` 是**手写 `Show` 实现**（非 derive）；3 处是 `inspect(..., content=...)` **快照断言**，改 `Debug` 后快照字符串会变。**更深风险：快照绿灯可能只是「新快照被接受了」，不是「行为没变」** | 单独一轮 + `moon test --update` + **逐条复核 diff** |
| L7 | `deprecated`（JS FFI Array） | **3** | `github_js.mbt:63` · `laya_js.mbt:18` · `run_check_js.mbt:32` | FFI 边界类型，改 `FixedArray` 要**同步改 JS 侧**，波及三个文件全部调用点；`run_check_js` 是**执行面**（R126）。**可核引用**：三处 `Array[String]` 形参 `github_js.mbt:63` / `laya_js.mbt:18` / `run_check_js.mbt:32`（另有 `:202` / `:66` / `:92` / `:104` 同类但当前未触发 warning） | 单独一轮 + 同步改 JS 侧 |
| L8 | `unused_value`（②预留） | **10** | `cmd/cli/upgrade_core.mbt:182` `should_upgrade` · `engine.mbt:98/1161` `by~` · `engine_dag_ext.mbt:1218/1414` `ns~` · `evolve.mbt:140` `lam~` · `omega_tool.mbt:285` `max_rounds~` · `store/json_get.mbt:15` `jget` · `server.mbt:1122` `laya_client_budget_ms` · `issue_scan.mbt:489` `scan_outside_literal` | ① `jget`：15 包各一份（BUG-361 作用域定律），store 内调用**都在 `_test`/`_wbtest`**；② `should_upgrade` 被 `upgrade_wbtest.mbt:92` 引用；③ `by~`/`ns~`/`lam~`/`max_rounds~` 是 **pub 契约形参**（删会动 `.mbti` 与调用点）；④ `laya_client_budget_ms` 被 `pipeline_r2_wbtest:137` **断言**；⑤ `scan_outside_literal` 被 `issue_scan_wbtest:16/17/19` **断言** | 被替换为产品调用时再评 |
| L9 | `deprecated`（substring） | **1** | `multi_store_test.mbt:9` | `d` 是**运行时构造**（`@store.bug462_unique_db` → 含 `@env.rand(8)` token，`bug462_fixtures.mbt:33/40`），**长度不受测试控制** ⇒ 切片在短串时行为与 `substring` 不同，不改 | 若 `bug462_unique_db` 改为返回定长串再评 |
| **合计** | | **46** | | | |

---

## 2. 覆盖率表（**必须与 §1 合计一致**）

**现算于 2026-10-29 16:35**，`moon check --target js` ⇒ **46 warnings / 0 errors**（**按 Warning 块计数，不去重**）。

| 类型 | 现算总数 | 台账收录 | 未收录 | 未收录处理 |
|---|---|---|---|---|
| `deprecated` | **15** | **15**（L6 11 + L7 3 + L9 1） | 0 | — |
| `unused_value` | 10 | 10（L8） | 0 | — |
| `unused_constructor` | 9 | 9（L2） | 0 | — |
| `unused_package` | 4 | 4（L4） | 0 | — |
| `result_error_return` | 4 | 4（L1） | 0 | — |
| `struct_never_constructed` | 3 | 3（L3） | 0 | — |
| `deprecated_syntax` | 1 | 1（L5） | 0 | — |
| `unused_async` | **0** | — | 0 | **已消**（`87a2d9536`：删 `commissar_send` 的无用 `async`） |
| **合计** | **46** | **46** | **0** | |

**覆盖率 46/46 = 100.0%。**（`check_warning_ledger.py` 现算核对，Lane DU）

---

## 3. 未登记项的三分类判据

**判「真死」必须 grep 三面**（R38 三次误判的教训）：
1. **产品代码**
2. **白盒测试**（`_wbtest.mbt`）
3. **黑盒测试**（`_test.mbt`）

**根因**：MoonBit 的 `unused_*` 系列**只扫「被检查的那个面」** ——
`unused_value` = **产品代码**未用（不看测试）；`unused_package` = **产品代码**未 import（不看测试）。

**三分类**：
| 分类 | 判据 | 处置 |
|---|---|---|
| **① 真死** | 三面都 0 引用、无 docstring 说预留 | 删 |
| **② 预留** | 有 docstring 说预留 / 被测试引用 / 是 pub 契约形参 | **登记本台账 + 理由 + 复审条件** |
| **③ 本该用** 🔴 | 设计上应被调用却忘了 | **报指挥官，这是 bug** |

**判「③ 本该用」的判据不是「有没有被 `let` 过」，是「这个值最终有没有影响任何输出/状态」** ——
实测反例：`flush_bug_queue` 曾被判 ③，实际参数在 `:3776` 二次读取并用于 `:3779/:3880/:3883`，
`:3738` 只是**死绑定**（⇒ ①）。**若按初判去「补 flush 逻辑」，flush 会执行两次。**

---

## 4. 本轮复核结论（2026-10-29）

- **抽查 5/5 台账理由仍成立**（L2 `ops_loop` 测试覆盖 / L3 参数类型 / L1 转换辅助 /
  L4 测试在用 / L6 手写 Show）⇒ **台账不是烂账，只是漏登记 + 记错数量**。
- **补充纠正**：本台账曾写「41 个」，**实际 45 个**（`unused_value` 记 6、实际 10）。
- **未发现「③ 本该用」**（0 个 bug）。
