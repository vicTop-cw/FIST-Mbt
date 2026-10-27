# BUG-454：`tx_contract` / `task_challenge` / `task_cleanup` 缺 `namespace` · Lane BQ · 2026-10-27

> **这是 BUG-452 普查列出的「待议 3 个」的收口。**
> 三个都处理了：**2 个修，1 个修但**刻意**不做遍历**（附理由）。
> **`tx_contract` 的错误最危险** —— 它不是「查不到」，是**给出与 `get` 相反的结论**。

---

## 一、结论

| 工具 | 处理 | 说明 |
|---|---|---|
| **`tx_contract`** | ✅ **加 `namespace` + 按 ns 路由** | 原先对**主库同名任务**做预检 ⇒ **结论与 `get(namespace=…)` 相反** |
| **`task_challenge`** | ✅ **加 `namespace` + 按 ns 路由** | 原先 `engine.challenge(...)` 取全局引擎 ⇒ 源任务在独立 ns 库时找不到 |
| **`task_cleanup`** | ✅ **加 `namespace`，但刻意不做遍历** | 一次只清**一个**库；**理由见 §3.2** |

| 项 | 结果 |
|---|---|
| 编译 | `moon check --target js` → **0 errors** |
| 测试 | 全量 **1635/1635/0** |
| 变异对照 | **2 个真跑**，各自精确打红 |
| 零回归 | ✅ 三个工具的 `namespace` 缺省都是 `"default"` |

---

## 二、证据

### 2.1 可粘贴 patch

**`tx_contract`**
```diff
         "force": bool_prop("…"),
+        "namespace": string_prop(
+          "可选：目标命名空间（默认 default）。⚠️ 任务在独立 ns 库里时**必须传** —— " +
+          "否则本工具会对**主库**同名任务做迁移预检，给出与 `get(namespace=…)` 相反的结论",
+        ),
       },
       ["task_id", "action"],
     ),
     fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
       let task_id = get_str(args, "task_id")
       let action = get_str(args, "action")
+      let ns_tx = get_str(args, "namespace", default="default")
+      let eng_tx = match engine_for_ns(ns_tx) { Ok(e) => e ; Err(m) => return Err(m) }
       ...
-          engine
+          eng_tx
           .transition_contract(task_id, action, assignee~, completed_by~, force~)
```

**`task_challenge`**
```diff
+        "namespace": string_prop("可选：目标命名空间（默认 default）。源任务在独立 ns 库里时必须传"),
       },
       ["task_id"],
     ),
+      let ns_ch = get_str(args, "namespace", default="default")
+      let eng_ch = match engine_for_ns(ns_ch) { Ok(e) => e ; Err(m) => return Err(m) }
       ...
-        engine.challenge(task_id~, by~, factor~, strat~, now=ts, critic=gated) {
+        eng_ch.challenge(task_id~, by~, factor~, strat~, now=ts, critic=gated) {
```

**`task_cleanup`**
```diff
-    "归档清理：删除超过保留期的已归档任务。参数：retention_days(可选默认30)。",
+    "归档清理：…参数：retention_days(可选默认30)、namespace(可选)。⚠️ **一次只清一个库** ——
+     不传 namespace 只清主库（零回归）；要清独立 ns 的库必须显式传。
+     清理是**不可逆删除**，故刻意**不做**「自动遍历所有 ns」。",
     schema(
-      { "retention_days": int_prop("…") },
+      { "retention_days": int_prop("…"),
+        "namespace": string_prop("可选：目标命名空间（默认 default，只清主库）…**不会被遍历**") },
       [],
     ),
+      let ns_tc = get_str(args, "namespace", default="default")
+      let eng_tc = match engine_for_ns(ns_tc) { Ok(e) => e ; Err(m) => return Err(m) }
-      match @ops.cleanup_archived(engine, ts, retention_days~) {
+      match @ops.cleanup_archived(eng_tc, ts, retention_days~) {
```

### 2.2 四格锁 + 两个变异（**都真跑**）

| 锁 | 断言 |
|---|---|
| **`bq_01`** | `tx_contract` 有 `namespace` + 用 `engine_for_ns(ns_tx)` + `transition_contract` 作用在 `eng_tx` + **无旧形态**（`engine` 单独成行 + 下一行 `.transition_contract(`）|
| `bq_02` | **零回归**：三个工具的 `namespace` 缺省都是 `"default"` |
| `bq_03` | `task_challenge` 用 `eng_ch.challenge` · `task_cleanup` 用 `cleanup_archived(eng_tc, …)` |
| **`bq_04`** | ★ **设计决策格**：`task_cleanup` 里**不许有任何 `for … in …` 遍历**、不许出现 `active_namespaces` / `foreach_ns` |

| 变异 | 结果 |
|---|---|
| **M1** `tx_contract` 的 `eng_tx` 改回 `engine` | **438/439**，`bq_01` 红 |
| **M2** `task_cleanup` 里加 `for ns_x in [ns_tc] { … }` | **438/439**，`bq_04` 红 |

---

## 三、分析

### 3.1 为什么「错误结论」比「查不到」更糟

| | 查不到（`conflicts_check` 的病）| 错误结论（`tx_contract` 的病）|
|---|---|---|
| 调用方看到 | `task not found` | **`verdict: allowed/rejected` + 理由 + `target_state`** |
| 调用方判断 | **知道有问题**，去查 ns / 换工具 | **以为得到答案**，据此执行 |
| 后果 | 停在原地 | **按相反结论去做迁移/归档** |

`tx_contract` 是**只读预检**，它的输出被当作「能不能做这一步」的**依据**。
缺 ns 时它会拿**主库的同名任务**（或空任务）算 pre/postcondition，
给出的是**一个完全自洽的、但属于另一个对象的结论** —— 这正是最难被发现的形态：
**它不是报错，是一个看起来正常的答案。**

### 3.2 为什么 `task_cleanup` 刻意**不**遍历所有 ns

派单提到「可能需要 `namespace`，或者『清理所有已 open 的 ns』」。**我选了前者，并刻意拒绝后者**：

- `task_cleanup` 是**不可逆删除**；
- 若自动遍历所有已打开 ns ⇒ **一次调用波及多个租户库**，事后**无法核对到底删了哪些**；
- 与 `delete` / `archive` 必须显式指定 ns + task 的既定纪律一致。

⇒ **语义**：不传 ⇒ 只清主库（零回归）；要清别的库 ⇒ 逐个显式传。
**`bq_04` 把这个决策写成锁**：将来有人加遍历，格会红，逼着重新评审这个取舍 ——
而不是让它悄悄变成「一次删多个库」。

---

## 四、缺口与风险

1. **`tx_contract` 的「错误结论」仍是静默的**：现在**传了 ns 就对**，
   但**不传 ns 且任务在别的库**时，它依然会对主库同名任务给出结论（不报错）。
   ⇒ 建议后续：当主库有同名任务、但目标 ns 也打开着且该任务也在其中时，**回执附带提示**
   （「本次预检基于 default 库的同名任务」）。这是「让错误结论变得可见」的下一步。
2. **`task_cleanup` 不做遍历 ⇒ 多租户下要多次调用**：这是**有意的取舍**，
   不是遗漏。若将来确实需要「一键清所有库」，应做成**显式开关**（如 `all_namespaces=true`）
   且**回执逐库列出删除了什么**，不能默认开。
3. **`reserve_scope` / `lock_*` 仍缺 ns**：它们按 `scope` 而非 `task_id`，
   ns 语义不同（锁表在主库），**需要设计决策**，不是顺手补参数。
4. **本单期间多次遇到并发 lane 的编译中断**（`engine_rsv_bug453_wbtest.mbt` 等），
   均已等待其收口后重跑，**未使用 `--no-verify`**。

---

## 五、建议入档位置

| 内容 | 位置 |
|---|---|
| BUG-454 修复 | 账本挂 `- fix:`，作为 BUG-452 普查的**收口单** |
| **「错误结论 > 查不到」** | 判例集：静默错答比显式失败危险，因为它不触发怀疑 |
| **「不可逆操作不该跨库遍历」** | 判例集（`task_cleanup` 的取舍，`bq_04` 钉住）|
| **「检测词不能只写一种拼法」** | 本单实测：`for ns in` 漏过 `for ns_x in`；已改为「行首 `for ` + 行含 ` in `」 |
| 下一步：让「基于主库同名任务」的预检可见 | BUG-454 风险项 1 |
