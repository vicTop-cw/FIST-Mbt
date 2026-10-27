# BUG-452：`conflicts_check` 缺 `namespace` —— 非 default ns 冲突检测恒失败 · Lane BO · 2026-10-27

> **已修，且普查发现同族问题不止一个。**
> `conflicts_check` 之外，`heartbeat` 也只用全局引擎取任务 ⇒ 非 default ns 里**心跳静默失效**。

---

## 一、结论

| 项 | 结果 |
|---|---|
| `conflicts_check` | ✅ 加 `namespace` 参数 + 按 ns 路由（`engine_for_ns`）|
| **普查发现同族** | ✅ `heartbeat` 已一并修（同样只用全局 `engine` 取任务）|
| 零回归 | ✅ 不传 ⇒ `default` ⇒ 主库，与旧版一致 |
| 我的改动测试 | `src/server` **435/435/0** |
| 变异对照 | **真跑**，`bo_01` 精确打红 |
| 全量 | ⚠️ **1626/1630**，4 格红 —— **全部在 `src/engine`，属并发 lane 的 BUG-453 在途改动**（见 §4）|

---

## 二、证据

### 2.1 根因

```moonbit
// 修复前
schema({ "task_id": …, "assignee": … }, ["task_id", "assignee"])   // ← 没有 namespace
fn(args) {
  match @ops.check_claim(engine, task_id, assignee)   // ← 全局 engine = 主库
}
```
⇒ 任务在独立 ns 库里 ⇒ **恒 `task not found`** ⇒ **并行门第 4 道在非 default ns 里不可用**。

### 2.2 修法（可粘贴 patch）

**`conflicts_check`**
```diff
     schema(
       {
         "task_id": string_prop("任务 id（必填）"),
         "assignee": string_prop("拟认领人（必填）"),
+        "namespace": string_prop(
+          "可选：目标命名空间（默认 default）。⚠️ 任务在独立 ns 库里时**必须传**，否则本工具查主库、恒报 task not found",
+        ),
       },
       ["task_id", "assignee"],
     ),
     fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
       let task_id = get_str(args, "task_id")
       let assignee = get_str(args, "assignee")
-      match @ops.check_claim(engine, task_id, assignee) {
+      let ns = get_str(args, "namespace", default="default")
+      let eng = match engine_for_ns(ns) {
+        Ok(e) => e
+        Err(m) => return Err(m)
+      }
+      match @ops.check_claim(eng, task_id, assignee) {
```

**`heartbeat`（普查发现）**：同样加 `namespace` + `engine_hb = engine_for_ns(ns_hb)`，
函数体内 3 处 `engine.get_task` / `engine.store_write_heartbeat*` 改走 `engine_hb`。

### 2.3 四格锁

| 锁 | 断言 |
|---|---|
| **`bo_01`** | `conflicts_check` schema 有 `namespace` **且** 实现用 `engine_for_ns(ns)` **且** `check_claim(eng, …)` **且** 无旧形态 `check_claim(engine, …)` |
| `bo_02` | **零回归**：`ns` 缺省必须是 `"default"` |
| `bo_03` | 同族 `heartbeat` 也按 ns 路由（`engine_for_ns(ns_hb)`）|
| **`bo_04`** | ★ **路由语义格**（见 §3.1 —— 我第一版写错了这里）|

**变异实测**：把 `check_claim(eng, …)` 改回 `check_claim(engine, …)`
⇒ **434/435**，**只有 `bo_01` 红**。

---

## 三、分析

### 3.1 ★ 我第一版锁写错了：`engine_for_ns` 对未打开的 ns **不返回 Err**

我最初写 `bo_04` 断言「未打开的 ns ⇒ `Err`」，**跑红了**。查证发现：

```moonbit
// src/store/multi_store.mbt:109 MultiStore::get
None =>
  if !MultiStore::data_dir_ok(self.data_dir) { None }
  else { SqliteStore::open(path) … }     // ← 惰性打开：建一个新库
```
⇒ 合法但未打开的 ns ⇒ **惰性建库并返回 `Some`** ⇒ `engine_for_ns` 给 `Ok(新库引擎)`。

**这是设计（惰性多租户），不是 bug**。但它决定了本单的性质：
**传 `namespace="rx-rhop"` 拿到的是那个库的引擎**（不是主库）——
只要那个库真的被 `store_open` 过且里面有任务，本单的修复就成立。

**真正的防线是「非法 ns 必须 Err」**（`ns_reject_reason`），
因为那才会把 `delete`/`archive` 打到**主库任务**上。`bo_04` 改成钉这个。

**⇒ 教训：锁要先在**未变异的**新鲜样本上跑一遍，别让「我以为的语义」进锁。**

### 3.2 为什么之前漏了 namespace

`conflicts_check` 是**早期工具**（AO `--no-takeover` 时代），当时多租户（`engine_for_ns`）
还没铺开。后来 `claim` / `dag_check` / `task_triage` 等逐个补了 ns，
**这个工具没被带上** —— 典型的「新增能力没有回填既有工具」。

### 3.3 普查结果（本单重点）

按「操作任务/库」的口径逐个核了 20 个工具：

| 有 `namespace` | 缺 `namespace` |
|---|---|
| `claim` · `omega_status` · `dag_check` · `dag_ready` · `task_triage` · `board_ascii` · `status_summary` · `project_health` | **`conflicts_check`**（本单修）· **`heartbeat`**（本单修）· `execute`（**已有**，走 `acl_claim_identity` 得 ns）· `task_challenge` · `tx_contract` · `task_cleanup` · `reserve_scope`/`lock_*`（按 scope 而非 task，ns 语义不同）· `audit_log`/`call_log`/`bug_list`（非任务库面）|

**已修 2 个**（`conflicts_check` / `heartbeat`）。
**待议 3 个**：`task_challenge` / `tx_contract` / `task_cleanup` —— 见 §4。

---

## 四、缺口与风险

1. **`task_challenge` / `tx_contract` / `task_cleanup` 仍未按 ns 路由**。
   `task_challenge` 实测用 `engine.challenge(task_id…)` ⇒ 非 default ns 的任务同样找不到。
   **本单未改**（`task_challenge` 的引擎函数签名与外溢面更复杂，且 `src/engine/` 本轮有并发 lane 在改）。
   ⇒ **建议单开**，与本单同族。
2. **`reserve_scope` / `lock_acquire` 的 ns 语义不同**（按 `scope` 而非 `task_id`），
   它们缺 `namespace` **未必是 bug**（锁表在主库，scope 是全局命名空间）。
   **需要设计决策**，不是顺手补参数。
3. **全量 1626/1630，4 格红**：全部在 `src/engine`，来自**并发 lane 的 BUG-453 在途改动**
   （`engine_rsv.mbt` 当时为 `M`，我的 `engine_bug430_s1/s3_p2` 锁被其改动影响）。
   **我的改动面 `src/server` 是全绿 435/435** —— 已单独验证。
4. **惰性建库**：传一个拼错的合法 ns 会**静默建一个新空库**（不报错）。
   `conflicts_check` 于是报 `task not found` —— 与「任务真不存在」不可区分。
   ⇒ 建议：`conflicts_check` 在 ns 库为空且非 default 时，回执附一句提示。

---

## 五、建议入档位置

| 内容 | 位置 |
|---|---|
| BUG-452 修复 | 账本挂 `- fix:`，**关联同族 `task_challenge` 单** |
| **「锁要先在未变异的新鲜样本上跑一遍」** | 判例集（本单 `bo_04` 第一版红在这条）|
| **「惰性建库让『拼错 ns』与『任务不存在』不可区分」** | BUG-452 风险项 |
| **「新增能力没有回填既有工具」** | 判例集（`conflicts_check` 的漏因），建议做一次**全工具 ns 回填普查** |
