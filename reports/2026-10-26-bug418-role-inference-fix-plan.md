# BUG-418 诊断与修复方案 · `infer_role_from_agent` 名字宽松推断 = 可主动利用的越权面

> **文种**：只读诊断 + 可粘贴 patch
> **日期**：2026-10-26 · **执行**：Lane S（commander-alpha）
> **边界**：**未改 `src/` 任何文件**（`src/engine/` `src/store/` `src/server/` 均被拒，`Executor` 无权）
> **所有行号、库读数均为本次现读**

---

## 结论

**选 (a) 角色显式声明 + 服务端校验，且必须配合 (b) 收窄推断 —— 单做 (a) 或单做 (b) 都不够。**

**一句话理由**：`agents` 表**已经有 `role` 列且默认 `'Executor'`**（`store_sqlite.mbt:133`）——
**权威来源早就存在，`infer_role_from_agent` 是绕过它的旁路**。真正的修法是**让权威来源生效**（(a)），
同时把旁路收窄到「只在权威面查不到时才会用到，且不给高角色」（(b)）。

| 项 | 值 |
|---|---|
| **推荐档位** | **(a) + (b) 组合**（见 §3） |
| **调用点** | **2 个**（`engine_rsv.mbt:18`、`:41`），都在**作用域预订**，不在四条受保护文件的写路径 |
| **权威来源** | `agents.role` 列（`store_sqlite.mbt:133`，默认 `'Executor'`），读法 `agents_get`（`:2831`） |
| **迁移影响面** | **几乎为零**（库内 2 个 active agent，无 `commander-*`/`leader-*` 命名，见 §5） |
| **仍存在的真实攻击面** | ✅ **代码面成立**——`agent` 是 MCP 工具入参、未经哈希，攻击者自称 `commander-x` 即可 |

---

## 证据：4 项事实核验（逐条读数）

### 事实① `infer_role_from_agent` 全仓调用点 = **2 个**

```
$ grep -rn "infer_role_from_agent" src/ --include=*.mbt
src/engine/engine_rsv.mbt:18:  let role = infer_role_from_agent(agent)
src/engine/engine_rsv.mbt:41:  let role = infer_role_from_agent(agent)
src/engine/engine_scope_perm.mbt:145:pub fn infer_role_from_agent(agent_name : String) -> String
```

**两个调用点都在 `rsv_set` / `rsv_try_set`（作用域预订）里**：

```moonbit
// engine_rsv.mbt:16-27
  // 权限门禁：先过权限，再预订（BUG-413 三态分流）
  let role = infer_role_from_agent(agent)
  match check_scope_permission(scope, role) {
    RoleDenied(e) => Err(e)        // ← HumanSteward 保护走这一档
    Allowed | Unregistered(_) => self.store.rsv_set(...)
  }
```

**⇒ 这是「作用域预订」的门，不是「写四条受保护文件」的门。**

### 事实② 有没有别的路径也能拿到角色？——**有，而且是权威面**

```
$ grep -rn "agents_get\|SELECT.*role.*FROM agents" src/store/store_sqlite.mbt
2831: pub fn SqliteStore::agents_get(
2838:   SELECT agent_id, agent_type, role, soldier, pid, pubkey_fp, ... FROM agents WHERE agent_id = ?
```

**⇒ `agents_get(agent_id)` 能读出 `agents.role` —— 这就是 (a) 的落点。**
**但 `engine_rsv.mbt` 当前完全没调它**（两个调用点都只用 `infer_role_from_agent`）。

**⚠️ 一个必须说清的细节**：`agent_fp(raw)` 把原始名哈希成 16 位指纹（`server.mbt:455`，
`@omega.fnv1a64("agent_id:" + raw)`）。**ACL / 注册路径用的是指纹，但 `rsv_*` 用的是原始名**
（`server.mbt:5089` 直接传 `agent~`）⇒ `infer_role_from_agent` 拿到的是**未哈希的原始字符串**，
**攻击面的前提成立**。

### 事实③ `agents` 表**有 `role` 列**

```
store_sqlite.mbt:133
CREATE TABLE IF NOT EXISTS agents (
  agent_id TEXT PRIMARY KEY,
  agent_type TEXT NOT NULL DEFAULT 'unknown',
  role TEXT NOT NULL DEFAULT 'Executor',      ← ★ 权威来源，默认 Executor（fail-closed）
  soldier TEXT NOT NULL DEFAULT '工兵',
  pid INTEGER NOT NULL DEFAULT 0,
  ...
)
```

**⇒ 权威来源早就在，且默认值是安全的 `'Executor'`。`infer_role_from_agent` 是个从不查它的旁路。**

### 事实④ `audit_permission` 与推断的关系

```
server.mbt:6093  工具注册
        fn(args) → @ops.Role::from_string(role_s)  ← 只接受 human_steward/leader/agent 三种字符串
```

**⇒ `audit_permission` 是「角色矩阵查询」，它只回答「这个角色名义上能做什么」，
完全不看 `agents` 表、也不看 `infer_role_from_agent`。**

**⇒ 这是 **第三道独立面**（BUG-408 记的「角色矩阵 vs ns ACL」两道门之外，预订门是第三道）：
| 门 | 判据 | 数据源 |
|---|---|---|
| ① 角色矩阵（`audit_permission`） | 角色名义能力 | 硬编码矩阵 |
| ② ns ACL（`agent_write_gate`） | `can_write` 列 | `agent_acl` 表 |
| **③ 作用域预订（BUG-418 所在）** | **角色** | **`infer_role_from_agent` 猜的** ← 病灶 |

**⚠️ 门 ③ 是三道门里**唯一**一个「角色来源是猜的」——另两道都查表。**

---

## 3. 修法：(a) + (b) 组合

### 3.1 为什么不单做 (a)

单做 (a) 要改 `agents_register` 的调用面（让 `human_steward` 显式赋 role），
**但 `rsv_*` 的 agent 是临时字符串**（未注册也能预订，见 `engine_rsv.mbt:24-25` 的 `Unregistered` 档）
⇒ **查不到 `agents.role` 的 agent 仍要有个兜底** ⇒ 兜底仍是 `infer_role_from_agent`。
**兜底不收窄，漏洞还在。**

### 3.2 为什么不单做 (b)

单做 (b) 把 `contains("commander")` 改成精确匹配 `== "human_steward"`，
**能堵住 `commander-fake`**，但 `agents.role` 里明明有权威数据却**永远不用**
⇒ 合法 Leader 只能靠改名字来获得 Leader 权限（**把权限表达绑定在名字上**，仍是坏设计）。

### 3.3 组合方案（推荐）

```
查 agents.role  →  查到 ⇒ 用它（role_source = "declared"）
                →  查不到 ⇒ 用收窄后的 infer_role_from_agent，且**最高只给 Executor/Leader，永不给 HumanSteward**
```

### 3.4 可粘贴 patch

#### patch 1：`src/engine/engine_scope_perm.mbt` —— 收窄推断 + 新增带来源的角色解析

```diff
--- a/src/engine/engine_scope_perm.mbt
+++ b/src/engine/engine_scope_perm.mbt
@@ -142,16 +142,52 @@
 ///|
-/// 从 agent 名字推断角色（宽松推断，不是安全门禁）。
-/// fail-soft：宁可放行也不要卡死开发。
+/// 从 agent 名字推断角色（**BUG-418 收窄后：只做缺省提示，不是授权依据**）。
+///
+/// ⚠️ BUG-418 前的实现用 `contains("commander")` 做子串匹配 ⇒
+/// 任何自称 `commander-fake` 的 agent 都能拿到 HumanSteward，进而过 HumanSteward 保护门。
+/// **那不是「文档不准」，是可主动利用的越权面。**
+///
+/// 收窄规则（BUG-418 裁决 (b)）：
+///   · **禁止**「前缀/子串命中即给高角色」
+///   · **永不**从名字推断出 HumanSteward —— 高角色必须显式声明（见 `resolve_agent_role`）
+///   · 只保留 `Leader` 一档的整名精确匹配，其余一律 Executor
+/// 这样即使有人起名 `commander-fake`，拿到的也只是 Executor。
 pub fn infer_role_from_agent(agent_name : String) -> String {
   let a = agent_name.to_lower()
-  if a.contains("commander") || a.contains("human_steward") || a == "human" {
-    "HumanSteward"
-  } else if a.contains("leader") ||
-    a.contains("lead") ||
-    a.contains("polish") ||
-    a.contains("optimization") {
+  // 整名精确匹配才有意义；子串/前缀一律不给高角色。
+  if a == "leader" || a == "lead" {
     "Leader"
   } else {
-    "Executor" // 默认最宽松
+    "Executor"
   }
 }

+///|
+/// 解析 agent 的**权威角色**与**来源**（BUG-418 裁决 (a)）。
+///
+/// 优先级：`agents.role`（显式声明，权威） > `infer_role_from_agent`（缺省提示）。
+///
+/// `declared` 由调用方查库传入（`agents_get(agent_id).role`），保持本函数纯、可单测、无 IO。
+/// 查不到（None / 空串）⇒ 退到推断，且**推断结果只可能是 Executor 或 Leader**（见上）。
+pub fn resolve_agent_role(
+  agent_name : String,
+  declared : String?,
+) -> (String, String) {
+  match declared {
+    Some(r) if r != "" => (r, "declared")
+    _ => (infer_role_from_agent(agent_name), "inferred")
+  }
+}
+
 ///|
```

#### patch 2：`src/engine/engine_rsv.mbt` —— 两个调用点改为查权威面

```diff
--- a/src/engine/engine_rsv.mbt
+++ b/src/engine/engine_rsv.mbt
@@ -15,10 +15,17 @@ pub fn FistEngine::rsv_set(
   created_at~ : String,
 ) -> Result[String, String] {
   // 权限门禁：先过权限，再预订（BUG-413 三态分流）
-  let role = infer_role_from_agent(agent)
+  // BUG-418：角色先查权威面 `agents.role`（显式声明），查不到才退到收窄后的推断。
+  // 旧实现只用名字推断 ⇒ 自称 `commander-*` 即可拿 HumanSteward（可主动利用的越权面）。
+  let declared = match self.store.agents_get(agent_fp_of(agent)) {
+    Some(a) => Some(a.role)
+    None => None
+  }
+  let (role, _role_source) = resolve_agent_role(agent, declared)
   match check_scope_permission(scope, role) {
```

**⚠️ `agent_fp_of` 与 `agents_get` 的返回结构我未逐字核实**，应用前需：
```bash
grep -n "fn agent_fp" src/server/server.mbt            # 确认它在 engine 包可见性
grep -n "pub fn SqliteStore::agents_get" -A 8 src/store/store_sqlite.mbt   # 确认返回 struct 的字段名
grep -rn "fn agents_get" src/engine/engine.mbt          # 确认 engine 层有没有透传
```
**⇒ 若 `agent_fp` 是 `server.mbt` 的私有函数，engine 层需要自己算指纹（`@omega.fnv1a64("agent_id:" + raw)`）。**
**不给一个可能编不过的 patch。**

同样改法用于 `rsv_try_set`（`engine_rsv.mbt:41`）。

---

## 4. 三条锁设计（成对 + 变异对照）

### 锁 1（**本缺陷的反例格**）：`commander-fake` 拿不到 HumanSteward

```moonbit
test "bug418_commander_prefixed_name_gets_no_humansteward" {
  // 这是 BUG-418 的现场复现：修前返回 "HumanSteward"，修后必须 "Executor"
  assert_eq(infer_role_from_agent("commander-fake"), "Executor")
  assert_eq(infer_role_from_agent("commander"), "Executor")      // 连整名 commander 也不给
  assert_eq(infer_role_from_agent("human_steward"), "Executor")  // 名字自证不算数
  assert_eq(infer_role_from_agent("human"), "Executor")
  // 且 resolve 时没有 declared 也拿不到
  assert_eq(resolve_agent_role("commander-fake", None).0, "Executor")
}
```

### 锁 2（正例，防修过头）：显式声明 ⇒ 拿到 HumanSteward

```moonbit
test "bug418_declared_role_wins" {
  let (r, src) = resolve_agent_role("any-name-at-all", Some("HumanSteward"))
  assert_eq(r, "HumanSteward")   // 名字无关紧要，声明说了算
  assert_eq(src, "declared")
  // 对照：无声明 ⇒ 推断，且来源标记为 inferred
  let (r2, src2) = resolve_agent_role("leader", None)
  assert_eq(r2, "Leader")
  assert_eq(src2, "inferred")
}
```

### 锁 3（⭐ 变异对照，判例-29/30）

```moonbit
test "bug418_variant_substring_rule_must_break_lock1" {
  // 【变异对照】本格证明锁 1 真在看规则，而不是恒绿。
  // 变异：把 infer_role_from_agent 改回 `contains("commander")` ⇒ 锁 1 的第一条必红。
  //
  // ⚠️ 判例-30 防护：本格**不断言源码字符串**（那会命中注释里的字面量 ⇒ 自指假绿），
  // 只断言**行为**：对所有可能被 contains 命中的名字，角色必须是 Executor。
  let attack_names = [
    "commander", "commander-fake", "my-commander", "COMMANDER",
    "human_steward", "human_steward-x", "human", "HUMAN",
  ]
  for n in attack_names {
    let r = infer_role_from_agent(n)
    if r == "HumanSteward" {
      fail("BUG-418 回归：\{n} 拿到了 HumanSteward —— 子串规则被改回去了")
    }
  }
  // 反向：合法 Leader 仍能拿到（防修过头把 Leader 也砍了）
  if infer_role_from_agent("leader") != "Leader" {
    fail("BUG-418 修过头：整名 leader 拿不到 Leader")
  }
}
```

**锁 3 的设计要点**：`attack_names` 里的 `COMMANDER`（大写）专抓「忘记 `to_lower()`」的变异；
`my-commander`（后缀）专抓「只判 `starts_with`」的变异。

### 锁 4（⭐ 补：钉住「(a) 真生效」而不是静默失效）

```moonbit
test "bug418_declared_lookup_must_use_fingerprint" {
  // 这是 §5.4 那个陷阱的锁：若 patch 2 直接用 agents_get(agent)（不哈希），
  // declared 恒为 None ⇒ (a) 静默失效、role_source 恒 "inferred"、行为等于只做了 (b)。
  // 本格钉住「查询用的键」这件事本身。
  let raw = "exec_1"
  let fp = agent_fp_raw(raw)
  // 前置：该 agent 已注册（夹具里先 agents_register 一次）
  if agents_get(fp) is None {
    fail("夹具前置不成立：指纹键查不到")
  }
  if agents_get(raw) is Some(_) {
    fail("BUG-418: 原始名居然能查到 —— 说明键不是指纹，patch 2 的前提变了")
  }
  // 端到端：走完 resolve，declared 必须真被取到
  let declared = match agents_get(fp) {
    Some(a) => Some(a.role)
    None => None
  }
  let (r, src) = resolve_agent_role(raw, declared)
  if src != "declared" {
    fail("BUG-418: 已注册 agent 却没走 declared 路径 ⇒ 哈希漏了，修了个寂寞")
  }
}
```

**为什么这条锁值钱**：它是「**修了但没生效**」这一类的通用防线。
`(a)` 的机制（查库）与「查库用的键」（指纹）是**两件事** ——
**只测「查了库」不测「查的键对」**，就是判例-29 说的「机制格 ≠ 实现路径格」。

---

## 5. 迁移影响面（**必须明说**）

### 5.1 库内实数

```
$ SELECT agent_id, role FROM agents WHERE status='active'
  active agents 共 2 个
  ⚠ b2acdbf4c6cea9fe   store=Leader   推断=Executor   ← store 与推断不一致（1 个）

  agent_id 全部是 16 位指纹哈希，**没有任何可读的 commander-*/leader-* 名字**
```

**⇒ 迁移影响面 = 几乎为零。** 理由：
1. 库内 agent 名字是**指纹**（`agent_fp` 哈希后），不含 `commander`/`leader` 子串 ⇒ 旧推断对它们**本来就返回 Executor**
2. 新推断对非 `leader`/`lead` 整名也返回 Executor ⇒ **行为不变**
3. `b2acdbf4c6cea9fe` 的 `store.role=Leader` 在**修前就已被推断为 Executor**（推断从不看 store）
   ⇒ **(a) 修完后它反而会拿到 Leader**（从「被误降级」变成「正确」）

### 5.2 会掉级的真实场景（代码面，非库内）

| 场景 | 修前 | 修后 | 影响 |
|---|---|---|---|
| agent 自称 `commander-xxx` | HumanSteward | **Executor** | ✅ **这是要修的** |
| agent 自称 `leader-xxx` | Leader | **Executor** | ⚠️ **会掉级** —— 若某 lane 靠 `leader-xxx` 名字预订 `src/engine/` 之类 Leader-only 路径，**修后会拿不到预订** |
| agent 自称 `polish-xxx` / `optimization-xxx` | Leader | **Executor** | ⚠️ 同上（这两个泛词命中面最广） |
| agent 名 `leader` / `lead`（整名） | Leader | Leader | ✅ 不变 |

**⇒ 真正会掉级的是「靠名字前缀拿 Leader」的 lane。** 缓解：
- 修完 (a) 后，这些 lane 只要**在 `agents` 表里有 `role=Leader` 的登记**，就仍然拿到 Leader —— **(a) 正好补上这条正道**
- 建议 patch 落地时**同时给现有活跃 lane 补 `agents.role`**（用 `agents_register` 带 role，或直接 SQL 更新）

### 5.3 三条不变量怎么保证

| 不变量 | 保证方式 |
|---|---|
| **① HumanSteward 保护不能变松** | `check_scope_permission` 的 `RoleDenied` 分支**完全没动**；`infer_role_from_agent` 现在**永不返回 HumanSteward** ⇒ 更严不更松 |
| **② 合法 agent 不被误伤** | 两条路走通：整名 `leader`/`lead`，或在 `agents.role` 显式声明 Leader（锁 2 钉住） |
| **③ 不能只改注释** | patch 改的是**两个分支的判定表达式**与**新增函数**；锁 1/3 断言**行为**（返回值），不断言注释 |

---

### 5.4 ⭐ R3 实测结论：键不同源，patch 必须哈希

**`reserve_scope` 的 `agent` 是调用方自由填写的原始字符串**（工具文档示例就是 `exec_1`）：

```moonbit
// server.mbt:5072
"agent": string_prop("预订者（如 exec_1，必填）")
// server.mbt:5084
let agent = get_str(args, "agent")
// server.mbt:5089
match engine.rsv_try_set(scope~, agent~, ...)   ← 原始名字直接透传，未哈希
```

**而 `agents.agent_id` 全部是 16 位指纹**（现读）：
```
id=b2acdbf4c6cea9fe   type=server    role=Leader
id=c335207187d95324   type=execute   role=Executor
非 16 位的 agent_id：（全部是 16 位指纹）
```

**⇒ 两者不同键。patch 2 必须写成：**

```moonbit
let declared = match self.store.agents_get(agent_fp_raw(agent)) {
  Some(a) => Some(a.role)
  None => None
}
```

**其中 `agent_fp_raw` = `@omega.fnv1a64("agent_id:" + raw)`**（与 `server.mbt:455` 的 `agent_fp` 同一算法）。

**⚠️ 硬前提**：若直接 `agents_get(agent)`（不哈希），**永远查不到** ⇒ (a) 静默失效、
只剩 (b) 生效、`role_source` 恒为 `"inferred"`。**这是一个「看起来修了、实际没修」的陷阱**——
建议 patch 落地时**加一条锁专门钉它**：

```moonbit
test "bug418_declared_role_lookup_uses_fingerprint" {
  // 用一个已注册的 agent（agent_id = fnv1a64("agent_id:" + name)）验证：
  // 传原始名查不到，传指纹查得到。若实现漏了哈希，本格必红。
  assert_eq(agents_get(agent_fp_raw("exec_1")), ...)   // 查得到
  assert_eq(agents_get("exec_1"), None)                 // 原始名查不到
}
```

---

## 6. 缺口与风险

| # | 项 | 说明 |
|---|---|---|
| **R1** | **我无权改 `src/`** | `src/engine/` `src/store/` `src/server/` 均被 `reserve_scope` 拒绝（`Executor` 无权）⇒ 只出 patch |
| **R2** | **`agents_get` 在 engine 层的可见性未核** | patch 2 用了 `self.store.agents_get(agent_fp_of(agent))`。**应用前需核 3 处**（见 §3.4 的 grep 清单）。若 `agent_fp` 是 `server.mbt` 私有，engine 需自算 `@omega.fnv1a64` |
| **R3** | ~~`rsv_*` 的 agent 与 `agents.agent_id` 未必同键~~ | ✅ **已实测消解**（见 §5.4）：两者**不同键**，`rsv_*` 收原始名、`agents.agent_id` 是 16 位指纹。**⇒ patch 2 必须写 `agents_get(agent_fp(agent))`，直接传原始名永远查不到。这条是应用 patch 的硬前提** |
| **R4** | **三道门里只有第③道会被修** | `audit_permission`（①）与 `agent_write_gate`（②）都不经 `infer_role_from_agent` ⇒ **修完后它们的行为不变**。但「三道门角色来源不一致」这个结构问题**依然存在**（①硬编码矩阵、②查 ACL、③查 store+推断） |
| **R5** | **未做运行时复现** | 需起 MCP server 进程 + 自称 `commander-fake` 发起 `reserve_scope`。超出「只读 + 写 reports/」边界。**锁 1 就是它的纯函数版复现** |
| **R6** | **`b2acdbf4c6cea9fe` 为何 store=Leader** | 未查它的来源（谁给它登的 Leader）。**如实标注未查** |

---

## 7. 建议入档位置

1. **本报告**：`reports/2026-10-26-bug418-role-inference-fix-plan.md`
2. **判例候选**：
   > **判例-XX：「不用于安全」的注释不能替代硬门。**
   > `infer_role_from_agent` 的注释写「宽松推断，**不是安全门禁**」，
   > 但 `engine_rsv.mbt` 两个调用点**拿它的返回值直接决定 RoleDenied / 放行**。
   > **⇒ 注释说不用于安全、代码却用于安全，等于两者都不可信。**
   > 判断方法：**看返回值是否进了 `if`/`match` 的分支选择**，而不是看注释怎么说。
3. **结构性建议**（R4）：三道门的角色来源应统一为 `agents.role` 单一真源，
   `audit_permission` 的硬编码矩阵降级为「角色名 → 能力」的展示层。**那是大改，另单。**
4. **落地时的配套动作**（§5.2）：patch 应用时**同时给现有活跃 lane 补 `agents.role`**，
   否则原来靠名字前缀拿 Leader 的 lane 会掉级。

---

**本报告未修改 `src/` 任何文件。未 commit。所有 diff 均为提案。**
