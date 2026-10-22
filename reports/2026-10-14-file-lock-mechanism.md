# 2026-10-14 多 Agent 文件锁定机制速览

> 顺带考察：fist-mbt 里"多个 agent 操作同一个目标项目文件"的锁定机制如何防止冲突。
> 结论：**两层互不替代**——`reserve_scope` 是真互斥（轻量），`lock_acquire` 是持久化版（带 TTL/续租/接管），底层裁决共用同一份真源。

## 一、两套工具的定位

| 层面 | 工具 | 语义 | 冲突时 |
|---|---|---|---|
| 作用域预订（轻量） | `reserve_scope` / `reserve_check` / `reserve_release` | 对"文件/目录/资源"做轻量独占预订，TTL 内独占 | **不写**，回 `held_by`（持有者） |
| 分布式文件锁（持久） | `lock_acquire` / `lock_renew` / `lock_release` / `lock_status` | 同上但带 lock_id、续租、违例接管、状态查询 | **不写**（BUG-145 修复后），回 `blocked_by` |

## 二、底层裁决（单一真源）

`src/store/store_rsv.mbt` 的 `rsv_action(prev, agent, now)` 是**唯一**冲突矩阵：

```moonbit
match prev {
  None                       => (true,  "reserved")   // 无前置 → 写
  Some((owner, _, _)) if owner == agent => (true, "renewed")  // 同主 → 写（续）
  Some((_, ttl, _))  if ttl < now      => (true,  "taken_over") // 他人但 TTL 过期 → 写 + 记 prev_agent
  _                         => (false, "conflict")  // 他人活体 → 拒绝，不写
}
```

要点：
- **同持有者排在过期之前**：自己续一条已过期的预订报 `renewed`，不报 `taken_over`。
- `agent`/`ttl_until` 一律返回**库里现值**，不是调用方请求值——回执不许由请求反推。
- 锁层 `lock_acquire_action` **逐字委托** `rsv_action`，不另写谓词（BUG-145）。

## 三、写路径差异（为何两套都要）

### reserve_scope（`rsv_try_set`）
- 先取写前快照 → `rsv_action` 裁决 → 只在该写时写 → **写后回读**收口。
- 跨进程下先读后写有竞态窗口，但写前裁决 + 写后回读把"两边都读到空闲就都写成功"堵住（BUG-136）。

### lock_acquire（`locks_try_acquire`）
- SQLite 后端把裁决编码进 `INSERT ... ON CONFLICT(scope) DO UPDATE WHERE reservations.agent = excluded.agent OR reservations.ttl_until < excluded.created_at`——**数据库级裁决**，不是先读后写。
- BUG-145 历史：旧实现 `locks_upsert` 是 last-write-wins，恒"拿到"——A 持锁时 B 照样 acquire 成功（只记一条 violation）。修复后走 `locks_try_acquire` 的数据库级裁决，B 会拿到 `granted=false, blocked_by=A`。

## 四、关键设计教训

1. **先读后写是竞态温床**：内存后端没有窗口，SQLite 有——所以两后端必须同形状（同裁决 + 同写后回读），否则单测绿而生产红。
2. **手写 forked 谓词是漂移雷**：锁层曾自带一段手写谓词，只决定"要不要记违例"，随后无条件覆盖写——把 `rsv_action` 的 `conflict` 丢弃。单一真源纪律把它拉回 `rsv_action` 一处。
3. **TTL 过期不是删除**：过期让渡走 `taken_over`（记 `prev_agent`），释放走 `reserved`（新主）。过期后旧主的行仍在库里，`reserve_check` 会回 `free=true` + `expired_ttl_until` 供审计。
4. **失效锁不许靠续期复活**：`lock_renew` 对非 `active` 锁（released/expired/violated）显式报错，要重新获取走 `lock_acquire`。

## 五、源码落点

| 文件 | 内容 |
|---|---|
| `src/store/store_rsv.mbt` | `rsv_action` 单一真源 + 内存后端 `rsv_*` + 锁层 `lock_acquire_action` 委托 |
| `src/store/store_sqlite.mbt` | SQLite 侧 `ON CONFLICT ... WHERE` 编码同一裁决 + `locks_try_acquire` |
| `src/server/server.mbt` | `reserve_scope`/`reserve_check`/`reserve_release` + `lock_acquire`/`lock_renew`/`lock_release`/`lock_status` 工具注册 |
| `src/store/store_rsv_test.mbt` | `lock_acquire_action` 5 条白盒锁（含 BUG-145 修复面） |
| `src/claimguard/claimguard_wbtest.mbt` | 逻辑层（claimguard 裁决矩阵）与物理层（reserve/lock）一致性锁 |

## 六、实操建议（给并发 agent）

- 动文件前先 `reserve_scope scope=<path> agent=<self> ttl_until=<now+300s>`，拿到 `reserved=true` 才动；别人拿到 `conflict` 就换文件或等 TTL。
- 同一 agent 重复 `reserve_scope` 会得到 `action=renewed`——顺手刷新 TTL 是正确姿势。
- `reserve_check` 只读不写，先查再动手更省心。
- 长任务用 `lock_acquire` + 定期 `lock_renew`（比 reserve_scope 多一重"过期即失"的兜底）。