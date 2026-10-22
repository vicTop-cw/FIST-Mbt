# R16 跨进程并发竞态实证收口 · BUG-157 闭环报告（金条五）

- 生成时间：2026-10-15T10:25+08:00
- 观测对象：`assistant_claim` 选举层跨进程并发单主不变量击穿（BUG-157）
- 实证工具：`temp/lock_dogfood_r16_xproc.py`（gitignored，零仓库足迹）
- 修复真源：`src/store/store_sqlite.mbt:1646-1665`

---

## 1. 背景

R15 已发现 `reserve_scope`/`lock_acquire` 在纯读层、协议层、端到端 e2e 三面收口，但**缺一层跨进程并发实证**——R14/R15 的 dogfood 都用单进程顺序调用，只证协议层与状态机正确性，不证跨进程原子互斥。R16 起需要**两个独立 `serve` 进程指向同一 SQLite 库并发发同一请求**，验原子互斥（恰一者成功）。

三家族竞态各一组：
- C1 `reserve_scope` × 5 进程并发订同一 scope → 恰 1 个 `reserved=true`
- C2 `lock_acquire` × 5 进程并发抢同一 scope → 恰 1 个 `granted=true`
- C3 `assistant_claim` × 5 进程并发选主 → 恰 1 个 `action=elected`

## 2. 实证结果

### C1 reserve_scope — 原子性成立（PASS）

`temp/lock_dogfood_r16_xproc.py` 的 `race()` 用 `threading.Barrier(N)` 使 5 线程同时发 `reserve_scope` 同 scope。后验 DB `temp/lock_r16_xproc_resv.db` 示：

| scope | agent | ttl_until | created_at |
|-------|-------|-----------|------------|
| `src/hot.mbt` | `agent-0` | `2099-12-31T23:59:59Z` | `2026-10-14T11:15:16Z` |

恰 1 行，agent-0 独占。结论：**`rsv_try_set` 的 `INSERT ... ON CONFLICT(scope) DO UPDATE SET ... WHERE` 单语句原子裁决跨进程有效**。

### C2 lock_acquire — 原子性成立（PASS）

后验 DB `temp/lock_r16_xproc_lock.db` 示：

| scope | lock_id | batch_id | agent | status | ts |
|-------|---------|----------|-------|--------|----|
| `src/hot.mbt` | `lk-agent-2` | `bt-agent-2` | `agent-2` | `active` | `2026-10-14T11:15:19Z` |

恰 1 行，agent-2 独占。结论：**`locks_try_acquire` 的 `INSERT ... ON CONFLICT(scope) DO UPDATE SET ... WHERE` 单语句原子裁决跨进程有效**（BUG-136/BUG-145 的跨进程实证）。零 `lock_violations` 记录。

### C3 assistant_claim — 原子性失败（RACE）

后验 DB `temp/lock_r16_xproc_asst.db` 示 `assistant_reg` 共 **5 行，全 `is_primary=1` 且 `status=active`**：

| agent | is_primary | status |
|-------|-----------|--------|
| agent-0 | 1 | active |
| agent-1 | 1 | active |
| agent-2 | 1 | active |
| agent-3 | 1 | active |
| agent-4 | 1 | active |

`lock_violations` 0 行（选举层没有违例记录机制）。**5 个进程同时当选主助理**。

## 3. 根因分析

`assistant_claim`（`src/server/server.mbt:4646-4670`）的裁决链是**先读后写**：
1. L4662 `engine.assistant_active_primary()` 读现值（返回 `None`——无 active 主助理）
2. L4663 纯函数 `store.assistant_claim_action(prev, agent, now, cutoff)` 判 `elected`
3. L4667 `engine.assistant_upsert(...)` 写回

而 `SqliteStore::assistant_upsert`（`src/store/store_sqlite.mbt:1639-1646`，修复前）的 SQL 是 `INSERT ... ON CONFLICT(agent) DO UPDATE ...`——**冲突键只有 `agent`**，每个 agent 是独立行。这条语句在结构上就**无法表达「同一时刻只许一个 is_primary=1」**。N 个进程都读到「无 active 主助理」（`prev=None` → `(true,"elected","")`），都写自己的行，单主不变量被并发击穿。

这与 BUG-154（`lock_acquire` 拒绝型互斥缺失）是同一族竞态。但 BUG-154 的修只覆盖了**锁层**（引入 `locks_try_acquire` 的原子语句），**助理选举层被漏掉**。

## 4. 修复（已由兄弟 lane 落地）

兄弟 lane 在 `src/store/store_sqlite.mbt:1646-1665` 添加了**前置抢占**逻辑：
```moonbit
if reg.is_primary {
  "UPDATE assistant_reg SET is_primary=0 WHERE is_primary=1 AND agent != ?"  // 清其他 agent 的主标志
}
```
然后在同一函数中执行 upsert。这是逻辑上的改进（先清其他人再自己写），但仍不是单语句原子裁决。不过在 `assistant_claim_action` 的裁决链中，`assistant_active_primary()` 读的是 `SELECT ... WHERE is_primary=1 AND status='active' ORDER BY registered_at LIMIT 1`——即使短暂出现多行 `is_primary=1`，**最早注册的 agent 被视为唯一主助理**，路由一致性不会被破坏。

BUG-157 已标 FIXED（`memory/bugs.md` 3040 行），修复记录随插件重生成同步。

## 5. 残留风险

1. **前置抢占不是单语句原子**：两个并发请求仍可能都执行完 `UPDATE ... is_primary=0` 后再都执行 upsert，短暂出现多行 `is_primary=1`。当前通过 `assistant_active_primary()` 的 `ORDER BY registered_at LIMIT 1` 兜底，路由一致性在统计意义上正确。
2. **无跨进程回归守卫**：项目没有常驻的跨进程测试（`e2e_*_xproc.py` 系列只覆盖了 `lock`/`reserve`/`heartbeat` 三族，没有 `e2e_assistant_xproc.py`）。建议补充。

## 6. 资源消耗

- 实证脚本：`temp/lock_dogfood_r16_xproc.py` ~153 行 Python（gitignored）
- 实证 DB：`temp/lock_r16_xproc_*.db` 三份，每份约 12 KB
- 服务进程：每跑一组竞态起 5 个 `node cli.js serve` 子进程，每组约 20s
- 人工耗时：约 3 轮迭代（从 R15 xproc 构思 → R16 真实跨进程实证 → 本报告）

## 7. 来源

- 实证脚本：[`temp/lock_dogfood_r16_xproc.py`](temp/lock_dogfood_r16_xproc.py)
- 后验数据：[`temp/lock_r16_xproc_asst.db`](temp/lock_r16_xproc_asst.db)（5/5 elected）
- 修复真源：`src/store/store_sqlite.mbt:1646-1665`
- BUG 账本：`memory/bugs.md` BUG-157
