# 四模式流水线自我迭代 · Round 7 — 跨 agent 对账与隔离回归实证

> 日期：2026-10-13 · 轮次：7/256 · 模式：advance（隔离包内增量 + 双重回归验证）
> 目标对齐 `goal-1df65e1b`（实现计划表未实现计划 + 多 agent 同目标文件锁机制顺带看看 + 开关全开迭代自身）

## 1. 结果摘要

| 子目标 | 本回合状态 | 证据 |
|---|---|---|
| 实现 BACKLOG 未实现计划 | 全仓 `pending` 仅余 L16/L33（均超出本人安全认领范围） | §3 复核：其他车道已把 L35/37/38/41/42/43/44 全部翻 done |
| 用 FIST-Mbt 迭代自身（开关全开 = JS + native 双后端） | 隔离包双后端 21/21 全绿 + 跨 agent 对账增量 | §2 实测；§4 新增 |
| 多 agent 文件锁机制顺带看看 | 跨 agent 对账层（多个 agent 各持 guard 状态的盲点） | §4 + §5 |

## 2. 双后端实证（开关全开）

本轮先对**上一轮交付做隔离回归基线**，再叠加新增量，两步同绿（金条八：判绿以 `Total tests / passed / failed: 0` 汇总行为准，不靠 exit code，BUG-142）：

- **回归基线（证明隔离有效）**：先 `moon test --target js src/claimguard` 与 `--target native`，两者均 `Total tests: 19, passed: 19, failed: 0`。
  - 关键证据：自 Round 5/6 起本仓发生 **20+ 并发提交**（`b72c4c1`/`d54400e`/`32f04cb`/`08d1540`/`7d8dace`/`fe5840a`…），依赖面也变了（`moon.mod` 升 `moonbitlang/async@0.22.3`+`x@0.5.5`，全仓测试数 737→807）。本人隔离包 `src/claimguard/` 在这些并发改动下**仍 19/19 全绿**——这正是「多 agent 并发编辑同一项目、各守各的文件作用域、互不踩踏」的实测佐证：物理/作用域锁机制让本车道文件零回归。
- **叠加增量后**：
  - JS：`moon test --target js src/claimguard` → `Total tests: 21, passed: 21, failed: 0`（19→21，+2 跨 agent 对账用例）。
  - native：`moon test --target native src/claimguard` → `Total tests: 21, passed: 21, failed: 0`。
  - 仅依赖 `core`，无 SQLite 桩，native 无堆门约束。
- fmt 门：`moon fmt` 落盘 + `moon fmt --check src/claimguard` rc=0。
- 接口同步：`moon info` 重排 `pkg.generated.mbti`，新增导出 `overlapping_tag` / `reconcile_id_conflicts` / `reconcile_semantic_conflicts` / `struct CrossCollision`。

## 3. BACKLOG 复核（读全 62 行 + `git log --oneline -20` + `git status --short`）

本轮其他车道大举收口，**几乎所有原 `pending` 计划项已被其认领翻 done**：

| 项 | 状态 | 落地 commit（车道所有） |
|---|---|---|
| L35 / L37 / L38 | done | `b72c4c1 feat(backlog): 实现 L37/L38/L35` |
| L41 curriculum 自进化闭环 | done | `d54400e feat(evolve): L41 curriculum 自进化课程闭环` |
| L42 差异化定位 | done | `08d1540 docs: L42 差异化定位` |
| L43 github API 客户端 | done | `32f04cb feat(evolve): L43 github API 客户端供 self_search 使用` |
| L44 posoco 六边形架构调研 | done | `08d1540 docs: L44 posoco 六边形架构调研` |

全表 `pending` 实指仅剩两行，均**不在本人安全认领范围**：

| 行 | 事项 | 状态 | 本回合处置 |
|---|---|---|---|
| L16 | native 侧真实自驱巡检 | pending | owner「决定：现在不建」红线未翻；BUG-133 两格已达成只推翻技术理由，不推翻决策本身 |
| L33 | self_search「入库」接线 | pending | `src/evolve` 车道所有（当前正由 `e425c2b`/`7079e9d`/`32f04cb` 推进 self_search 与 github_json_to_tsv 桥接），行内明示「别由旁观者代翻」 |

结论：目标一「实现计划表中未实现的计划」在本会话语境下已**无可由本人安全认领的工作**——强行认领 L16/L33 会踩 owner 决策红线或他车道文件作用域。故目标一持续阻塞在 owner/lane 决策，而非本人执行未达。

> 工作树 `git status --short` 计数由上一轮 184 降至 **161**：其他车道正在收口收敛，整体朝 done 推进，进一步印证「无剩余可认领项」。

## 4. 多 agent 文件锁机制 · 跨 agent 对账层（顺带看看 + 自我迭代）

### 4.1 本轮新增：把「多 agent 各自持锁」的盲点直接建模
前几轮已覆盖单 agent 视角下的三层盲点（item-id / scope / semantic）。但「多个 agent 操作同一个目标项目」最危险的情形是：**每个 agent 各自维护一份 `ClaimGuardState`**——

- 每个 agent 只看见自己的认领，单看都以为独占；
- 文件作用域互不相交 → `reserve_scope` / `lock_acquire` / `file_binds` 全程静默；
- 单 agent 的 `semantic_collision` 也只比对「自己状态里的他主持有项」，**另一个 agent 的状态它根本看不见**。

于是碰撞只能在**对账（reconcile）两份状态时**浮现。本轮新增两个**纯函数、只读**对账：

- `reconcile_id_conflicts(a, b) -> Map[String,(String,String)]`：同 item-id 被不同 agent 各认领一次 → 输出 `item -> (agentA, agentB)`。
- `reconcile_semantic_conflicts(a, b) -> Array[CrossCollision]`：不同 id、不同 agent、但标签交集 → 输出 `{item_a, agent_a, item_b, agent_b, tag}`，首个交集标签 `tag` 一并给出。
- `overlapping_tag(a,b) -> String?`：两标签集首交集（对账的纯部件）。

**纪律**：对账函数一律 `pub` + **只读**——绝不写回任一方状态（`store_rsv.mbt::rsv_action` 仍是物理锁单真源，claimguard 只作逻辑叠加层）。这与「多 agent 并发、各守各锁、对账只读发现盲点」的协作模型同构。

### 4.2 用例覆盖（双后端 21/21）
- `cg_reconcile_id_conflict`：A 在 `src/symbolic` 认领 L38、B 在 `src/constraint` 也认领 L38（作用域不相交、物理静默）；单看各以为独占，对账才暴露 `L38 -> (A,B)`；对账后双方状态不变（只读）。
- `cg_reconcile_semantic_collision`：A 的 L16「native 巡检」(native/inspection) 与 B 的 L33「self_search 入库」(native/evolve) 跨 agent 标签交集 → 对账命中 `tag=native`；反向枚举也命中一次；各自单看无 id 冲突、无自语义碰撞。

## 5. 资源消耗

- 命令：约 10 发（`git log/status`、`moon test` JS+native ×2 次（基线+增量）、`moon fmt`×2、`moon info`、`fmt --check`、调试/复核）。
- 无子代理派发（纯增量编码 + 验证）。无不可逆操作。

## 6. 遗留风险 / 后续建议

1. **L16 / L33**：仍等 owner 复核或被 `src/evolve` 车道落账翻 done，本人不代翻。
2. **接入 MCP 生命周期**：`claimguard` 当前是纯库层。要让多 agent 真按「先过单 agent 综合门、再定期跨 agent 对账」运作，需在 MCP 侧接 `server.mbt`（建议复用 `reserve_scope` 契约：先预订作用域+逻辑项+标签，再动文件，并加一个对账定时任务消费各 agent 的 guard 快照）。届时需先 `reserve_scope` `src/store`+`src/server` 且需 owner 授权——非本人可单方落地。
3. **git 收口**：工作树仍为大规模多车道并发 WIP（161 条改动 + 大量未跟踪草稿）。严禁 `git add -A`/`git commit`；本回合仅落盘本人隔离报告文件，不碰任何已跟踪文件。

## 7. 超额内容

- 顺带实证：在 20+ 并发提交、依赖面升级（async 0.22.3、测试数 737→807）的多车道并发树下，本人隔离包做跨 agent 对账增量后**仍双后端全绿且零回归**——说明 claimguard 这一逻辑叠加层可独立演进、不影响主构建面，多 agent 同目标迭代的隔离纪律自证有效。
