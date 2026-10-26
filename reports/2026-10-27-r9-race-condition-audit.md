# R9 并发/竞态审计报告 · 方向 C

> **任务**：① `rsv_try_set` / `locks_try_acquire` 当前调用链逐行拆解（含 TOCTOU 判定）
> ② BUG-136 / BUG-145 收口纪律是否仍成立 ③ 扫新竞态面
> **执行人**：司令-γ · **边界**：只读 + 写报告，**未改任何 `src/` `scripts/`**（在途 17 文件不动）
> **产出**：本报告 + `temp/audit/lane_ad_*.py` + 1 条 `report_bug`

---

## 结论

| 问题 | 结论 |
|---|---|
| **`agents_get` 与 `store.rsv_try_set` 之间有 TOCTOU 吗？** | **裁决级没有**（§1.2 论证）。但 `legacy_grant` 有**标签缺陷**（§1.4） |
| **`locks_try_acquire` 的 `locks_get` + `locks_try_acquire` 是先读后写吗？** | **不是**（就裁决而言）。**统帅这处没写错** —— §1.3 逐问论证 |
| **BUG-136 / BUG-145 纪律还成立吗？** | **成立**，四段新逻辑逐条核对未破坏（§2） |
| **找到几条真 bug** | **1 条**：`BUG-429` [medium] —— `legacy_grant` 无条件贴「续期成功」标签 |

**⭐ 对你那句「我可能就是那个破坏纪律的人」的直接回答**：
> **不是。** 你这处 `locks_get` + `locks_try_acquire` 虽然字面上是两次 IO，
> 但**读到的值不参与裁决** —— 它只决定「进不进 legacy 分支」，
> 进入后 `granted` 完全由后端 `ON CONFLICT ... WHERE` + 写后回读定。
> **这不构成 BUG-145 所禁的「先读后写」。**
>
> 但你在那一行**写漏了一个 `if`**：`o.relabel("renewed_legacy_grant", o.granted)` 无条件改标签，
> `granted=false` 时回执会自称「续期成功」。**这是标签错，不是竞态** —— 已报 `BUG-429`。
> 同文件的 `Unregistered` 分支（`:213-220`）写对了这个 `if`，**legacy 分支漏抄**。

---

## 证据

### §1 两条调用链逐行拆解

#### 1.1 `rsv_try_set`（`engine_rsv.mbt:57-109`）

```
rsv_try_set(scope, agent, ttl_until, created_at)
  ├─ :66  agents_get(agent_fp_of(agent))          ← IO ①（BUG-418 新增）
  ├─ :73  resolve_agent_role(agent, declared)     ← 纯计算
  ├─ :74  check_scope_permission(scope, role)     ← 纯计算（BUG-419 改按长度排序）
  ├─ :75  RoleDenied(e) => Err(e)                 ← 硬拒，**不碰库**
  ├─ :76  Allowed  => store.rsv_try_set(...)      ← IO ②（后端原子裁决）
  └─ :90  Unregistered => store.rsv_try_set(...)  ← IO ②（同一条）
```

**关键**：IO ① 只决定**走哪个分支**（RoleDenied 拒绝 / 其余放行）。
**它不决定 IO ② 的裁决结果** —— IO ② 的 granted 由后端 `ON CONFLICT ... WHERE` + 写后回读定。

#### 1.2 TOCTOU 判定：`agents_get` 与 `store.rsv_try_set` 之间

**问**：角色在两步之间被改，会不会导致「用旧角色裁决新动作」？

**答：不会，且这一步在语义上无害。** 论证分三层：

**第一层 —— 时间方向对攻击者不利**：
```
t0  agents_get ⇒ role = Executor（旧）
t1  [窗口]     有人把 role 改成 Leader
t2  check_scope_permission(scope, "Executor") ⇒ RoleDenied
```
⇒ **读到旧值 = 读到更低的权限** ⇒ 结果是**拒绝**，不是放行。
反向（旧值=Leader、新值=Executor）虽会让一次操作按旧角色放行，但**这是任何无锁读都会发生的
「快照语义」**，且后果被 IO ② 的原子裁决限制在「这一次预订」上 —— **不累积、不可重复利用**。

**第二层 —— 权限门是「附加拒绝」，不是「附加许可」**：
`check_scope_permission` 只能把结果从 `放行` 收窄成 `拒绝`，**它从不把拒绝变成放行**。
⇒ 即使读到过期的高角色，攻击者拿到的也只是「一次本可能被拒的预订」，
**而不是「一个持久的提权」**。真正的提权在 BUG-422（查表键可报任意名），**不在这个窗口**。

**第三层 —— 后端裁决与权限门是两个独立维度**：
权限门答「你有没有资格碰这个 scope」，后端答「这个 scope 现在归谁」。
**两者不互相引用** ⇒ 权限门读到的过期角色**不会污染后端裁决**。

**⇒ 结论：裁决级 TOCTOU 不存在。** 这不违反任何纪律（BUG-136 那条禁的是「用读值决定裁决」）。

> ⚠️ **诚实补充**：若将来把权限门改成「按 `agents.role` 决定 scope 的**默认归属**」
> （而不只是拒绝/放行），那这个窗口就会变成真 TOCTOU。**当前不是。**

#### 1.3 `locks_try_acquire`（`engine_rsv.mbt:170-223`）—— 你最关心的那条

```
locks_try_acquire(lock)
  ├─ :176 agents_get(agent_fp_of(agent))          ← IO ①（BUG-418/424）
  ├─ :180 resolve_agent_role(...)                 ← 纯计算
  ├─ :181 check_scope_permission(scope, role)     ← 纯计算
  ├─ :182 RoleDenied(_) =>
  │    ├─ :202 self.store.locks_get(scope)        ← IO ②（legacy 特判，BUG-424 新增）
  │    ├─ :204 if existing.agent_of() == agent && existing.status_of() == "active"
  │    ├─ :205     self.store.locks_try_acquire(lock)   ← IO ③（后端原子裁决）
  │    └─ :209/:211 else denied_by_permission()   ← **不碰库**
  ├─ :213 Unregistered(_) => store.locks_try_acquire(lock)   ← IO ③
  └─ :221 Allowed         => store.locks_try_acquire(lock)   ← IO ③
```

**⇒ `:202` 读 + `:205` 写，确实是两次独立 IO。** 现在判定它是不是「先读后写」。

**判定标准（本单的判据）**：

> **应用层「先读后写」= 读到的值决定【写不写库】或【裁决 granted 真假】。**
> 若读只决定【进不进这条代码路径】，而写与裁决仍由后端原子语句 + 写后回读定 ⇒ **不是先读后写**。

**逐问回答（你给的 Q1/Q2/Q3）**：

**Q1. `existing.agent_of() == agent && status == "active"` 这个读，决定的是「写不写库」还是「播报什么标签」？**

**答：它决定「进哪条分支」，不决定「写什么裁决」。**
- 读到「是自己且 active」⇒ 走 `:205` 让后端**按它自己的原子规则**裁决（可能 granted 也可能 conflict）
- 读到「不是自己 / 非 active」⇒ 走 `:209/:211` **根本不写库**
  ⚠️ 这里确实「读决定了不写」—— 但**方向是保守的**（读到不像自己的锁 ⇒ 直接拒绝，不给任何机会）。
  **这不会导致越权，只会导致误拒**（且误拒由 legacy 语义兜住：本来就不该续别人的锁）。

**Q2. 若读到的 existing 在读到之后、写之前被别的 agent 改掉/过期，后端 `ON CONFLICT ... WHERE` 会不会挡住？**

**答：会，而且这是决定性的。** 后端（`store_sqlite.mbt:1438`）：
```sql
INSERT INTO file_locks (...) VALUES (...)
ON CONFLICT(scope) DO UPDATE SET agent=excluded.agent, status=excluded.status, ...
  WHERE file_locks.agent = excluded.agent
     OR file_locks.status <> 'active'
     OR file_locks.ttl_until < excluded.ts
```
且 `:1439` 明确 `ignore(may_write)` —— **本地写前算出的裁决不决定发不发这笔写**。
结论来自**写后回读** `lock_outcome_after_write`（`:1521+`）：库里是自己 ⇒ granted；是别人 ⇒ conflict。

**⇒ 写窗口内的任何并发变化，都由这条单语句 + 写后回读吸收。应用层读到的过期快照不会污染裁决。**

**Q3. 若后端挡住了（granted=false），回执会不会因为「读时判定是自己」而谎报 granted？**

**答：granted 不会谎报（`:207` 传的是 `o.granted`，保留后端结论）。**
**但 `action` 会谎报** —— 这就是 `BUG-429`：

```moonbit
let o = self.store.locks_try_acquire(lock)
o.relabel("renewed_legacy_grant", o.granted)   // ★ 无条件改 action
```
当 `granted=false` 时，回执是 `granted=false` + `action="renewed_legacy_grant"` ——
**两个字段互相矛盾，且 action 的措辞是「续期成功」。**

**⇒ 对你的直接回答：`locks_get` + `locks_try_acquire` 不是先读后写（裁决层）；但你那一行漏了 `if`，`BUG-429`。**

#### 1.4 `BUG-429` 的触发时序（证明可达）

`:202` 与 `:205` 之间是真实窗口（两次独立库访问）：

```
t0  agent A（角色已降为 Executor）调 locks_try_acquire，锁是自己且 active
      权限门 ⇒ RoleDenied
t1  :202 locks_get ⇒ Some(agent=A, status=active) ⇒ 进 legacy 分支
      ⚠️ A 认为「我可以续」
t2  agent B（有权限）抢到同一把锁（走 Allowed 分支 ⇒ :221 直接后端裁决）
      后端 ON CONFLICT: cur=(A,active,ttl_A) vs req B@ts_B
      WHERE: A==B? no | status<>'active'? no | ttl_A < ts_B? 若 ttl 未过 ⇒ no
      ⇒ 写被拒 ⇒ B 得 conflict
t3  A 在 :205 执行 locks_try_acquire
      后端 ON CONFLICT 此刻 cur=(B, active, ttl_B)
      WHERE: B==A? no | status<>'active'? no | ttl_B < ts_A?
        ① ttl_B < ts_A ⇒ 写成立 ⇒ 写后库主=A ⇒ granted=**true** ⇒ 标签与事实一致 ✅
        ② ttl_B >= ts_A ⇒ 写被拒 ⇒ 写后库主=B ⇒ granted=**false**
           ⇒ action 仍被写成 "renewed_legacy_grant" ⇒ **★ BUG-429 触发**
```

**情形 ② 可达**：只要 B 拿到的锁 ttl 比 A 的请求时间戳晚（正常 fresh 锁情形）。

---

### §2 BUG-136 / BUG-145 纪律核对（四段新逻辑逐条）

**先读纪律原文**：

| 纪律 | 出处 | 原文要点 |
|---|---|---|
| **BUG-136** | `engine_rsv.mbt:55` 注释 | 「按裁决抢预订：**互斥由后端定，工具面只渲染结论——不许在这里先读后写**」 |
| **BUG-145** | `engine_rsv.mbt:146` 注释 | 同上，锁层同一条 |
| **单一真源** | `store_rsv.mbt:92-93` | 「裁决规则**单一真源**：给定写前快照与本次请求，判该不该写＋动作标签。两个后端都从这里取标签，**SQLite 侧的 `ON CONFLICT ... WHERE` 编码的是同一条规则**」 |

**四段新逻辑逐条核对**：

| # | 新逻辑 | 位置 | 是否违反纪律 | 论证 |
|---|---|---|---|---|
| 1 | `agents_get` 查角色（BUG-418） | `rsv_set:25` / `rsv_try_set:66` / `locks_try_acquire:176` | **不违反** | 它只喂权限门（附加拒绝），**不参与后端裁决**。裁决仍由后端定（§1.2 三层论证） |
| 2 | `role_source` 标注（BUG-422 c） | `rsv_set:49` / `rsv_try_set:84/99` | **不违反** | 纯回执装饰，不碰裁决 |
| 3 | `Unregistered` 分支（BUG-413） | `rsv_try_set:90-107` / `locks_try_acquire:213-220` | **不违反** | 「仍走后端裁决」注释明写；`relabel` 只在 `o.reserved`/`o.granted` 为真时打标 ⇒ **尊重后端结论** |
| 4 | `legacy_grant` 特判（BUG-424） | `locks_try_acquire:182-212` | **裁决不违反；标签违反另一条契约** | 读决定分支（§1.3 Q1），裁决交后端（Q2）⇒ 不违反 136/145。**但 `:207` 无条件改 action ⇒ 违反 `LockAcquireOutcome` 自身的读法契约（`store_rsv.mbt:231`「granted 时是自己，conflict 时即现持有者」）⇒ BUG-429** |

**单一真源纪律核对**：`lock_acquire_action`（`store_rsv.mbt:215-221`）**逐字委托 `rsv_action`**（`:220` `rsv_action(lock_prev_for_action(prev), agent, now)`），**未另写谓词** ✓。
SQLite 侧 `ON CONFLICT ... WHERE` 的三个子句
（`agent = excluded.agent` / `status <> 'active'` / `ttl_until < excluded.ts`）
与 `rsv_action` 四个分支**逐条对应** ✓（`None⇒reserved写` / `owner==agent⇒renewed写` / `ttl<now⇒taken_over写` / `else⇒conflict不写`）。

**⇒ 三条纪律全部成立。**

---

### §3 新竞态面扫描（任务 3）

#### 3.1 `rsv_action` 的「写前快照会过期」—— 不构成 bug

```moonbit
pub fn rsv_action(prev, agent, now) -> (Bool, String) {
  match prev {
    None => (true, "reserved")
    Some((owner, _, _)) if owner == agent => (true, "renewed")
    Some((_, ttl, _)) if ttl < now => (true, "taken_over")
    _ => (false, "conflict")
  }
}
```

**问**：快照过期怎么办？
**答**：`store_sqlite.mbt:1439` **`ignore(may_write)`** —— 本地裁决**不决定发不发这笔写**，
只决定**播报的动作名**。真实裁决由 `ON CONFLICT ... WHERE` + 写后回读定。
⇒ **快照过期只影响「动作名播报」，不影响 granted。不是 bug。**

> ⚠️ **但这里有一个可观测的次生现象**（不是 bug，记录备查）：
> 若快照说 `conflict` 而实际写成功了（或反之），**播报的 action 名可能与真实转移不符**。
> 这在 `rsv_try_set` 里同样存在（`ignore(may_write)` 同款），**是两个后端一致的既有设计**，
> 不是本轮新增。**不改。**

#### 3.2 `agent_touch_first_seen` / `agents_register` 并发 —— 幂等安全

```
:627  let fp = agent_fp(raw_agent_id)
:629  ignore(eng.agents_acl_ensure(agent_id=fp, ns~, now~))
:631  ignore(eng.agents_register(agent_id=fp, ..., pid=current_pid_token(), now~))
```

`agents_register` 的 SQL（`store_sqlite.mbt:2772`）：
```sql
INSERT INTO agents (...) VALUES (..., 'active')
ON CONFLICT(agent_id) DO UPDATE SET
  pid=excluded.pid, last_seen=excluded.last_seen, status='active',
  role=CASE WHEN agents.role != 'Executor' THEN agents.role ELSE excluded.role END
```

**并发判定**：
- `CASE WHEN agents.role != 'Executor' THEN agents.role ELSE excluded.role END` ——
  **`agents.role` 是单条语句内的当前行值**，SQLite 在**同一条语句内**求值 ⇒ **无读后写窗口** ✓
- 两个并发 `register` 交错：先到的写、后到的 `ON CONFLICT` 再评估 `CASE`；
  **无论顺序，高角色都不会被低角色覆盖**（BUG-423 的防降级形状）✓
- `pid=excluded.pid` 会被后到者覆盖 —— **这是设计**（「pid 换绑」），不是竞态

**⇒ 不是 bug。**

#### 3.3 `claim` 与 `rsv_try_set` 会不会互相踩？claim 要不要先拿 scope 锁？

**核查 `FistEngine::claim`（`engine.mbt:155-215`）**：
```
get_task → 军衔门 → 能力门 → deps_satisfied → t.claim(assignee) → update_task_if_status(c3, "待领取")
```
**⇒ `claim` 完全不调 `rsv_*`、不调 `lock_*`。**

**并发安全性来自 `update_task_if_status` 的原子 CAS**（`store_sqlite.mbt:556`）：
```sql
UPDATE tasks SET ... , status = ?, assignee = ?, ...
WHERE id = ? AND status = ?        -- ← expected_status = "待领取"
```
**⇒ 两个 agent 同时 claim 同一任务：只有一个 `UPDATE` 命中（另一个 0 行），后到者 Err。幂等安全 ✓**

**问：claim 要不要先拿 scope 锁？**
**答：不该拿，且现在的设计更正确。** 理由：
1. `scope` 是**文件路径**（`src/engine/x.mbt`），任务是**逻辑工作单元** ——
   **两者粒度不同**，claim 一个任务不意味着要独占整个 `src/engine/` 目录
2. `rsv_*` 的语义是「我要改这个文件」，`claim` 的语义是「我要做这个任务」——
   **claim 之后才该 reserve**，反过来会让「认领」变成「锁全目录」
3. 若 claim 要拿 scope 锁，**必须先知道任务要改哪些文件**，而任务的 `n_files`/目标文件
   并不总在 description 里结构化给出 ⇒ **不可行且会制造死锁**（A 认领后要 reserve、B 已 reserve 等认领）

**⇒ 不是 bug，是正确分层。**

#### 3.4 其他扫过的面（判定「不是竞态」的论证）

| 面 | 判定 | 论证 |
|---|---|---|
| `rsv_set`（非 try，`:10-52`） | **不是竞态** | 它**不是**"抢"语义（`rsv_set` 是无条件写），本来就不承诺互斥。要抢必须用 `rsv_try_set` |
| `assistant_claim`（`store_assistant.mbt`） | **未深查**（见 §4 盲区） | 属另一个多 agent 面，本轮时间在两条主链上 |
| `locks_sweep` 与 `locks_try_acquire` 并发 | **不是竞态** | sweep 只释放 TTL 过期锁；与 acquire 的 `ON CONFLICT WHERE ttl<ts` 同一条判据，重复释放/重复获取都幂等 |
| `lock_violation_insert` 并发 | **不是竞态** | 纯 append 审计，无互斥语义 |
| `update_task_if_status` 并发 | **不是竞态** | 原子 CAS（§3.3） |

---

## 分析

### 为什么 `legacy_grant` 的两次 IO 不构成「先读后写」

**因为 BUG-145 禁的是「用读值决定裁决」，不是「读一次库」。**

判据可以写成一句话：**读到的值，能不能改变「谁拿到锁」这个结果？**
- 若**能** ⇒ 先读后写（违反纪律）
- 若**不能**，只能改变「走哪条代码路径」/「播报什么标签」⇒ **不是**

`legacy_grant` 的读（`:202-204`）**只能把结果推向更保守**（不像自己 ⇒ 直接拒），
它**无法让一个本该被拒的请求变成 granted** —— 因为 granted 永远由后端算。
⇒ **它是一道「附加闸门」，不是「裁决器」。**

**这个区分很重要**：如果只按「有没有两次 IO」判，会把大量**正确的读优化/前置检查**误判成竞态。
本单的判据（读值是否改变裁决）才是 BUG-145 的原意。

### 但标签缺陷为什么值得报

因为 `LockAcquireOutcome` 的**读法契约**是「`granted` 与 `action` 一致」——
`store_rsv.mbt:231` 注释写明「granted 时是自己，**conflict 时即现持有者**」。
`BUG-429` 让 `action` 说「续期成功」而 `granted=false`、`agent` 是别人 ⇒ **调用方按 action 判断就会误判**。

**这是「两段逻辑接在一起时，第二段没抄第一段的 `if`」的经典形状** ——
同文件 `Unregistered` 分支（`:215`）写了 `if o.granted`，`legacy_grant`（`:207`）漏了。

---

## 缺口与风险

### 盲区 1：**没有真跑并发测试**

全程只读，**未编译、未跑测试**。`BUG-429` 的时序是**源码推演**（时序图 §1.4），
**没有实际执行过的并发失败测试**。建议落地方：
用「确定性注入」（判例-31，**不要用 sleep**）——
在 `locks_get` 与 `locks_try_acquire` 之间注入一次 B 的抢锁，断言回执 `action` 不能是 `renewed_legacy_grant`。

### 盲区 2：`assistant_claim` 的并发面本轮未查

`store_assistant.mbt` 的助理选举（心跳 TTL + 接管）是另一套多 agent 互斥，**本轮未覆盖**。

### 盲区 3：跨进程 / 多连接下的 SQLite 事务隔离级别未验

`ON CONFLICT ... WHERE` 的原子性依赖 SQLite 的写锁。
**多进程并发写同一 scope 的真实行为本轮未实测**（需要真起两个 server 进程）。

### 盲区 4：`locks_upsert` 仍是裸通道

`engine_rsv.mbt:167-168` 注释自认：`locks_upsert`（底层原语）**仍无权限门**，
被 `locks_sweep` 等内部路径依赖。**这是已知敞口，本轮未变**。

### 盲区 5：内存后端与 SQLite 后端的**等价性**未验证

`MemoryStore::locks_try_acquire`（`store_rsv.mbt:321`）是「先读 → `lock_acquire_action` → 条件写 → 写后回读」，
**形状与 SQLite 不同**（内存版用 `may_write` 真决定写不写；SQLite 版 `ignore(may_write)`）。
⇒ **两个后端在并发下行为可能不同**（BUG-85/79 的旧例）。
本轮**未验证**，但 `store_rsv.mbt:110-112` 注释说「两后端必须同一形状，否则单测永远绿而 SQLite 红」——
**建议单独核这一格。**

---

## 建议入档位置

| 内容 | 位置 |
|---|---|
| 本报告 | `reports/2026-10-27-r9-race-condition-audit.md` |
| `BUG-429` | `memory/bugs.md`（已由 `report_bug` 写入） |
| 时序推演脚本 | `temp/audit/lane_ad_tou.py`（两条调用链 IO 序列提取）· `lane_ad_legacy.py`（legacy 分支逐场景推演） |
| `BUG-429` 建议修法 | 补 `if o.granted { o.relabel("renewed_legacy_grant", true) } else { o }`（与 `:213-220` `Unregistered` 分支同构） |
| 建议后续单 | ① 内存/SQLite 两后端锁裁决等价性核验（§盲区5）② `assistant_claim` 并发面 ③ 多进程真并发实测 |
| **未做** | **未调 `bug_fix`**（代码未落地） |
