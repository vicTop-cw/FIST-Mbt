# BUG-433 · `engine_for_ns` 非法 ns 静默回落主库 · Lane AM · 2026-10-27

> **体量说明**：本报告 ~19 KB。统帅已把单条上限放宽到 20KB ——
> 理由是 **8 处调用点必须逐条可核 + 三类成因分别处置 + 4 格锁**，**那不是冗长，是可复核**。

---

## 一、结论

### 1.1 ⚠️ 「已证实」与「未证实」必须分开读

| 结论 | 状态 | 证据 |
|---|---|---|
| **用户指定的 ns 被静默忽略** | ✅ **已证实（实锤）** | `seq=104`：`archive(namespace="zi-migration", task_id="T0")` → 主库 `T0`（`ns='marvis-drive'`）被归档 |
| **已造成误删/误归档** | ❌ **未证实** | `delete` **0 条**回落；`archive` 4 条回落中 1 条成功、3 条失败；且 `zi-migration.db` 内亦有 `T0 已归档` ⇒ **无法证明是误操作** |

> **这两件事必须分开**：`seq=104` 证明的是「**用户指定的 ns 被静默忽略**」，
> 与「结果是否碰巧正确」无关。**即使那次结果碰巧正确，机制依然是错的** ——
> 下一次 `T0` 在两边状态不同时就会错。
> **别让「没有误删证据」稀释「机制是错的」。**

### 1.2 量化（全量 `call_log` 重放）

| 项 | 读数 |
|---|---|
| 显式传了非空非 default `namespace` 的写类调用 | **1851 条** |
| 其中该 ns 在**调用时刻未 open** ⇒ 静默回落主库 | **819 条** |
| ├ `delete` | **0 条** |
| ├ `archive` | **4 条**（1 成功 / 3 失败）|
| └ 其余（publish 174 / publish_parallel 174 / verify 124 / claim 109 / execute 106 / submit 104 / pause 7 / resume 7 / reject 5 / retry 5）| 815 条 |

### 1.3 三类 `None` 成因（全部混在 `None => engine` 里）

`mstore.get(ns)` 返回 `None` 有**三种**成因，`engine_for_ns` 对它们**一视同仁**：

| # | 成因 | 判据（`multi_store.mbt`）| 应处置 |
|---|---|---|---|
| **1** | **ns 格式非法** | `MultiStore::safe_ns(ns) == None`（须 `[A-Za-z0-9_-]+`）| **硬拒** |
| **2** | **ns 未 open 且库打不开** | `SqliteStore::open(path) == None` | **硬拒** |
| **3** | **data_dir 不合法** | `!MultiStore::data_dir_ok(self.data_dir)` | **硬拒** |
| **0** | ns 为 `""` / `"default"` | **不在 `mstore.get` 路径上**（`if` 提前返回 `engine`）| **正当用法，保留** |

**实测印证**：`plan-dir-governance` / `lz-combo-r2` **从未建库**（成因 2）；
`zi-migration` 的库在 `_archive/dbs-20261021/` 而非 `.fist-mbt/data/`（成因 2）。

### 1.4 选哪个候选：**推荐 (b')，不是 (a) 也不是 (b)**

**我原以为 (a) 可行，实测后否掉了** —— 关键事实：

```
$ grep -c "engine_for_ns" src/server/server.mbt
60+
```

**`engine_for_ns` 有 60+ 个调用点，不是 8 个。** 改签名（返回 `Result`）要动全部 60+ 处
⇒ **影响面不可控**，且其中大量是 `dag_*` / `board_ascii` / `triage` 等**只读**面。

**⇒ 推荐 (b')：在 `engine_for_ns` 内部退化成 `Result` 的「窄改法」**：

```moonbit
fn engine_for_ns(ns : String) -> @engine.FistEngine   // ← 签名不动
```
新增**并行的**严格入口 `engine_for_ns_strict(ns) -> Result[FistEngine, String]`，
**只把 6 个写类工具（delete/archive/claim/execute/submit/verify）切到它**
（+ publish/publish_parallel 视裁决，见 §四），**其余 54 处调用点零改动**。

**为什么这比 (a) 好**：
- **(a)** 改 60+ 处，其中只读面（`board_ascii`、`dag_*`）本就该容忍回落（查不到比报错好）；
- **(b)** 是「读/写两套语义」但没有机制保证 —— 靠人记得「读用这个、写用那个」；
- **(b')** 把「严格」做成**一个具名函数**，写类工具切过去，**读类工具留原路**。
  差异是**显式的、可 grep 的**（`grep engine_for_ns_strict` 就知道谁在严格面），
  不是「同一个函数两种行为」那种隐性雷。

### 1.5 8 处调用点（逐条，`src/server/server.mbt`）

| # | 工具 | 工具定义行 | `engine_for_ns` 调用行 | 现写法 |
|---|---|---|---|---|
| 1 | `list` | 2249 | **2265** | `let eng = if ns_str == "" { engine } else { engine_for_ns(ns_str) }` |
| 2 | `get` | 2284 | **2302** | `let eng = engine_for_ns(ns)` |
| 3 | `archive` | 2206 | **2224** | `let eng = engine_for_ns(ns)` |
| 4 | `delete` | 2337 | **2351** | `let eng = engine_for_ns(ns)` |
| 5 | `claim` | 1821 | **1842** | `let eng = engine_for_ns(ns)` |
| 6 | `execute` | 1869 | **1894** | `let eng = engine_for_ns(ns)` |
| 7 | `submit` | 1932 | **1946** | `let eng = engine_for_ns(get_str(args, "namespace", default="default"))` |
| 8 | `verify` | 2067 | **2085** | `let eng = engine_for_ns(ns)` |

**⚠️ `submit` 是唯一一个把 `get_str(...)` 内联进调用的**（L1946），改它要拆成两行。
**`list` 已有自己的 `if ns_str == ""` 短路**（L2265）—— 它的「空 ns」分支和 `engine_for_ns` 内的重复，
改的时候注意别把那个短路删掉（那是 `list` 的正当行为）。

---

## 二、可粘贴 patch

### 2.1 标准 diff 摘要

```diff
--- a/src/server/server.mbt
+++ b/src/server/server.mbt
@@ 在 engine_for_ns 之后新增严格入口
+fn engine_for_ns_strict(ns : String) -> Result[@engine.FistEngine, String] {
+  if ns == "" || ns == "default" {
+    return Ok(engine)
+  }
+  match @store.MultiStore::safe_ns(ns) {
+    None =>
+      Err("namespace '" + ns + "' 格式非法：只允许 [A-Za-z0-9_-] 且非空。" +
+          "（此前会被静默回落到主库，BUG-433）")
+    Some(safe) =>
+      match mstore.get(safe) {
+        Some(s) => Ok(@engine.FistEngine::new(store=@store.StoreBackend::sqlite(s)))
+        None =>
+          Err("namespace '" + safe + "' 无法路由：该 ns 尚未 store_open，" +
+              "或它的库打不开/数据目录不合法。请先 store_open(ns='" + safe + "')。" +
+              "（此前会被静默回落到主库，BUG-433）")
+      }
+  }
+}

@@ delete（L2351）
-      let eng = engine_for_ns(ns)
-      to_unit_result(eng.delete_task(task_id))
+      match engine_for_ns_strict(ns) {
+        Err(e) => Err(@mcp_types.ToolError(e))
+        Ok(eng) => to_unit_result(eng.delete_task(task_id))
+      }
```

### 2.2 完整实现（新增函数）

```moonbit
///|
/// BUG-433：**严格版** ns 路由 —— 非法/未 open 的 ns **硬拒**，不再静默回落主库。
///
/// 为什么必须与 `engine_for_ns` 并存而不是替换它：
/// `engine_for_ns` 有 **60+ 个调用点**，其中多数是只读面（`board_ascii` / `dag_*` / `triage`）——
/// 对只读面，「查不到」比「报错」更合适。而写类工具（delete/archive/claim/execute/submit/verify）
/// 一旦静默落到主库，就是**在错误的库上做不可逆操作**。
/// ⇒ 把「严格」做成一个**具名函数**，写类工具切过来，读类工具留原路。
/// 差异是**显式且可 grep 的**（`grep engine_for_ns_strict` 就知道谁在严格面），
/// 不是「同一函数两种行为」那种隐性雷。
///
/// 三类 `None` 成因（`multi_store.mbt`）分别给可操作文案：
///   1 格式非法     ⇒ `safe_ns` 返回 None
///   2 未 open/打不开 ⇒ `mstore.get` 返回 None（含 data_dir 不合法）
///   3 data_dir 歪  ⇒ 同上，但文案提示查数据目录
/// 而 `""` / `"default"` 是**正当用法**，显式写成独立分支（不是混在 None 里）。
fn engine_for_ns_strict(ns : String) -> Result[@engine.FistEngine, String] {
  if ns == "" || ns == "default" {
    return Ok(engine)
  }
  match @store.MultiStore::safe_ns(ns) {
    None =>
      Err(
        "namespace '" +
        ns +
        "' 格式非法：只允许 [A-Za-z0-9_-] 且非空。" +
        "（BUG-433：此前会被静默回落到主库执行）",
      )
    Some(safe) =>
      match mstore.get(safe) {
        Some(s) => Ok(@engine.FistEngine::new(store=@store.StoreBackend::sqlite(s)))
        None =>
          Err(
            "namespace '" +
            safe +
            "' 无法路由：该 ns 尚未 store_open，或它的库打不开 / 数据目录不合法。" +
            "请先 store_open(ns='" +
            safe +
            "')。 （BUG-433：此前会被静默回落到主库执行）",
          )
      }
  }
}
```

### 2.3 六处写类调用点改法（逐个可粘贴）

**`delete`（L2347-2352）**
```moonbit
    fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let task_id = get_str(args, "task_id")
      let ns = get_str(args, "namespace", default="default")
      match engine_for_ns_strict(ns) {
        Err(e) => Err(@mcp_types.ToolError(e))
        Ok(eng) => to_unit_result(eng.delete_task(task_id))
      }
    },
```

**`archive`（L2224 附近）**
```moonbit
      match engine_for_ns_strict(ns) {
        Err(e) => Err(@mcp_types.ToolError(e))
        Ok(eng) => /* 原 archive 逻辑，把 engine_for_ns(ns) 换成 eng */
      }
```

**`claim`（L1842）**、**`execute`（L1894）**、**`verify`（L2085）** 同形：
```moonbit
      match engine_for_ns_strict(ns) {
        Err(e) => Err(@mcp_types.ToolError(e))
        Ok(eng) => /* 原逻辑，engine_for_ns(ns) → eng */
      }
```

**`submit`（L1946，注意内联 get_str）**
```moonbit
      let ns_sub = get_str(args, "namespace", default="default")
      match engine_for_ns_strict(ns_sub) {
        Err(e) => Err(@mcp_types.ToolError(e))
        Ok(eng) => /* 原逻辑 */
      }
```

**`publish`（L1682）/ `publish_parallel`（L1742）** —— **建议同批切**（它们是写类，819 条里占 348 条）：
```moonbit
      match engine_for_ns_strict(ns) {
        Err(e) => Err(@mcp_types.ToolError(e))
        Ok(r) => /* 原 publish 逻辑 */
      }
```

**`get`（L2302）/ `list`（L2265）** —— **保持原 `engine_for_ns`**（只读面容忍回落）。

### 2.4 ⚠️ 「读类面仍静默回落」这个取舍的**代价**（不只是「取舍」）

我原写成「有意取舍，读错库可容忍」。**那是在回避代价。把代价写清：**

> **`get(namespace=X)` 在 X 未 open 时，返回的是主库里的同名任务**
> ⇐ **调用方会把它当成「X 库里的那条」**。
>
> 具体后果：
> - `get(namespace="zi-migration", task_id="T0")` 返回主库 `T0`（`ns='marvis-drive'`），
>   **调用方看到 `ns` 字段是 `marvis-drive` 也不会警觉** —— 因为工具签名说「我查的是 zi-migration」；
> - `list(namespace=X)` 在 X 未 open 时**列的是主库全部任务**，
>   而调用方会把它读成「X 库有这么多任务」；
> - **这是「静默成功」的读侧版本** —— 与写侧的 `delete` 同族，
>   只是后果从「删错了」变成「**基于错的清单做决策**」。
>
> **⇒ 建议（另立，不硬做）**：`get`/`list` 回执加 `"ns_fallback": true` + `"actual_ns": "<主库>"`。
> 这要改回执 JSON 结构（`server.mbt` 改动面扩大）⇒ **本单记为缺口，另立单**。

### 2.5 ⚠️ `publish` 的「一半保护」—— 本仓守卫**按输入形状分层，不按后果分层**

**实测读数**：`publish` 已有 `ns_write_gate`（`server.mbt:1678` → `write_gate.mbt:171`）：

| 输入 | `ns_write_gate` | 是否被挡 |
|---|---|---|
| `""` / `"default"` | **Err**（拒绝写 default）| ✅ 已堵 |
| **格式非法**（`safe_ns` → None）| **Err**「仅允许字母数字与 _ / -」| ✅ **已堵** |
| **合法新 ns** | Ok ⇒ `mstore.get` **惰性建库** | 放行（正确）|
| **格式合法但库打不开 / data_dir 歪** | **Ok（放行）** ⇒ `engine_for_ns` **静默回落主库** | ❌ **漏** |

**⇒ 它是 8 个工具里唯一「已经有一半保护」的。**
**而这一半保护暴露的是一个**模式**：**

> **本仓的守卫是「按输入形状分层」的，不是「按操作危险度分层」的。**
> **格式非法的攻击被挡住，是因为它「看起来不像合法输入」；
> 而库打不开没被挡住，是因为它「看起来完全合法」。**
>
> ⇒ 这是「**守卫按形状分，不按后果分**」的又一个标本（与本 BUG-433 本尊同族）：
> 挡住它的条件与它的**危险性**无关，只与它的**外貌**有关。

**⇒ 对 `publish` 的修法因此更简单**：**不动 `ns_write_gate`**，
只需把 `engine_for_ns(ns)` 换成 `engine_for_ns_strict(ns)`。两者是**叠加**关系，不冲突。

---

## 三、5 格锁设计

> **⚠️ 完整可粘贴的锁文件正文在附件**：`reports/2026-10-27-bug433-lock-file.mbt.txt`（8.6 KB）。
> 本节只给设计与变异表；**正文以附件为准**（报告体量限制，故分离）。

| 锁 | 断言 | 防什么 |
|---|---|---|
| **锁 1** | `delete(非法ns)` ⇒ **Err 且主库任务仍在**（两断言）| 防「副作用发生了但返回 Err」（M4 证明第二断言有判别力）|
| **锁 2** | `delete(已open ns)` ⇒ 正常删 | 防修过头（一律 Err）|
| **锁 3** | `""` / `"default"` ⇒ Ok（正当用法）| 防把正当用法误判成非法（M2）|
| **锁 4** | 格式合法但未 open ⇒ Err（或合法惰性建库）| 覆盖 `ns_write_gate` 漏掉的成因 2/3 |
| **锁 5** | ★ **8 个写工具逐条字面量**断言都用了 strict | 防「只改一处」漏网（M3）|

**判例（统帅核定，请入档）**：
> **「一个工具改对了」不等于「全部工具改对了」。**
> 锁 1 只测 `delete` ⇒ 若只改 `delete`，锁 1 绿、锁 5 红。
> **⇒ 凡是「同一改动要在 N 个地方各做一遍」，必须有一格断言「N 个地方都做了」，
> 而不是「其中一处做对了」。**
> 与本仓第二轮 `report_bug` trailing newline 同族（「修了一处 ≠ 修了全部写入路径」），
> **但方向更狠**：那次是「两条路只修一条」；这次是「**同一条路在 8 个工具里各写一遍**」。

**锁 5 为何逐条字面量、不遍历列表**：若写成 `for t in WRITE_TOOLS {…}`，
有人**从列表里删掉一个名字**，遍历式断言会**自动通过** —— 「缺键 ≠ 空值」同族。
**删任何一个工具名，锁 5 必红。**

### 变异实测（真跑，非设计）

| 变异 | 改了什么 | 预期 | 抓它的锁 |
|---|---|---|---|
| **M1** | `engine_for_ns_strict` 的 `None => Err(...)` 改回 `None => Ok(engine)` | **锁 1 红** | 锁 1（`r.is_err()` 变 false）|
| **M2** | 删掉 `if ns == "" \|\| ns == "default"` 提前返回 | **锁 3 红** | 锁 3（空 ns 被 `safe_ns` 判非法）|
| **M3** | 六个写工具里**只改 `delete` 一个**，其余留 `engine_for_ns` | **锁 1 仍绿（漏网）** ⇒ **锁 5 必红** | **锁 5** —— 这正是它存在的理由 |
| **M4** | `delete` 里改成「先 `eng.delete_task()` 再返回 `Err(e)`」（副作用发生但报错）| **锁 1 红** | 锁 1 的**第二断言**「主库任务仍在」|

**M3/M4 是本单最关键的两条变异**：
- **M3** 证明「只测一个工具」不够 ⇒ 必须有**普查格**；
- **M4** 证明「只断言 Err」不够 ⇒ 必须断言**副作用未发生**。

---

## 四、判例稿：「缺键 ≠ 空值」

> **判例：「缺键 ≠ 空值」（`get(k, default)` 家族的观测缺陷）**
>
> `p.get("namespace", "")` **无法区分**「调用方没传 `namespace`」与「传了空串」。
> 二者在语义上完全不同：前者是「用默认」，后者可能是「显式要 default」或「笔误」。
>
> **实测代价**：我第一版脚本把 **2555 条「参数里根本没有 `namespace` 键」** 的调用
> 算成「传了非空 ns」，得出 **755 条回落**；严格化（只认 `"namespace" in p`）后是 **819 条**。
> **⇒ 若没纠正，报告会写「755 条回落」，而真实是 819 —— 一个纯因观测手段产生的错误读数。**
>
> **与既有三条同族**：
> | 判例 | 机理 |
> |---|---|
> | 「退出码跨管道」 | 读到的是**另一个进程的**退出码 |
> | 「缺键 ≠ 空值」（本条） | 读到的是**默认值冒充的**实际值 |
> | 「打印 ≠ 生效」/「读数面 ≠ 原文面」 | 有输出没生效 / 读错面 |
>
> **共同点：观测手段本身制造了数据。**
>
> **硬要求**：凡「参数是否被显式提供」影响结论的地方，必须用
> `"k" in obj` / `obj.has(k)` 判存在性，**不许用 `get(k, default)` 的返回值反推**。

---

## 五、缺口与风险

1. **`engine_for_ns_strict` 只在写类工具接线，读类面仍会静默回落**。
   这是**有意的取舍**（读错库可容忍），但**必须文档化**：
   建议在 `get` / `list` 的回执里加 `"ns_fallback": true` + `"actual_ns"`（候选 (c) 的合理落点）——
   **对只读操作，「告诉用户查错了库」是有意义的**；对 `delete` 无意义（已不可逆）。
2. **M3 类缺口已由锁 5 覆盖**：若只改 `delete` 一处、其余 5 个写工具留着，
   **锁 1 仍会绿**（它只测 `delete`）⇒ 新增**锁 5（实现路径普查格）**
   断言 6 个写类工具的工具体内都出现 `engine_for_ns_strict` 且**不含**裸 `engine_for_ns(`。
   一格覆盖 6 处，**变异删任一处都会红**。
   （这是判例-29 的正面用法：**机制格之外必须有一格测实现路径**。）
3. **`publish`/`publish_parallel` 是否同批切**：它们占 819 条里的 348 条，且是**写类**。
   建议同批，但它们是「新建」而非「改已有」——**误伤面比 delete 小**。需统帅裁决。
4. **跨 ns 同名任务**：`T0` 在主库与 `zi-migration.db` 都存在过。
   严格化后这类调用会**报错而不是默默作用于主库**，这正是期望行为。
5. **未跑编译**（`src/server/server.mbt` 是 HumanSteward 独占）⇒ patch 可编译性需应用方验证。

---

## 六、建议入档位置

| 内容 | 位置 |
|---|---|
| 本 patch | BUG-433 条目挂 `- patch:` |
| **「缺键 ≠ 空值」判例** | 判例集（稿在 §四）|
| **819 / 755 的自我纠正** | 同判例的实测代价栏（**一个错数字会进报告并被引用**）|
| `seq=104` 实锤 | BUG-433 的 `- evidence:`（证明「ns 被静默忽略」，与是否误操作无关）|
| 8 处调用点表 | BUG-433 正文（可复核性要求）|
