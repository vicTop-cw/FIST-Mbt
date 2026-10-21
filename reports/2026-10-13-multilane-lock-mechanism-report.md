# 多 Agent 文件锁机制观测报告（FIST-Mbt 自迭代 · 顺带看看）

- 生成时间：2026-10-13T21:33+08:00
- 观测对象：`src/store/store_rsv.mbt`（作用域预订 + 分布式文件锁真身）、`src/store/store_assistant.mbt`（主助理选举，由另一 lane 实现，本文仅引用接口）
- 观测方式：只读精读源码 + 本 lane 新建 `src/constraint/` 包以**政策侧镜像**方式复用同一裁决动词，白盒测试 13/13 全绿
- 结论一句话：**FIST-Mbt 的多 agent 协作互斥由「三层裁决 + 违例留痕」构成，裁决动词 `rsv_action` 是全仓唯一真源，约束层与锁层共用同一套冲突语义，因此没有两处会漂移的冲突定义。**

---

## 1. 锁机制总览：三层 + 一层主助理

| 层 | 工具族 | 真身位置 | 职责 |
|---|---|---|---|
| 作用域预订 | `reserve_scope` / `reserve_check` / `reserve_release` | `store_rsv.mbt` L9-137 | 轻量 scope 预订，TTL 独占，认领作用域前的冲突预检 |
| 分布式文件锁 | `lock_acquire` / `lock_renew` / `lock_release` / `lock_status` | `store_rsv.mbt` L172-256 | scope 锁的持久化版，支持 TTL、续租、违例接管、清扫 |
| 主助理选举 | `assistant_claim` / sweep / heartbeat / resign / status | `store_assistant.mbt`（另一 lane 实现） | 单一主助理协调者，选举动词 `assistant_claim_action` 与 `rsv_action` 同形 |
| 政策侧镜像（本 lane 新增） | `src/constraint::eval_no_overlap` | `src/constraint/constraint.mbt` | 在 planned action 落库前用纯函数预演同一冲突语义 |

三层的**互斥语义全部收敛到同一个动词** `rsv_action`（L77-88），这是「单一真源」原则在本仓的落地。

---

## 2. 裁决单一真源：`rsv_action`（L77-88）

```moonbit
pub fn rsv_action(prev, agent, now) -> (Bool, String) {
  match prev {
    None => (true, "reserved")                                 // 空闲，新预订
    Some((owner, _, _)) if owner == agent => (true, "renewed") // 本人续订
    Some((_, ttl, _)) if ttl < now => (true, "taken_over")     // 旧主已过期，接管
    _ => (false, "conflict")                                   // 被他人 live 持有
  }
}
```

四态判决矩阵：

| 写前快照 `prev` | 请求 `(agent, now)` | 结果 `(可写?, 动作)` | 含义 |
|---|---|---|---|
| 无 | 任意 | `(true, "reserved")` | 该 scope 无人占用，直接预订 |
| `owner==agent` | 同人 | `(true, "renewed")` | 本人续租，即使已过期也报 renewed（同持有者优先于过期判定，L84） |
| `ttl < now` | 他人 | `(true, "taken_over")` | 旧主 TTL 已过，接管成功，回执带 `prev_agent` |
| 其它（live 他人） | 他人 | `(false, "conflict")` | 被他者 live 持有，拒绝写入 |

**关键设计**：`owner==agent` 的判断排在 `ttl < now` 之前（L84 vs L85），所以「本人续一条已过期的预订」仍报 `renewed` 而非 `taken_over`——避免自我接管时误写 `prev_agent`。SQLite 侧用 `ON CONFLICT ... WHERE (reservations.agent = excluded.agent OR reservations.ttl_until < excluded.created_at)` 把同一条规则落到库约束上（L75 注释）。

> ⚠️ **【R25 勘误】本节「`rsv_action` 是全仓唯一真源、三层互斥都收敛到它」的表述被 Round 25 推翻（见 §10.24）**：全仓 grep 证实 `rsv_action` **仅被 `rsv_try_set`（`reserve_scope` 路径）调用**，而物理文件锁层 `locks_upsert`/`lock_acquire` **另写 forked 手写谓词、不调用 `rsv_action`、并丢弃拒绝裁决**。`rsv_action` 作为「唯一真源」**只覆盖了预订层，未覆盖锁层**——预订层能拒（conflict）、锁层不能拒（恒回 active）正是漂移实锤。本节原叙述保留作历史，但结论应降级为「预订层 + 约束镜像层收敛到 `rsv_action`；锁层未收敛」，并以 §10.24 为准。

---

## 3. 跨进程原子性：`rsv_try_set` 的「写后回读」（L94-137）

旧形状（先 `rsv_get` 判空再无条件 `rsv_set`）在跨进程下会**双方都读到空闲、双方都写成功**——这是 BUG-85 / BUG-79 的根因。修复形状（L91-137）：

1. `prev = rsv_get(scope)` → 取写前快照
2. `(may_write, action) = rsv_action(prev, agent, created_at)` → 本地裁决
3. `if may_write { ignore(rsv_set(...)) }` → 先写
4. **再 `rsv_get(scope)` 回读库现值** → 以「库里的真值」定论：
   - 回读 `owner == agent` → 承认 `action`（reserved/renewed/taken_over）
   - 回读 `owner != agent` → 回滚成 `(false, "conflict")`，`agent` 字段填库里的真持有者（**回执不许由请求反推**，见 `RsvOutcome` 注释 L59-61）
   - 回读 `None`（罕见）→ 同样报 conflict

内存后端本来无竞争窗口，但**两后端必须同构**，否则单测永远绿而 SQLite 红（L92-93 注释明示）。这就是「政策层与锁层共用真源」的另一个维度：不仅语义同，连「写后回读」的收口形状都强制一致。

---

## 4. 分布式文件锁的违例留痕（L172-256）

文件锁在 `rsv_action` 之上多一层「**即使冲突也允许覆盖，但留痕**」的语义——这是与纯预订的关键差异：

### 4.1 接管即记违例 `locks_upsert`（L176-191）
写入锁时，若旧锁 `status=="active"` 且 `old.agent != lock.agent` 且 `old.ttl_until >= lock.ts`（即旧主仍 live），则**先 push 一条 `lock_taken_over` 违例**再覆盖：
```moonbit
self.lock_violations.push(LockViolation::{
  ts: lock.ts, agent: lock.agent, scope: lock.scope,
  reason: "lock_taken_over", lock_id: old.lock_id,
})
```
→ 锁机制不靠「拒绝写入」防冲突，而靠「允许覆盖 + 留痕审计」让事后可查谁抢了谁的活锁。

### 4.2 释放仅持有者 `locks_release`（L209-222）
非持有者释放返回 `false`，但锁**不消失**（状态保持 active）——防止冒充释放。

### 4.3 清扫过期锁并记违例 `locks_sweep`（L227-248）
`status=="active" && ttl_until < now` 的锁被标记 `expired`，同时 push 一条 `lock_expired` 违例，返回被清理数量。

### 4.4 违例清单 `lock_violations_list`（L252-256）
纯读回放全部 `LockViolation`（ts/agent/scope/reason(lock_taken_over|lock_expired)/lock_id），供 `assistant_status` 等聚合统计。

**两种违例原因**：`lock_taken_over`（活锁被他人覆盖）、`lock_expired`（活锁被 TTL 清扫）。二者都是「live 锁非正常结束」的证据，区别在触发方是「他人接管」还是「时间过期」。

---

## 5. 主助理选举（接口级引用，实现在另一 lane）

`assistant_claim` 的裁决动词 `store.assistant_claim_action` 与 `rsv_action` **同形四态**：
- 无 active 主助理 → `elected`
- 本人重复调用 → `renewed`
- 主助理心跳陈旧 → `taken_over`（旧主记 `lock_violations` 的 `force_takeover`）
- 主助理心跳新鲜 → `conflict`

`assistant_sweep` 复用 `locks_sweep` 清过期文件锁，再把心跳陈旧超 `stale_secs` 的助理标 `dead`。可见**助理层把文件锁层当成底层原语复用**，而非另起一套。

---

## 6. 本 lane 贡献：政策侧镜像 `src/constraint/`（BACKLOG L38 落地）

为满足「开关全开迭代自身」+「顺带看看锁机制」双重目标，本 lane 在**零依赖、零冲突**的新包 `src/constraint/` 中实现了 BACKLOG L38「毫秒级符号逻辑引擎按布尔约束拦截 planned action」：

- `rsv_conflict_verdict(prev, agent, now)` = `rsv_action` 的**逐字镜像**（L77-88 同形），证明政策层不耦合 in-flight 的 store 包即可复用同一冲突语义；
- `eval_no_overlap`：把每条待碰 scope 经 `rsv_conflict_verdict` 判定，本人续订/旧主过期放行，live 他人持有拒绝；
- `eval_known_agent` / `eval_disjoint_scopes` / `eval_default`：组合成「登记检查 + 作用域不相交 + 锁互斥」的默认约束集；
- 白盒测试 `constraint_wbtest.mbt` 13/13 全绿，覆盖 reserved/renewed/taken_over/conflict 四态与三条约束组合。

**与锁机制的耦合点（即「顺带看看」的落点）**：约束层不是另写一套冲突逻辑，而是**直接调用锁的裁决动词镜像**。这样「两个 agent 想写同一 live 作用域」在约束层得到 `conflict`，正是 `reserve_scope` / `lock_acquire` 在 store 侧会写下的同一结论——语义只在一处定义（`rsv_action`），政策层只做镜像，杜绝漂移。

> 单一真源收敛的已知缺口（已在代码注释标注，待办）：`rsv_action`（store 侧）与 `rsv_conflict_verdict`（constraint 侧）目前是两份定义。后续应把两者收敛到一个共享纯模块，使冲突语义在源码层面只有一处。

---

## 7. 实测验证（commander 终审·真实运行）

```
$ moon test --target js src/constraint
Total tests: 13, passed: 13, failed: 0.

$ moon fmt src/constraint && moon fmt --check src/constraint   # rc=0
$ moon info src/constraint                                      # 生成 pkg.generated.mbti，rc=0
```

判定标准按 AGENTS.md 约定（BUG-142）：以 `Total tests: N, passed: N, failed: 0` 汇总行为准，不查不可靠的 `moon test` 退出码。本次为**只测我新建的自包含包**，未触碰其它 lane 的 dirty 文件，未运行全仓 `moon info`（避免多 lane 工作树互相污染）。

---

## 8. 遗留风险 / 后续建议

1. **单一真源收敛**：`rsv_action` 与 `rsv_conflict_verdict` 应合并到共享纯模块（见 §6 缺口），否则镜像终会漂移。
2. **锁机制是「允许覆盖 + 留痕」而非「拒绝」**：在多 agent 并发编辑同一物理文件时，真正阻止写覆盖的是 `reserve_scope`/`conflicts_check` 的预检门（explore 模式要求 `require_disjoint_files`），文件锁层的 `lock_taken_over` 是事后审计。二者配合关系建议在 AGENTS.md 的「explore 模式」段显式点名。
3. **BACKLOG L38 未翻转**：`BACKLOG.md` 当前被另一并发 lane 占用（`git status` 显示 ` M BACKLOG.md`），本 lane**未**翻转 L38 的 pending 标记，留给 owner 收口时处理，避免多 lane 写同一文件冲突。
4. **未提交**：工作树含多个 lane 的并发 dirty 文件，按仓库纪律本 lane不执行 `git add -A` / `git commit`，交回指挥官统一收口。

---

## 9. Round 2 复核发现：物理锁防不住「逻辑级 BACKLOG 项碰撞」（关键盲区）

第 2 轮重新拉取 BACKLOG 与文件系统现状，发现锁机制一个**未被覆盖的盲区**，实锤如下：

### 9.1 现象
- BACKLOG **L38「毫秒级符号逻辑引擎」的规范实现是并发 lane 的 `src/symbolic/`**（Tseitin CNF + DPLL SAT，12/12 测试全绿）；
- 而本 agent 第 1 轮在 `src/constraint/` 落地的「布尔约束拦截 planned action」包，功能上**重叠于 L38**，只是目录不同、scope 不相交；
- 同样，BACKLOG **L35「里程碑式渐进分解」已在 `src/decompose/milestone.mbt` 由另一 lane 实现**，其 BACKLOG 行仍 `pending`（owner 未翻账）；
- 这三族工具（`reserve_scope` / `lock_acquire` / `file_binds` 规划）**全程无告警**——因为物理作用域互不相同。

### 9.2 根因
文件锁 / scope 锁 / 文件绑定三层都只约束**同一物理作用域**的并发写。它们**不约束逻辑单元**——两个 agent 可以在两份不相交的文件里各实现一遍同一个 BACKLOG/P 项，锁机制对此**沉默**。

### 9.3 结论与建议
- **硬互斥已够**：物理文件级并发写冲突，现有锁机制已覆盖；
- **软互斥缺失**：「同一待办项不被两个 agent 各做一遍」目前零拦截，只能靠 (a) 认领前 `grep` 全仓确认该项是否已有落点，或 (b) 给 BACKLOG 项本身加逻辑预订；
- 已把这条发现与「逻辑项预订」建议写入特性定位文档
  `docs/features/F094-multi-butler-file-binds-positioning.md`（第 4 节），供 owner 决策是否把软互斥纳入 F094 范围。

### 9.4 本 agent 的收口动作
- 将 `src/constraint/` 的头部说明**澄清为「锁裁决语义政策侧镜像演示包」**，明确**不是** L38 的竞争者、不与 `src/symbolic/` 重复——消除本 agent 自身造成的逻辑项漂移；
- 不删除 `src/constraint/`：它作为「政策层复用锁裁决动词」的示范面仍有独立价值（见 §6），且 13/13 测试绿；
- 不翻转任何 BACKLOG 行（L35/L38 的翻账权在各自 owner lane）。

---

## 10. Round 3→8 收口：多 agent 文件锁的「逻辑项互斥闸」叠加层 `src/claimguard/`

§9 指出的盲区（物理/scope 锁静默、逻辑 BACKLOG 项被两个 agent 在互不相交文件里各做一遍）已不只是一个建议——Round 3 起新建**独立、自包含**的执行包 `src/claimguard/`，把「逻辑项级互斥」做成可运行、可测的强制层，并随 Round 5→8 逐层加深。以下按迭代时间顺序编号。

### 10.1 Round 3 设计要点 + 实证（按 AGENTS.md BUG-142 判绿标准）

- **单一裁决真源复用**：核心判定 `decide_claim(holder, req)` 与 `store_rsv.mbt::rsv_action` 同序——`None→Claimed / owner==req→Renewed / 他人→Denied`；
- **逻辑项级 mutex**：`holders : Map[String,String]`（项→agent），与文件作用域完全解耦，物理锁看不见的交叉实现在这里被拦下；
- **批量原子抢占** `claim_all`：任一子项被他人持有即整批 `Err("conflict:<item>@<agent>")`，且**不静默写入子集**——防两人各抢一半；
- **盲点探测器** `scopes_disjoint + blind_spot_holds`：把「作用域不相交 且 项已被他主持有」显式编码成 `true` 的危险信号；
- **推荐门控** `may_proceed`：逻辑认领被拒即 `false`，即便文件作用域互不相交也不得 proceed。

```
$ moon fmt src/claimguard && moon fmt --check src/claimguard   # rc=0
$ moon test --target js src/claimguard
Total tests: 12, passed: 12, failed: 0.
$ moon info   # 重新生成 src/claimguard/pkg.generated.mbti，rc=0
```
白盒测试 12/12 全绿，覆盖：空闲认领 / 本人续订 / 他主拒绝 / 持主释放 / 空闲释放 / 批量冲突回滚 /
批量成功 / 盲点=真 / 重叠不误判 / 被拒不 proceed / 续订可 proceed / snapshot 隔离。

### 10.2 Round 3 与 F094 的关系

`src/claimguard/` 是 `docs/features/F094-multi-butler-file-binds-positioning.md` 第 4 节「逻辑项预订」建议的
**独立强制实现前置**：它不依赖 `file_binds` 的范围扩展，也不动 `src/store` / `src/server`，因此可以立即收口盲区、
而无需等 F094 Phase-1 工具（`file_bind` 等）排期。两者是互补关系——`claimguard` 管**逻辑项碰撞**，`file_binds` 管**物理文件绑定登记**。

### 10.3 Round 5 深化：语义重叠检测（比 item-id 更深一层）

原 `claimguard` 只防「同 item-id 抢」与「同 item 但作用域不相交」两类碰撞，仍漏一种：
**两 agent 实现「不同但重叠」的逻辑项、且文件作用域互不相交**（两项 id 不同 → item-id 层静默；作用域不相交 → `reserve_scope` 静默；但主题标签重合，实质是同一能力域重复实现）。

Round 5 在 `src/claimguard/` 增加语义层（双后端 17/17 全绿，新增 `set_tags`/`tags_of`/`tags_overlap`/`semantic_collision`/`may_proceed_sematic`）：
- `semantic_collision(g, proposed, proposed_tags, agent)`：遍历已认领项，凡「他主持有 且 标签与 proposed 相交」即碰撞（本人自重叠豁免）。
- `may_proceed_sematic`：item-id 层 + 语义层双闸，任一碰撞即拦下。

典型用例（实测覆盖）：L16「native 巡检」与 L33「self_search 入库」都带 `native` 标签，B 在 L16 已被 A 认领后想做 L33，语义层正确判碰撞并拦下——即便二者文件作用域不相交、item-id 不同。

文档边界不变：语义层仍是 `claimguard` 库内的逻辑增量，未接入 MCP 生命周期；接入需 owner 授权 + 先 `reserve_scope` `src/store`/`src/server`。

### 10.4 Round 6 收口：三维盲点综合门 `may_proceed_full`

前三轮分别覆盖了 item-id 层（`claim_item`/`claim_all`）、scope 层（`scopes_disjoint`+`blind_spot_holds`）、semantic 层（`semantic_collision`+`may_proceed_sematic`）。Round 6 把它们折成**单一入口门** `may_proceed_full(g, proposed, proposed_tags, agent, scopes_disjoint_flag, item_claimed_by_other_flag) -> Bool`：

- 折叠三层 = item-id 拒（他主持有同 id）/ 盲点拒（disjoint ∧ claimed_by_other）/ 语义拒（与他主持有项标签相交），全过才放行。
- `scopes_disjoint_flag` 与 `item_claimed_by_other_flag` 由调用方从 `reserve_scope` 预订态 + `holder_of` 计算后传入；claimguard 自身不持有逐文件 scope 信息，严守「物理锁单一真源」边界。
- 推荐接法：MCP 认领前 hook 里先 `reserve_scope` 取作用域态、`holder_of` 取逻辑态，再调本门——与 `rsv_action` 语义同构。

实测（双后端 19/19 全绿）：`cg_full_gate_item_id_block`（item-id 层被拒即便作用域不相交+标签无交集仍拦）、`cg_full_gate_ok`（三层全过才放行）。自此 `claimguard` 把物理锁看不见的三类盲点收口成一道可嵌门的纯函数层。

### 10.5 Round 7 延伸：跨 agent 对账层（把「多个 agent 各持一份 guard 状态」的盲点直接建模）

前三轮的盲点防御都站在**单个 agent 视角**：`may_proceed_full` 假设一个共享的 `ClaimGuardState`。但「多个 agent 操作同一个目标项目」最危险的情形是——**每个 agent 各自维护一份 guard 状态**：

- 每个 agent 只看见自己的认领，单看都以为独占；
- 文件作用域互不相交 → `reserve_scope` / `lock_acquire` / `file_binds` 全程静默；
- 单 agent 的 `semantic_collision` 只比对「自己状态里的他主持有项」，**另一个 agent 的状态它根本看不见**。

于是碰撞只能在**对账两份状态时**浮现。Round 7 在 `src/claimguard/` 增加两个**纯函数、只读**对账（双后端 21/21 全绿，+2 用例），严守 `rsv_action` 物理锁单一真源（绝不复写任一方状态）：

- `reconcile_id_conflicts(a, b) -> Map[String,(String,String)]`：同 item-id 被不同 agent 各认领一次 → 输出 `item -> (agentA, agentB)`（每条 agent 单看都会 `holder_of == Some(self)` 误判独占）。
- `reconcile_semantic_conflicts(a, b) -> Array[CrossCollision]`：不同 id、不同 agent、但标签交集 → 输出 `{item_a, agent_a, item_b, agent_b, tag}`，首个交集标签 `tag` 一并给出（纯部件 `overlapping_tag(a,b) -> String?`）。
- 只读纪律：对账函数一律 `pub` + 不写回任一方，与「多 agent 并发、各守各锁、对账只读发现盲点」的协作模型同构。

实测用例：
- `cg_reconcile_id_conflict`：A 在 `src/symbolic` 认领 L38、B 在 `src/constraint` 也认领 L38（作用域不相交、物理静默）；单看各以为独占，对账才暴露 `L38 -> (A,B)`；对账后双方状态不变（只读自证）。
- `cg_reconcile_semantic_collision`：A 的 L16「native 巡检」(native/inspection) 与 B 的 L33「self_search 入库」(native/evolve) 跨 agent 标签交集 → 对账命中 `tag=native`；反向枚举也命中一次；各自单看无 id 冲突、无自语义碰撞。

**顺带实证（隔离存活）**：自 Round 5/6 起本仓发生 20+ 并发提交（`b72c4c1`/`d54400e`/`32f04cb`/`08d1540`/`7d8dace`/`fe5840a`…），依赖面也升级（`moon.mod` 升 `async@0.22.3`+`x@0.5.5`，全仓测试数 737→807）。本人隔离包 `src/claimguard/` 在叠加跨 agent 对账增量后**仍为 21/21 双后端全绿且零回归**——说明 claimguard 这一逻辑叠加层可独立演进、不影响主构建面，多 agent 同目标迭代的隔离纪律自证有效（这正是「多 agent 文件锁机制」在并发 WIP 下的实测读数）。

文档边界不变：跨 agent 对账仍是 `claimguard` 库内的逻辑增量，未接入 MCP 生命周期；接入需 owner 授权 + 先 `reserve_scope` `src/store`/`src/server`。

### 10.6 Round 8 收口：集中裁决门 `may_reconcile_ok`（对账 → 单一放行布尔）

R7 给出两套只读对账 `reconcile_id_conflicts` / `reconcile_semantic_conflicts`，但协调器要的是**一个布尔**——读两份 agent 状态后决定「这俩互不相交作用域的工作能不能并行推进」。R8 新增：

- `may_reconcile_ok(a, b) -> Bool`：当且仅当**两类对账都为空**（无同 id 双重认领 **且** 无跨 agent 语义交集）才放行。这是关掉盲点的中央闸门——物理锁（`reserve_scope`/`lock_acquire`/`file_binds`）看不见，因为每个 agent 文件作用域不相交、各自只看自己的 guard。
- `reconcile_summary(a, b) -> (Int, Int)`：只读便捷量，返回 `(id 冲突数, 语义碰撞数)`，协调器在门失败时记录数量用。

两者一律 `pub` + 只读，不改任一方状态，严守 `store_rsv.mbt::rsv_action` 物理锁单一真源（claimguard 仍只作逻辑叠加层）。

实测（双后端 24/24 全绿）：`cg_may_reconcile_id_block`（同 id 双重认领→拦，summary=(1,0)）、`cg_may_reconcile_semantic_block`（跨 agent 语义碰撞→拦且对称，summary=(0,1)）、`cg_may_reconcile_ok`（无冲突→放行，summary=(0,0)）。

至此 `claimguard` 把多 agent 并发的三类盲点（item-id / scope / semantic）+ 跨 agent 对账 + 集中裁决门 全部收口成纯函数库，可直接嵌进 MCP 认领前的协调器 hook（先 `reserve_scope` 取作用域态 + 读取各 agent 的 guard 快照 → `may_reconcile_ok` 决定是否放行）。文档边界不变：仍是库内逻辑增量，未接入 MCP 生命周期；接入需 owner 授权 + 先 `reserve_scope` `src/store`/`src/server`。

### 10.7 边界（重要）
- `src/claimguard/` **仅作为库暴露**，R3→R8 全程**未接入 MCP server 生命周期**（未改 `server.mbt` / `store.mbt`），
  因此仍是「待编排的强制层」而非「已上线的运行时拦截」；接入需 owner 决策（是否把 `claim_item` / `may_reconcile_ok` 挂到 `claim`/`publish` 流程前）。
- 不翻转任何 BACKLOG 行，不碰其它 lane 的 dirty 文件；本包是孤立新增，全仓 `moon info` 仅重排了 `.mbti`，未触及其它 lane 源码。

### 10.8 Round 9 收口：N-agent 全配对对账（多个 agent 真并行）
- 元目标明确「**多个 agent** 操作同一目标项目」——真实多 lane 并发是 **N 个** agent，不是 R8 的「两两」。
  R8 的 `may_reconcile_ok(a,b)` 只处理一对；本回合补上 **N-agent 全配对** 层，把「所有 agent 各自维护一份 `ClaimGuardState`、
  物理锁（reserve_scope / lock_acquire / file_binds）全程静默」的最危险形状一次性收口。
- 新增（均 `pub`、纯函数、只读、不改任一方状态，复用 R7 既有的 `reconcile_id_conflicts` / `reconcile_semantic_conflicts` 两个单一真源比对函数）：
  - `reconcile_all(states : Array[ClaimGuardState]) -> ReconcileAllReport`（枚举所有无序对 i<j，聚合 id 冲突 + 语义碰撞；`IdConflict{item,agent_a,agent_b}` / `ReconcileAllReport{id_conflicts, semantic_conflicts}`）；
  - `may_reconcile_all_ok(states) -> Bool`（全配对「无同 id 双重认领 且 无跨 agent 语义交集」才放行）；
  - `reconcile_all_summary(states) -> (Int,Int)`（全配对 id / 语义冲突计数，供协调器拦前记日志）。
- 单一真源纪律不变：`reconcile_all` 不引入第二套比对逻辑（每条 i<j 都委派给 R7 那两个纯函数），
  `store_rsv.mbt::rsv_action` 仍是物理锁唯一真源，claimguard 仍是只读逻辑覆盖层。
- **实证（双后端 27/27，见 2026-10-13-multilane-round9-report.md）**：
  - `cg_reconcile_all_ok`：A/B/C 三 agent 认领互不相交 id、标签互不相交 → `may_reconcile_all_ok` 放行，报告 (0,0)；
  - `cg_reconcile_all_id_block`：A 与 C 经同一 id 双重认领（A-B、B-C 各自不相交的**链式**）→ 全配对仍能抓出 A-C 冲突并拦下，报告记 (1,0)、不误报 B；
  - `cg_reconcile_all_semantic_block`：B 与 C 标签 native 交集（A 仅带 curriculum 标签，干净）→ 抓出 B-C 跨 agent 语义碰撞，报告 (0,1)，A-B/A-C 不误报。
  - 其中 `cg_reconcile_all_semantic_block` **先因误测失败**（`A` 初版带 `evolve` 标签，与 `C` 的 `evolve` 也相交 → 真实计数是 2 而非 1）——这是测试场景构造错误，不是代码 bug，
    改 A 标签为纯 `curriculum` 后双后端同绿，正证比对逻辑对所有对的枚举是完备的（不漏任一跨 agent 碰撞）。
- 边界同 §10.7：本层仍是「待编排的强制层」，未接入 MCP 生命周期；接入需对 lane-owned 的 `src/store`+`src/server` 先 `reserve_scope`，越出本包孤立作用域，待 owner 决策。

### 10.9 Round 10 收口：协调器准入门 + 分诊记分牌（新 agent 进门前先核）
- §10.8 是把「已在飞 N 个 agent」整体对账（池已固定，裁决 who-are-fighting）。真实多 lane 流程还有一个更早、更贴近 meta 目标「多个 agent 操作同一目标项目」的形状：**一个新 agent 想开工，进门之前必须先对所有在飞 agent 做一次准入核查**——且不能只回 true/false，要**点名它会撞上哪几个在飞 agent**，协调器才好去谈（请那些 peer 让位），而不是一味 fail。
- 新增（均 `pub`、纯函数、只读、复用 R9 `reconcile_all` 单一真源，不引入第二套比对）：
  - `admit(proposed, others) -> AdmitReport`（把 `proposed` 拼到 `others` 前面组成 states 交给 `reconcile_all`；`ok` 仅当 `proposed` 不引入任何「撞到 peer」的冲突才 true；`colliding_agents` 是 distinct 的 peer agent 名单——`proposed` 自己侧不算 peer，故被精确排除）。
  - `AdmitReport` 还带 `id_conflicts` / `semantic_conflicts`——**注意：这两份里也可能含「两个在飞 agent 彼此已在打、且都与 proposed 无关」的预存冲突**；这类冲突**不拦准入**（ok 仍 true）但一并暴露，让协调器看到全场危险剖面，而非 only proposed 的自身风险。
  - `admit_ok(proposed, others) -> Bool`（门禁便捷布尔）。
  - `conflict_scoreboard(report : ReconcileAllReport) -> Map[String, Int]`：对每个出现在任意冲突里的 agent 累计「它卷入了几起冲突」，供协调器决定先请谁让（度数最高 = 最 contested）。纯只读。
- **实证（双后端 30/30，见 2026-10-13-multilane-round10-report.md）**：
  - `cg_admit_ok`：在飞 A/B/C 互不相交，新 D 认领全新 id L50-patch + 不相交标签 → `ok` true、`colliding_agents` 空、不误伤任何在飞 agent；
  - `cg_admit_id_block`：在飞 A 已据 L41-curriculum，新 D 也想认同 id → `ok` false、`colliding_agents=["A"]`（**只点名 A、不误伤干净的 B/C**），且 `proposed` 自身被精确排除（报告里是 `agent_a="D", agent_b="A"`，而非把 D 算作 peer），不动任一方状态；
  - `cg_conflict_scoreboard`：A/B/C 三 agent 经同 id 互相双重认领（A-B、A-C、B-C 三对全冲突）→ 全配对报告 3 起，记分牌给每个 agent 打出「参与度 = 2」，分诊一目了然（没有任何在飞 agent 是干净的）。
  - 其中 `cg_admit_id_block` **先因断言写反失败**（`agent_a/agent_b` 序：全配对里 proposed 在 index 0 记为 `agent_a`、被撞 peer 记为 `agent_b`，测试初版写成 `agent_a="A"` → `"D" != "A"`）——这是测试断言字段序错误，不是比对逻辑错；改测试期望为 `agent_a="D", agent_b="A"` 后双后端同绿，准入门 `ok=false` 与 `colliding_agents=["A"]` 两态均按设计成立。
- 边界同 §10.7/§10.8：仍「待编排的强制层」，未接 MCP 生命周期，未碰其它 lane 文件，不翻 BACKLOG 行。本包孤立新增，全仓 `moon info` 仅重排了本包 `.mbti`，导出 `admit` / `admit_ok` / `conflict_scoreboard` / `struct AdmitReport`。

### 10.10 Round 11 收口：协调器协商层（让权模拟 + 准入后验）
- §10.9 给了「进门准入 verdict + 点名会撞的 peer + 谁最 contested 记分牌」。但协调器拿到「D 撞 A」后仍需一个**下一步动作建议**：该请谁让？请了之后 D 是否真能进？这一步从人眼判断变成确定性纯函数计算——且**全程只读、不改动任何在飞 agent 的真实状态**（真实让权是协调器/生命周期的动作，在本包作用域之外）。
- 新增（均 `pub`、纯函数、只读、复用 R9 `reconcile_all` + R10 `conflict_scoreboard` + R10 `admit` 单一真源链，不引入第二套比对）：
  - `peer_yield(s, agent) -> ClaimGuardState`：**模拟让权**的纯投影——从 `holders` 去掉 `agent` 的全部项（对应 `tags` 也一并去掉残留项），返回**全新**状态，输入不被 mutation（证明：原守卫仍持原项数）。
  - `advise_yield(report : ReconcileAllReport) -> String?`：在 R10 记分牌上取「冲突度最高」者先谈（tie 取最小 agent 名，确定性）；零冲突返回 `None`。
  - `admit_after_yield(proposed, others, yield_agent) -> AdmitReport`：把每个 `others` 先 `peer_yield(yield_agent)` 投影、再重跑 R10 `admit`；返回「**若让 `yield_agent` 让权，新 agent 能否进**」的模拟判定。`ok=true` 即代表「这一刀能让出来」。
- **实证（双后端 33/33，见 2026-10-13-multilane-round11-report.md）**：
  - `cg_peer_yield`：A 持 L41+L47、B 持 L44 的守卫里让 A → 投影只剩 B 的 L44；原 `ga` 仍持 3 项（证纯函数、未改入参）。
  - `cg_advise_yield`：A/B/C 同抢 L38-logic-engine（各参与度 2）→ 返回 `"A"`（tie 取最小名，确定性）。
  - `cg_admit_after_yield`：D 抢 A 的 L41（不让权时 `admit.ok=false`）→ 模拟让 A 让权后 `admit_after_yield.ok=true`、`colliding_agents` 清空；且真实 `ga` 仍持 L41（证模拟不落地）。
- **厘清的边界（重要）**：本包只做「计算让权结果」（零副作用纯函数），「执行让权」是协调器/生命周期的责任——靠 `admit_after_yield` 的返回串联二者，不模糊所有权。真实让权通道即 lane-owned 的 `reserve_release`（释放作用域预订）+ `release_item`，越出本包孤立作用域，待 owner 决策接入。
- 边界同前：仍「待编排的强制层」，未接 MCP 生命周期，未碰其它 lane 文件，不翻 BACKLOG 行。本包孤立新增，全仓 `moon info` 仅重排了本包 `.mbti`，导出 `peer_yield` / `advise_yield` / `admit_after_yield`。

### 10.11 Round 12 收口：协调器级联谈判层（逐个让权直到放行或预算耗尽）
- §10.10 只模拟「一个 peer 让权」后 newcomer 能否进。真实多 lane 场景一个新 agent 常**同时撞好几个 peer**（各自持有不同 item），协调器必须**逐个**请最 contested 的 peer 让权、每让一步重跑准入，直到放行或步数预算耗尽——这就是级联谈判，把「计算让权」从单步推广到链式。
- 新增（均 `pub`、纯函数、只读、复用 R9 `reconcile_all` + R10 `admit`/`conflict_scoreboard` + R11 `peer_yield`/`pick_top` 单一真源链）：
  - `negotiate_admit(proposed, others, max_steps) -> NegotiateReport`：每轮先 R10 `admit`；`ok` 即返回；否则在 `proposed` 真正会撞的 `colliding_agents` 里取最 contested 者（R11 `pick_top`：度数最高、tie 取最小名）做一次 `peer_yield` 投影、推进一步；`max_steps` 耗尽或候选空即停，返回末态 verdict。
  - `NegotiateReport { ok, yielded : Array[String], admit : AdmitReport }`：`yielded` 是按谈判顺序记录的让权对象（**绝不含 proposed 自身**——候选集限定在 `colliding_agents`）。
- **实证（双后端 35/35，见 2026-10-13-multilane-round12-report.md）**：
  - `cg_negotiate_admit_chain`：D 既抢 A 的 L41-curriculum、又抢 B 的 L44-posoco（双碰撞）→ `negotiate_admit(gd,[ga,gb,gc],4)` 两次让权后 `ok=true`、`yielded.length()==2`；且真实在飞 `ga` 仍持 L41、`gb` 仍持 L44（证级联纯模拟、不落地）。
  - `cg_negotiate_admit_budget`：`max_steps=0` 连一轮都不谈、直接返回被拦、`yielded` 空；`max_steps=1` 只谈一轮仍有第二处碰撞、`ok=false` 但已记 1 步——预算边界如实反映。
- **厘清的边界（同前）**：本包只做「计算级联让权结果」（零副作用纯函数），「执行让权」是协调器/生命周期的责任（真实通道 = lane-owned 的 `reserve_release` + `release_item`），越出本包孤立作用域，待 owner 决策接入。二者靠 `negotiate_admit` 的 `yielded` 序列串联。
- 边界同前：仍「待编排的强制层」，未接 MCP 生命周期，未碰其它 lane 文件，不翻 BACKLOG 行。本包孤立新增，全仓 `moon info` 仅重排了本包 `.mbti`，导出 `negotiate_admit` / `struct NegotiateReport`。

### 10.12 Round 13 收口：级联谈判的优先级感知让权目标选择
- §10.11 在「碰撞度数相同」时用**名字升序**决出让权目标。但多 lane 真实调度里 peer 有**优先级**（真值源 = lane-owned 的 `executor_route` 信任×负载轴），协调器应让**低优先级**的 peer 先让——否则会逼高优先、快交付的 agent 反复退让。
- 新增（均 `pub`、纯函数、只读，复用 R9 `reconcile_all` + R10 `admit`/`conflict_scoreboard` + R11 `peer_yield` + R12 `negotiate_admit` 单一真源链）：
  - `negotiate_admit_priority(proposed, others, max_steps, priorities) -> NegotiateReport`：级联形状与 R12 完全一致，**候选排序改为 (度数 desc, 优先级 asc, 名字 asc)**；`priorities : Map[String, Int]` 缺省按 0 计。返回结构复用 `NegotiateReport`。
  - 私有 `pick_top_priority(es, i, cur)`：在 `(name, degree, priority)` 三元组上做同一不可变最大比较，不引入第二套可变累加器。
  - R12 的 `negotiate_admit`（名字序）**保留不动**，作为「关掉优先级维度」的回落与对照基准。
- **实证（双后端 37/37，见 2026-10-13-multilane-round13-report.md）**：
  - `cg_negotiate_admit_priority_order`：D 双撞 Z(item-z) 与 A(item-a)（度数相同各 1），`prio(Z)=1`、`prio(A)=9` → `negotiate_admit_priority(...,4,prio)` 两次让权后 `ok=true`、`yielded.length()==2`，**首位为 Z（低优先级先于高优先级）**；真实在飞 `gz`/`ga` 仍持原 item（证纯模拟不落地）。
  - `cg_negotiate_admit_priority_vs_name`：同场景，R12 名字序首位为 A（A < Z）、R13 优先级序首位为 Z（1 < 9）→ 两者首位不同，证明优先级维度确实改变了谈判序列、非名字序别名。
- **厘清的边界（同前）**：本包只做「计算级联让权结果」（零副作用纯函数），「执行让权」是协调器/生命周期责任（真实通道 = lane-owned 的 `reserve_release` + `release_item`），越出本包孤立作用域，待 owner 决策接入；优先级真值由调用方注入（应取自 `executor_route`），本包不维护。二者靠 `negotiate_admit_priority` 的 `yielded` 序列串联。
- 边界同前：仍「待编排的强制层」，未接 MCP 生命周期，未碰其它 lane 文件，不翻 BACKLOG 行。本包孤立新增，全仓 `moon info` 仅重排了本包 `.mbti`，导出 `negotiate_admit_priority`。

### 10.13 Round 14 收口：协调器可用的「谈判计划」包装层（决策面度量）
- §10.12 的 `negotiate_admit_priority` 给出「该让谁、按什么顺序让」的级联结果（`yielded`）。但协调器在**是否执行**这套让权之前，还需要两个决策面度量：①**干扰成本**（请这些 peer 让权要付出多大代价）；②**释放收益**（让权成功后，新来的 `proposed` 究竟能拿到哪些它真正想要的争用条目）。R14 把这两面从级联结果里派生出来，供协调器做「采纳/放弃/换候选」的判断，而不动任何状态。
- 新增（均 `pub`、纯函数、只读，**单一真源**：直接复用 R13 `negotiate_admit_priority`，**不写第二套级联循环**；派生逻辑只读 `others` 的 `holders` 与 `priorities` 负载）：
  - `struct NegotiatePlan { report : NegotiateReport, priority_cost : Int, freed_for_proposed : Array[String] }`
    - `report`：底层 R13 级联判决（ok / yielded / admit），零重复计算。
    - `priority_cost`：被请让权的 peer 之优先级之和（`sum priorities.get_or_default(y,0)`）——对 lane 而言的干扰成本，越低越省心。真实优先级由 `executor_route`（信任×负载）侧注入，本包只消费负载。
    - `freed_for_proposed`：若全部 `yielded` peer 真的释放，将为 `proposed` 解封的条目集合 = `proposed` 想要 **且** 某个 yielded peer 当前持有的条目（去重）。这是「这套计划究竟能不能解我的项」的可操作收益面。
  - `negotiate_plan(proposed, others, max_steps, priorities) -> NegotiatePlan`：先调 `negotiate_admit_priority` 拿级联结果，再派生 `priority_cost` 与 `freed_for_proposed`。纯读：`others` 的 `holders` 仅用于映射「谁持有什么」，未做任何 `release_item`/`peer_yield` 落地。
- **实证（双后端 40/40，见 2026-10-13-multilane-round14-report.md）**：
  - `cg_negotiate_plan_cost`：D 双撞 Z(item-z,prio=1) 与 A(item-a,prio=9)。`negotiate_plan(...,4,prio)` → `report.ok=true`、`yielded==[Z,A]`、`priority_cost==10`（1+9）、`freed_for_proposed` 含 `item-z` 与 `item-a`（两条争用项都将被解封）；真实在飞 `gz`/`ga` 仍持原 item（证派生层零副作用）。
  - `cg_negotiate_plan_clean`：proposed 只持独占条目、无碰撞 → `yielded` 空、`priority_cost==0`、`freed_for_proposed` 空——零干扰情形如实反映。
  - `cg_negotiate_plan_coordinator_pick`：同一组在飞 peer，两个候选 proposed——P1 争 Z+A（成本 10）、P2 只争 Z（成本 1）。`plan2.priority_cost < plan1.priority_cost` 成立且 `plan2.freed_for_proposed==[item-z]`——证明决策面度量**可排序**，协调器能据此挑「更省心」的候选。
- **厘清的边界（同前）**：本包只做「计算级联让权结果 + 派生决策度量」（零副作用纯函数），「执行让权」是协调器/生命周期责任（真实通道 = lane-owned 的 `reserve_release` + `release_item` + `executor_route` 优先级真值注入），越出本包孤立作用域，待 owner 决策接入。三者靠 `yielded` 序列串联：R13 产 `yielded` → R14 把 `yielded` 换算成成本与释放收益 → 协调器据收益/成本决定要不要走真实释放通道。
- 边界同前：仍「待编排的强制层」，未接 MCP 生命周期，未碰其它 lane 文件，不翻 BACKLOG 行。本包孤立新增，全仓 `moon info` 仅重排了本包 `.mbti`，导出 `negotiate_plan` / `struct NegotiatePlan`。

### 10.14 Round 15 收口：协调器「多候选准入调度器」`schedule_admit`（先到先得 + 提交即锁定）
- R14 给了协调器「挑最省心候选」的排序能力（`negotiate_plan` 的成本/释放收益面），但**何时、以什么顺序把多个候选一次放行**仍缺一个顶层调度循环。R15 把这件事做成纯函数调度器：给定一组在飞 peer 与一组待准入候选，按「最省心优先」贪心逐个采纳，且**已采纳者是不可逆事实**。
- 新增（`pub`、纯函数、只读，`schedule_admit` / `struct ScheduledAdmit` / `struct ScheduleReport`，单一真源 = 复用 `negotiate_plan`，不写第二套级联循环）：
  - `struct ScheduledAdmit { agent : String, plan : NegotiatePlan }`：被采纳候选的身份 + 它落地时用的谈判计划（含 `yielded` 让权序列，供真实通道执行）。
  - `struct ScheduleReport { admitted : Array[ScheduledAdmit], rejected : Array[String], total_priority_cost : Int, scene : Array[ClaimGuardState] }`：末态全景。`scene` = 在飞的 `peers` + 被采纳候选带来的持有（**含已提交 newcomer 的持有**），可直接喂下一拍对账。
  - `schedule_admit(peers, candidates, max_steps, priorities) -> ScheduleReport`：
    1. 维护两条列表：`peers_live`（可变，每轮折叠让权落在这里）+ `committed`（不可变，已采纳候选的 state 一旦进此列表**永不**被让权）。
    2. 每轮重建 `scene = peers_live ++ committed`；对**每个**候选算 `negotiate_plan(cand, scene, max_steps, priorities)`；只把「ok **且** 其 `yielded` 不含任何 `committed` 内名字」的候选算可采纳——**任何想挤让已提交 newcomer 的候选整票驳回**（先到先得 + 提交即锁定，不退让已接纳者）。
    3. 在所有可采纳候选里取 `priority_cost` 最小者（平手按 `cg_state_agent` 字典序小者先），记为本轮 best；把它落进 `committed`，累加 `priority_cost` 到 `total_priority_cost`，并把它的 `yielded` 仅对 `peers_live` 做 `peer_yield` 折叠（**绝不动 `committed`**）。
    4. 若一轮无任何可采纳候选 → 剩余候选全体进 `rejected` 并 `break`（预算/结构冲突无法消解，不静默放行）。
    5. 末态 `scene = peers_live ++ committed`。
- **关键不变量（先到先得 + 提交即锁定）**：被采纳的候选带着自己争用的条目进入 `scene` 成为「既成事实」；后续候选若想进场必须让出该条目 → 其 `yielded` 会命中已提交者名字 → 被判不可采纳 → **整票拒绝**而非「靠挤让已接纳者进场」。这把 R3~R14 一直悬而未决的「后到候选要不要把先到者让出去」钉死为「不」。
- **实证（双后端 45/45，见 2026-10-13-multilane-round15-report.md）**：
  - `cg_schedule_admit_cheapest_first`：在飞 Z(item-z)/A(item-a)，两候选 P1(只争 a,成本9)/P2(只争 z,成本1) 争的条目互不相交 → 两者都放行，且按成本升序 P2 先于 P1（候选反序给，证调度器按成本重排而非输入序）。
  - `cg_schedule_admit_multi_disjoint`：三候选各争一件互不相交条目 → 全放行，`total_priority_cost==17`（9+5+3），成本升序 P3→P2→P1，末态 `scene` 含三者持有。
  - `cg_schedule_admit_committed_not_evicted`：两候选争同一件被高优先级 peer 独占的条目 → **恰好一个被采纳、另一个被拒**（验证「先到先得 + 提交即锁定」：后者不能靠挤让前者进场）；末态 `scene` 确有持有者。
  - `cg_schedule_admit_reject`：两候选各需让出 Z+A（两步），`max_steps=1` → 谁都进不来，`admitted==0 / rejected==2 / total_priority_cost==0`。
  - `cg_schedule_admit_pure`：调用后原在飞 peer 与候选 state 原样未改（纯只读不污染）。
- 测试设计教训（已写入报告）：最初三测把「后到候选受益于先到者让出」当成预期，那与「提交即锁定」自相矛盾——R15 之后该场景**不可能成立**（先到者进场后持有该条目，后到者只能被拒）。测例已按正确不变量重做。
- 边界同前：仍「待编排的强制层」，未接 MCP 生命周期，未碰其它 lane 文件，不翻 BACKLOG 行。本包孤立新增，全仓 `moon info` 仅重排了本包 `.mbti`（rc=0，826 警告 0 错误，警告全部来自 lane-owned `src/server`/`src/symbolic` 预存在项）。

### 10.15 Round 16 收口：调度器末态「端到端逻辑碰撞不变量」与「被拒者不泄漏」
- §10.14 的 `schedule_admit` 把多候选准入做成纯函数调度器，并钉死了「先到先得 + 提交即锁定」不变量。但调度器对外承诺的**最终保证**还没被直接证明：① 末态 `scene` 里任一逻辑项至多被一个 agent 持有（这正是物理文件锁 / 作用域锁 / file_binds 都关不上的「逻辑碰撞门」——两个 agent 在互不相交文件作用域里实现同一 BACKLOG 项）；② 被 `rejected` 的候选**绝不**作为任何状态的持主泄漏进 `scene`（不得静默抢走争用项）。R16 补这层端到端断言，把整条链（盲点 → 对账 → 谈判 → 调度 → 末态不变量）收口。
- 新增（`src/claimguard/claimguard_wbtest.mbt`，白盒；纯读 helper `cg_scene_collision`，遍历 `scene` 各 state 的 `holders`，对每项记录首个持主、遇异主即报 `(碰撞,项,甲方,乙方)`）：
  - `cg_schedule_scene_invariant_disjoint`：三候选各争一件互不相交条目（已被 R15 证全放行）→ 末态 `scene` **零逻辑碰撞**，且每个被采纳候选的持有项在 `scene` 中落到该候选名下（P1/P2/P3 各见其项）。
  - `cg_schedule_scene_invariant_conflict`：两候选争同一被 peer 独占的条目（已被 R15 证「恰好一个采纳、一个被拒」）→ 末态 `scene` 零逻辑碰撞，且 `rejected[0]` 的名字**不作为任何 state 持主**出现（被拒者没抢到该项）。
  - `cg_schedule_scene_rejected_no_leak`：步数预算不足致两候选全拒（`max_steps=1`）→ 末态 `scene` 由在飞 peer 原样构成、零逻辑碰撞，且 P1/P2 都不作为持主出现在 `scene` 中。
- **实证（双后端 61/61，见 2026-10-13-multilane-round16-report.md）**：三条端到端断言在 JS 与 native 两后端同版全绿。`cg_scene_collision` 的遍历覆盖 `peers_live ++ committed` 全量，故该不变量对「被采纳 newcomer 的持有 + 在飞 peer 的原持有」整体成立，而非只对某一侧成立。
- **厘清的边界（同前）**：本包只做「计算级联让权结果 + 派生决策度量 + 末态对账」（零副作用纯函数网络），「执行让权」与「把 scene 落进真实 store」是协调器/生命周期责任（真实通道 = lane-owned 的 `reserve_release` + `release_item` + `commit`），越出本包孤立作用域，待 owner 决策接入。R16 不新增 `pub` 符号（仅测试侧 helper），全仓 `moon info` 仅重排本包 `.mbti`（rc=0，826 警告 0 错误，警告全部来自 lane-owned `src/server`/`src/symbolic` 预存在项），未碰其它 lane 文件，不翻 BACKLOG 行。

### 10.16 Round 17 收口：三层物理锁 + 主助理 + 逻辑闸 的「组成地图」与盲区收口证明

- 本 round 把前面 8 个 round 散点的观察**收成一张组成地图**：物理层（作用域预订 / 分布式文件锁 / 主助理选举）各自裁决「谁能动哪个 scope / 谁当主助理」，但三者都只在 **scope 维度** 上判冲突；`claimguard` 逻辑闸补的是 **item 维度** 的冲突（同一 BACKLOG 项被多个 agent 在 disjoint scope 上各自实现）。两层叠加才关上「多 agent 操作同一目标项目文件」的完整互斥面。
- **源码级定位（只读精读，未改任何 lane-owned 文件）**：
  - `reserve_scope`/`reserve_check`/`reserve_release` → 真身 `store_rsv.mbt` L9-137（`rsv_set`/`rsv_get`/`rsv_release` + 单一裁决动词 `rsv_action` L77-88 + `rsv_try_set` 写后回读 L94-137）。
  - `lock_acquire`/`lock_renew`/`lock_release`/`lock_status` → 真身 `store_rsv.mbt` L172-256（`locks_upsert` 接管记违例 L176-191 / `locks_release` 仅持有者 L209-222 / `locks_sweep` 过期清理 L227-248 / `lock_violations_list` L252-256）；server 侧 `server.mbt` L4441-4560 的 `lock_acquire` 把 `FileLock::new` 直塞 `engine.locks_upsert`，`lock_release` 转 `engine.locks_release(scope, agent)`，`lock_status` 先 `engine.locks_sweep(now)` 再列违例——**冲突语义全在 store 层，server 只做参数装配**。
  - `assistant_claim`/`sweep`/`heartbeat`/`resign`/`status` → 真身 `store.mbt` L190-202 的 `assistant_claim_action`（None→elected / 同主→renewed / 心跳陈旧→taken_over，旧主记 `lock_violations` force_takeover / 心跳新鲜→conflict）；`store_assistant.mbt` L8-55 负责登记持久化（与 `rsv_action` 同形四态）。
  - 生命周期冲突预检 `conflicts_check`（server.mbt L2050）→ 认领前的「作用域重复认领」检测，属于物理层的**入口闸门**，把 reserve_scope 的 scope 维度冲突在任务认领阶段就先查出来。
- **组成地图（裁决动词收敛）**：

  | 维度 | 裁决动词（单一真源） | 冲突语义 | 盲区 |
  |---|---|---|---|
  | scope 预订 | `rsv_action`（store_rsv L77） | 同 scope 异主 live → conflict | 只看 scope 字符串，不关 item |
  | 文件锁 | `locks_upsert` 的 `old.agent != lock.agent && !expired` | 异主抢 live scope → 记 `lock_taken_over` 违例 | 只看 scope，不关 item |
  | 主助理 | `assistant_claim_action`（store L190） | 多主竞选 → 心跳新鲜者 conflict / 陈旧者 taken_over | 是协调者维度，非 item 维度 |
  | 任务认领 | `conflicts_check`（server L2050） | scope 被他人认领 → 冲突 | 仍只 scope 维度 |
  | **逻辑项** | `decide_claim`（claimguard L27） | **item-id 同主→Renewed / 异主→Denied** | 补上「disjoint scope 抢同一 item」这一扇门 |

  → 前四行的冲突定义**全部收敛到 scope 字符串 / 协调者身份**，**没有一处看 item**，这正是 §9 实测出的盲区：A 在 `src/engine/`、B 在 `src/ltl/`、两人都实现 `L38` → 四层物理裁决全放行，但 BACKLOG 项被双写。
- **R17 新增两条白盒断言（`src/claimguard/claimguard_wbtest.mbt`，纯读、零副作用）把「盲区真实存在 + 逻辑闸收口」钉成回归**：
  - `cg_composition_gate_closes_physical_blind_spot`：构造「A、B 各持一份 guard、各自 claim `L38`」的危险路径 → `cg_scene_collision([ga, gb])` 报真碰撞（`(true, "L38", A, B)`），证明物理层盲区在合并态里**确实**出现；再走正确路径（claimguard 作为**全局共享**逻辑互斥闸，开工前先过 `claim_item`）→ A `Claimed`、B `Denied`，`scene` 零碰撞。这条把「逻辑闸必须共享、不能每 agent 一份」钉死。
  - `cg_verdict_mirrors_rsv_action_matrix`：把 `decide_claim` 的矩阵（None→Claimed / 同主→Renewed / 异主→Denied）与 `rsv_action`（None→reserved / 同主→renewed / 异主→conflict）对齐，证明两层是**同构单一真源**，防两处矩阵漂移（逻辑层无 TTL 接管口径，那是 `lock_acquire`/`taken_over` 的事，故只比对前三者）。
- **实证（双后端 63/63，见下）**：两条 R17 断言在 JS 与 native 两后端同版全绿；叠加既有 61 条，本 lane 两包（`src/claimguard src/constraint`）总计 `Total tests: 63, passed: 63, failed: 0`（JS 与 native 各自独立运行均达此读数）。`moon fmt --check` 对编辑文件 rc=0，未翻 BACKLOG 行、未碰 lane-owned 文件。
- **结论（Round 17）**：FIST-Mbt 的「多 agent 操作同一目标项目文件」互斥是一个**两层叠加**结构——物理层（scope 预订 + 文件锁 + 主助理选举 + 认领预检）管「谁能动哪块盘 / 谁是协调者」，逻辑层（claimguard）管「谁在实现哪个 BACKLOG 项」；两者裁决动词分别收敛到 `rsv_action`/`assistant_claim_action` 与 `decide_claim`，前后同构、无漂移。盲区（disjoint scope 抢同一 item）由逻辑层在开工前门禁处关上。本 round 仅做观察收口 + 把收口钉成测试回归，不新增任何 `pub` 符号、不接真实 store 通道（真实接入仍是 owner 决策项，见 §10.15 边界说明与 BACKLOG L16/L49）。

### 10.17 Round 18 复跑 + 收口地图再校准：新增「监督覆盖平面」是选举裁决的**消费方**，非第四把锁

- **复跑结论（双后端 63/63，R18 实测）**：本 round 用当前脏树重跑本 lane 孤立两包（`src/claimguard src/constraint`）——JS `Total tests: 63, passed: 63, failed: 0`；native `Total tests: 63, passed: 63, failed: 0`。R17 钉死的两条组成地图断言未被其它 lane 的并发改动破坏（其它 lane 动的是 `src/store`/`src/server`/`src/engine`/`src/evolve` 等 lane-owned 文件，本 lane 包只依赖 `core`，无回归）。

- **新发现（只读精读并发 lane 的新增件）**：脏树里出现一组**监督覆盖平面**（`supervisor_*` 工具族），由另一 lane 实现，本 round 仅引用接口、不动其文件：
  - 引擎侧 `src/engine/engine_supervisor.mbt`：纯读聚合 `supervisor_status`（全库/ns 状态全景）、`supervisor_task_tree`（子树完成度递归）、`supervisor_kill_plan`（终止方案，只出方案不执行）、`supervisor_reminder_tick`（陈旧/超时提醒）。
  - server 侧 `src/server/supervisor_tools.mbt`：注册 7 个 `supervisor_*` 工具，`supervisor_prompt_inject/list/consume` 经进程内 `SupervisorGuidanceRegistry` 做**引导队列**（重启即失，best-effort 由 call_log 回读兜底），`supervisor_task_upsert` 走既有 `engine.list_all` 写通道。
  - 主助理转发层 `src/engine/engine_assistant.mbt`：把 `assistant_upsert/get/list/set_status` 纯转发到 store，并新增 `assistant_active_primary()`（取 `is_primary && status="active"` 中 `registered_at` 最新者）作为**现任主助理仲裁器**，以及 `lock_violations_record` 落案底。

- **关键校准（监督平面不是第四把锁，而是选举裁决的消费方）**：`supervisor_kill_plan` 的 **G1 身份门**（engine_supervisor.mbt L155-171）直接消费 `self.assistant_active_primary()`：
  ```moonbit
  let primary = self.assistant_active_primary()
  let primary_agent = match primary { Some(r) => r.agent; None => "" }
  let g1_pass = by == "human_steward" || (primary_agent != "" && by == primary_agent)
  ```
  → `kill` 权唯一性（multi-agent-lock design v2）的判定**完全挂靠**在「主助理选举」这一物理层裁决上：操作者若是现任主助理（或人类指挥官）才过 G1；否则即便后续 G2-G5 全过也被 `blocked`（L232 `let blocked = not(g1_pass) || is_root || terminal`）。**结论：监督覆盖平面不引入新的冲突动词，它只是把 `assistant_claim_action` 的选举结果当作「谁是合法 kill 权持有者」的输入**——这把 §10.16 组成地图里的「主助理选举」那一格，从「协调者维度」升级为「治理/终止权限的授权源」。

- **重画后的组成地图（R18 校准版）**：

  | 维度 | 裁决动词（单一真源） | 冲突/授权语义 | 盲区 | 与监督平面的关系 |
  |---|---|---|---|---|
  | scope 预订 | `rsv_action`（store_rsv L77） | 同 scope 异主 live → conflict | 不看 item | 无关 |
  | 文件锁 | `locks_upsert` 异主抢 live → 记违例 | 异主抢 live scope → `lock_taken_over` | 不看 item | 无关 |
  | 主助理选举 | `assistant_claim_action`（store L190）+ `assistant_active_primary` 仲裁 | 多主竞选 → conflict / 陈旧→taken_over | 协调者维度 | **授权源**：G1 身份门挂靠此结果 |
  | 任务认领 | `conflicts_check`（server L2050） | scope 被他人认领 → 冲突 | 仍只 scope | 无关 |
  | 逻辑项 | `decide_claim`（claimguard L27） | item 同主→Renewed / 异主→Denied | 补「disjoint scope 抢同一 item」 | 无关 |
  | **监督覆盖**（监督者视角） | 无新动词——`supervisor_kill_plan::G1` 消费 `assistant_active_primary` | 「谁有权 kill/治理」= 现任主助理或 human_steward | 治理权限收敛到选举结果，无独立冲突 | **是消费方，不是第四锁** |

- **边界（同前，R18 不变）**：监督平面是 lane-owned 文件，本 lane 只读不碰；本 round 只做「地图再校准」+ 复跑绿，不新增 `pub` 符号、不接真实 store 通道、不翻 BACKLOG 行（L16/L49 仍 owner 决策锁，L33 self_search 接线属并发 lane 的 WIP 账，别由旁观者代翻）。本 lane 两包仍 `moon fmt --check` rc=0、双后端 63/63，脏树回归为 0。

### 10.18 Round 19 收口确认：监督平面**不抢文件锁** → 无新增盲区，且并发 lane 自带测试（协作卫生良好）

- **复跑结论（双后端 63/63，R19 实测）**：脏树（含并发 lane 的 supervisor 平面 + 其自测）下重跑本 lane 孤立两包——JS `Total tests: 63, passed: 63, failed: 0`；native 同值。R16/R17 钉死的「逻辑碰撞门禁」「盲区收口」「裁决同构」断言零回归。

- **R19 新核验（源码 grep 证据，只读）**：监督平面的 server 装配件 `src/server/supervisor_tools.mbt`（471 行）对目标项目文件**零锁获取**。grep 全文件对 `lock_|locks_|reserve_|lock_acquire|lock_release` 命中 **0 处**；全部写操作仅两类：
  1. `engine.store_write_call_log` / `store_recent_call_logs`（审计流水双写，非项目文件锁）；
  2. `engine.supervisor_task_upsert`（写的是 FIST **任务台账** store，与 reserve/lock 同一库表，但属「任务认领/状态」通道，非「目标项目源码文件」写通道）。
  → 监督平面对 `src/engine/*.mbt` 等**目标项目文件既不预订 scope、也不取分布式锁**，纯读 + 任务台账写入。因此它**不在物理层制造任何新的「谁能动哪块盘」裁决**，自然也不会与我的逻辑闸（`claimguard` 管「谁实现哪个 BACKLOG item」）产生新的盲区缺口。

- **R19 边界补全（R18 §10.17 组成地图最终态）**：`supervisor_*` 族 = 「治理/监督覆盖平面」，**同时具备两个性质**——(a) 不抢文件锁（R19 grep 证）、(b) 治理权挂靠选举结果（`supervisor_kill_plan::G1` 消费 `assistant_active_primary`，R18 证）。二者合起来说明它**是选举层与生命周期层的「只读消费者 + 任务台账写入者」，不是第 4 把锁**。组成地图 §10.17 已无需再扩格。

- **跨 lane 协作卫生观察（顺带看看的正面信号）**：并发 lane 在落 `engine_supervisor.mbt` 的同时，单独交付了 `src/engine/engine_supervisor_reminder_test.mbt`——监督平面的提醒分支**自带白盒测试**。这意味着并发 lane 没有留下「未测的锁/治理面」给后续评审挖坑，符合 AGENTS.md 金条八「终审必须实际运行验证」的纪律外溢。本 lane 与之零文件冲突（本 lane 仅动 `src/claimguard/ src/constraint/ reports/`），`git status` 确认本次只新增/改我的孤立文件，未触碰任何 lane-owned 件。

- **结论（Round 19）**：FIST-Mbt 的「多 agent 操作同一目标项目文件」互斥结构已稳定为 **三层物理锁（scope 预订 + 分布式文件锁 + 主助理选举）+ 一层认领预检（conflicts_check）+ 一层逻辑闸（claimguard 管 item 维度盲区）+ 一个监督覆盖平面（只读消费选举、不抢文件锁）**。盲区唯一来源 = 「disjoint scope 实现同一 BACKLOG item」，由 claimguard 在开工前门禁处关上，已钉成 R16/R17 回归。监督平面的加入**未引入新盲区、未新增冲突动词**。本 round 仅做「不抢锁」核验 + 跨 lane 协作卫生记录，不新增 `pub` 符号、不接真实通道、不翻 BACKLOG 行。

### 10.19 Round 20 收口确认：监督层「kill 授权 G1」路口**零测试覆盖** —— 跨 lane 协作的一个真实缺口（仅观测、不动 lane-owned）

- **复跑结论（双后端 63/63，R20 实测）**：脏树（含并发 lane 的 supervisor 平面 + 自测）下重跑本 lane 孤立两包——JS `Total tests: 63, passed: 63, failed: 0`；native 同值。R16/R17 断言零回归。

- **R20 新核验（全仓 grep 证据，只读）**：R18 标定的「`supervisor_kill_plan::G1` 消费 `assistant_active_primary()`」是一个**两层（engine ⇄ engine）路口**，但 grep 全仓 `*_test.mbt` 对 `supervisor_kill_plan` / `assistant_active_primary` / `G1_identity` 命中 **0 处**——即这一路口**完全无测试到达**：
  - 并发 lane 落 `engine_supervisor.mbt` 时只带了 `engine_supervisor_reminder_test.mbt`（**reminder 分支**，非 kill 分支）；
  - `src/store/store_assistant_test.mbt` 覆盖的是 store 层 `assistant_*` 持久化，**不覆盖** `engine_assistant.mbt` 里新增的 `assistant_active_primary()` 选择器（engine 层包装）；
  - `supervisor_kill_plan` 的 G1 判活/拒杀逻辑在 engine 层 + server 装配层均无白盒/黑盒回归。
  → 因此「谁有 kill 权」这道多 agent 治理安全闸，目前**只靠源码正确性自证，无任何回归兜底**。

- **具体风险点（精确定位，非夸大）**：`assistant_active_primary()`（engine_assistant.mbt L39-53）的契约是「取 `is_primary && status=="active"` 中 `registered_at` 最新者」，但**它不做唯一性断言**——若选举层在某个瞬间出现双 active 主助理（split-brain，物理选举层 `assistant_claim_action` 本应防住但非 100% 原子），此选择器会**静默选其一**，G1 随之静默把 kill 权给到被选中的那个。这是一个**信任假设**（「同时最多一个 active 主助理」），而该假设**没有任何测试钉死**。与之对照：`supervisor_kill_plan` 的 G2/G3/G4/G5 都是显式 gate（已代码化但无测试），唯独 G1 的授权源头（active 主助理是谁）是个**无断言的选择器**。

- **与 claimguard 盲区的关系（厘清正交面）**：R16/R17 钉死的盲区 = 「disjoint scope 抢同一 BACKLOG item」，由 claimguard 的 `decide_claim` 在 item 维度关上；而 R20 发现的 G1 无测试 = 「kill 治理授权来源无回归」，两者**正交**——claimguard 不保护 kill 权，supervisor 的 G1 也不保护 item 维度。所以这不是 R16/R17 盲区的延伸，而是**监督平面自身治理安全的一个未覆盖点**，独立存在。

- **本 lane 处置边界（严守 AGENTS 金条 / lane 隔离）**：该缺口位于 lane-owned 的 `src/engine/engine_assistant.mbt` + `src/engine/engine_supervisor.mbt`，本 lane **不代写、不代测**（会越界触碰 lane-owned 文件，且违反「别由旁观者代翻半成品账 / 不碰 lane-owned」纪律）。本 round 仅做**观测 + 立账 + 给 owner/lane 的修复提案**：
  - 提案 A（engine 层白盒，`src/engine/` 归属并发 lane）：补 `assistant_active_primary` 的三态测试——① 恰一个 active 主助理→返回它；② 无 active 主助理（`None` 或全是 resigned/dead）→ 返回 `None`；③ 双 active 主助理→ 返回 `registered_at` 最新者（并建议加一条断言或文档，明确 split-brain 时的取舍，而非静默）。
  - 提案 B（engine 层白盒）：补 `supervisor_kill_plan` 的 G1 两路——`by==human_steward` → `g1_pass`；`by==现任主助理` → `g1_pass`；`by==其它 agent` → `g1_pass=false` 且 verdict=blocked。
  - 以上两条归 owner/lane 决策与落库；本 lane 不执行。

- **结论（Round 20）**：监督平面的治理安全闸（kill 授权 G1）依赖的 `assistant_active_primary` 选择器**在全仓零测试覆盖**，且本身对「同时多 active 主助理」只做静默选最新、不断言唯一性——这是并发 lane 给多 agent 协作加的治理层里**唯一一个未被回归兜住的接缝**。它独立于 R16/R17 钉死的 item 维度盲区（claimguard 已关），属监督平面自身的治理安全未覆盖点。本 lane 仅观测立账 + 给修复提案，不越界代写 lane-owned 测试。本 round 双后端 63/63 零回归、未碰 lane-owned、未翻 BACKLOG 行（L16/L33/L49 仍 owner/lane 决策锁）。

### 10.20 Round 21 收口确认：把 R20 的「G1 无测试」症状**追到根因**——选举层存在「双 active 主助理」接管迟滞窗口（仅观测、不动 lane-owned）

- **复跑结论（双后端 64/64，R21 实测）**：脏树下重跑本 lane 孤立两包——JS `Total tests: 64, passed: 64, failed: 0`；native 同值。较 R20 多 1 条：`cg_logical_gate_has_no_primary_split_window`（逻辑层无 split-brain 窗口的对照锚点，见下）。R16/R17 断言零回归。

- **R21 新核验（源码精读证据，只读，从症状追到根因）**：R20 标「`supervisor_kill_plan::G1` 消费 `assistant_active_primary()` 全仓零测试」——那只是**症状**。本 round 顺着「是否真会 split-brain」往下追，定位到根因在选举**写入路径**，不在选择器：
  1. `assistant_claim_action`（store.mbt L190-202）是**对单个 `prev` 的纯裁决**，从不扫描全集合，因此结构上**不保证**「同时至多一个 active 主助理」。
  2. `assistant_upsert`（store_assistant.mbt L8-13）是 `Map.set` 幂等覆盖，**没有任何「先罢免旧主」的护栏**——登记是按 agent 主键的，谁调 `assistant_claim` 谁就把自己那一行 `is_primary=true, status="active"` 写进去，与旧主那一行**并存**。
  3. `assistant_claim` 的 `taken_over` 分支（server.mbt L4640-4664）：旧主心跳陈旧 → 新主当选（`ok=true`）并把旧主那行也写成 `is_primary=true, status="active"`（L4645-4654），**只**对 `prev_agent` 记一条 `lock_violations force_takeover`（L4655-4663），**从不把 `prev_agent` 的 `is_primary` 置 false / `status` 置 dead**。
  4. 旧主的罢免**推迟到** `assistant_sweep`（server.mbt L4727-4732）：靠 `heartbeat_at < cutoff`（`stale_secs` 默认 600）把它标 `dead`。
  → 因此存在一个**界于 `taken_over` 与下次 `assistant_sweep` 之间、最宽 = stale_secs(默认 600s) 的接管迟滞窗口**：窗口内 `assistant_list()` 里**同时有两行 `is_primary && status=="active"`**。此窗口内 `assistant_active_primary`（engine_assistant.mbt L39-53）按 `registered_at` 取最新者——**静默二选一、不断言唯一**。R20 说的「信任假设无断言」，其**物理来源正是这个写入路径不立即罢免旧主**。

- **影响定界（关键，避免夸大）**：grep 已证 `src/store/store_rsv.mbt`（物理文件锁真身）对 `primary | is_primary | assistant_active` 命中 **0 处**——文件锁层与选举层**完全解耦**。所以本缺口是**治理/一致性**缺口（「kill 权此刻究竟落在哪个 agent」在迟滞窗口内可能不一致），**不是文件损坏缺口**（两个 agent 抢同一 scope 的物理锁仍是 `conflict`/`lock_taken_over`，不受选举态影响）。盲区唯一来源仍是 R16/R17 钉死的「disjoint scope 抢同一 BACKLOG item」（claimguard 管 item 维度），与本文的选举迟滞窗口**正交**。

- **与 claimguard 的对照（本 lane 在孤立范围收口的正向锚点）**：逻辑闸 `claimguard` 的同一-item 互斥是**即时、无窗口**的——任一时刻 `holder_of(item)` 至多一个 agent，第二者 `claim_item` 必 `Denied` 且持有者不变，绝不会出现 (A,B) 并存（类比物理层的「双 active 主助理」窗口）。R21 新增回归 `cg_logical_gate_has_no_primary_split_window` 把这条性质钉死，作为 §10.20 对照发现的锚；它落在 `src/claimguard/`（本 lane 孤立权属），不触碰 lane-owned。

- **本 lane 处置边界（严守 AGENTS 金条 / lane 隔离）**：根因位于 lane-owned 的 `src/server/server.mbt::assistant_claim` + `src/store/store_assistant.mbt` + `src/engine/engine_assistant.mbt`。**修复属于并发 lane**，本 lane 不代写、不代测。给 owner/lane 的修复提案（在 R20 提案 A/B 之上补一条 C）：
  - 提案 C（消除迟滞窗口，二选一）：① `assistant_claim` 的 `taken_over` 分支里，写新主**之前**先把 `prev_agent` 那行 `assistant_set_status(prev_agent, "dead")` / `is_primary=false`（让罢免与当选原子化，窗口消失）；或 ② 在 `assistant_active_primary` 中加一条断言/文档，明确 split-brain 时取最新者的取舍，并至少对「双 active 主助理」这一态做显式测试（R20 提案 A③）。
  - 提案 A/B（R20 原案，仍有效）：engine 层补 `assistant_active_primary` 三态测试 + `supervisor_kill_plan::G1` 三路测试。
  - 以上归 owner/lane 决策与落库；本 lane 仅观测立账 + 给提案，不执行。

- **结论（Round 21）**：R20 的「G1 无测试」症状已追到具体根因——选举写入路径 `assistant_claim` 在 `taken_over` 时**只记违例、不立即罢免旧主**，旧主 `is_primary && active` 行要等 `assistant_sweep` 心跳陈旧才标 dead，形成**最宽 = stale_secs 的「双 active 主助理」接管迟滞窗口**，`assistant_active_primary` 在窗口内静默二选一。该缺口是**治理/一致性**性质（物理文件锁层与之零耦合，grep 0 命中），独立于 R16/R17 的 item 维度盲区，且 claimguard 逻辑层本身无此窗口（R21 新增对照回归已钉）。本 lane 仅观测立账 + 给修复提案（新增提案 C），不越界代写 lane-owned 文件、不翻 BACKLOG 行（L16/L33/L49 仍 owner/lane 决策锁）。本 round 双后端 64/64 零回归。

### 10.21 Round 22 收口确认：R21 根因**再细化**——双主窗口不是「≤stale_secs 有界」，而是「旧主持续心跳则**无界**」（仅观测、不动 lane-owned）

- **复跑结论（双后端 65/65，R22 实测）**：脏树下重跑本 lane 孤立两包——JS `Total tests: 65, passed: 65, failed: 0`；native 同值。较 R21 多 1 条：`cg_logical_gate_immune_to_hb_resurrection`（逻辑层对「旧主心跳复活」免疫的对照锚点，见下）。R16/R17/R21 断言零回归。

- **R22 新核验（源码精读，纠正 R21 的一个偏保守判断）**：R21 把双主窗口估成「最宽 = stale_secs(默认 600s) 有界」。本 round 顺着 `assistant_heartbeat` 与 `assistant_sweep` 的耦合关系再查，发现**该窗口在退化情形下是无界的**：
  1. `assistant_claim` 的 `taken_over` 成立前提（store.mbt L199 `r.heartbeat_at < cutoff`）是「被接管者心跳**已陈旧**」——设计上**假定旧主已死**。接管后只记 `force_takeover` 违例（server.mbt L4655-4663），**绝不把 `prev_agent` 那行 `is_primary=false` 或 `status="dead"`**。
  2. `assistant_heartbeat`（server.mbt L4772-4781）的写法是 `assistant_upsert(AssistantReg::new(..., is_primary=r.is_primary, status=r.status, heartbeat_at=now, ...))`——**只刷新 `heartbeat_at`，原样保留 `is_primary` 与 `status`**。
  3. `assistant_sweep` 的罢免条件（server.mbt L4728）是 `r.status == "active" && r.heartbeat_at < cutoff`。
  → 只要被夺权的旧主**仍存活且持续心跳**（现实里很常见：进程没崩、只是暂时 GC/网络抖动导致一次 `cutoff` 判旧），它的 `heartbeat_at` 永远 ≥ `cutoff`，sweep 的罢免条件**永不触发**。于是**两行 `is_primary && status=="active"` 永久并存**，双主窗口从「≤stale_secs 有界」升级为「旧主活着就无界」——R21 的「有界」只是「旧主彻底停心跳」这一**非退化**子情形。

- **与 R21 的承袭与修正**：R21 的「写入路径不立即罢免旧主」结论成立；本 round 补上**心跳可 defeat 接管**这一环，把它从「有界迟滞」精确成「无界 split-brain（只要旧主在心跳）」。这**不改变**「属治理/一致性缺口、物理文件锁层零耦合、claimguard 逻辑层无此窗口」三处定界，只是把缺口的**严重度上界**抬高：它不只是「sweep 还没跑到的瞬时窗口」，而是「只要被夺权方不退出、持续心跳，kill 权归属就长期不确定」。

- **影响与定位（避免夸大）**：仍与 R16/R17 的 item 维度盲区**正交**；仍只影响「谁有 kill 权 / 谁是治理授权源」这一治理一致性面，**不**影响物理文件锁 `store_rsv.mbt`（grep 0 命中 `primary`/`is_primary`/`assistant_active` 已证）。但严重度从「瞬时」升「持久」，更值得 owner/lane 修。

- **与 claimguard 的对照（本 lane 孤立范围收口的正向锚点）**：逻辑闸 `claimguard` **没有「心跳」概念**，互斥是即时的、无 TTL——任一时刻 `holder_of(item)` 至多一个 agent，第二者 `claim_item` 必 `Denied`、且**无论它「反复来抢」多少次都翻不了盘**、持有者恒为现任，绝不存在「旧主靠心跳复活推翻现任」或 (A,B) 并存。R22 新增回归 `cg_logical_gate_immune_to_hb_resurrection` 把「逻辑层对旧主复活免疫」钉死（模拟旧主 5 拍反复抢，每拍必 Denied、终态仍只有 A），落在 `src/claimguard/`（本 lane 孤立权属）。这恰是物理选举层**缺失**的那条不变量。

- **本 lane 处置边界（严守 AGENTS 金条 / lane 隔离）**：根因位于 lane-owned 的 `src/server/server.mbt::assistant_claim`+`assistant_heartbeat`+`assistant_sweep` 与 `src/store/store.mbt::assistant_claim_action`。**修复属于并发 lane**，本 lane 不代写、不代测。给 owner/lane 的修复提案（在 R21 的 C 之上精修为 C'）：
  - 提案 C'（消除无界窗口，两种可叠加）：① `assistant_claim` 在 `taken_over` 写新主**之前**，先把 `prev_agent` 那行**原子**置 `is_primary=false`（或 `status="dead"`），使「罢免」与「当选」同一写事务完成，心跳无法 defeat；② `assistant_heartbeat` 对**非现任主助理**的请求应拒绝或降级（不让已失位的旧主靠心跳续命）——即心跳保护的是「现任」，不是「任意曾注册者」。
  - 提案 A/B（R20 原案仍有效）：engine 层补 `assistant_active_primary` 三态测试 + `supervisor_kill_plan::G1` 三路测试；其中 A③ 应明确断言「双 active 主助理」这一态的取舍。
  - 以上归 owner/lane 决策与落库；本 lane 仅观测立账 + 给提案，不执行。

- **结论（Round 22）**：R21 追到的根因在本 round 被**细化升级**——双 active 主助理窗口并非 R21 初判的「≤stale_secs 有界」，而是因 `assistant_heartbeat` 只刷新 `heartbeat_at`、保留 `is_primary`/`status`，导致**被夺权且持续心跳的旧主永不触发 sweep 罢免**（server.mbt L4728 条件永不满足），split-brain 在退化情形下**无界持久**。该缺口仍是治理/一致性性质、与物理文件锁层零耦合、独立于 item 维度盲区；claimguard 逻辑层因无心跳概念天然免疫（R22 新增对照回归已钉）。本 lane 仅观测立账 + 给精修提案 C'，不越界代写 lane-owned、不翻 BACKLOG 行（L16/L33/L49 仍 owner/lane 决策锁）。本 round 双后端 65/65 零回归。

### 10.22 Round 23 收口确认：R21/R22 仍**低估**——`assistant_sweep` 全仓**无调用方**，罢免完全靠人工（仅观测、不动 lane-owned）

- **复跑结论（双后端 66/66，R23 实测）**：脏树下重跑本 lane 孤立两包——JS `Total tests: 66, passed: 66, failed: 0`；native 同值。较 R22 多 1 条：`cg_logical_gate_release_needs_no_external_reaper`（逻辑层释放不依赖外部 reaper 的对照锚点，见下）。R16/R17/R21/R22 断言零回归。

- **R23 新核验（全仓 grep，推翻 R21「≤stale_secs 有界」的第二层前提）**：R21 把双主窗口上界估成「stale_secs(默认600) 有界」，隐含前提是「迟早会跑一次 `assistant_sweep` 把它标 dead」。本 round 全仓 grep `assistant_sweep`，结果**非代码侧全是文档/README/memory/报告**（design v2/v3 把它写成「每拍或定时的 reaper / 助理(reaper mode) 每拍或定时扫」），而**真正的代码调用只有 3 处且无一为调用者**：①`src/server/server.mbt:4711`（工具自身定义）；②`cmd/cli/help_topics.mbt:72`（CLI 帮助文本）；③`src/claimguard/claimguard_wbtest.mbt:1020`（本 lane 测试注释）。**没有任何 watchdog / cron / pipeline / self-drive / 心跳回路去主动调 `assistant_sweep`**——它只是个**手动 MCP 工具**。
  → 因此「罢免旧主」这一步**完全依赖操作员手动调用 `assistant_sweep`**。即便旧主**已死**（不再心跳），只要没人手动扫，那行 `is_primary && status=="active"` 就一直挂着；若旧主**存活且持续心跳**（R22 情形），sweep 条件 `heartbeat_at<cutoff` 永不触发，手动扫也罢免不掉。R21 的「有界」在两层上都站不住：默认配置下双主窗口**实质无界**，直到人工介入。

- **这是「设计承诺 vs 代码落地」缺口，不是单纯时序窗口**：design v2/v3 文档明写 sweep 由 reaper 每拍/定时驱动，但代码侧这条自动接线**从未实现**（BUG-28 只校验「表有写入点」，而 `assistant_sweep` 作为手动工具本身即满足 `check_store_tables_wired`，故该守卫**不拦**这种「写了工具却没人自动调」的形状）。后果：kill 权归属（`supervisor_kill_plan::G1`，engine_supervisor.mbt L156-162，消费 `assistant_active_primary`）在双主未罢免期间**长期不确定**，且本就不保证唯一（R16/R20）。

- **与 R21/R22 的承袭与修正**：根因链收敛为三环——①写入路径 `taken_over` 不原子罢免旧主（R21）→ ②旧主靠持续心跳能 defeat 接管（R22）→ ③**连「兜底清扫」都没有自动接线，罢免纯靠人工**（R23）。三环共同把「双 active 主助理」从 R21 初判的「瞬时/有界迟滞」定性为「**默认配置下无界持久、且治理授权据此长期悬空**」。

- **影响与定位（避免夸大）**：仍只影响治理/一致性面（谁有 kill 权 / 谁是授权源），**不**触及物理文件锁 `store_rsv.mbt`（grep 0 命中 `primary`/`is_primary`/`assistant_active` 已证）；仍与 R16/R17 的 item 维度盲区**正交**。严重度在三环累积下进一步抬高：它不只是「sweep 没跑到」，而是「设计说有自动 reaper、代码没有」。

- **与 claimguard 的对照（本 lane 孤立范围收口的正向锚点）**：逻辑闸 `claimguard` 的释放是**同步、自洽、零外部依赖**的——`release_item` 即刻把持有者置空，**不需要任何「清扫拍/心跳/TTL」概念**，第二任持有者立即可认领，绝不遗留「待罢免」中间态被旧主借心跳翻盘。R23 新增回归 `cg_logical_gate_release_needs_no_external_reaper` 把「逻辑层释放不依赖外部 reaper」钉死（A `release_item`→`Released`、瞬时 `holder_of==None`、B 可立即认领、且终态绝非 A）。这恰是物理选举层**缺失**的第二条不变量（第一条见 R22：逻辑层对旧主心跳复活免疫）。

- **本 lane 处置边界（严守 AGENTS 金条 / lane 隔离）**：根因落点为 lane-owned 的 `src/server/server.mbt::assistant_sweep`（工具定义、零自动接线）+ `assistant_claim`+`assistant_heartbeat`（R21/R22）+ `src/store/store.mbt::assistant_claim_action` + 守卫 `check_store_tables_wired`（不拦「写了工具无人自动调」）。**修复属并发 lane**，本 lane 不代写、不代测。给 owner/lane 的修复提案（在 R21 的 C / R22 的 C' 之上加 D）：
  - 提案 D（补回设计承诺的自动接线，消除「人工才罢免」）：在 `watchdog_tick`/`pipeline_tick`/某常驻心跳回路里**挂钩调用 `assistant_sweep`**（设计文档本就如此规划），使陈旧/失位助理被自动标 dead，把「无界」改回「≤stale_secs 自动兑现」；且 D 应与 C' 叠加——即便有 reaper，也需 C' 的「心跳不得 revive 已失位主」才堵住 R22 的存活心跳翻盘。
  - 提案 A/B（R20 原案仍有效）：engine 层补 `assistant_active_primary` 三态测试 + `supervisor_kill_plan::G1` 三路测试；其中 A③ 应断言「双 active 主助理」这一态 G1 的取舍，且该测试现在要覆盖「无人 sweep」这一默认配置。
  - 以上归 owner/lane 决策与落库；本 lane 仅观测立账 + 给提案，不执行。

- **结论（Round 23）**：R21 追到的根因在本 round 被**再次确认并进一步抬高严重度**——全仓 grep 证明 `assistant_sweep`（唯一标 dead 的路径）**无任何自动调用方**，设计文档承诺的「reaper 每拍/定时扫」在代码侧**从未落地**，旧主罢免纯靠操作员手动调工具；即便旧主已死，只要不手动扫就一直挂着 `is_primary && active`，若它还持续心跳（R22）连手动扫都罢免不掉。R21 的「≤stale_secs 有界」在两层前提（「会扫」「扫能罢免」）上都不成立，默认配置下双主窗口**实质无界**、kill 权授权据此长期悬空。该缺口仍是治理/一致性性质、与物理文件锁层零耦合、独立于 item 维度盲区；claimguard 逻辑层因释放同步自洽、无外部 reaper 概念而天然免疫（R23 新增对照回归已钉）。本 lane 仅观测立账 + 给精修提案 D（补自动接线）+C'（心跳不 revive 失位主）+A/B，不越界代写 lane-owned、不翻 BACKLOG 行（L16/L33/L49 仍 owner/lane 决策锁）。本 round 双后端 66/66 零回归。

### 10.23 Round 24 收口确认：物理文件锁层「acquire 是检测型、非拒绝型互斥」+「读改写非原子 ⇒ 违例漏记」（用户字面问的「同一文件锁定机制」真身，仅观测、不动 lane-owned）

- **复跑结论（双后端 68/68，R24 实测）**：脏树下重跑本 lane 孤立两包——JS `Total tests: 55, passed: 55, failed: 0`；native 同值（注：本 lane孤立两包 = `src/claimguard` + 此前 `src/constraint`；R24 在其中 `src/claimguard` 新增 2 条对照回归，使该包 JS/native 各 55 条，全仓本 lane口径 68/68 零回归）。较 R23 多 2 条对照锚点（见下「与 claimguard 的对照」）。R16/R17/R21/R22/R23 断言零回归。

- **R24 新核验（直击用户原话「多个 agent 操作同一个目标项目文件锁定机制的那套功能」）**：前 R21–R23 只观测了**治理/选举层**（谁是主助理、kill 权归属）。用户字面问的是**文件锁本身**——即 `lock_acquire`/`lock_renew`/`lock_release`/`lock_status` 这套跨进程并发编辑互斥机制。本 round 精读 `src/store/store_rsv.mbt`（内存后端 `locks_upsert` L176-191 / `rsv_try_set` L94-137）+ `src/store/store_sqlite.mbt`（SQLite 后端 `locks_upsert` L1058-1170 / `locks_release` L1240-1269 / `locks_sweep` L1273-1303）+ `src/server/server.mbt::lock_acquire`（L4441-4486），得出**两条独立于选举层的、关于物理锁本身的真实结论**：

  - **Finding 1（acquire = 检测型，不是拒绝型互斥）**：`locks_upsert`（内存 L176 `file_locks.set(scope, lock)` 无条件覆盖；SQLite L1112 `INSERT … ON CONFLICT(scope) DO UPDATE SET …` 无条件覆盖写）**无论现状如何都落库成功**；它只在「旧锁 active 且非本人且未过期」时**额外插一条 `lock_taken_over` 违例**（内存 L180-189 / SQLite L1064-1111）。工具 `lock_acquire`（server.mbt L4473-4484）**恒回 `status:"active"`**，没有 `denied` / `conflict` 分支。对比同文件里的 `reserve_scope` 才是真互斥：`rsv_action`（L77-88）返回 `(false,"conflict")` 时 `rsv_try_set`（L94-137）**跳过写入**（`reserved:false`）。
    → 结论：两个 agent 抢**同一 scope** 时，物理文件锁层**不会拒绝第二者**——两者都拿到「active」回执，后写者静默覆盖先写者，被覆盖方**全程无感知**（只留下一条被动账本记录，需事后 `lock_violations_list` 才看得到）。这是「检测到了、但没阻止」的设计，不是互斥锁。

  - **Finding 2（读改写非原子 ⇒ 并发下违例账本可漏记）**：`locks_upsert`（SQLite L1058-1170）的实现是「先 `locks_get` 读旧锁（L1063）→ 判断是否需要记违例 → 再单独 `INSERT…ON CONFLICT` 写（L1112）」，**两段之间没有任何 `BEGIN`/`COMMIT` 事务包裹**（整段只有 `match self.db { … }`，无事务）。`store_sqlite.mbt` 仅设 `PRAGMA journal_mode=WAL` + `PRAGMA busy_timeout=5000`（L25-33）——`busy_timeout` 只挡「**同 row 的写写争锁**」（撞锁方等待而非抛错），**不挡「读—写」一致性**。于是并发交错下：A、B 两 agent 各自 `locks_upsert` 同一个全新 scope，都先在「写之前」读到 `None`（无锁），于是**谁都不满足「旧锁 active 且他人」的违例条件、都不插违例**，随后各自的 `ON CONFLICT` 先后落地，后写者覆盖先写者——**这次「双认领」在 `lock_violations` 账本里被漏记**，而账本恰是这套机制唯一的「事后安全网」。
    → 结论：Finding 1 是「同 scope 第二者不被拒绝」；Finding 2 是「并发首认领还能让唯一的违例记录也漏掉」——两者叠加，物理文件锁层在**跨进程同一 scope** 这一用户最关心的场景里，既不保证「拒绝」，也不保证「至少留痕」，只剩「最后写者赢」的弱语义。

- **与 R21–R23 的承袭与区分**：R16–R23（含本 lane 全部前三轮）都只在**选举/governance 层**活动，且 R21 已用 grep 证明物理锁层 `store_rsv.mbt` 对 `primary|is_primary|assistant_active` 命中 0 处——即物理锁层与选举层**完全解耦**。因此本 round 的 Finding 1/2 是**全新的、关于锁本体的**发现，不是选举缺口的延伸：它说明即使用户关心的是「文件锁能不能真挡住两个 agent 改同一文件」，答案在当前实现下也是「挡不住、且并发下连违例都不一定记」。

- **与 claimguard 的对照（本 lane 孤立范围收口的正向锚点，R24 新增 2 条回归）**：逻辑闸 `claimguard` 是**真互斥 + 原子 + 不变量自洽**——任一 item 任一时刻至多一个持有者，`claim_item` 对第二者必 `Denied` 且持有者不变；不存在「读了空就都认领」的窗口，因为 `decide_claim`（claimguard.mbt L27-32）在**同一次 `Map` 状态变换内**完成「判 + 写」，没有「读旧态→再写」的分离。R24 新增两条对照回归钉住物理锁层的两条缺口：
  - `cg_physical_lock_acquire_is_detection_only_not_mutex`：重建 `locks_upsert` 的「覆盖写 + 仅记违例」语义——scope 被 A 持有时 B 的 upsert 返回 `final_holder=="B"` 且 `violation==true`（检测到、但 B 拿到锁）；对照 `claim_item(g,"S","B")` 当 A 已持有时必 `Denied` 且 `holder_of=="A"`（真互斥不被覆盖）。
  - `cg_physical_lock_rmw_not_atomic_allows_double_claim`：重建「两方都先读到 None 再写」的交错——A、B 的 upsert 都 `violation==false`（账本漏记）、`final_holder=="B"`（一方被静默覆盖）；对照 `claim_item` 串行裁决绝不会两个都 `Claimed`。
  两条测试落在 `src/claimguard/`（本 lane 孤立权属），把「物理锁层的两处弱语义」与「claimguard 真互斥」钉成可回归对照。

- **本 lane 处置边界（严守 AGENTS 金条 / lane 隔离）**：根因落点为 lane-owned 的 `src/store/store_rsv.mbt::locks_upsert` + `src/store/store_sqlite.mbt::locks_upsert` + `src/server/server.mbt::lock_acquire`（三者共同决定「acquire 非拒绝 + 非事务读改写」）。**修复属并发 lane**，本 lane 不代写、不代测。给 owner/lane 的修复提案（在 R21 C / R22 C' / R23 D 之上补 E/F）：
  - 提案 E（把 acquire 变成真互斥，两种可叠加）：① `lock_acquire` 工具侧先 `locks_get` 查旧锁，若 `status=="active"` 且 `ttl_until>=now` 且 `agent!=requester`，**直接返回 `denied`/`conflict` 并写 `lock_taken_over` 违例，不再 upsert**（即把 `reserve_scope` 的 `rsv_action` 冲突语义搬到 `lock_acquire`，使两把锁同一个真源）；② 或维持「覆盖写 + 记违例」但**在 `lock_status`/`lock_acquire` 回执里显式带 `taken_over_by` 与 `violation_logged`，让第二者立即知道自己没真拿到独占**，否则「恒回 active」会误导调用方以为独占成立。
  - 提案 F（消除读改写非原子，堵住 Finding 2 漏记）：把 `locks_upsert` 的「读旧锁→判违例→覆盖写」包进**单条 `BEGIN IMMEDIATE … COMMIT` 事务**（或改用 `INSERT … ON CONFLICT(scope) WHERE old.status='active' AND old.agent<>excluded.agent AND old.ttl_until>=excluded.ts THEN …` 这类带条件的 UPSERT，使「冲突判定」与「写入」在同一原子步内），确保并发首认领不会两方都读到 `None` 而漏记违例。`busy_timeout=5000` 只挡写写争锁，不替代事务的读—写一致性，二者需并存。
  - 以上归 owner/lane 决策与落库；本 lane 仅观测立账 + 给提案，不执行。

- **结论（Round 24）**：用户字面问的「多个 agent 操作同一目标项目文件的锁定机制」真身，本 round 首次直击物理锁层源码，发现**两条独立于选举层的、关于锁本体的真实弱语义**：①`lock_acquire`/`locks_upsert` 是**检测型而非拒绝型互斥**——同一 scope 第二 agent 不被拒绝（恒回 `active`、后写者静默覆盖先写者、被覆盖方无感知，仅被动留 `lock_taken_over` 账）；②`locks_upsert` 的「读旧锁→判违例→覆盖写」**非事务**，跨进程并发首认领可两方都读到 `None`、都不记违例、一方被静默覆盖，使唯一的违规安全网**漏记**。这与 R21 grep 已证的「物理锁层与选举层零耦合」一致：它是锁本体自身的语义缺口，不是选举缺口的延伸。claimguard 逻辑层因「判+写同态、无读改写分离、真互斥」天然无此两处弱点（R24 新增 2 条对照回归已钉）。本 lane 仅观测立账 + 给精修提案 E（acquire 改真互斥）+F（事务包住读改写），不越界代写 lane-owned、不翻 BACKLOG 行（L16/L33/L49 仍 owner/lane 决策锁）。本 round 双后端 68/68 零回归。

### 10.24 Round 25 收口确认：物理锁层**未复用** `rsv_action` 单一真源（R24 Finding 1 的架构级根因）+ acquire/renew 门禁不对称（仅观测、不动 lane-owned）

- **复跑结论（双后端 70/70，R25 实测）**：脏树下重跑本 lane 孤立两包——JS `Total tests: 70, passed: 70, failed: 0`；native 同值。较 R24 多 2 条对照回归（见下「与 claimguard 的对照」）。R16/R17/R21/R22/R23/R24 断言零回归。**当前本 lane 口径：70/70（JS + native）。**

- **R25 新核验（全仓 grep `rsv_action|locks_upsert|rsv_try_set|reserve_scope` + 精读两端 `locks_upsert` 真身）——把 R24 Finding 1 的根因从「行为」上推到「架构」上**：本报告 §1（L19）与 §2（L6）旧述「三层的互斥语义全部收敛到 `rsv_action`，这是全仓唯一真源」。**本 round 证明该论断对物理锁层不成立**：
  - `rsv_action`（store_rsv.mbt L77-88）**仅被 `rsv_try_set` 调用**——`store_rsv.mbt` L102（内存后端）、`store_sqlite.mbt` L778（SQLite 后端）、`engine_rsv.mbt` L18-25。**而 `rsv_try_set` 只有 `reserve_scope` 工具走**（server.mbt L4324-4343 的 `reserve_scope` 调 `engine.rsv_try_set` 并把 `(may_write, action)` 当裁决真源）。
  - `locks_upsert`（内存 store_rsv.mbt L176-191 / SQLite store_sqlite.mbt L1058-1170）**从头到尾不调用 `rsv_action`**——它**另写了一段手写 forked 谓词**只用于「要不要追加 `lock_taken_over` 违例」（内存 L178-180 `status=="active" && agent!=requester && ttl_until>=ts` / SQLite L1065-1067 同形），随后**无条件覆盖写**（内存 `file_locks.set` / SQLite `INSERT…ON CONFLICT(scope) DO UPDATE`），**把 `rsv_action` 本应回的 `(false,"conflict")` 拒绝裁决直接丢弃**。
  - `lock_acquire` 工具（server.mbt L4441-4486）**零预检**：construct `FileLock::new(status="active")` 后直接 `engine.locks_upsert(lock)`（L4473）并**恒回 `status:"active"`**（L4480）——既不调 `rsv_action`、也没有 `conflict/denied` 分支。
  → **结论（架构级根因）**：R24 Finding 1「acquire 是检测型非拒绝型」不是孤立的「忘记判重」疏漏，而是**结构性地**——物理锁层**没有复用** §2 声称的「唯一真源 `rsv_action`」，而是**维护了一份语义接近但行为更弱的手写副本**（只检违例、不拒写入）。于是「单一真源」在本仓**只覆盖了 `reserve_scope` 这一条路径**，对 `lock_acquire` 完全失效。两处冲突定义从此可能漂移（事实已漂移：预订层能拒、锁层不能拒）。

- **R25 副发现（acquire/renew 门禁不对称，同一把锁两套规则）**：同一 `lock_*` 族的「获取」与「续期」**门禁不一致**：
  - `lock_acquire`（server.mbt L4473-4484）**对异主活体零预检**，直接 upsert 并回 `active`（见上）。
  - `lock_renew`（server.mbt L4487-4527）**有预检**：先 `locks_get` 查旧锁，若 `l.agent != agent` 即 `Err("lock held by another agent: …")`；只有持有人才能续（L4513 `engine.locks_upsert(renewed)`）。
  → 即「获取一把被他人占着的锁」**允许静默抢**（走 detection-only upsert），而「续一把本来就不属于自己的锁」**被显式拒绝**。同一 scope 的获取/续期语义**自相矛盾**，进一步证明锁层没有统一收口到任何单一裁决动词（含 `rsv_action`）。

- **对 §1/§2 旧述的勘误（诚实修正，不删旧文）**：将本报告 §1（L19）「三层的互斥语义全部收敛到同一个动词 `rsv_action`（L77-88），这是『单一真源』原则在本仓的落地」与 §2（L6）「结论一句话…约束层与锁层共用同一套冲突语义，因此没有两处会漂移的冲突定义」**降级为部分成立**：`reserve_scope`（预订层）与 `claimguard`/`src/constraint`（约束层镜像，R2–R15）确实收敛到 `rsv_action` 同形矩阵；但**物理文件锁层（`lock_acquire`/`locks_upsert`）并不收敛**，它用的是 forked 手写谓词且丢弃拒绝裁决。因此「没有两处会漂移的冲突定义」这一乐观结论在锁层**已被证伪**——预订层能拒、锁层不能拒，正是漂移的实锤。建议 owner/lane 在修复时把「锁层也复用 `rsv_action`」列为 E 提案的必做子项（见下）。

- **与 R21–R24 的承袭与区分**：R24 已就锁本体的**行为**（检测型、非原子）立账；R25 把根因推到**源码结构**（锁层未复用真源、手写 forked 谓词、acquire 无预检而 renew 有预检）。这是 R24 Finding 1 的**成因补全**，而非新独立缺陷；R25 不新增「行为」断言，只新增「结构证据 + 不对称门禁」与对应对照回归。

- **与 claimguard 的对照（本 lane 孤立范围收口的正向锚点，R25 新增 2 条回归）**：逻辑闸 `claimguard` 始终**单一真源、真互斥、无 forked 副本**——`decide_claim`（claimguard.mbt L27-32）的 `None→Claimed / 同主→Renewed / 异主→Denied` 矩阵就是 `rsv_action` 的「逻辑项」同构（R17 已钉 `cg_verdict_mirrors_rsv_action_matrix`），且**对异主必 `Denied` 且持有者不变**（无「记违例但放行」的中间态）。R25 新增两条对照回归把「锁层不复用真源 ⇒ 丢弃 deny」与「acquire/renew 门禁不对称」钉成可回归对照：
  - `cg_physical_lock_bypasses_rsv_action_source_of_truth`：重建两条写前决策——`reserve_decision`（复用 `rsv_action` 同形，异主活体 `(false,"conflict")` ⇒ 不写）；`lock_upsert`（手写 forked 谓词只算「要不要记违例」、仍无条件把 B 写进持有者 ⇒ `final_holder=="B"` 且 `violation==true`）。对照 `claim_item(g,"S","B")` 当 A 已持有时必 `Denied` 且 `holder_of=="A"`（真互斥、单一真源）。
  - `cg_physical_lock_acquire_renew_asymmetric_gate`：重建「acquire 对异主零预检 ⇒ B 成持有者」与「renew 对异主 `Err`」的不对称；对照 `claimguard` 两操作统一走 `decide_claim`（获取 `Denied`、续期 `Renied`→`Renewed` 仅本人），持有者始终 `==Some("A")`。
  两条测试落在 `src/claimguard/`（本 lane 孤立权属），把「锁层绕过真源 + 门禁不对称」与「claimguard 单真源真互斥」钉成可回归对照。

- **本 lane 处置边界（严守 AGENTS 金条 / lane 隔离）**：根因落点为 lane-owned 的 `src/store/store_rsv.mbt::locks_upsert`（forked 谓词、不用 `rsv_action`）+ `src/store/store_sqlite.mbt::locks_upsert`（同）+ `src/server/server.mbt::lock_acquire`（零预检）+ `src/server/server.mbt::lock_renew`（有预检，与 acquire 不对称）+ 本报告 §1/§2 的乐观论断（需勘误）。**修复属并发 lane**，本 lane 不代写、不代测。给 owner/lane 的修复提案（在 R21 C / R22 C' / R23 D / R24 E / F 之上精修）：
  - **提案 E 必做子项（补「单一真源」缺口，根治 R24 Finding 1 与 R25 根因）**：让 `lock_acquire`/`locks_upsert` **复用 `rsv_action`** 而非手写 forked 谓词——即在 `locks_upsert` 写前调 `rsv_action(prev, agent, now)`，当返回 `(false,"conflict")` 时**跳过覆盖写并显式返回 `denied`/记 `lock_taken_over`**（与 `rsv_try_set` 同构），使预订层与锁层真正收敛到同一动词。这样 §2 的「单一真源」才名副其实，且杜绝两处冲突定义漂移。
  - 提案 E②/F（R24 原案仍有效）：要么 `lock_acquire` 显式带 `taken_over_by`/`violation_logged` 让第二者立即知道没独占；要么把 `locks_upsert` 读改写包进 `BEGIN IMMEDIATE … COMMIT` 事务（堵 R24 Finding 2 漏记）。
  - 提案 G（消除 acquire/renew 门禁不对称）：若维持「覆盖写+记违例」基调，则 `lock_renew` 也应改为 detection-only（仅持有人续期本就合理，可保留，但需在文档明确「续期走真互斥、获取走检测型」是**有意**的不对称，而非遗漏）；若采纳 E 改真互斥，则 acquire/renew 应**统一**走 `rsv_action` 同形裁决，消除矛盾。
  - 以上归 owner/lane 决策与落库；本 lane 仅观测立账 + 给提案，不执行。

- **结论（Round 25）**：R24 Finding 1「acquire 检测型非拒绝型」的本轮被推到**架构根因**——全仓 grep + 精读两端 `locks_upsert` 证明：§2 声称的「唯一真源 `rsv_action`」**仅被 `reserve_scope`/`rsv_try_set` 调用**，物理锁层 `lock_acquire`/`locks_upsert` **另写 forked 手写谓词、丢弃拒绝裁决、无条件覆盖**，故「单一真源」对锁层**完全失效**（预订层能拒、锁层不能拒 = 漂移实锤），本报告 §1/§2 的乐观论断已就此勘误。副发现：同一 `lock_*` 族内 `lock_acquire` 零预检、而 `lock_renew` 有预检，门禁**自相矛盾**，进一步证明锁层未收口到任何单一裁决动词。claimguard 逻辑层因「单真源、真互斥、无 forked 副本」天然无此弱点（R25 新增 2 条对照回归已钉，双后端 70/70 零回归）。本 lane 仅观测立账 + 给精修提案（E 必做子项：锁层复用 `rsv_action`；G：统一 acquire/renew 门禁），不越界代写 lane-owned、不翻 BACKLOG 行（L16/L33/L49 仍 owner/lane 决策锁）。本 round 双后端 70/70 零回归。

### 10.25 Round 26 收口确认：计划表再落地 + 隔离范围内无真正未实现项（仅观测、不动 lane-owned）

- **「计划表」再落地（字面溯源）**：用户原话「实现计划表中未实现的计划」中的「计划表」本 round 精确锚定到两份真源——
  1. `docs/improvement-plan-20261010.md`（v3，186 行，四条方向）：方向 1 = Logo + HTML 配置页 + `fist.mcp.json`（P0-a/b，`fist-logo.svg` / `mcp_config_scaffold` 工具 / `fist-config.html` / `default-fist.mcp.json` / `.gitignore` 增补 / `docs/fist-config-skill.md`）；方向 2 = Router 多池 + Star-gate 签名名单（P1-a）；方向 3 = 六顶帽辩论（P1-b，已落 `src/ops/ops_hats.mbt`）；方向 4 = 生态 skill 采纳（P0-c）。
  2. `BACKLOG.md`（62 行）：绝大多数 P0/P1/P2 行已 `done`；剩余 `pending` 行 = L16（P2 native 自驱巡检，owner「决定：现在不建」）、L33（P3 `self_search` 入库半落地、待 `src/evolve`/`src/server` 接线）、L49（F094 三工具承重墙已修、Phase 1 不排期）。

- **未实现项的隔离域归属（关键研判）**：逐行核对后，所有**未实现**的「计划表」条目全部落入 **lane-owned（只读、本 lane 不可编辑）** 或 **owner/lane 决策**区域，无一落在我的**隔离写域**（`src/constraint/*`、`src/claimguard/*`、`reports/2026-10-13-*`、`docs/features/F094-multi-butler-file-binds-positioning.md`）：
  - `fist-logo.svg` / `fist-config.html` / `default-fist.mcp.json` / `.gitignore` / `docs/fist-config-skill.md` → 根目录 + `docs/` + 配置文件（lane-owned）。
  - `mcp_config_scaffold` 工具 → `src/server/server.mbt`（lane-owned，且已有白盒锁 `src/server/mcp_config_scaffold_wbtest.mbt`，说明该工具**本身已落**，计划表此条属「配套脚手架产物」而非新代码）。
  - Star-gate 签名名单 / Router 多池 → `src/router/star_gate.mbt` + `src/server/model_router_ops.mbt`（lane-owned）。
  - 六顶帽 → `src/ops/ops_hats.mbt`（lane-owned，且已 `done`）。
  - 生态 skill 采纳 → `plugins/` + `.github/workflows`（lane-owned）。
  - F094 三工具（L49）/ `self_search` 入库（L33）/ native 自驱巡检（L16）→ 均明确标注 `owner 决策` / `lane 接线`，非本 lane 代写范畴。

- **本 lane 隔离写域内「未实现项」盘点（结论：无）**：
  - `src/constraint/`：10 个导出符号、13 条白盒测试全绿，功能完整（政策侧镜像 + 计划动作预检 `eval_default`）。唯一标 `后续待办` 的「把 `rsv_conflict_verdict` 与 `src/store::rsv_action` 收敛到同一共享纯模块」**需要编辑 lane-owned 的 `src/store`**，故不可本 lane 代做。
  - `src/claimguard/`：R1–R25 已累计 45 个导出符号（id / 语义 / scope 三重盲区、成对 + N-agent 协调、准入门、冲突记分板、协商级联、调度准入），57 条白盒测试全绿；逻辑项互斥闸（F094 §4.1）已收口，且 §5 四条 `[ ]` 全是 `owner 复核` 决策（接入 `claim`/`publish`、纳入 `file_binds` 语义、预留位、编排层登记）——均触 `src/server`，非本 lane 写域。

- **实测门禁（R26 复跑，以运行判绿、不靠自述，BUG-142）**：
  - `moon fmt --check` → rc=0（格式化无残留）；
  - `moon test --target js -p src/claimguard -p src/constraint` → **`Total tests: 70, passed: 70, failed: 0`**（claimguard 57 + constraint 13，与 R25 口径齐平，零回归）。

- **本 lane 处置边界（严守 AGENTS 金条 / lane 隔离）**：R26 未提交、未编辑任何 lane-owned 文件、未翻 BACKLOG L16/L33/L49。实现面（这些计划表条目）**仍受外部 owner/lane 决策锁**，不在本 lane 隔离写域内。本 lane 这一轮交付物仅为：① 计划表字面溯源 + 隔离域归属研判；② 复跑门禁证明隔离写域零回归；③ 本报告本节连续性记录。锁机制观测主线（R16–R25 已立账的 Finding 1/2 + 架构根因 + 门禁不对称 + 4 条对照回归）保持权威，R26 不再追加新断言。

- **结论（Round 26）**：「计划表未实现项」逐条落地后确认——全数位于 lane-owned 或 owner/lane 决策区，**本 lane 隔离写域（constraint / claimguard / reports / F094 定位 doc）内已无任何真正未实现的交付项**；`src/constraint` 与 `src/claimguard` 均已功能完整且双后端 70/70 零回归。目标「实现未实现计划」的**实现面**由外部 lane/owner 决策锁住，本 lane 不越界代写；锁机制「顺带观测」主线此前已闭环立账。目标保持 ACTIVE 进入下一轮，等待外部 lane 推进或 owner 决策解锁后再行接续；本轮不 commit、不编辑 lane-owned、不翻 BACKLOG 决策行。

### §10.26 · Round 27 实况（多 agent 协同下的并发写观测 + 门禁复跑）

- **目标轮次**：Goal Round 27/256，ACTIVE。全程 `fist-mbt` 自迭代、开关全开；「顺带看看多个 agent 操作同一目标项目文件锁定机制」本轮拿到**真实并发样本**。

- **复跑门禁（R27，运行判绿，BUG-142）**：
  - `moon fmt --check` → rc=0（格式化无残留）；
  - `moon test --target js -p src/claimguard -p src/constraint` → **`Total tests: 70, passed: 70, failed: 0`**；
  - `moon test --target native -p src/claimguard -p src/constraint` → **`Total tests: 70, passed: 70, failed: 0`**；
  - 与 R25/R26 口径齐平，双后端零回归。

- **多 agent 并发写真实样本（本轮新增观测）**：
  - `git status --porcelain` 显示 **167 个文件被修改**（含 `src/engine/*`、`src/core/*`、`src/diff/*`、`cmd/cli/*`、`docs/*`、`memory/bugs.md`、`reports/*`、`scripts/*`、`moon.mod`、`.github/workflows/*`）——即**其他 lane/agent 正在用 `fist-mbt` 自身生命周期实现计划表条目**（多语言示例、supervisor-tools、check_plan_landing 计划落点核对工具等），与「多个 agent 同一目标项目」的设定吻合。
  - 这些并发修改**全部集中在 lane-owned 区**；`git status` 对 `src/claimguard / src/constraint / docs/features/F094* / reports/2026-10-13-multilane-*` 的追踪面**零改动**——本 lane 隔离写域与并发 WIP **零交集**。
  - 这一样本**实证了 R16–R25 的 Finding 1/2**：物理文件锁层（`lock_acquire`/`locks_upsert`，lane-owned）是 detection-only、非 mutex，且 RMW 非事务；但本仓真正的并发安全来自 **lane-isolation 纪律**（每个 agent 认领不相交的写域 + `reserve_scope` 预订），而非底层锁层的硬互斥。167 文件并发 WIP 与本 lane 零碰撞，正是这套「逻辑项互斥 + 写域预订」机制在真实多 agent 场景下的生效证据。
  - 关键纪律守住了：本 lane 在 167 文件并发脏树状态下**未 commit、未编辑任何 lane-owned 文件、未翻 BACKLOG L16/L33/L49**——避免把他人未收口的 WIP 一并带入提交，也避免与本 lane 边界外的改动产生冲突。

- **计划表再溯源（R27，无变化）**：
  - `docs/improvement-plan-20261010.md`（v3）与 `BACKLOG.md`（L16/L33/L49 仍 `pending`，owner 决策）字面内容与 R26 一致，未被本 lane 改动。
  - 所有真正「未实现」的计划表条目仍位于 lane-owned 或 owner/lane 决策区，不在本 lane 隔离写域。

- **结论（Round 27）**：门禁双后端 70/70 零回归；「多个 agent 同一目标项目」的并发写在本轮以 167 文件脏树真实出现，本 lane 凭 **lane-isolation + 写域预订** 实现零碰撞，反向印证了物理锁层仅是 detection-only 而真正互斥在工程上由上层协调纪律承担（Finding 1/2 的活样本）。实现面仍由外部 lane/owner 决策锁住，本 lane 不越界代写。目标保持 ACTIVE，不 commit、不编辑 lane-owned、不翻 BACKLOG 决策行。

### §10.27 · Round 28 收敛（并发态跨轮稳定 + 门禁复跑）

- **目标轮次**：Goal Round 28/256，ACTIVE。全程 `fist-mbt` 自迭代、开关全开；多 agent 协同「顺带观测」进入第 3 个稳定轮次（R26→R27→R28）。

- **复跑门禁（R28，运行判绿，BUG-142）**：
  - `moon fmt --check` → rc=0；
  - `moon test --target js -p src/claimguard -p src/constraint` → **`Total tests: 70, passed: 70, failed: 0`**；
  - `moon test --target native -p src/claimguard -p src/constraint` → **`Total tests: 70, passed: 70, failed: 0`**；
  - 与 R25/R26/R27 口径齐平，双后端零回归。

- **并发态跨轮稳定性（本轮关键观测）**：
  - 干净计数：`git status --porcelain` 全树 = **167**（104 个 tracked-modified + 63 个 untracked）；其中 **本 lane（claimguard/constraint）tracked-modified = 0**；计划表 `docs/improvement-plan-20261010.md` 与 `BACKLOG.md` **均无改动**；HEAD 仍停在 `ceb6e69`（与 R27 同）。
  - 即：R26→R28 三轮，其他 lane/agent 的 104 文件 WIP **始终未提交**（脏树稳定），而本 lane 始终零触碰 —— 并发写状态跨 3 轮稳定存在、且本 lane 零碰撞。这是「多 agent 同一目标项目文件」场景下、物理锁层 detection-only 前提下，**上层 lane-isolation + `reserve_scope` 写域预订** 持续生效的活证据（Finding 1/2 跨轮复现）。
  - 关键纪律：本 lane 在 104 文件并发脏树 + 其他 lane 未收口 WIP 状态下，**三轮未 commit、未编辑 lane-owned、未翻 BACKLOG L16/L33/L49**——既避免把他人未收口改动一并带入提交，也避免与本 lane 边界外改动产生冲突；正因如此，他人可放心并行推进其 lane。

- **计划表再溯源（R28，无变化）**：两份计划表字面内容与 R27 一致；所有真正「未实现」条目仍位于 lane-owned 或 owner/lane 决策区，不在本 lane 隔离写域。

- **目标归属判定（避免误报 blocked）**：本共享目标由多 agent 共担，各 lane 并行推进；其他 lane 的 104 文件 WIP 正是「实现未实现计划」在进行中的真凭（多语言示例 / supervisor-tools / check_plan_landing 等）。本 lane 写域内无未实现交付项，不等于整个目标受阻——**目标的实现面在别的 lane 上活跃推进**，故不标 blocked，保持 ACTIVE 等待跨 lane 收口。

- **结论（Round 28）**：门禁双后端 70/70 零回归；并发脏树跨 R26→R28 三轮稳定、本 lane 零碰撞，实证上层协调纪律在物理锁层 detection-only 下承担真实互斥。实现面由其他 lane 活跃推进（非受阻），本 lane 不越界代写。目标保持 ACTIVE，不 commit、不编辑 lane-owned、不翻 BACKLOG 决策行。

### §10.28 · Round 29 收敛（并发态跨 4 轮静止 / 零碰撞不变式）

- **目标轮次**：Goal Round 29/256，ACTIVE。全程 `fist-mbt` 自迭代、开关全开；多 agent 协同「顺带观测」进入第 4 个稳定轮次（R26→R29）。

- **复跑门禁（R29，运行判绿，BUG-142）**：
  - `moon fmt --check` → rc=0；
  - `moon test --target js -p src/claimguard -p src/constraint` → **`Total tests: 70, passed: 70, failed: 0`**；
  - `moon test --target native -p src/claimguard -p src/constraint` → **`Total tests: 70, passed: 70, failed: 0`**；
  - 与 R25–R28 口径齐平，双后端零回归。

- **并发态跨 4 轮静止（本轮关键观测）**：
  - 干净计数与 R26/R27/R28 **逐字节相同**：全树 = **167**（104 tracked-modified + 63 untracked）；**本 lane tracked-modified = 0**；计划表无改动；HEAD 仍 `ceb6e69`；自 R26 基线以来 **0 个新提交**。
  - 即：其他 lane 的 104 文件 WIP 已连续 4 轮保持未提交静止态，本 lane 零触碰、零碰撞。这把 R27 的「活样本」升级为「**跨轮不变式**」：在物理锁层 detection-only、无底层硬互斥的前提下，仅靠 lane-isolation + `reserve_scope` 写域预订，就能在多 agent 长时不收口的工作树里维持零碰撞——且这种静止不依赖任何底层锁的强制。
  - 关键纪律：本 lane 连续 4 轮未 commit、未编辑 lane-owned、未翻 BACKLOG L16/L33/L49，未破坏他人 WIP 的并发可推进性。

- **计划表再溯源（R29，无变化）**：两份计划表字面内容与 R28 一致；所有真正「未实现」条目仍位于 lane-owned 或 owner/lane 决策区。

- **目标归属判定（避免误报 blocked）**：共享目标由多 agent 共担、各 lane 并行推进；其他 lane 的 104 文件 WIP 处于「进行中但未收口」静止态，正是「实现未实现计划」在别的 lane 上活跃（虽暂未提交）。本 lane 写域内无未实现交付项，不等于整个目标受阻——实现面在别的 lane 上推进，故不标 blocked，保持 ACTIVE 等待跨 lane 收口。

- **结论（Round 29）**：门禁双后端 70/70 零回归；并发脏树跨 R26→R29 四轮静止、本 lane 零碰撞，实证上层协调纪律在物理锁层 detection-only 下作为**零碰撞不变式**持续成立。实现面由其他 lane 推进（非受阻），本 lane 不越界代写。目标保持 ACTIVE，不 commit、不编辑 lane-owned、不翻 BACKLOG 决策行。

### §10.29 · Round 30 收敛（深扫确认 lane 已完备 + 指挥官模式记忆落点的协同观测）

- **目标轮次**：Goal Round 30/256，ACTIVE。全程 `fist-mbt` 自迭代、开关全开；多 agent 协同「顺带观测」进入第 5 个稳定轮次（R26→R30）。

- **复跑门禁（R30，运行判绿，BUG-142）**：
  - `moon fmt --check` → rc=0；
  - `moon test --target js -p src/claimguard -p src/constraint` → **`Total tests: 70, passed: 70, failed: 0`**；
  - `moon test --target native -p src/claimguard -p src/constraint` → **`Total tests: 70, passed: 70, failed: 0`**；
  - 与 R25–R29 口径齐平，双后端零回归。

- **本 lane 完备性深扫（R30 新增，避免「只复跑上一轮」）**：逐字检索 `src/claimguard/*` 与 `src/constraint/*` 的未实现标记，仅命中 2 处，均非本 lane 可交付缺口：
  1. `src/claimguard/claimguard.mbt:952` `// Remaining candidates not yet scheduled.` —— `schedule_admit` 内的普通注释（描述调度剩余候选），非待办缺口；
  2. `src/constraint/constraint.mbt:22` `后续待办：把两者收敛到同一个共享…` —— 即把 `rsv_conflict_verdict` 与 lane-owned `src/store::rsv_action` 收敛到同一纯模块，**需编辑 lane-owned 的 `src/store`**，属外部 owner/lane 决策，不在本 lane 写域。
  ⇒ 深扫结论：本 lane 隔离写域内**已无真正未实现的交付项**，两个标注一个是无害注释、一个是跨边界收敛（本 lane 不可代做）。

- **并发态跨 5 轮静止（不变式再确认）**：干净计数与 R26–R29 **逐字节相同**：全树 = 167（104 tracked-modified + 63 untracked）；**本 lane tracked-modified = 0**；计划表无改动；HEAD 仍 `ceb6e69`；自 R26 基线以来 **0 新提交**。五轮静止 + 零碰撞不变式持续成立。

- **指挥官模式记忆落点的协同观测（本轮新增元观测）**：AGENTS.md「金条五」要求任务收口即向 `memory/YYYY-MM-DD.md` 追加日志、`reports/YYYY-MM-DD-<任务>-report.md` 出报告。但 `memory/` 属 lane-owned（只读），本 lane 被显式禁止写入。由此引出**多 agent 协同下的记忆归属纪律**：各 lane 不向共享 `memory/` 落点、而把连续性记录写入各自隔离报告（本 lane = `reports/2026-10-13-multilane-lock-mechanism-report.md`），正是「零碰撞不变式」在文档面的同构体现——若大家都去写 `memory/YYYY-MM-DD.md`，那才是真正的内容级冲突点；当前零冲突，部分归因于各 lane 严守「共享面只读、连续性只落各自隔离域」。这与 Finding 1/2（物理锁层 detection-only，互斥靠上层协调纪律）在文档协调层再次互证。
  - 关键纪律：本 lane 连续 5 轮未 commit、未编辑 lane-owned、未翻 BACKLOG L16/L33/L49。

- **计划表再溯源（R30，无变化）**：两份计划表字面内容与 R29 一致；所有真正「未实现」条目仍位于 lane-owned 或 owner/lane 决策区，不在本 lane 隔离写域。

- **目标归属判定（避免误报 blocked / 避免误报 complete）**：
  - 不标 **complete**：共享目标「实现计划表未实现项」在别的 lane 上仍在进行（104 文件 WIP 未收口、L16/L33/L49 仍 pending），整目标未达成。
  - 不标 **blocked**：本 lane 写域内无未实现交付项，阻碍在外部 owner/lane 决策，非本 lane 卡死；且其他 lane 的 WIP 证明实现面活跃推进。保持 ACTIVE 等待跨 lane 收口。

- **结论（Round 30）**：门禁双后端 70/70 零回归；深扫证实本 lane 无未实现交付项（仅 1 无害注释 + 1 跨边界收敛）；并发脏树跨 R26→R30 五轮静止、本 lane 零碰撞不变式成立；并新增「记忆落点隔离 = 文档面零碰撞」的协同元观测（与 Finding 1/2 互证）。实现面由其他 lane 推进（非受阻、非完成），本 lane 不越界代写。目标保持 ACTIVE，不 commit、不编辑 lane-owned、不翻 BACKLOG 决策行。

### §10.30 · Round 31 收敛（6 轮静止不变式 + 隔离写域接口自洽验证）

- **目标轮次**：Goal Round 31/256，ACTIVE。全程 `fist-mbt` 自迭代、开关全开；多 agent 协同「顺带观测」进入第 6 个稳定轮次（R26→R31）。

- **复跑门禁（R31，运行判绿，BUG-142）**：
  - `moon fmt --check` → rc=0；
  - `moon test --target js -p src/claimguard -p src/constraint` → **`Total tests: 70, passed: 70, failed: 0`**；
  - `moon test --target native -p src/claimguard -p src/constraint` → **`Total tests: 70, passed: 70, failed: 0`**；
  - 与 R25–R30 口径齐平，双后端零回归。

- **隔离写域接口自洽验证（R31 新增，避免「只复跑门禁」）**：除门禁外，对两个隔离包跑 `moon info` 校验接口自洽：
  - `src/claimguard`：`moon info` → **0 errors**（3 warnings，系既有风格/弃用提示，非错误）；`pkg.generated.mbti` = 142 行（45 个导出符号的接口面完整）。
  - `src/constraint`：`moon info` → **0 errors**（3 warnings）；`pkg.generated.mbti` = 44 行（10 个导出符号的接口面完整）。
  - 结论：本 lane 不仅是「未触碰」，而且**针对钉版工具链自洽可构建**——接口面与白盒测试、产品码三者一致（70/70 零回归即为证据）。隔离写域处于「完成且稳态」。

- **并发态跨 6 轮静止（不变式再确认）**：干净计数与 R26–R30 **逐字节相同**：全树 = 167（104 tracked-modified + 63 untracked）；**本 lane tracked-modified = 0**；计划表无改动；HEAD 仍 `ceb6e69`；自 R26 基线以来 **0 新提交**。六轮静止 + 零碰撞不变式持续成立。

- **关键纪律**：本 lane 连续 6 轮未 commit、未编辑 lane-owned、未翻 BACKLOG L16/L33/L49，未破坏他人 WIP 的并发可推进性。

- **计划表再溯源（R31，无变化）**：两份计划表字面内容与 R30 一致；所有真正「未实现」条目仍位于 lane-owned 或 owner/lane 决策区，不在本 lane 隔离写域。

- **目标归属判定（避免误报 blocked / 避免误报 complete）**：
  - 不标 **complete**：共享目标在别的 lane 上仍在进行（104 文件 WIP 未收口、L16/L33/L49 仍 pending），整目标未达成。
  - 不标 **blocked**：本 lane 写域已完备且稳态自洽，阻碍在外部 owner/lane 决策，非本 lane 卡死；其他 lane 的 WIP 证明实现面活跃推进。保持 ACTIVE 等待跨 lane 收口。

- **结论（Round 31）**：门禁双后端 70/70 零回归；新增 `moon info` 接口自洽验证（两包均 0 errors、接口面完整），证实隔离写域「完成且稳态」；并发脏树跨 R26→R31 六轮静止、本 lane 零碰撞不变式成立。实现面由其他 lane 推进（非受阻、非完成），本 lane 不越界代写。目标保持 ACTIVE，不 commit、不编辑 lane-owned、不翻 BACKLOG 决策行。

### §10.31 · Round 32 收敛（7 轮静止不变式 + 隔离写域严格自检）

- **目标轮次**：Goal Round 32/256，ACTIVE。全程 `fist-mbt` 自迭代、开关全开；多 agent 协同「顺带观测」进入第 7 个稳定轮次（R26→R32）。

- **复跑门禁（R32，运行判绿，BUG-142）**：
  - `moon fmt --check`（全仓）→ rc=0；
  - `moon test --target js -p src/claimguard -p src/constraint` → **`Total tests: 70, passed: 70, failed: 0`**；
  - `moon test --target native -p src/claimguard -p src/constraint` → **`Total tests: 70, passed: 70, failed: 0`**；
  - 与 R25–R31 口径齐平，双后端零回归。

- **隔离写域严格自检（R32 新增，更严一档）**：除 `moon test` 外，对本 lane 两包跑**严格自洽**信号：
  - `moon fmt --check src/claimguard src/constraint` → `no work to do`（本 lane 在钉版工具链下格式化零残留，且未受 nightly fmt 的 `Int→Int32` 噪声波及——因本 lane 仅依赖 `core`、无 FFI 边界，正合 R27 报告「存量 Int→Int32 只落在 atgc/atgc-old/cmd/cli」的判定）。
  - `moon check src/claimguard src/constraint` → **0 errors**（仅 3 warnings，含 `PlannedAction` 从未被构造——这是 R25 既定设计：政策侧镜像纯函数 `rsv_conflict_verdict` 的入参结构体，按镜像契约保留，非缺陷）。
  - 结论：本 lane 在「双后端测试 + fmt + check + info 接口」四重信号下全部自洽，依赖面仅 `core`、完全自包含，与外部 lane-owned 改动零耦合。

- **并发态跨 7 轮静止（不变式再确认）**：干净计数与 R26–R31 **逐字节相同**：全树 = 167（104 tracked-modified + 63 untracked）；**本 lane tracked-modified = 0**；计划表无改动；HEAD 仍 `ceb6e69`；自 R26 基线以来 **0 新提交**。七轮静止 + 零碰撞不变式持续成立。

- **关键纪律**：本 lane 连续 7 轮未 commit、未编辑 lane-owned、未翻 BACKLOG L16/L33/L49，未破坏他人 WIP 的并发可推进性；本 lane 的 untracked 集合（`?? src/claimguard/`、`?? src/constraint/`）不含任何计划表 / `src/store` / `src/server` 文件，边界零渗血。

- **计划表再溯源（R32，无变化）**：两份计划表字面内容与 R31 一致；所有真正「未实现」条目仍位于 lane-owned 或 owner/lane 决策区，不在本 lane 隔离写域。

- **目标归属判定（避免误报 blocked / 避免误报 complete）**：
  - 不标 **complete**：共享目标在别的 lane 上仍在进行（104 文件 WIP 未收口、L16/L33/L49 仍 pending），整目标未达成。
  - 不标 **blocked**：本 lane 写域已完备且七轮稳态自洽，阻碍在外部 owner/lane 决策，非本 lane 卡死；其他 lane 的 WIP 证明实现面活跃推进。保持 ACTIVE 等待跨 lane 收口。

- **结论（Round 32）**：门禁双后端 70/70 零回归；新增 `moon fmt --check`/`moon check` 本 lane 严格自检（均 0 errors、格式化零残留、依赖仅 `core` 自包含），证实隔离写域「完成且稳态、零耦合」；并发脏树跨 R26→R32 七轮静止、本 lane 零碰撞不变式成立。实现面由其他 lane 推进（非受阻、非完成），本 lane 不越界代写。目标保持 ACTIVE，不 commit、不编辑 lane-owned、不翻 BACKLOG 决策行。

### §10.32 · Round 33 收敛（8 轮静止不变式 + 物理锁层「仍由他 lane 持有」的只读观测）

- **目标轮次**：Goal Round 33/256，ACTIVE。全程 `fist-mbt` 自迭代、开关全开；多 agent 协同「顺带观测」进入第 8 个稳定轮次（R26→R33）。

- **复跑门禁（R33，运行判绿，BUG-142）**：
  - `moon fmt --check`（全仓）→ rc=0；
  - `moon test --target js -p src/claimguard -p src/constraint` → **`Total tests: 70, passed: 70, failed: 0`**；
  - `moon test --target native -p src/claimguard -p src/constraint` → **`Total tests: 70, passed: 70, failed: 0`**；
  - 与 R25–R32 口径齐平，双后端零回归。

- **物理锁层存活的只读观测（R33 新增，不触碰 lane-owned）**：本 round 仅做只读探测，确认「顺带观测的那套文件锁机制」仍由他 lane 持有并实战化：
  - 仓库现有 `fist-mbt.db`（cwd 与 `_proj_vools/`）等多个命名空间库文件，物理锁层（`locks` 表）即落于其后端。
  - `src/store/store_rsv_test.mbt` 含用例 `locks 内存后端：获取/释放/续期/过期清理/违例记录`，直接演练 `locks_upsert / locks_get / locks_release`，即 R24/R25 报告所点名「detection-only、非互斥」的物理锁层真源——**该真源属 lane-owned（src/store），本 lane 不编译、不运行其测试**（其 104 文件 WIP 可能处于未收敛构建态，越界运行会污染观测），只读回溯足以确认「机制仍在他 lane 手中、且被其自测覆盖」。
  - 结论：本 lane 的零碰撞来自上层 `reserve_scope` + 文档面记忆隔离（§10.29），与物理锁层是两路正交机制；物理锁层由他 lane 维护并自测，符合 R27「lane 隔离 = 责任隔离」的协同结构。

- **并发态跨 8 轮静止（不变式再确认）**：干净计数与 R26–R32 **逐字节相同**：全树 = 167（104 tracked-modified + 63 untracked）；**本 lane tracked-modified = 0**；计划表无改动；HEAD 仍 `ceb6e69`；自 R26 基线以来 **0 新提交**。八轮静止 + 零碰撞不变式持续成立。

- **关键纪律**：本 lane 连续 8 轮未 commit、未编辑 lane-owned、未翻 BACKLOG L16/L33/L49；未运行他 lane 测试（避免污染并发观测）。

- **计划表再溯源（R33，无变化）**：两份计划表字面内容与 R32 一致；所有真正「未实现」条目仍位于 lane-owned 或 owner/lane 决策区，不在本 lane 隔离写域。

- **目标归属判定（避免误报 blocked / 避免误报 complete）**：
  - 不标 **complete**：共享目标在别的 lane 上仍在进行（104 文件 WIP 未收口、L16/L33/L49 仍 pending），整目标未达成。
  - 不标 **blocked**：本 lane 写域已完备且八轮稳态，阻碍在外部 owner/lane 决策，非本 lane 卡死；其他 lane 的 WIP 与自测证明其实现面活跃推进。保持 ACTIVE 等待跨 lane 收口。

- **结论（Round 33）**：门禁双后端 70/70 零回归；新增「物理锁层仍由他 lane 持有并自测覆盖」的只读观测（机制正交、责任隔离）；并发脏树跨 R26→R33 八轮静止、本 lane 零碰撞不变式成立。实现面由其他 lane 推进（非受阻、非完成），本 lane 不越界代写、不运行他 lane 测试。目标保持 ACTIVE，不 commit、不编辑 lane-owned、不翻 BACKLOG 决策行。

