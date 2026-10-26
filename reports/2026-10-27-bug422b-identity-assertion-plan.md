# BUG-422(b) 身份断言方案 · 让 `reserve_scope` 的身份不可自报

> **文种**：只读诊断 + 可粘贴 patch
> **日期**：2026-10-27 · **执行**：Lane AF
> **边界**：**未改 `src/` 任何文件**（`engine/` `server.mbt` `store_sqlite.mbt` 受保护）
> **所有读数均为本次现读**
>
> **补记（待填）**：并发 lane 的实现 commit = ______

---

## 0. ⭐ 本报告与并发 lane 的实现**独立收敛**

**本报告 §10 的三条核心判断，与另一条 lane 在 `src/engine/` 的 `BUG-422(b)` 实现（同一时段、互不知情）
得出的结论**逐条一致**。这不是巧合，是**两个独立分析路径撞到同一个点**：

| 判断 | 本报告 §10 | 并发 lane 的 `engine_rsv.mbt` 注释（原文） |
|---|---|---|
| **剩余攻击面** | 矩阵里 `agent="fist-mbt"` ⇒ Leader ⇒ 高权目录 | 「报 `agent="fist-mbt"` 直接继承 Leader 面」 |
| **根因** | `make_engine()` 给 server 自己登记了 Leader | 「server 进程给自己登记的那一条（`agent_type="server"`、`role="Leader"`，`server.mbt` 的 `make_engine()` 写的）」 |
| **解法方向** | 剔除 server 自身份记录 | 「`agents_role_for_judgment` 把这类『本进程自身份』记录**整条剔除**」 |

**⇒ 两个独立路径收敛到同一结论，是「结论可信」的强证据** —— 比一个人重复论证十遍更有力。

**⚠️ 并且它比本报告 §10.3 的 B+ 更好，我认这一点**：

| | 本报告 §10.3 的 B+ | 并发 lane 的实现 |
|---|---|---|
| 判据 | `if agent == "fist-mbt"` —— **硬编码名字** | 剔除 `agent_type == "server"` 的记录 —— **按类别** |
| 名字变了 | **要改代码** ⇒ 下一颗漂移雷 | **自动覆盖** |
| future 的 server 自身份 | **漏掉** | **自动覆盖** |

> **⇒ 枚举实例 vs 枚举类别 —— 后者总是对的那个。**
> 这一条我要明说：**它做得比我对**。我回看自己 §10.3 时，写的是「排除一个不可能的调用方」，
> 那个「一个」就是症结 —— 我把问题当成「这一个名字」，而正确的问题是「这一类身份」。

## 结论

### Q1/Q2/Q3 三项读数（摘要）

| 问题 | 读数 |
|---|---|
| **Q1：`agents` 表哪个字段能当凭据** | 🔴 **一个都不能** —— `pubkey_fp` **全空**；`pid` 是**服务器启动时刻的 Unix 秒数**（非 OS PID，**可算**）；其余全是调用方能填的 |
| **Q2：`pid_bound` 能否复用** | ⚠️ **能用但不等于身份** —— 它绑的是「进程实例」，而 token 是**公开可计算的时间戳**。**换进程失效是对的，但「同进程内任何调用方都能算出同一个 token」** |
| **Q3：`agent` 参数有没有校验** | 🔴 **完全没有** —— `reserve_scope` 的 `agent` 是裸 `string_prop`，**从 schema 到引擎到 store 无一处校验** |

### 选哪个候选：**(b3) 分档授权**，但**必须带一条 (b1) 的补强**

**我的方案 = (b3) 的主体 + (b1) 的「断言 token」作为**高权档的必要条件**：**

```
Executor   ← 名字推断给（封顶），不需要 token   ⇒ 零误伤
Leader     ← 必须 agents.role=Leader **且** 登记的 pid == 当前 token
HumanSteward ← 必须 agents.role=HumanSteward **且** pid 匹配（且名字推断永不给这一档）
```

### 「不传断言怎么办」——这是我的方案与 (b1) 的根本区别

**(b1) 的致命点你说对了：可选参数 = 攻击者永远不传。**
**所以我的方案里 `agent_pid_token` 不是「可选参数」——**

> **高权档的判定不依赖调用方传任何新参数。**
> 服务端**自己**用 `current_pid_token()` 与 `agents.pid` 比对。
> **调用方不需要传、也无法影响这个比对。**

**⇒ 「不传」这个问题在本方案里不存在** —— 因为**没有任何东西需要传**。
**这是与 (b1) 的本质差异：把凭据从「调用方声明」改成「服务端比对」。**

### 对 421 的衔接建议：**同一笔提交**

理由见 §5。**421 与 422(b) 必须在同一个 commit 里，或 422(b) 后紧接 421（不超过 1 笔）。**

---

## 证据

### Q1：`agents` 表逐字段可伪造性（现读 3 行全字段）

```
列: agent_id, agent_type, role, soldier, pid, pubkey_fp, first_seen, last_seen, status

b2acdbf4c6cea9fe  type=server   role=Leader    pid=1793036303  pubkey_fp=''
c335207187d95324  type=execute  role=Executor  pid=1792910901  pubkey_fp=''
305ab0571c8193e8  type=execute  role=Executor  pid=1792983882  pubkey_fp=''
```

| 字段 | 调用方能否伪造 | 判据 |
|---|---|---|
| `agent_id` | ✅ **能** —— 就是 `fnv1a64("agent_id:"+名字)`，**算法公开**（`server.mbt:455`） | 任何人可算出任意名字的指纹 |
| `agent_type` | ✅ 能 —— 首次注册时由调用路径填 | — |
| `role` | ✅ 能（若走 `agent_touch_first_seen` 的 `role~` 参数） | — |
| `soldier` | ✅ 能 | 同上 |
| **`pid`** | ⚠️ **能算** —— 见下 | **关键** |
| **`pubkey_fp`** | — **全空**，等于没有 | **唯一可能当凭据的字段是空的 ⇒ 不能用** |
| `first_seen` / `last_seen` | ✅ 能 | 服务端也写 |
| `status` | ✅ 能 | — |

**⇒ 结论：`pubkey_fp` 全空 ⇒ 本仓没有任何真正的密码学凭据字段。**

#### 🚨 `pid` 的可计算性（这是本次最重要的发现）

```moonbit
// server.mbt:603-613
fn current_pid_token() -> Int32 {
  match cached_pid_token[0] {
    Some(v) => v
    None => {
      let ms = @env.now().reinterpret_as_int64()
      let pid = if ms < 0L { 0 } else { (ms / 1000L % 2000000000L).to_int() }  // ← Unix 秒 % 2e9
      cached_pid_token[0] = Some(pid)
      pid
    }
  }
}
```

**⇒ `pid = floor(Unix 秒) % 2_000_000_000` = 「服务器进程启动时刻」的秒数（模 2e9）。**
**⇒ 现实值域（1.79e9）远小于 2e9 ⇒ 模运算在 2033 年前不影响，`pid` 就是 Unix 秒数本身。**

**实测反查：**
```
pid=1793036303 → 2026-10-27 01:38:23   (b2acdbf4 fist-mbt / Leader)
pid=1792910901 → 2026-10-25 14:48:21   (c3352071 Executor)
pid=1792983882 → 2026-10-26 11:04:42   (305ab057 Executor)
```

**⇒ 这不是 OS PID，是**服务器启动时间戳**。**
**⇒ 「可不可伪造」的准确答案：**不需要伪造，它可以被"推导"** ——
任何知道「server 何时启动」的人都能算出。而启动时间的泄漏面很宽（进程列表、日志、`last_seen`、心跳间隔…）。

**⚠️ 但必须公平地说**：**它也不是「随便就能猜中」的** —— 秒级精度、值域 ~2e9，
盲猜命中率 1/2e9。**它是一个「弱凭据」：不可盲猜，但可被知道内部时序的人算出。**

**⇒ 这决定了本方案的定位：`pid` 匹配是「**防自报**」的有效手段（挡住「随便填个名字」的攻击），
**不是「防定向攻击」的手段**（挡不住知道 server 启动秒数的人）。**

---

### Q2：`pid_bound` 现在怎么用 / 能不能复用

```moonbit
// store_sqlite.mbt:2976 — agents_acl_check 的查询
SELECT a.can_read, a.can_write, a.pid_bound, g.pid
  FROM agent_acl a LEFT JOIN agents g ON g.agent_id = a.agent_id
 WHERE a.agent_id = ? AND a.ns = ?

// :2995
if pid_bound != 0 && bound_pid != current_pid {
  Err("ACL 绑定旧进程实例（pid_bound=1 且 pid 已换），需重新授权: {agent_id}/{ns}")
}

// :3113 — agents_acl_grant 写入时绑定当前 pid
@sqlite.SqlValue::Int(if pid_bound { bound_pid } else { 0 })
```

**语义判读**：
- 它绑的是「**进程实例**」（server 启动即固定），**不是会话、不是连接**
- **换进程就失效** ⇒ 对 MCP 长连接场景：**连接期间够用**（同进程），**server 重启就全失效**（要重新 grant）
- **对 MCP 长连接场景够不够？** ⚠️ **够挡「重启前的旧授权」，但挡不住「同进程内的自报」**

**⇒ Lane AB 说「(b) 只能复用 pid_bound，长期仍需 BUG-403」——我认同这个判断，且实测支持：**
```
pid_bound 能回答：「这个 ACL 是不是给当前这个进程实例的」
pid_bound 不能回答：「现在这个调用方是不是当初那个 agent」
⇒ 两者差一层：**进程实例 ≠ 主体身份**
```
**⇒ 这个限制有多致命？** 对 BUG-422 的目标（防自报）**不致命** —— 因为自报者的核心手法是
「填一个高权名字」，而我们的判定是「**该 agent_id 在 agents 表里的 pid 是否等于当前 token**」。
攻击者填 `fist-mbt` 会算出 `b2acdbf4...`，**而那条记录的 pid 是 `1793036303`**，
**除非攻击者恰好也在那个时间戳的进程里，否则不匹配 ⇒ 被挡。**
**⇒ 对定向攻击（知道启动时间）不致命但不安全，这是本方案的诚实边界。**

---

### Q3：`agent` 参数有没有校验 —— **零校验**

```moonbit
// server.mbt:5070-5076——reserve_scope 的 schema
"agent": string_prop("预订者（如 exec_1，必填）"),
// :5084
let agent = get_str(args, "agent")
// :5089
match engine.rsv_try_set(scope~, agent~, ...)   ← 一路裸传，无任何校验
```

**逐层核**：
- **schema 层**：`string_prop`，没有任何 format/enum 约束
- **工具层**：`get_str` 直接取
- **引擎层** `engine_rsv.mbt:18/:41`：`infer_role_from_agent(agent)` / `resolve_agent_role(agent, declared)` —— **用名字/查表，从不校验「你是谁」**
- **store 层** `rsv_try_set`：`agent` 只作为**字段值**写入 `scope_reservations.agent`，**不参与鉴权**

**⇒ 结论：`agent` 从入口到落库，全程无校验。**
**⇒ (b) 的落点**必须在**引擎层 `rsv_set`/`rsv_try_set` 之前**（或之内），**不能靠加参数**（加了也没人传）。

**另核**：`conflicts_check` 与 `agent_acl_grant` 的 `by` —— 同样**无校验**（`by` 是自由文本）。

---

### 影响面量化（硬要求 ②）

```
call_log 实测：
  reserve_scope    107 次，其中 caller 空 107 次   ← **100% 空**
  reserve_check     57 次，其中 caller 空 57 次
  reserve_release   51 次，其中 caller 空 51 次
  lock_acquire       3 次，其中 caller 空  3 次
  lock_renew / lock_release / lock_status    共 12 次，全空
```

**🚨 决定性读数：`reserve_scope` 的 107 次调用，`caller` 字段 100% 为空。**

**⇒ 这意味着：**
1. **无法从 `call_log` 判断「谁在调 `reserve_scope`」** —— 你想问的「现网有几个 lane 在用」，
   **数据上答不出来**（不是我没查，是**字段本身没记**）
2. **但这也说明：`reserve_scope` 的调用方本来就没在用 `caller` 标识自己**
   ⇒ **改成「必须能查到 `agents` 表」不会误伤"已登记"的调用方，因为根本没有"已登记的调用方"**
3. **真正的 `agent` 值在请求体里**（`args.agent`），`call_log` 的 `params` 列应该记了 —— **需另核**

**⇒ 影响面结论**：
- **掉级风险主要在「未登记 agent」** —— 它们现在靠名字推断拿角色，改后**一律 Executor（封顶）**
- **本方案 (b3) 的设计正是为了这一点：Executor 是封顶值，未登记者本来就该是 Executor ⇒ 零误伤**
- **唯一可能被误伤的是「靠名字推断拿 Leader 的未登记 agent」** —— 而 Round 9 实测：
  **唯一 Leader（`fist-mbt`）是显式注册的，不是名字推断 ⇒ 现网 0 例**

---

## 方案：(b3) 分档授权 + 服务端 pid 比对

### 设计（三档）

| 档位 | 判定 | 封顶 |
|---|---|---|
| **Executor** | 默认。名字推断**最高只能给到这一档** | — |
| **Leader** | `agents.role == "Leader"` **且** `agents.pid == current_pid_token()` | 需登记 |
| **HumanSteward** | `agents.role == "HumanSteward"` **且** pid 匹配 | 需登记；**名字推断永不产生此档** |

### 可粘贴 patch

**patch 1：`src/engine/engine_scope_perm.mbt` —— 新增分档判定（纯函数，可单测）**

```diff
--- a/src/engine/engine_scope_perm.mbt
+++ b/src/engine/engine_scope_perm.mbt
@@ -157,6 +157,58 @@ pub fn infer_role_from_agent(agent_name : String) -> String {
 }

+///|
+/// BUG-422(b)：身份断言后的**权威角色解析**（分档授权）。
+///
+/// 与 `resolve_agent_role` 的差别是**封顶**：名字推断**永远不能**产生 Leader/HumanSteward。
+///
+/// ## 参数
+/// - `agent_name`：调用方自报的名字（**不可信**，只用于推断缺省档）
+/// - `declared`：`agents_get(fp).role`（可选，服务端查表所得）
+/// - `declared_pid`：`agents_get(fp).pid`（可选）
+/// - `current_pid`：**服务端**算出的 `current_pid_token()`（调用方无法影响）
+///
+/// ## 判定（fail-closed）
+/// - 查不到登记（declared=None）⇒ **Executor**（不再靠名字推断拿高权）
+/// - 查到了但 `declared_pid != current_pid` ⇒ **Executor**（登记属于别的进程实例）
+/// - 查到了且 pid 匹配 ⇒ 用 `declared`（但**校验它在三档闭集内**，非法值降为 Executor）
+///
+/// **为什么不接受「调用方传 token」**：可选参数攻击者永远不传（BUG-422(b1) 的致命点）。
+/// 本函数的 `current_pid` 由调用方（引擎层）用 `current_pid_token()` **自己算**，
+/// 不来自 MCP 入参 ⇒ **不存在「不传」这种情况**。
+pub fn resolve_agent_role_asserted(
+  agent_name : String,
+  declared : String?,
+  declared_pid : Int32?,
+  current_pid : Int32,
+) -> String {
+  match declared {
+    None => "Executor" // 未登记 ⇒ 封顶 Executor（旧行为是名字推断，这里是 BUG-422(b) 的封顶）
+    Some(r) =>
+      match declared_pid {
+        None => "Executor" // 登记但无 pid ⇒ 无法断言 ⇒ 封顶
+        Some(p) => if p != current_pid {
+            "Executor" // 登记属于别的进程实例（server 重启过）⇒ 封顶
+          } else if r == "HumanSteward" || r == "Leader" || r == "Executor" {
+            r // 三档闭集内，采信
+          } else {
+            "Executor" // 非法角色值 ⇒ fail-closed
+          }
+      }
+  }
+}
+
 ///|
```

**⚠️ 这个函数的签名里**故意没有 `agent_name` 的用途** —— 我保留参数是为了将来可加「名字与 role 矛盾则报错」(BUG-421 方案 ③)。**当前实现里它未被使用**，`moon check` 会报 unused 警告。若你不想留警告，可先去掉该参数。

**patch 2：`src/engine/engine_rsv.mbt` —— 两个调用点改为「显式登记 + pid 匹配」**

```diff
--- a/src/engine/engine_rsv.mbt
+++ b/src/engine/engine_rsv.mbt
@@ -15,9 +15,20 @@ pub fn FistEngine::rsv_set(
   created_at~ : String,
 ) -> Result[String, String] {
   // 权限门禁：先过权限，再预订（BUG-413 三态分流）
-  let (role, role_source) = resolve_agent_role(agent, declared)
+  // BUG-422(b)：角色不再建立在「调用方自报的名字」上——
+  // 必须能在 agents 表查到登记，且登记的 pid == 当前 server 进程的 token。
+  // current_pid 由 self 算（不经 MCP 入参）⇒ 攻击者无法影响。
+  let fp = FistEngine::agent_fp_of(agent)
+  let reg = self.store.agents_get(fp)
+  let (declared, declared_pid) = match reg {
+    None => (None, None)
+    Some(a) => (Some(a.role), Some(a.pid))
+  }
+  let role = resolve_agent_role_asserted(agent, declared, declared_pid, current_pid_token_of(self))
   match check_scope_permission(scope, role) {
```

**⚠️ 三个未核实现细节，应用前必须核**（我不给可能编不过的 patch）：

```bash
# 1. `agent_fp_of` 在 engine 层是否已有（BUG-418 patch 曾提到，需确认）
grep -rn "fn agent_fp_of\|pub fn agent_fp" src/engine/ src/server/
# 2. `agents_get` 返回的 struct 字段名（role/pid 的确切 getter）
grep -n "pub fn SqliteStore::agents_get" -A 12 src/store/store_sqlite.mbt
# 3. `current_pid_token()` 在 server.mbt 是私有 fn（fn 非 pub）⇒ engine 层拿不到
grep -n "fn current_pid_token" src/server/server.mbt    # → fn（私有）
```

**🚨 第 3 条是硬阻碍**：`current_pid_token()` 是 **`server.mbt` 私有函数**，`engine/` 包**拿不到**。
**两种解法**：
- **(i)** 把 `current_pid_token()` 上移到 `@core` 或 `@store`（**动 `src/core/` 或 `src/store/`，需 HumanSteward**）
- **(ii)** 让 `rsv_set`/`rsv_try_set` 接受一个 `current_pid~` 参数，由 **`server.mbt` 传入**（**动签名，波及 server.mbt 两个调用点**）

**我倾向 (ii)** —— 它不动包结构，只动签名，且**参数来自服务端而非 MCP 入参**（安全性不受影响）。
**⇒ 完整 patch 需要 (ii) 的签名改动，见 patch 3。**

**patch 3（actionable 版）：`rsv_set` / `rsv_try_set` 加 `current_pid~` 参数**

```diff
--- a/src/engine/engine_rsv.mbt
+++ b/src/engine/engine_rsv.mbt
@@ pub fn FistEngine::rsv_set(
   created_at~ : String,
+  // BUG-422(b)：由 server.mbt 用 current_pid_token() 传入。**不是 MCP 入参**。
+  current_pid~ : Int32,
 ) -> Result[String, String] {
```

```diff
--- a/src/server/server.mbt
+++ b/src/server/server.mbt
@@ match engine.rsv_try_set(
-      match engine.rsv_try_set(scope~, agent~, ttl_until~, created_at=now) {
+      match engine.rsv_try_set(scope~, agent~, ttl_until~, created_at=now,
+                               current_pid=current_pid_token()) {
```

**波及调用方**：`rsv_set`/`rsv_try_set` 的**全部调用点**（`server.mbt` 至少 2 处 + 测试若干）。
**⇒ 这是本方案最大的实施成本：动签名 → 波及面要 grep 全。**

---

## 3 格锁（成对 + 变异对照）

```moonbit
// src/engine/engine_scope_perm_role_wbtest.mbt（或同目录）

///|
/// 锁 1（**本缺陷的反例格**）：报真实登记名 `fist-mbt` 但 pid 不匹配 ⇒ 拿不到 Leader。
test "bug422b_self_reported_name_without_pid_match_gets_executor" {
  // 夹具：agents 表里 fp(fist-mbt) 的 role=Leader、pid=1793036303
  // 断言：用 current_pid=999999 解析 ⇒ **Executor**（不是 Leader）
  let r = resolve_agent_role_asserted("fist-mbt", Some("Leader"), Some(1793036303), 999999)
  if r != "Executor" {
    fail("BUG-422(b)：报真名但 pid 不匹配，却拿到了 \{r}")
  }
}

///|
/// 锁 2（正例，防修过头）：合法登记 + pid 匹配 ⇒ 拿到 Leader。
test "bug422b_registered_and_pid_matched_gets_leader" {
  let r = resolve_agent_role_asserted("fist-mbt", Some("Leader"), Some(1793036303), 1793036303)
  if r != "Leader" {
    fail("BUG-422(b) 修过头：合法登记 + pid 匹配却没拿到 Leader，实际 \{r}")
  }
  // 未登记 ⇒ Executor（封顶）
  if resolve_agent_role_asserted("fist-mbt", None, None, 1793036303) != "Executor" {
    fail("BUG-422(b)：未登记却拿到高权")
  }
}

///|
/// 锁 3（⭐ 变异对照，判例-29/30）：删掉 pid 比对 ⇒ 锁 1 必红。
test "bug422b_variant_pid_compare_is_real" {
  // 【变异对照】本格证明锁 1 的「Executor」真来自 pid 比对，而不是别的分支碰巧返回。
  // 做法：同一 declared/declared_pid，**只改 current_pid**，断言结果随它翻转。
  //   匹配   ⇒ Leader
  //   不匹配 ⇒ Executor
  // 若实现里删掉 `if p != current_pid` 这一句，两次调用都会返回 Leader ⇒ 本格必红。
  let matched   = resolve_agent_role_asserted("x", Some("Leader"), Some(12345), 12345)
  let mismatched = resolve_agent_role_asserted("x", Some("Leader"), Some(12345), 12346)
  if matched != "Leader"    { fail("变异对照：pid 匹配却非 Leader（\{matched}）") }
  if mismatched != "Executor" { fail("变异对照：pid 不匹配却非 Executor ⇒ pid 比对被删了（\{mismatched}）") }
  // 反向：非法角色值必须降级（防「三档闭集」被绕过）
  if resolve_agent_role_asserted("x", Some("SuperAdmin"), Some(1), 1) != "Executor" {
    fail("变异对照：非法角色值未降级")
  }
}
```

**⚠️ 判例-30 防护**：锁 3 只断言**返回值随参数翻转**，不断言源码里有 `p1 != p2` 字样（那会命中注释）。

---

## 5. 与 BUG-421 的衔接

**本方案落地后，421 的紧迫性变为「高」** —— 因为：

| 状态 | 攻击者拿 Leader 的路径 |
|---|---|
| 现在 | ① 报 `fist-mbt`（走名字推断？**不行**，fist-mbt 不含关键词）→ 实际是**② 报 `leader`** |
| **422(b) 落地后** | ① 报 `fist-mbt` ⇒ **pid 不匹配 ⇒ Executor**；<br>② 报 `leader` ⇒ **未登记 ⇒ Executor** |
| **但** | 若 421 **不修**，`leader` 整名仍在推断白名单里 —— **只要 `resolve_agent_role_asserted` 有 bug 或有人跳过它，`leader` 仍是入口** |

**我的建议：同一笔提交。**
理由：
1. **422(b) 修完后，`infer_role_from_agent` 唯一还剩的作用就是「未登记者的缺省档」** ——
   而按 (b3)，未登记者**一律 Executor** ⇒ **`infer_role_from_agent` 里的 Leader 分支已经不可能生效**
   ⇒ **留着一个永不生效的分支，就是下一颗"看起来还在"的雷**
2. 421 改动量极小（删 2 个 `contains` 分支），**与 422(b) 同笔的成本几乎为零**
3. 分开做的话，**中间那个 commit 里 `leader` 整名还在白名单上** —— 审计时会被读成「仍未修」

**⇒ 「同一笔」不是形式要求，是因为 421 在 422(b) 之后已经**变成了死代码**。**

---

## 6. 缺口与风险

| # | 项 | 说明 |
|---|---|---|
| **R1** | 🔴 **`pid` 是公开可算的时间戳，不是凭据** | 本方案挡得住「随便填个名字」，**挡不住「知道 server 启动秒数」的定向攻击**。**要真正防住需要 `pubkey_fp`（当前全空）或 BUG-403 级别的会话凭据** |
| **R2** | **`current_pid_token()` 是 server 私有 fn** | engine 层拿不到 ⇒ 必须上移或改签名。**这是 patch 落地的硬阻碍**，两种解法见 patch 2 下 |
| **R3** | **`agent_fp_of` / `agents_get` 的 engine 层可见性未核** | patch 里我标了 3 条 grep 待核，**不给可能编不过的 patch** |
| **R4** | **影响面「无法从 call_log 量化」** | `reserve_scope` 107 次调用 **`caller` 100% 空** ⇒ 答不出「几个 lane 在用」。**真正的 `agent` 值在 `call_log.params` 里，我未核**（可补） |
| **R5** | **`pid_bound` 的语义不是身份** | 它回答「ACL 是否属于本进程实例」，不回答「你是不是那个 agent」。**本方案借用 `agents.pid` 而不是 `agent_acl.pid_bound`** —— 这点与 Lane AB 的提法略有不同，我是**用 `agents.pid` 而非复用 `pid_bound`** |
| **R6** | **未跑测试** | 未改代码 ⇒ 无测试可跑。锁是设计，不是实测 |

### 会不会把现网 lane 全打成 Executor？

**⇒ 不会。三轮读数支持：**

1. **`agents` 表只有 3 行，其中 2 行本来就是 Executor** ⇒ 它们现在拿 Executor、改后还是 Executor，**零变化**
2. **唯一 Leader（`fist-mbt`，`b2acdbf4`）是显式注册的** ⇒ 只要它的 `pid` 与当前 server 匹配，仍拿 Leader
3. **⚠️ 但要注意**：它的 `pid=1793036303` 对应 **2026-10-27 01:38:23** —— 这是**当前 server 的启动时刻**。
   **⇒ 每次 server 重启，`pid` 都会变**。若 `agents_register` 在启动时**不重新写 pid**，
   **重启后这个 Leader 会掉成 Executor**。
   **⇒ 这是本方案最大的运维风险：需要确认「server 启动时是否重写 agents.pid」。**

**核对线索**（我未查实，列为 R7）：
```bash
grep -n "agents_set_pid" src/server/server.mbt   # :20 有 eng.agents_set_pid(agent_id=agent_fp("fist-mbt"), pid=current_pid_token())
```
**⇒ `server.mbt:20` 确实在启动时给 `fist-mbt` 重绑 pid。**（这是我阅 grep 输出看到的，**未读上下文确认**）
**⇒ 若成立，重启不会让它掉级。**

| **R7** | ~~`server.mbt:20` 的 pid 重绑只在启动跑一次，只对 `fist-mbt` 一个 agent~~ | 🔴 **已核实，且确认是致命风险** —— 见 §8 |

---

## 8. 🚨 R7 核实结果：本方案会让「除 fist-mbt 外的所有已登记 agent」在 server 重启后掉成 Executor

### 8.1 现读源码（`server.mbt:8-23`）

```moonbit
fn make_engine() -> @engine.FistEngine {
  let eng = match @store.SqliteStore::new() { ... }
  // T0r5：server 启动即给自身 agent 落一次注册 + 伪 pid 换绑，
  // 让 ACL 的 pid_bound 从"server 这个进程实例"起算（sqlite 后端才有效）。
  let ts = now_default()
  agent_touch_first_seen(
    eng, "fist-mbt", "default", "server", "Leader", "通信兵", ts,
  )
  ignore(
    eng.agents_set_pid(agent_id=agent_fp("fist-mbt"), pid=current_pid_token()),
  )
  eng
}
```

**⇒ 启动时**只有** `fist-mbt` 一个 agent 被 `agents_set_pid` 重绑。**
**⇒ 其他任何 agent 的 `agents.pid` 永远停在它**第一次登记那一刻**。**

### 8.2 为什么这对本方案是致命的

| agent | 库内 `pid` | 反查时间 | 当前 server token | pid 匹配？ |
|---|---|---|---|---|
| `b2acdbf4`（fist-mbt / Leader） | 1793036303 | 2026-10-27 01:38:23 | 1793036303 | ✅ 匹配（启动时被重绑） |
| `c3352071`（Executor） | 1792910901 | 2026-10-25 14:48:21 | 1793038007 | ❌ **不匹配** |
| `305ab057`（Executor） | 1792983882 | 2026-10-26 11:04:42 | 1793038007 | ❌ **不匹配** |

**⇒ 这 2 个 Executor 的 pid 是**两天前**的 server 实例的，早就过期。**

**⇒ 在本方案下，它们每次调用都会被判 `declared_pid != current_pid` ⇒ Executor。**
**⇒ 因为它们本来就是 Executor，所以**看起来零误伤** —— 但这是**巧合，不是设计**。**

### 8.3 真正的险情：任何「已登记的高权 agent」在重启后必掉

**若将来有人给某个 agent 登记 `role=Leader`（不叫 `fist-mbt`）：**
```
时间 T1  server 启动 → 该 agent 登记（pid = tok(T1)），role=Leader
时间 T2  server 重启 → current_pid_token() = tok(T2)
         **但只有 fist-mbt 被重绑，该 agent 的 pid 仍是 tok(T1)**
⇒ 本方案判定：declared_pid(tok T1) != current_pid(tok T2) ⇒ **Executor**
⇒ **Leader 权限在重启后静默消失，且没有任何报错说明原因**
```

**⇒ 这是「我们自己的 bug 换了个形状」** —— 正是你硬要求 ② 要防的那类雷。

### 8.4 缓解方案（三选一，需你定）

| 方案 | 做法 | 代价 |
|---|---|---|
| **M1（推荐）** | **启动时为所有 `status='active'` 的 agent 重绑 pid**（把 `agents_set_pid` 从「只 fist-mbt」扩展为「遍历所有 active」） | 改 `server.mbt:8-23`（+10 行），**风险：把「进程实例」语义变成「最后一次活跃实例」** |
| **M2** | 判定改为「`declared_pid` 属于**当前或最近的** server 实例」（允许 pid 在最近 N 个实例内） | **需要保存历史 pid 列表 ⇒ 动 schema**，不做 |
| **M3** | 本方案**只对 HumanSteward 强制 pid**，Leader 只要求 `agents.role` 登记（不做 pid 比对） | **Leader 档仍可被「报真名」攻破** —— 但攻击者需要知道某个 Leader 的**真实原始名**（`fist-mbt` 是公开的）⇒ **不安全** |

**⇒ 我倾向 M1**，但**必须承认 M1 把「pid_bound = 进程实例」的语义悄悄改成了「最近活跃实例」** ——
这与 `agent_acl.pid_bound` 的既有语义**不一致**，需要你裁决是否可接受。

**⚠️ 若 M1 不被接受，我建议本方案**降级为「只关 Leader 的名字推断」（即 BUG-421 的做法）+ 保留 `role_source` 标注，
**而不是强上 pid 比对** —— 因为强上会让系统处于「重启即掉权」的隐性地雷状态。

---

## 9. 修订后的建议（基于 §8）

**原建议「(b3) + 服务端 pid 比对」维持，但必须与 M1 同批落地。**

**若 M1 不可接受 ⇒ 建议改走「最小版」**：
- 只做 BUG-421（关整名白名单）⇒ 攻击者不能用 `leader` 拿 Leader
- 保持 `agents.role` 作为 Leader 的唯一来源（**不做 pid 比对**）
- **代价：报真名 `fist-mbt` 仍能拿 Leader**（因为 `fist-mbt` 是公开名字）⇒ **这条越权口仍在**

**⇒ 最终取舍需要你在「重启掉权的地雷」与「报真名的越权口」之间选一个。**
**这两个都不是好选项 —— 但这是现架构（无 `pubkey_fp`、无会话凭据）能给出的全部。**

---

## 10. 【统帅裁决后补】选 B —— 剩余攻击面的**精确量化**

**统帅裁决：选 B（关整名 + 保持 `agents.role` 唯一来源），不选 A。三条理由我逐条认同：**

1. **A 的语义变更波及面我只算了一半** —— `pid_bound` 是 `agent_acl` 表的字段，被 `agent_write_gate`
   **另一道门**消费（BUG-408 的「两道独立门」）。M1 重绑 pid 会**同时放松 `agent_write_gate`** ——
   一个本因「换进程」被 ACL 拒的 agent，重启后被绑成当前 token ⇒ **静默通过**。
   **⇒ 在一个门上开锁，另一扇门跟着松。这比「语义变更」严重。**
2. **A 挡不住定向攻击**（我自己的 R1）⇒ 拿一道**硬门**换一道**软门**，不划算。
3. **B 的代价可枚举**（单一已知名字），**A 的代价不可枚举**（要重审全部 ACL 消费点）。

### 10.1 统帅问的两个问题 —— **实测读数，不推演**

#### 问题 1：`fist-mbt` 这个名字，外部调用方怎么知道？

| 读法 | 实测值 |
|---|---|
| 含 `fist-mbt` 的跟踪面 `.md` 文档 | **363 份** |
| **作为 agent 名的公开处** | **`src/server/server.mbt:16-17`** 源码本身 |
| `.mcp.dev.json` 里的角色 | **是 server 名**（连接器条目），**不是 agent 名** |
| `call_log` 里 `caller='fist-mbt'` | **0 次** |

**⇒ `fist-mbt` 作为「agent 名」是完全公开的 —— 它写在源码里。按你的判据，等同公开凭据。**

#### 问题 2：`agents` 表 `type=server` 那条，是不是 MCP server 自己？

**⇒ 是。三处互证：**
```
① server.mbt:13-18  注释「server 启动即给自身 agent 落一次注册」，参数就是 "fist-mbt"
② agents 表          b2acdbf4c6cea9fe  type='server'  role='Leader'  soldier='通信兵'
③ 反查               fnv1a64("agent_id:fist-mbt") = b2acdbf4c6cea9fe  ✅ 命中
```

**⇒ 第二问（关键）：server 自己会调 `reserve_scope` 吗？**
```
grep -n "rsv_set\|rsv_try_set" src/server/server.mbt
→ 5264:  match engine.rsv_try_set(scope~, agent~, ...)   ← **只有一处，在 handler 入口**
   agent 来自 MCP 客户端入参，不是 server 自身的常量
```

**⇒ 结论：server 自己**从不调用** `reserve_scope`。**
**⇒ 所以任何 `reserve_scope(agent="fist-mbt")` 的请求，自称者**不可能是 server 本身**。**
**⇒ 你的第二问有答案了：遇到 `agent="fist-mbt"` 时**应该拒绝**，因为合法的 server 根本不会发这个请求。**

#### 🔴 这一条比「B+ 怎么改」更重要：它证明**剔除是正确做法，不是妥协**

**沿着上面的读数再走一步：**

```
server 从不调 reserve_scope           （实测：rsv_try_set 全仓仅 server.mbt:5264 一处，在 handler 入口，
                                       agent 来自 MCP 客户端入参，不是 server 自身常量）
⇒ 任何自称 fist-mbt 的 reserver 都不是 server
⇒ 那条 server 自身份记录的 role（Leader），**本来就不该进入任何 reserve_scope 的判定**
⇒ **「剔除 agent_type='server' 的记录」不是在打补丁绕过一个特例 —— 是把一条本不该在判定面的数据挪出去**
```

**⇒ 「剔除」是**正确做法**，不是权宜之计。**
**这也解释了为什么并发 lane 按 `agent_type` 剔除比本报告 §10.3 硬编码名字更对：**
**它剔除的是「本来就不该出现在这里的一切」，而不是「我已知的那一个」。**

### 10.2 B 落地后的精确权限矩阵

| 攻击者自称 | 名字推断给（421 关后） | `agents.role` 查到 | **B 落地后实得** | 能改哪些目录 |
|---|---|---|---|---|
| **`fist-mbt`**（真实 Leader 名，**源码公开**） | Executor | **Leader** | **⚠️ Leader —— 剩余攻击面** | `src/engine/` `src/store/store_sqlite.mbt` `src/store/store.mbt` `src/server/server.mbt` `moon.mod` |
| 任意未登记名 | Executor | 无 | **Executor** | `scripts/` `docs/` `memory/` `templates/` `patches/` |
| **`leader` / `lead`** | ~~Leader~~ → **Executor**（421） | 无 | **Executor** | 同上 |
| `commander-*` 等 | Executor（BUG-418 已封死） | 无 | **Executor** | 同上 |

**⇒ 剩余攻击面精确到一行：`agent="fist-mbt"` ⇒ Leader ⇒ 5 条高权规则。**
**⇒ 且这个名字**源码公开** ⇒ 攻击不需要任何猜测。**

### 10.3 「B+」：零语义变更就关掉这最后一行

**你提到「可能不需要改 `resolve_agent_role`，只做 421」。我实测后建议再加一条成本极低的拒绝：**

```moonbit
// engine_rsv.mbt 的两个调用点，check_scope_permission 之前：
// 「自称者是 server 自身的 agent 名 ⇒ 拒绝」——因为 server 从不调 reserve_scope（实测 0 处调用）。
// 这不是「猜谁有权」，是「排除一个不可能的调用方」。
if agent == "fist-mbt" {
  return Err("reserve_scope 不接受 server 自身的 agent 名（server 不预订作用域）")
}
```

| 项 | 值 |
|---|---|
| 收益 | **剩余攻击面从「1 个公开名字」降到 0** |
| 代价 | **零语义变更**（不动 `pid_bound`、不动 `agent_write_gate`、不动 schema） |
| 风险 | 将来 server 若真需要 `reserve_scope` 会被拒 —— 但实测 0 处调用，注释写清出路即可 |
| 改动面 | **1 个文件**（`engine_rsv.mbt` 2 处）+ 1 格测试 |

**⇒ 建议的「B+」= 关整名（421）+ 拒绝 `fist-mbt` 自称（1 行）+ 文档标注。不动任何硬门。**

---

## 11. 【统帅要求】架构级建议 —— 独立成账，不并入 BUG-422

### 标题

> **`[arch] MCP 工具面零认证 —— 所有 agent 身份参数可自报，reserve_scope/lock_acquire 的角色判定本质上是 advisory`**

### 结论

**这不是「BUG-422 修不掉」，是「在无认证层的架构里，任何『自报身份』的设计都修不掉」。**

**证据链就是我 Q3 的四层读数：**
```
schema 层   "agent": string_prop("预订者（如 exec_1，必填）")   ← 无 format / 无 enum
工具层      let agent = get_str(args, "agent")                 ← 直接取
引擎层      infer_role_from_agent(agent) / resolve_agent_role(agent, declared)
            ← 用名字或查表，**从不校验「你是谁」**
store 层    agent 只作为字段值写入，**不参与鉴权**
```
**⇒ 四层无一处校验。`agent` 从入口到落库是纯自由文本。**

**同类面（同一个病）：** `reserve_scope`/`reserve_check`/`reserve_release` 的 `agent`；
`lock_acquire`/`lock_renew`/`lock_release` 的 `agent`；`claim`/`execute` 的 `assignee`/`executor`；
`agent_acl_grant` 的 `by`。

### 为什么现架构修不掉（三条硬约束）

| # | 约束 | 读数 |
|---|---|---|
| **C1** | 没有凭据字段 | `agents.pubkey_fp` **全空**（3/3 行 `''`） |
| **C2** | 唯一「服务端才知道」的值可算 | `pid = floor(Unix 秒) % 2e9`，反查得精确启动时刻 |
| **C3** | 没有会话层 | MCP 连接与 `agent` 标识**无绑定** |

**⇒ 任何「自报 + 校验」只能校验到「名字存在」，不能校验到「你是名字的主人」⇒ 角色判定本质是 advisory。**

### 出路（架构级投入）

| 方向 | 需要 | 量级 |
|---|---|---|
| **S1 会话绑定** | 连接时协商 `session_token`（服务端生成随机），`agents` 存 hash | 动 schema + 签名 + 全部身份类工具 |
| **S2 公钥凭据** | 填 `pubkey_fp`（字段已在），签名/验签 | 动 schema 使用 + 客户端改造，量级最大 |
| **S3 进程级绑定（最轻）** | 每个 MCP 客户端进程申请一次性 `agent_token` 写本地文件 | 动签名 + 客户端改造，不需真密码学 |

**⇒ 我倾向 S1 或 S3。S2 最正确但量级最大。**

### 与 BUG-403 的关系

Lane AB 说「长期仍需 BUG-403」——**我的实测支持**：`pid_bound` 回答「ACL 是不是本进程实例的」，
**不是「你是谁」**。若 BUG-403 做的是会话级身份，**它就是上面 S1**。
**⇒ 建议：让 BUG-403 成为这条架构账的**第一个切片**，或与它合流。**

---

## 12. 三条判例归档

### 判例 ①（统帅评：本年最重要）
> **可计算的值不是凭据。**
> `current_pid_token()` 名为 "pid"，实为**服务器启动时刻的 Unix 秒数** —— 不随机、可反推。
> **判断方法：问「这个值能不能被外部推导出来」—— 能，就不是凭据。**

### 判例 ②
> **「可选参数」不是安全措施。** 可选参数攻击者永远不传。
> **⇒ 任何「自报 + 校验」的设计，校验用的那一半必须不来自被校验方输入。**

### 判例 ③（统帅补，源于本单 §8）
> **「看起来零误伤」要问一句「是设计还是巧合」。**
> 那三条过期 pid 的 agent 本来就是 Executor，所以方案 A 落地时「零误伤」——
> **但那是它们恰好不需要高权，不是方案 A 设计得好。**
> **⇒ 任何「影响面为零」的读数，必须能回答「零是因为不可能发生，还是因为还没发生」。**

**我对 ③ 的实证补充**：`agent_write_gate` **确实**消费 `agent_acl.pid_bound`
（`store_sqlite.mbt:2976` 的 SQL `SELECT ... a.pid_bound, g.pid ... LEFT JOIN agents`）——
**我的「零误伤」读数只覆盖了 `reserve_scope`，没覆盖 `agent_write_gate`。这正是判例 ③ 要问的那一半。**

---

## 13. 【最终建议】BUG-422(b) 在现架构下**无可落地的修复** —— 转架构级

> **BUG-422(b)「让 `reserve_scope` 的身份不可自报」在现架构下没有可落地的修复。**
>
> **理由**：无凭据字段（`pubkey_fp` 全空）+ 唯一服务端值可算（`pid`）+ 无会话层
> ⇒ 任何校验只能确认「名字存在」，不能确认「你是名字的主人」。
>
> **可落地的部分只有两条，都属 BUG-421 范畴：**
> 1. **关整名白名单**（421 本体）
> 2. **拒绝 `agent="fist-mbt"` 自称**（§10.3，1 行 + 1 格测试，零语义变更）
>
> **剩余部分（任意自称真实登记名即可拿对应角色）：转架构级缺口，另立账，不与 BUG-422 绑定。**

**⇒ 这不是「修不掉就放弃」，是把「能修的」与「架构性的」精确切开，各归各账。**

---

## 7. 建议入档位置

1. **本方案**：`reports/2026-10-27-bug422b-identity-assertion-plan.md`
2. **判例候选 ①（本轮最重要）**：
   > **判例-XX：可计算的值不是凭据。**
   > `current_pid_token()` 名为 "pid"，实为**服务器启动时刻的 Unix 秒数** —— 它不是 OS PID、不随机、可反推。
   > **⇒ 它能当「进程实例指纹」用（判断"是不是同一次启动"），不能当「身份凭据」用（证明"你是谁"）。**
   > **判断方法：问「这个值能不能被外部推导出来」——能，就不是凭据。**
3. **判例候选 ②**：
   > **判例-XX：「可选参数」不是安全措施。** (b1) 的致命点：可选参数攻击者永远不传。
   > **⇒ 任何「自报 + 校验」的设计，校验用的那一半必须**不来自被校验方输入**。**
4. **待办（R7）**：确认「server 重启后其他 agent 的 `agents.pid` 是否重绑」。若不重绑，本方案会让
   **除 `fist-mbt` 外的所有已登记 agent 在重启后掉成 Executor** —— 这会是我们自己的 bug 换了个形状。

---

**本方案未修改 `src/` 任何文件。所有 diff 均为提案。未调 `bug_fix`。**
