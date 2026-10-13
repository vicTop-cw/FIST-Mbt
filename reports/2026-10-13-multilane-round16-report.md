# 四模式流水线自我迭代 · Round 16 报告（多 Agent 文件锁机制 · R16 末态不变量收口）

- 生成时间：2026-10-13T(本回合) +08:00（沿用本 lane 隔离报告序列 `round4→round15` 的 `2026-10-13` 日期前缀，不新开日期前缀以免与并发 lane 的 `reports/` 所有权边界混淆）
- 观测/实现对象：`src/claimguard/claimguard.mbt`（R15 `schedule_admit` 末态 `scene`）、`src/claimguard/claimguard_wbtest.mbt`（R16 端到端白盒测例 + 纯读 helper `cg_scene_collision`）
- 实现方式：在 R3~R15 已建的三维盲点门 + 对账门 + 级联谈判 + 谈判计划 + 多候选调度器之上，补一层**端到端断言**——直接验证调度器对外承诺的最终保证：① 末态 `scene` 任一逻辑项至多被一个 agent 持有（物理文件锁 / 作用域锁 / file_binds 都关不上的「逻辑碰撞门」）；② 被 `rejected` 的候选绝不作为任何状态持主泄漏进 `scene`。
- 结论一句话：**整条锁链（盲点 → 对账 → 谈判 → 调度 → 末态不变量）在 R16 闭合——调度器不只是「算出谁是 committed」，而是「保证末态全景无逻辑碰撞且被拒者不抢项」，这正是多层物理锁都补不到的协作互斥最后一块拼图。**

---

## 1. 背景与缺口

R15 的 `schedule_admit` 把多候选准入做成纯函数调度器，并钉死了「先到先得 + 提交即锁定」不变量（已采纳的 newcomer 是既成事实，绝不被后来候选挤让）。

但 R15 只证明了**调度过程**的正确性（恰好一个采纳 / 一个被拒、committed 不被逐出、纯只读）。它还缺一层**对外承诺的端到端保证**：

- 调度器吐出的 `scene = peers_live ++ committed` 是不是真·无逻辑碰撞？两个 agent 在互不相交文件作用域里实现同一 BACKLOG 项（逻辑碰撞），物理文件锁 / 作用域锁 / `reserve_scope` / `file_binds` 全都关不上这扇门——只有「调度层末态对账」这道逻辑门能挡。
- 被 `rejected` 的候选，会不会「静默落进 scene 抢走争用项」？若 `rejected` 列表之外的状态里出现被拒 agent 的持主署名，等于没真正拒绝。

R16 补这层端到端断言，把整条链收口。

---

## 2. R16 新增内容（白盒，零新增 `pub` 符号）

纯读 helper（测试侧，不导出）：

| 符号 | 位置 | 语义 |
|------|------|------|
| `cg_scene_collision(scene) -> (Bool, String, String, String)` | `claimguard_wbtest.mbt` | 遍历 `scene` 各 state 的 `holders`，对每项记录首个持主；遇异主即报 `(碰撞, 项, 甲方, 乙方)` |

三条端到端白盒测例：

| 测例 | 场景 | 断言 |
|------|------|------|
| `cg_schedule_scene_invariant_disjoint` | 三候选各争一件互不相交条目（已被 R15 证全放行） | 末态 `scene` **零逻辑碰撞**；且每个被采纳候选的持有项在 `scene` 中落到该候选名下（P1/P2/P3 各见其项） |
| `cg_schedule_scene_invariant_conflict` | 两候选争同一被 peer 独占的条目（已被 R15 证「恰好一个采纳、一个被拒」） | 末态 `scene` 零逻辑碰撞；且 `rejected[0]` 的名字**不作为任何 state 持主**出现（被拒者没抢到该项） |
| `cg_schedule_scene_rejected_no_leak` | 步数预算不足致两候选全拒（`max_steps=1`），`scene` 由在飞 peer 原样构成 | 末态 `scene` 零逻辑碰撞；且 P1/P2 都不作为持主出现在 `scene` 中 |

`cg_scene_collision` 的遍历覆盖 `peers_live ++ committed` **全量**，故该不变量对「被采纳 newcomer 的持有 + 在飞 peer 的原持有」整体成立，而非只对某一侧成立。

---

## 3. 关键不变量：末态全景零逻辑碰撞 + 被拒者不泄漏

这是整条锁链对外的**最终承诺**：

1. **逻辑碰撞门**（物理锁补不到）：`scene` 中任一逻辑项至多被一个 agent 持有。`cg_scene_collision` 全量扫描给出可证伪断言——一旦有任何 `(item, h1)` 与 `(item, h2)` 且 `h1 != h2`，测试立即红。这正是「两 agent 在互不相交文件作用域实现同一 BACKLOG 项」那类冲突的唯一收口点。
2. **拒绝完整性门**：`rejected` 集合里的 agent 名，**绝不**作为任何 state 的持主出现在 `scene` 中。拒绝不是「算了不报」，而是「真·没进场」。

这两门直接挂在 R15 的 `schedule_admit` 输出上，不引入第二套逻辑——R16 只做对账断言，复用既有的 `scene` / `rejected` 字段。

---

## 4. 实证（双后端同绿，按 AGENTS.md BUG-142 判绿标准）

> 判绿以 `Total tests: N, passed: N, failed: 0` 汇总行为准，exit code 不可靠（BUG-142，moon 0.1.20260920 实测 SIGABRT 仍回 exit 0）。

| 后端 | 命令 | 结果 |
|------|------|------|
| JS (Node ≥ 24) | `moon test --target js src/claimguard src/constraint` | `Total tests: 61, passed: 61, failed: 0.` |
| Native (Windows) | `moon test --target native src/claimguard src/constraint` | `Total tests: 61, passed: 61, failed: 0.` |

（注：本 lane 隔离两包 `src/claimguard` + `src/constraint` 合计 61 测——R15 时 58，R16 新增 3 条纯端到端断言后 61；`src/constraint` 13 测未动、全绿。非全仓 737，因本 lane 只持有这两包的孤立作用域，全仓门由 JS 后端（`moon.mod` 钉版）在并发 WIP 收口后统一跑。）

R16 新增 3 条白盒测例（全绿）：

- `cg_schedule_scene_invariant_disjoint`：三候选互不相交全放行 → `scene` 无逻辑碰撞，且 P1/P2/P3 各自持有的 `item-a/item-b/item-c` 在 `scene` 中确落到对应候选名下。
- `cg_schedule_scene_invariant_conflict`：两候选争同一被独占项 → 一采纳一拒；`scene` 无逻辑碰撞，且被拒候选名不出现在任何 state 持主中。
- `cg_schedule_scene_rejected_no_leak`：`max_steps=1` 致两候选全拒 → `scene` 由在飞 peer 原样构成、零碰撞，且 P1/P2 均不泄漏为持主。

格式与类型门（提交门禁前状态，本回合不提交）：

| 步骤 | 命令 | rc |
|------|------|-----|
| 格式化 | `moon fmt src/claimguard` | 0 |
| 格式校验 | `moon fmt --check src/claimguard` | 0 |
| 类型检查 | `moon check src/claimguard` | 0 |
| 接口重排 | `moon info` | 0（826 警告 0 错误，警告全来自 lane-owned `src/server`/`src/symbolic` 预存在项） |

---

## 5. 测试设计教训（本回合踩的坑）

`schedule_admit` 是纯函数、末态 `scene` 已是确定结构，端到端断言本应直白。但落笔时撞到本仓 MoonBit 版本（0.1.20260920）API 约束：

- `assert_true` 在此版本**只接受单个 `Bool` 位置参数**，`msg` 是具名可选、不能作第二位置参数。初版 `assert_true(!col.0, "场景出现逻辑碰撞: " + ...)` 直接报 `requires 1 positional arguments, but is given 2`。已改为只传 `Bool`（与既有 `assert_eq(rep.admitted.length(), 1)` 风格一致），碰撞详情靠 `col` 元组在失败时由测试框架呈现，不靠手拼消息。
- 这是「先按既有测例风格（单参 `assert_true`）写、别自创双参重载」的惯例提醒；同仓 `_wbtest` 里 `assert_true` 一律无消息参数。

---

## 6. 资源消耗

- 改动文件（本 lane 孤立，未碰任何并发 lane 文件）：`src/claimguard/claimguard_wbtest.mbt`（R16 测例 + `cg_scene_collision` helper，append 在文件尾）、`src/claimguard/pkg.generated.mbti`（regenerate，rc=0）。
- 全仓 `moon info`：rc=0，826 警告 0 错误；警告全部来自 lane-owned `src/server`/`src/symbolic` 的预存在项（`unused_async`/`deprecated` 等），与本回合无关。
- 提交门禁前状态：`moon fmt` + `moon fmt --check` 双绿（rc=0）。
- **本回合未提交**：`AGENTS.md` 金条四规定不可逆操作只给方案 + 预案；且当前工作树有并发 lane 的未提交改动，按约定不 `git add`/`commit`。
- **金条五日誌跳过**：`memory/` 属并发 lane 所有（critical-context 明确「do NOT edit lane-owned files」），故不追加 `memory/YYYY-MM-DD.md`；本报告即为本回合对外交付。

---

## 7. 遗留风险与后续建议

- R16 仍是「待编排的强制层」链条上的**对账断言**一环：`schedule_admit` 只算「采纳哪些候选 + 各自让权序列 + 末态 scene」，把 scene 落进真实 store / 执行让权（`reserve_release` + `release_item` + `commit`）是协调器/生命周期责任，越出本包孤立作用域，待 owner 决策接入。R16 不新增 `pub` 符号，只加测试侧 helper，零侵入。
- 整条链（R3 盲点 → R6 对账 → R13 级联谈判 → R14 谈判计划 → R15 调度 → R16 末态不变量）现已在 `src/claimguard/` 孤立包内**端到端白盒可证**，但「接 MCP 生命周期真把 scene 落库」仍悬（F094 Phase-1 三工具 `file_bind/file_release/file_status` 带 owner「先修承重墙、不建三工具」裁决，未排期）。
- BACKLOG 复核：本轮无新增可认领行（L16 native 巡检 / L33 P3 self_search / L49 F094 Phase-1 均带显式「现在不建」owner 裁决，未翻转）。

---

## 8. 超额内容

- 把 R16 同步追加进 `reports/2026-10-13-multilane-lock-mechanism-report.md` §10.15，与 §10.1~§10.14 同形收口，保持锁机制观测报告的连贯性（单一真源叙事不分裂）。

---

## 9. 来源

- 直接延续 R3~R15 的 `src/claimguard/` 孤立包（三维盲点门 `may_proceed_full`、对账门 `may_reconcile_ok`、级联谈判 `negotiate_admit_priority`、谈判计划 `negotiate_plan`、调度器 `schedule_admit`）。
- 多 agent 锁机制真身观测见 `reports/2026-10-13-multilane-lock-mechanism-report.md`（§1~§10.15）。
- 判绿标准：AGENTS.md 金条八 / 账本 BUG-142。
- 提交门禁：AGENTS.md「Commit gate（提交门禁 · 本仓强制标准）」——本回合未提交，仅留存格式化 + 门禁前状态。
