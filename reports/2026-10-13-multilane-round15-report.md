# 四模式流水线自我迭代 · Round 15 报告（多 Agent 文件锁机制 · R15 调度器收口）

- 生成时间：2026-10-13T23:56+08:00
- 观测/实现对象：`src/claimguard/claimguard.mbt`（`schedule_admit` 顶层多候选准入调度器）、`src/claimguard/claimguard_wbtest.mbt`（R15 白盒测例）
- 实现方式：在 R3~R14 已建的三维盲点门 + 对账门 + 级联谈判 + 谈判计划层之上，补一个**纯函数、只读、单一真源**的顶层调度循环；不写第二套级联，全部复用 `negotiate_plan`。
- 结论一句话：**多候选准入由「最省心优先贪心 + 先到先得 + 提交即锁定」三原则收口——已采纳的 newcomer 是既成事实，绝不被后来候选挤让；这一步把 R3~R14 一直悬而未决的「后到者要不要把先到者让出去」钉死为「不」。**

---

## 1. 背景与缺口

R14 给了协调器「挑最省心候选」的排序能力：`negotiate_plan` 把级联让权结果派生出 `priority_cost`（干扰成本）与 `freed_for_proposed`（释放收益），可排序、可比较。

但「**何时、以什么顺序把多个候选一次放行**」仍缺一个顶层循环：
- 多个候选同时敲门，先放谁？按成本升序（最省心优先）。
- 放了一个之后，场景变了，下一个候选的谈判计划要基于「已采纳者已进场」的新场景。
- 一个根本性的裁决问题始终悬而未决：**后到的候选想要一件已经被先到候选拿走的条目，协调器要不要把先到者让出去给后到者？**

R15 把这三件事做成纯函数调度器，并给出明确裁决。

---

## 2. R15 新增接口（单一真源：复用 `negotiate_plan`）

| 符号 | 位置 | 语义 |
|------|------|------|
| `struct ScheduledAdmit { agent : String, plan : NegotiatePlan }` | `claimguard.mbt` | 被采纳候选的身份 + 它落地时用的谈判计划（含 `yielded` 让权序列） |
| `struct ScheduleReport { admitted : Array[ScheduledAdmit], rejected : Array[String], total_priority_cost : Int, scene : Array[ClaimGuardState] }` | `claimguard.mbt` | 末态全景；`scene` = 在飞 `peers` + 被采纳候选的持有 |
| `schedule_admit(peers, candidates, max_steps, priorities) -> ScheduleReport` | `claimguard.mbt` | 顶层多候选准入调度器 |

`schedule_admit` 算法（纯读、零副作用）：
1. 维护 `peers_live`（可变，每轮折叠让权落这里）与 `committed`（不可变，已采纳候选 state 一旦进此列表**永不**被让权）。
2. 每轮重建 `scene = peers_live ++ committed`；对每个候选算 `negotiate_plan(cand, scene, max_steps, priorities)`。
3. **可采纳判据**：`report.ok` **且** 其 `yielded` 不包含任何 `committed` 内的 agent 名字。任何想挤让已提交 newcomer 的候选 → 整票不采纳。
4. 在可采纳集合里取 `priority_cost` 最小者（平手按 `cg_state_agent` 字典序小者先）为本轮 best；记入 `committed`，累加成本，并把它的 `yielded` 仅对 `peers_live` 做 `peer_yield` 折叠（**绝不动 `committed`**）。
5. 若一轮无任何可采纳候选 → 剩余全体进 `rejected` 并 `break`（预算/结构冲突无法消解，不静默放行）。
6. 末态 `scene = peers_live ++ committed`。

---

## 3. 关键不变量：先到先得 + 提交即锁定

被采纳的候选带着自己争用的条目进入 `scene`，成为「既成事实」。后续候选若想进场必须让出该条目 → 其 `yielded` 会命中已提交者名字 → 被判**不可采纳** → 整票拒绝，而非「靠挤让已接纳者进场」。

这把 R3~R14 悬而未决的「后到者要不要把先到者让出去」钉死为：**不**。调度器不是「全程最优重排」——它是贪心 + 先到先得，已落子的不悔棋。

---

## 4. 实证（双后端同绿，按 AGENTS.md BUG-142 判绿标准）

> 判绿以 `Total tests: N, passed: N, failed: 0` 汇总行为准，exit code 不可靠（BUG-142，moon 0.1.20260920 实测 SIGABRT 仍回 exit 0）。

| 后端 | 命令 | 结果 |
|------|------|------|
| JS (Node ≥ 24) | `moon test --target js src/claimguard` | `Total tests: 45, passed: 45, failed: 0.` |
| Native (Windows) | `moon test --target native src/claimguard` | `Total tests: 45, passed: 45, failed: 0.` |

R15 新增/重做 5 条白盒测例（全绿）：

- `cg_schedule_admit_cheapest_first`：在飞 Z(item-z)/A(item-a)，两候选 P1(只争 a,成本9)/P2(只争 z,成本1) 争的条目互不相交 → 两者都放行，且按成本升序 P2 先于 P1（候选反序给，证明调度器按成本重排而非输入序）。
- `cg_schedule_admit_multi_disjoint`：三候选各争一件互不相交条目 → 全放行，`total_priority_cost==17`（9+5+3），成本升序 P3→P2→P1，末态 `scene` 含三者持有。
- `cg_schedule_admit_committed_not_evicted`：两候选争同一件被高优先级 peer 独占的条目 → **恰好一个被采纳、另一个被拒**（验证「提交即锁定」：后者不能靠挤让前者进场）；末态 `scene` 确有持有者。
- `cg_schedule_admit_reject`：两候选各需让出 Z+A（两步），`max_steps=1` → 谁都进不来，`admitted==0 / rejected==2 / total_priority_cost==0`。
- `cg_schedule_admit_pure`：调用后原在飞 peer 与候选 state 原样未改（纯只读不污染）。

---

## 5. 测试设计教训（本回合踩的坑）

最初三测把「后到候选受益于先到者让出」当成预期（如 cascade_benefit：P2 先放让 Z 让出，P1 后续受益于 freed）。但 R15 的「提交即锁定」之后，**这个场景不可能成立**——先到者进场后**持有**该条目，后到者想进来只能去让先到者，而让先到者 = 挤让 committed = 整票驳回。原测试预期与不变式自相矛盾。

重做后的测例把语义钉成正确的 invariant：
- 互不相交条目 → 全放行（cheapest_first / multi_disjoint）。
- 互斥条目 → 恰好一个被采纳、另一个被拒（committed_not_evicted）。
- 步数预算不足 → 全部拒绝（reject）。
- 纯只读 → 不污染（pure）。

---

## 6. 资源消耗

- 改动文件（本 lane 孤立，未碰任何并发 lane 文件）：`src/claimguard/claimguard.mbt`（R15 块重写）、`src/claimguard/claimguard_wbtest.mbt`（R15 测例重做）、`src/claimguard/pkg.generated.mbti`（regenerate，rc=0）。
- 全仓 `moon info`：rc=0，826 警告 0 错误；警告全部来自 lane-owned `src/server`/`src/symbolic` 的预存在项（`unused_async`/`deprecated` 等），与本回合无关。
- 提交门禁前状态：`moon fmt` + `moon fmt --check` 双绿（rc=0）。
- **本回合未提交**：`AGENTS.md` 金条四规定不可逆操作只给方案 + 预案；且当前工作树有并发 lane 的未提交改动，按约定不 `git add`/`commit`。

---

## 7. 遗留风险与后续建议

- R15 仍是「待编排的强制层」：只算「采纳哪些候选 + 各自让权序列」，**执行**让权（`reserve_release` + `release_item` + `executor_route` 真实优先级注入）是协调器/生命周期责任，越出本包孤立作用域，待 owner 决策接入。
- 调度器是贪心 + 先到先得，不是全局最优；若未来需要「整体成本最低」语义，需在 committed 之外另开回溯层，但与「提交即锁定」互斥——需 owner 定调。
- BACKLOG 复核：本轮无新增可认领行（P2 native 巡检 / P3 self_search / F094 Phase-1 均带显式「现在不建」owner 裁决，未翻转）。

---

## 8. 超额内容

- 把 R15 同步追加进 `reports/2026-10-13-multilane-lock-mechanism-report.md` §10.14，与 §10.1~§10.13 同形收口，保持锁机制观测报告的连贯性（单一真源叙事不分裂）。

---

## 9. 来源

- 直接延续 R3~R14 的 `src/claimguard/` 孤立包（三维盲点门 `may_proceed_full`、对账门 `may_reconcile_ok`、级联谈判 `negotiate_admit_priority`、谈判计划 `negotiate_plan`）。
- 多 agent 锁机制真身观测见 `reports/2026-10-13-multilane-lock-mechanism-report.md`（§1~§10.13）。
- 判绿标准：AGENTS.md 金条八 / 账本 BUG-142。
