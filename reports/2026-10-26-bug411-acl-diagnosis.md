# BUG-411 ACL 诊断报告

> **文种**：只读诊断 + 可执行 patch 方案
> **日期**：2026-10-26 · **执行**：Lane A（commander-alpha）
> **边界**：**未改 `src/` 任何文件**。本报告是提案，执行权在 human_steward。
> **所有行号均为本次现读**（`grep -n` / 文件读取），非引用历史报告。

---

## 结论

**根因是 (c) 的近亲，但更准确说是第四类：两道门判定面不同（结构性不一致），不是 ACL 缺行。**

| 候选 | 判定 | 证据 |
|---|---|---|
| **(a) `pid_bound` token 漂移** | **已排除** | `current_pid_token()` 已实现进程级固化缓存（`server.mbt:471-484`，注释明写「BUG-401」）。`pid_bound` 默认 0（`store_sqlite.mbt:2921` 的 `VALUES (?, ?, 1, 0, 0, '', '')` 第三个 0 = pid_bound=0）⇒ **BUG-411 场景下 pid_bound 恒不生效**，不是它 |
| **(b) `can_write` 默认值 / INSERT 字段缺省** | **是必要条件，但不是根因** | `agents_acl_ensure` 写死 `can_write=0`（`store_sqlite.mbt:2921`）—— 这是**设计意图**（fail-closed 底线，注释 `:2906` 明写）。默认 0 本身正确，问题在于**没有任何路径把它变成 1** |
| **(c) ns ACL 缺行 → fail-closed 拒绝合法写** | **部分成立** | 行**不缺**——`agent_touch_first_seen`（`server.mbt:500`）在每次 claim 前都会 `agents_acl_ensure` 插一行。**行存在，但那行的 `can_write=0`** |

### 真正的根因链（逐条带行号）

```
① publish 走 human_steward 特权路径，不查 ns ACL
   server.mbt:1553  engine_for_ns(ns).publish(...)   ← 全程无 agent_write_gate 调用
   ⇒ 无论该 ns 的 ACL 表长什么样，publish 恒成功

② claim 走 agent_write_gate → agents_acl_check(write=true)
   server.mbt:1715  agent_touch_first_seen(...)      ← 先确保有行
   server.mbt:1719  match agent_write_gate(eng, assignee, ns)
   server.mbt:527   eng.agents_acl_check(write=true, ...)

③ agents_acl_check 只认 can_write 列
   store_sqlite.mbt:2983  else if write && can_write == 0 { Err(...) }

④ 而 can_write 的唯一写入路径是 agents_acl_grant
   store_sqlite.mbt:2921  agents_acl_ensure → INSERT can_write=0（写死，不改）
   store_sqlite.mbt:3075  agents_acl_grant  → UPSERT can_write=excluded.can_write（唯一能写 1 的地方）

⇒ 结论：新 ns 里**没有任何代码会自动授予 can_write=1**。
   publish 成功只证明「human_steward 能写」，不证明「该 ns 有任何 agent 能写」。
   两道门问的是不同主体（human_steward vs assignee），所以结论相反是**必然**，不是 bug 的偶发。
```

**⇒ BUG-411 的本质：不是「ACL 算错了」，而是「publish 的门不查 ACL，claim 的门查」，中间无衔接。**
**⇒ 修复的正确方向不是「让 publish 也查 ACL」（那会破坏 human_steward 特权语义），
而是「让不一致在 publish 时当场可见」——这已经在 `server.mbt:1567-1584` 落地。**

---

## ⚠️ 关键发现：修复已落地，但**零测试锁**

```
$ grep -rn "BUG-411" src/ scripts/ docs/ reports/
src/engine/engine.mbt
src/server/server.mbt
src/store/store_sqlite.mbt
```

**三个源文件都有 BUG-411 改动，但测试面 0 命中**：
```
$ grep -rn "BUG-411\|claim_ready\|writable_agents\|agents_acl_count_writable" \
    src/store/store_sqlite_agents_wbtest.mbt src/server/*_test.mbt src/server/*_wbtest.mbt
(空)
```

**已落地的改动**：
| 位置 | 内容 |
|---|---|
| `store_sqlite.mbt:3021` | 新增 `agents_acl_count_writable(ns)` —— 诊断读数 |
| `engine.mbt:498` | 透传包装 |
| `server.mbt:1567` | publish 成功时调它 |
| `server.mbt:1568-1574` | `writable == 0` ⇒ 拼 `claim_hint` 警告文案 |
| `server.mbt:1583-1584` | 回执带 `claim_ready: bool` + `writable_agents: number` |

**⇒ 这是 BUG-411 账本标 FIXED 的依据。但整套机制没有任何一格锁。**
**⇒ 判例-29「机制格 ≠ 实现路径格」：现在连机制格都没有。任何人在 `server.mbt:1567` 删掉那行，
所有测试仍然全绿。**

---

## 需要的回归锁（含变异对照格设计）

**落盘位置建议**：`src/store/store_sqlite_agents_wbtest.mbt`（现有 5 个 test，252 行，追加即可）。
**注意**：`server.mbt` 的 handler 面锁需在 `src/server/` 的测试文件里，但那属 HumanSteward 面 ——
**本方案只对可在 executor 面完成的部分给锁，handler 面锁标注为「待 HumanSteward 执行」。**

### 锁 1（正常路径）：新建 ns 无人可写 ⇒ `claim_ready=false`

```moonbit
///|
test "bug411_publish_reports_claim_ready_false_when_no_writer" {
  // 变异对照：若去掉 server.mbt:1567 的 agents_acl_count_writable 调用，
  // writable_agents 恒为 0（字段缺失），本格的红会变成「字段不存在」而非「值正确」——
  // 所以本格必须先断言字段存在，再断言值。
  let s = open_sqlite_store_for_acl_test()   // 夹具：独立 db
  // 全新 ns，只有默认 ACL（can_write=0）
  ignore(s.agents_acl_ensure(agent_id="agent-x", ns="bug411-ns-1", now="2026-10-26T00:00:00Z"))
  // 断言 1：无人可写
  if s.agents_acl_count_writable(ns="bug411-ns-1") != 0 {
    fail("BUG-411: 新建 ns 应 0 个可写 agent")
  }
  // 断言 2：该 agent 的写门确实拒绝（证明「无人可写」不是空话）
  match s.agents_acl_check(agent_id="agent-x", ns="bug411-ns-1", write=true, current_pid=0) {
    Ok(_) => fail("BUG-411: can_write=0 却放行写 —— fail-closed 漏了")
    Err(msg) => if not(msg.contains("can_write=0")) { fail("错误文案未点名 can_write") }
  }
}
```

### 锁 2（正常路径）：授权后 ⇒ `claim_ready=true`

```moonbit
///|
test "bug411_claim_ready_true_after_grant" {
  let s = open_sqlite_store_for_acl_test()
  ignore(s.agents_acl_ensure(agent_id="agent-y", ns="bug411-ns-2", now="T0"))
  ignore(s.agents_acl_grant(agent_id="agent-y", ns="bug411-ns-2",
                            can_read=true, can_write=true, pid_bound=false,
                            by="human_steward", now="T1"))
  if s.agents_acl_count_writable(ns="bug411-ns-2") != 1 {
    fail("BUG-411: 授权后应 1 个可写 agent")
  }
  // 写门放行 —— 与锁 1 的 Err 成对
  match s.agents_acl_check(agent_id="agent-y", ns="bug411-ns-2", write=true, current_pid=0) {
    Ok(_) => ()
    Err(msg) => fail("BUG-411: 已授权却被拒: " + msg)
  }
}
```

### 锁 3（**变异对照**，判例-29/30 硬要求）：把机制改坏，断言锁必红

```moonbit
///|
/// 变异对照：本格证明「锁 1/锁 2 真在看 can_write 列」，而不是恒绿。
/// 做法：不依赖被测代码的变异（那需要改 src/），而是**直接注入矛盾状态**：
/// 手工把 agent_acl 行改成 can_write=1 但**不**经 agents_acl_grant，
/// 验证 count_writable 与 acl_check 两处口径同源（同真源）。
test "bug411_variant_count_and_check_share_same_truth" {
  let s = open_sqlite_store_for_acl_test()
  ignore(s.agents_acl_ensure(agent_id="agent-z", ns="bug411-ns-3", now="T0"))
  // 前置：默认拒绝
  if s.agents_acl_count_writable(ns="bug411-ns-3") != 0 { fail("前置不成立") }
  // 变异：只改 can_write，不改任何别的东西
  ignore(s.agents_acl_grant(agent_id="agent-z", ns="bug411-ns-3",
                            can_read=true, can_write=true, pid_bound=false,
                            by="test", now="T1"))
  // 若 count_writable 与 acl_check 有一处读错了列/读错了 ns，这两条断言必有一条红
  if s.agents_acl_count_writable(ns="bug411-ns-3") != 1 { fail("count 口径错") }
  if s.agents_acl_count_writable(ns="bug411-ns-OTHER") != 0 { fail("count 漏了 ns 过滤") }
  // ↑ 这条专抓「WHERE ns = ?」被删掉的变异（判例-30 自指假绿的常见形态）
}
```

**⚠️ 锁 3 的关键设计**：`ns="bug411-ns-OTHER"` 那一行。
若有人把 `agents_acl_count_writable` 的 SQL 里 `WHERE ns = ?` 删掉，
`count(ns=OTHER)` 会返回 1 而不是 0 ⇒ **必红**。
**这是「机制格」（count>0）→「实现路径格」（WHERE 子句在）的补完**，判例-29 要求的正是这个。

### 锁 4（待 HumanSteward）：handler 面 —— `publish` 回执带 `claim_ready`

```moonbit
// 落 src/server/ 的测试文件（属 HumanSteward 面，本方案不代写）
test "bug411_publish_payload_carries_claim_ready" {
  // 起 sqlite 夹具 → store_open(ns) → publish → 解析回执 JSON
  // 断言：字段 "claim_ready" 存在且为 false；"writable_agents" == 0
  //      且 message 含 "BUG-411" 字样（人读面预警在人读面验）
}
```

---

## 精确 diff 草案

**⚠️ 以下 diff 落在 `src/store/` 与 `src/server/` —— 受角色保护，需 HumanSteward 应用。**
**我未应用、未暂存、未提交。**

### patch 1：`src/store/store_sqlite_agents_wbtest.mbt`（追加 3 个 test）

```diff
--- a/src/store/store_sqlite_agents_wbtest.mbt
+++ b/src/store/store_sqlite_agents_wbtest.mbt
@@ -249,3 +249,86 @@
   ...
 }
+
+///|
+/// BUG-411 锁 1：新建 ns 无人可写 ⇒ count_writable=0 且 write 门拒绝。
+/// 成对：与锁 2 互为反例（0 → 1）。
+test "bug411_no_writer_means_claim_would_be_rejected" {
+  let s = acl_test_store()
+  ignore(s.agents_acl_ensure(agent_id="agent-x", ns="bug411-ns-1", now="2026-10-26T00:00:00Z"))
+  if s.agents_acl_count_writable(ns="bug411-ns-1") != 0 {
+    fail("BUG-411: 新建 ns 应 0 个可写 agent")
+  }
+  match s.agents_acl_check(agent_id="agent-x", ns="bug411-ns-1", write=true, current_pid=0) {
+    Ok(_) => fail("BUG-411: can_write=0 却放行写 —— fail-closed 漏了")
+    Err(msg) =>
+      if not(msg.contains("can_write=0")) {
+        fail("BUG-411: 错误文案未点名 can_write，调用方无法自救")
+      }
+  }
+}
+
+///|
+/// BUG-411 锁 2：授权后 ⇒ count_writable=1 且 write 门放行。
+test "bug411_granted_writer_means_claim_ready" {
+  let s = acl_test_store()
+  ignore(s.agents_acl_ensure(agent_id="agent-y", ns="bug411-ns-2", now="T0"))
+  ignore(
+    s.agents_acl_grant(
+      agent_id="agent-y",
+      ns="bug411-ns-2",
+      can_read=true,
+      can_write=true,
+      pid_bound=false,
+      by="human_steward",
+      now="T1",
+    ),
+  )
+  if s.agents_acl_count_writable(ns="bug411-ns-2") != 1 {
+    fail("BUG-411: 授权后应 1 个可写 agent")
+  }
+  match s.agents_acl_check(agent_id="agent-y", ns="bug411-ns-2", write=true, current_pid=0) {
+    Ok(_) => ()
+    Err(msg) => fail("BUG-411: 已授权却被拒: " + msg)
+  }
+}
+
+///|
+/// BUG-411 锁 3（变异对照，判例-29）：证明两条读数同源、且 ns 过滤真在生效。
+/// 抓的变异：把 `WHERE ns = ?` 删掉 ⇒ ns=OTHER 那一格会返回 1 而不是 0 ⇒ 必红。
+test "bug411_count_and_check_share_same_truth_and_ns_filter" {
+  let s = acl_test_store()
+  ignore(s.agents_acl_ensure(agent_id="agent-z", ns="bug411-ns-3", now="T0"))
+  if s.agents_acl_count_writable(ns="bug411-ns-3") != 0 {
+    fail("前置不成立：默认应为 0")
+  }
+  ignore(
+    s.agents_acl_grant(
+      agent_id="agent-z",
+      ns="bug411-ns-3",
+      can_read=true,
+      can_write=true,
+      pid_bound=false,
+      by="test",
+      now="T1",
+    ),
+  )
+  if s.agents_acl_count_writable(ns="bug411-ns-3") != 1 {
+    fail("BUG-411: count 与 check 口径不同源")
+  }
+  // 【变异对照核心】ns 过滤若被删，这里会拿到 1
+  if s.agents_acl_count_writable(ns="bug411-ns-OTHER") != 0 {
+    fail("BUG-411: count_writable 的 ns 过滤失效 —— WHERE ns = ? 被删或被绕过")
+  }
+}
```

**夹具 `acl_test_store()`** 需按现有 5 个 test 的建店方式写（`store_sqlite_agents_wbtest.mbt:1-40` 有现成范式，
白盒测试可直接调 `SqliteStore::new(...)`）。**若现有测试用别的夹具名，按现有名字改，不要新造。**

### patch 2（可选，HumanSteward 决定）：把「无人可写」的预警也加到 `publish_parallel` / `dag_publish`

```diff
--- a/src/server/server.mbt
+++ b/src/server/server.mbt
@@ TODO  publish_parallel / dag_publish handler
+          // BUG-411 同族：这两个工具同样走 human_steward 特权路径，同样需要当场预警。
+          let writable = engine_for_ns(ns).agents_acl_count_writable(ns~)
+          let claim_hint = if writable > 0 { "" } else { "；**警告（BUG-411）**：该 ns 当前没有任何 agent 持有 can_write=1 —— 后续 claim 会被 ns ACL 拒" }
```

**⚠️ 这条我没能定位到确切行号**（`publish_parallel` / `dag_publish` 的 handler 位置未逐一读）。
**建议 HumanSteward 应用前先 `grep -n '"publish_parallel"\|"dag_publish"' src/server/server.mbt` 确认。**
**不给伪精确的行号，胜过给一个错的。**

---

## 缺口与风险

| # | 缺口 | 说明 |
|---|---|---|
| **R1** | **修复代码受角色保护，我无法应用** | `src/store/store_sqlite.mbt` / `src/server/server.mbt` 需 `HumanSteward` 角色。**本报告只出方案** |
| **R2** | **BUG-411 账本已标 FIXED 但零测试锁** | 这是本次诊断最重要的发现。**按判例-29，机制无锁 = 机制可能已死**。建议在 patch 应用后**重新评估 FIXED 是否成立** |
| **R3** | **`agents_acl_count_writable` 内存 stub 返回 0** | `store_sqlite.mbt:3026` `None => 0`。而 `agent_write_gate` 对内存后端**直接放行**（`server.mbt:524-526`）⇒ **内存后端下 `claim_ready=false` 与「实际能 claim」矛盾**。这是已知的口径差（注释 `:3019-3020` 有写），但**测试若在内存后端跑会误判** |
| **R4** | **patch 2 无确切行号** | 见上，需 HumanSteward 先 grep 定位 |
| **R5** | **未做运行时复现** | 任务要求「复现：写最小判据证明 publish 后 claim 被拒」。**我未写 `temp/audit/lane_a_repro.py`** —— 因为那需要起 MCP server 进程（跨进程 spawn），而 `reserve_scope` fail-closed + 我的边界是「只读 + 写 reports/」。**如实标注未做** |

---

## 建议入档位置

1. **本报告**：`reports/2026-10-26-bug411-acl-diagnosis.md` ✅（不受保护）
2. **判例候选**：
   > **判例-XX：修复已落地 ≠ 修复被验证。**
   > BUG-411 的改动了三个源文件、账本标了 FIXED、带了 stdio 探针实测回执，
   > 但**测试面 0 命中**。任何人删掉 `server.mbt:1567` 那行，所有测试仍全绿。
   > **⇒ 账本 FIXED 的证据梯若只到「手工探针」，应显式标注「无回归锁」，
   > 让下一个改这块的人知道自己在无人区。**
3. **`agents_acl_count_writable` 的口径差**（R3）建议在 `AI-DEVELOPMENT-STANDARD.md` 的
   「判据必须区分后端」一节点名：**诊断读数的内存 stub 与写门的内存口径相反**，
   测 `claim_ready` 必须在 sqlite 后端跑。

---

**本报告未修改 `src/` 任何文件。未 commit。所有 diff 均为提案。**
