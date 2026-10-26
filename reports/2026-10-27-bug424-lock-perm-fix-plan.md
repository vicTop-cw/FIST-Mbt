# BUG-424 · `lock_acquire`/`lock_renew` 权限门 · 精确 patch · Lane AA · 2026-10-27

> **交付形态**：`src/engine/` 受保护（Leader 级）⇒ **出 patch 由统帅应用**；
> `src/store/store_rsv.mbt` **不在保护名单**（`scope_permissions` 无 `src/store/` 通配）⇒ 本 lane 可改。
> 本报告含两个可粘贴 patch（store 侧 helper + engine 侧接线）与 4 格锁设计。

---

## 一、结论

### 1.1 注释里那个技术障碍：**已经不存在了**（类型系统限制从来就不是真障碍）

注释原文（`engine_rsv.mbt:108-110`，**写于 2026-10-22，已挂 4 天**）：
```
注：锁的权限门禁**暂时没接**——LockAcquireOutcome 是 read-only 类型，
必须在 store 内部创建；将来会在 store_rsv 层加一个 permission_denied 构造器。
目前先跳过锁的权限检查，等后端扩展。
```

**逐条核验**：

| 注释的说法 | 实测 | 判定 |
|---|---|---|
| `LockAcquireOutcome` 是「read-only 类型」 | `store_rsv.mbt:225-237`：`pub struct LockAcquireOutcome { granted : Bool, action : String, prev_agent : String, agent : String, ttl_until : String, violation_logged : Bool } derive(Debug)` —— **没有任何 `read-only` / `readonly` 标记**（`grep read-only\|readonly\|read_only` → 0 命中）| ❌ **说法不成立** |
| 「必须在 store 内部创建」 | **对**：字段是**包内私有**（无 `pub` 修饰符）⇒ 跨包 struct literal 被编译器拒绝。这一点 BUG-413 已实测（`RsvOutcome::relabel` 的注释原文：「跨包 struct literal 会被编译器拒绝（实测 4036/4033）」）| ✅ 成立 |
| 「将来会在 store_rsv 层加一个 permission_denied 构造器」 | **BUG-413 已经这么做了**：`store_rsv.mbt:81` `pub fn RsvOutcome::relabel(self, action : String) -> RsvOutcome` —— 正是「在 store 层加构造器」的原型 | ✅ **模式已存在，只是没人给 Lock 补一份** |

**⇒ 结论：障碍不是「类型系统不允许」，而是「没人给 `LockAcquireOutcome` 补一个同款 helper」。**
补一份 `relabel` 即可，**完全不需要「后端扩展」**。注释的理由已过期 4 天。

### 1.2 修法

| 层 | 改什么 |
|---|---|
| **store 侧**（本 lane 可改） | `store_rsv.mbt` 新增 `LockAcquireOutcome::relabel(self, action, granted) -> LockAcquireOutcome`（照 `RsvOutcome::relabel` 的形状，多一个 `granted` 参数——因为「拒绝」要同时改 granted 与 action） |
| **engine 侧**（受保护，出 patch） | `FistEngine::locks_try_acquire` 接 `check_scope_permission`：`RoleDenied` ⇒ 回 `relabel(.., action="permission_denied", granted=false)`；`Unregistered` ⇒ 正常抢锁但 `action` 标 `unregistered`；`Allowed` ⇒ 原样 |

### 1.3 `lock_renew` 历史遗留：**不拒绝、但标痕**（建议）

**关键事实**：`lock_renew` **没有自己的引擎层函数** —— 它在工具面（`server.mbt:5279`）**直接复用 `engine.locks_try_acquire(renewed)`**：
```
// 与 lock_acquire 同一个写通道（BUG-145 + 提案 G：acquire/renew 不再两套规则）
let o = engine.locks_try_acquire(renewed)
```
⇒ **接了 `locks_try_acquire` 的权限门，`lock_renew` 自动被覆盖**，不需要单独改。
（这消除了任务书里「acquire/renew 要不要各接一次」的疑问——它们本来就是同一个门。）

**但 `lock_renew` 的语义问题必须单列**（任务书 §②）：

> 一个 Executor 在权限门接上**之前**可能已经持有 `src/engine/` 的锁，现在它要续期。

**两条路的后果**：

| 做法 | 后果 |
|---|---|
| **拒绝** | 该 agent **卡死**：它持有锁却续不了期，锁到期后自动失效，它既拿不回来（新门拒绝）也没法优雅收尾 ⇒ **制造僵尸锁 + 僵尸持有人** |
| **放行** | 等于承认历史遗留：低权 agent 继续把持高权工作面，**攻击面没关** |

**我的建议：第三条路 —— 放行续期，但强制留痕并禁止扩大**：

1. **`lock_renew` 路径允许续期**（不因权限而拒）——理由：拒绝会把「历史遗留」升级成「僵尸」，
   而僵尸锁**比历史遗留更难清理**（僵尸没人负责，遗留至少有主）。
2. **但必须留痕**：续期时若 `check_scope_permission` 为 `RoleDenied`，在回执里加
   `permission_warning: "本锁系权限门接通前取得；续期已放行，但不视为授权通过"`，
   并写一条 `LockViolation(reason="renew_after_denied")` —— **让遗留可计数**。
3. **禁止扩大**：只允许「用**相同 scope**、相同 agent」续期（现有逻辑已保证），
   **不允许借此拿到新 scope**。`lock_acquire` 仍然硬拒。

**为什么不在这一步就拒绝**：现在拒绝的收益是「关掉攻击面」，成本是「立刻制造 N 个僵尸」；
而**先留痕统计再清理**能拿到真实存量。若统帅要「立即硬拒」，patch 改一行即可（见 §二.3 的 `--strict-retro` 变体）。

---

## 二、可粘贴 patch

### 2.1 patch ①（store 侧，**本 lane 可直接应用**）：`src/store/store_rsv.mbt`

```diff
--- a/src/store/store_rsv.mbt
+++ b/src/store/store_rsv.mbt
@@ (插入在 LockAcquireOutcome 的 Debug extend 之后，约 L241 后)
+
+///|
+/// BUG-424：锁裁决结果的**受控改写**（与 `RsvOutcome::relabel` 同款手法）。
+///
+/// 为什么需要它：`LockAcquireOutcome` 的字段是**包内私有**，`engine_rsv` 跨包无法构造
+/// struct literal（编译器拒绝，BUG-413 已实测 4036/4033）。而锁的权限门需要在
+/// 「角色无权」「未登记路径」两种情况下改写 action/granted，故必须有本 helper。
+///
+/// **本函数不改变任何裁决事实** —— 只改标签与 granted，agent/ttl_until/violation_logged
+/// 一律原样透传（谁持有、持到什么时候，仍由库里现值说话）。
+pub fn LockAcquireOutcome::relabel(
+  self : LockAcquireOutcome,
+  action : String,
+  granted : Bool,
+) -> LockAcquireOutcome {
+  LockAcquireOutcome::{
+    granted,
+    action,
+    prev_agent: self.prev_agent,
+    agent: self.agent,
+    ttl_until: self.ttl_until,
+    violation_logged: self.violation_logged,
+  }
+}
```

**为什么多一个 `granted` 参数**（与 `RsvOutcome::relabel` 不同）：`RsvOutcome` 只在「advisory 登记**成功**」时改标签（`reserved` 恒 true），
而锁这边要表达**拒绝**（`granted=false` + `action="permission_denied"`）⇒ 必须能改 granted。

### 2.2 patch ②（engine 侧，**受保护，出 patch**）：`src/engine/engine_rsv.mbt`

```diff
--- a/src/engine/engine_rsv.mbt
+++ b/src/engine/engine_rsv.mbt
@@
-///|
-/// 按裁决抢锁（BUG-145）：互斥由后端定，工具面只渲染结论——不许在这里先读后写。
-/// 注：锁的权限门禁**暂时没接**——LockAcquireOutcome 是 read-only 类型，
-/// 必须在 store 内部创建；将来会在 store_rsv 层加一个 permission_denied 构造器。
-/// 目前先跳过锁的权限检查，等后端扩展。
-pub fn FistEngine::locks_try_acquire(
-  self : FistEngine,
-  lock : @store.FileLock,
-) -> @store.LockAcquireOutcome {
-  self.store.locks_try_acquire(lock)
-}
+///|
+/// 按裁决抢锁（BUG-145）：互斥由后端定，工具面只渲染结论——不许在这里先读后写。
+///
+/// **BUG-424：权限门已接**。原注释（2026-10-22）称「LockAcquireOutcome 是 read-only 类型，
+/// 必须在 store 内部创建」——实测该说法不成立：字段只是**包内私有**（跨包 literal 被拒），
+/// 与「read-only」无关；而 store 侧已有 `LockAcquireOutcome::relabel` 同款构造器
+/// （参照 `RsvOutcome::relabel`，BUG-413 已立此模式）。⇒ **无需任何后端扩展**。
+///
+/// 三态语义与 `check_scope_permission` 一致（BUG-413）：
+///   · RoleDenied   ⇒ 硬拒：`granted=false` + `action="permission_denied"`，**不写库**
+///   · Unregistered ⇒ advisory：正常抢锁，但 `action` 标 `unregistered`（拿到时）
+///   · Allowed      ⇒ 原样
+pub fn FistEngine::locks_try_acquire(
+  self : FistEngine,
+  lock : @store.FileLock,
+) -> @store.LockAcquireOutcome {
+  let role = infer_role_from_agent(lock.agent)
+  match check_scope_permission(lock.scope, role) {
+    RoleDenied(_) =>
+      @store.LockAcquireOutcome::{
+        granted: false,
+        action: "permission_denied",
+        prev_agent: "",
+        agent: "",
+        ttl_until: "",
+        violation_logged: false,
+      }.relabel("permission_denied", false)
+    Unregistered(_) => {
+      let o = self.store.locks_try_acquire(lock)
+      if o.granted {
+        o.relabel("unregistered", true)
+      } else {
+        o
+      }
+    }
+    Allowed => self.store.locks_try_acquire(lock)
+  }
+}
```

**⚠️ 上面 `RoleDenied` 分支写得别扭**（先构造再 relabel 是冗余的）。
**更干净的写法**（推荐用这个，但需要 store 侧再暴露一个 `denied(...)` 构造器）：

```moonbit
    RoleDenied(_) => @store.LockAcquireOutcome::denied_by_permission()
```
配套 store 侧补：
```moonbit
///|
/// BUG-424：权限拒绝态的规范构造（`granted=false` + `action="permission_denied"`，库里无对应行）。
pub fn LockAcquireOutcome::denied_by_permission() -> LockAcquireOutcome {
  LockAcquireOutcome::{
    granted: false,
    action: "permission_denied",
    prev_agent: "",
    agent: "",
    ttl_until: "",
    violation_logged: false,
  }
}
```
**两个 patch 二选一**：只加 `relabel` 则用前一种写法；同时加 `denied_by_permission` 则用后者（**更推荐**，语义更直白）。

### 2.3 `lock_renew` 的留痕变体（可选，若统帅采纳 §1.3 建议）

`lock_renew` 走 `locks_try_acquire`，**自动继承门**。但要「放行续期 + 留痕」，需在**工具面**区分。
`server.mbt:5279` 处：

```diff
--- a/src/server/server.mbt
+++ b/src/server/server.mbt
@@
           let o = engine.locks_try_acquire(renewed)
+          // BUG-424：lock_renew 复用 locks_try_acquire，故自动继承权限门。
+          // 若本 agent 对 scope 已无权（权限门接通前取得的锁），续期**放行但留痕**：
+          // 拒绝会把「历史遗留」升级成「僵尸锁」（持有者续不了、锁到期后谁也拿不回）。
+          let perm_warn = if o.action == "permission_denied" {
+            "本锁系权限门接通前取得；续期已放行，但不视为授权通过"
+          } else {
+            ""
+          }
           Ok(
             @mcp.ToolResult::text(
               Json::object({
                 …
+                "permission_warning": Json::string(perm_warn),
```

> **注意**：这一支要求 `lock_renew` 在 `permission_denied` 时**不直接返回拒绝**，
> 而是「以旧锁事实为准继续」——需要在工具面把 `o.granted == false && o.action == "permission_denied"`
> 特判为「放行续期」。**这是唯一需要改 `server.mbt` 的地方**，且它受 HumanSteward 保护 ⇒ 由统帅应用。

---

## 三、4 格锁设计（+ 变异对照）

新增 `src/engine/lock_perm_wbtest.mbt`（同目录 ⇒ 受保护，出 patch）：

```moonbit
///|
/// 锁 1：Executor 抢 `src/engine/` 的锁 ⇒ **被拒**（granted=false, action="permission_denied"）
test "lock_perm_wb1_executor_denied_on_engine" {
  let eng = ... // 内存后端引擎
  let lock = @store.FileLock::{ lock_id: "L1", batch_id: "B", scope: "src/engine/x.mbt",
                               agent: "exec-1", ttl_until: "2026-10-28T00:00:00+08:00",
                               ts: "2026-10-27T00:00:00+08:00", ... }
  let o = eng.locks_try_acquire(lock)
  assert_false(o.granted)
  assert_eq(o.action, "permission_denied")
}

///|
/// 锁 2：Leader 抢同一 scope ⇒ **拿到**（防修过头）
test "lock_perm_wb2_leader_allowed_on_engine" {
  let o = eng.locks_try_acquire(lock_with_agent("lead-1"))
  assert_true(o.granted)          // infer_role_from_agent("lead-1") = Leader
}

///|
/// 锁 3：Executor 抢 `scripts/` ⇒ 拿到（本就对 Executor 开放）
test "lock_perm_wb3_executor_allowed_on_scripts" {
  let o = eng.locks_try_acquire(lock_with_scope("scripts/x.py"))
  assert_true(o.granted)
}

///|
/// 锁 4：**Unregistered 走 advisory**（与 BUG-413 三态一致）
test "lock_perm_wb4_unregistered_is_advisory" {
  let o = eng.locks_try_acquire(lock_with_scope("reports/x.md"))  // reports/ 无规则
  assert_true(o.granted)          // advisory 放行
  assert_eq(o.action, "unregistered")   // 但标签能区分
}
```

**变异对照（判例-29/30）**：
- **M1**：把 patch ② 的 `match check_scope_permission(...)` 整段删掉、恢复 `self.store.locks_try_acquire(lock)` ⇒ **锁 1 必红**（Executor 变成能拿到）
- **M2**：把 `RoleDenied` 分支改成 `Allowed` ⇒ **锁 1 必红**
- **M3**：把 `Unregistered` 分支的 `relabel("unregistered", true)` 改回直接返回 `o` ⇒ **锁 4 必红**
- 全部变异**只改代码、不改注释**；锁只断言 `o.granted` / `o.action` 的**返回值**，
  **不断言源码里有某字符串**（否则命中注释 ⇒ 判例-30 自指假绿）。

---

## 四、分析：为什么挑这条路

### 4.1 为什么在 `locks_try_acquire` 接门，而不是在工具面接

- **`lock_acquire` 与 `lock_renew` 共用这一个通道**（`server.mbt:5279` 注释原文：「acquire/renew 不再两套规则」）
  ⇒ 在引擎层接一次 = 两条路径同时覆盖，**天然不会漏**。
- 若在工具面各接一次，就**复制了两份判据** —— 那正是本仓反复批评的「同一语义两份实现」
  （BUG-424 的同族案例：`09c0867c` 只修了 `bug_lines_to_text` 一条路，`report_bug` 漏了）。

### 4.2 为什么复用 `ScopeVerdict` 三态（回答任务书 §④）

**复用**。理由：
1. 权限判据的**语义**只有一套：够格 / 不够格 / 没人管。锁和预订只是两个**消费方**，
   没有理由各自定义一套三态。
2. BUG-413 已把三态立起来；锁直接 `match check_scope_permission(...)` 即可，
   **零新增判据代码**（只新增「三态 → LockAcquireOutcome」的映射）。
3. 复用后，**动作标签在两个通道上一致**（`unregistered` 在两边都表示「advisory 放行」），
   调用方不必记两套词汇。

**唯一差异**：`LockAcquireOutcome` 需要一个 `granted=false` 的拒绝态，而 `RsvOutcome` 在
`RoleDenied` 时是**返回 `Err`**（不进 outcome）。⇒ 锁这边**不用 Result，用 outcome 的
`permission_denied` action 表达拒绝**。这个差异的理由见 §4.3。

### 4.3 为什么锁用 action 而不是 Err 表达拒绝

`locks_try_acquire` 的签名是 `-> @store.LockAcquireOutcome`（**无 Result**）。
改成 `Result[_, String]` 会波及 3 处调用方（工具面 acquire/renew + 可能的 sweep），
**属接口变更**。而 `action` 字段本就是 `String`、本就承载 `conflict`/`taken_over` 等否定态
⇒ **加一个 `permission_denied` 取值是最小侵入**，且与既有 `conflict` 的读法一致。

---

## 五、缺口与风险

### 5.1 ⚠️ 接门后已有的锁怎么办（任务书点名）

**实测：本机库里现在有没有 Executor 持有 `src/engine/` 的锁？** —— **未核**（引擎层接口要求真实 store，
本 lane 只能在 `--selftest` 之外另写脚本查；建议统帅应用 patch 前先跑一次 `lock_status` 全表扫）。

**已确定的处置原则**（§1.3）：
- `lock_acquire` **硬拒**（新锁拿不到）
- `lock_renew` **放行但留痕**（不制造僵尸）
- 建议另开一单做「存量清理」：列出 `RoleDenied` 且仍 active 的锁，逐个 `lock_release` 后重取

### 5.2 `permission_denied` 时不写库 ⇒ `violation_logged=false`

当前 patch 的 `RoleDenied` 分支**完全不碰 store** ⇒ 不会写 `lock_violations`。
**是否应该记一条违例**？两种意见：
- **不该**：`lock_violations` 语义是「**锁**层面的违例」（抢别人的锁），权限拒绝是**更早一道门**，
  混进去会污染 `lock_denied` 的统计口径。
- **该**：拒绝尝试本身就是安全事件，值得审计。

**我的建议：不写 `lock_violations`**（保持该表语义纯净），但如果统帅要审计，
应在**工具面**另记一条（或复用 `audit_log`），**不要混入 lock_violations**。

### 5.3 `infer_role_from_agent` 是名字推断（承自 BUG-413 的同一缺口）

`lock.agent` 是调用方自报的字符串，`infer_role_from_agent` 按名字含 `lead`/`polish` 判 Leader
⇒ **一个 Executor 只要把 agent 名字写成 `lead-xxx` 就能绕过本门**。
**这不是本 patch 引入的**，而是整个权限体系的前提假设。
**已在 BUG-413 报告中记为独立安全面缺口，本 patch 不修**（修它要引入可信身份，属架构级变更）。

### 5.4 未跑编译 / 未跑测试

`src/engine/` 改不了 ⇒ **patch 未编译验证**。锁代码里的 `@store.FileLock` 构造参数表
（`lock_id`/`batch_id`/`scope`/`agent`/`ttl_until`/`ts`/…）需按实际 struct 补全；
`assert_eq` 对 `String` 的比较按本仓既有 wbtest 惯例写。

### 5.5 `locks_upsert` 仍是**无门**的裸通道

`engine_rsv.mbt:99` 的 `locks_upsert` 直接 `self.store.locks_upsert(lock)`，**没有权限门**。
本 patch **未覆盖它** —— 若它对外暴露（工具面 `lock_acquire` 是否走 `locks_upsert`？实测：**不走**，
走的是 `locks_try_acquire`），则攻击面已关闭；但**若将来有人用 `locks_upsert` 直连**，门会被绕过。
**建议在 `locks_upsert` 上补一行注释警告**（不出门，因为它是底层原语，加门会破坏 `locks_sweep` 等内部路径）。

---

## 六、建议入档位置

| 内容 | 位置 |
|---|---|
| patch ①（store relabel/denied_by_permission） | 本 lane **可直接应用**（`src/store/` 不受保护）——若统帅要我落，说一声 |
| patch ②（engine 接线） | 受保护，统帅应用；应用后本报告即 BUG-424 的 `- patch:` 链接 |
| 「注释理由过期 4 天」 | 判例集：**注释里的技术障碍会随代码演进而失效，必须复核**（同族：判例「文档即实现」） |
| `locks_upsert` 无门警告 | 建议单开（或本轮 patch 附注释） |
| `lock_renew` 历史遗留处置原则 | BUG-424 追记 |
