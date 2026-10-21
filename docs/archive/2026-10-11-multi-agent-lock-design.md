# 多 Agent 同项目文件锁 + 项目助理 设计（2026-10-11）

> 需求：多个管家/多个 agent 同时用 fist-mbt 开发**同一个目标项目**时，写文件要有锁；
> 锁上带**持有者 PID（判活）+ 待写文件清单**；文件被写时他人只能等或先去做空闲任务；
> 新增角色 **`项目助理`（每目标项目唯一）**：清死锁、监控规范性、"警察"权——可直接 kill 注册的 PID。
> 约束：**兼容现有功能、零破坏**（既有工具/表/测试/守卫全不动，能力纯增量）。

---

## 1. 设计总原则

1. **纯增量，零回归**：新表 + 新工具组，既有 `reserve_scope/check/release`、`reservations` 表、`rsv_*` 函数、`heal`/`heartbeat` 全部原样保留。旧预订是"建议性软锁"，新文件锁是"强制性互斥锁"，两层并存、互不干扰（旧层今后仍可用于非文件类作用域，如"模块名/资源"）。
2. **单真源复用**：原子裁决规则直接复用 `rsv_action` 的成熟形态（写前快照→规则→写后回读；SQLite 侧 `ON CONFLICT ... WHERE` 编码同一规则），不重造轮子、不引入新的竞态窗口。
3. **判活双通道**：PID 判活是**辅助证据**，心跳（heartbeat）是**主判据**——因为多个 agent 可能共享同一个 MCP server 进程（PID 相同），单凭 PID 无法区分持有者；且 PID 有复用问题。锁的存活 = `ttl_until 未过期` 且（可选）`heartbeat_at 新鲜`。助理清扫时：TTL 过期 → 释放；心跳陈旧 + PID 确认死亡 → 释放并记违规。
4. **杀进程走专用固定 argv 通道**：仿 `executor_run`/`cli_argv.mbt` 先例——`assistant_kill` 在服务端拼死 argv（win32: `taskkill /PID <n> /T /F`；posix: `kill -9 <n>`），**不经 shell**、参数全整形、目标 PID 必须存在于 `file_locks` 登记表内。复用 `run_check_guard` 的子树约束思路，但**不借用 run_check 白名单**（taskkill/kill 不在白名单内），是独立的受控宿主能力。
5. **一切治理动作落审计**：锁的强取/释放/杀 PID/助理接管，全部进 `audit_log`（进程内）+ `call_log`（跨进程），与既有治理面一致。

## 2. 数据模型（新表，CREATE TABLE IF NOT EXISTS，随 store 初始化）

存放位置：与 `reservations` 同一个库（每目标项目一个 `fist-mbt.db`）——锁天然按项目隔离，无需加 project_dir 列。

### 2.1 `file_locks` —— 文件互斥锁

| 列 | 类型 | 说明 |
|---|---|---|
| `lock_id` | TEXT PRIMARY KEY | `L-<ulid>`，服务端生成 |
| `path` | TEXT NOT NULL | 待写文件（相对项目根，拒绝对路径/`..`，同 `run_check` workdir 口径） |
| `agent` | TEXT NOT NULL | 持有者身份（调用方自报，可审计） |
| `pid` | INTEGER NOT NULL DEFAULT 0 | 持有者进程 PID |
| `acquired_at` | TEXT NOT NULL | 服务端盖章（BUG-33 政策，调用方无 now） |
| `ttl_until` | TEXT NOT NULL | 服务端盖章 = acquired_at + ttl_sec（调用方传 ttl_sec 秒数，不传默认 600） |
| `heartbeat_at` | TEXT NOT NULL DEFAULT '' | 最近一次 lock_renew |
| `batch_id` | TEXT NOT NULL | 同一笔多文件锁共享一个 batch_id，**全有或全无** |

> **多文件锁 = all-or-nothing**：`lock_acquire(files=[a,b,c])` 原子检查 a/b/c 全部空闲（或全部归本 agent 续期）才授予，任一被占则整笔拒绝并回 `blocked_by`。这从根上排除多锁顺序死锁（不存在部分持锁状态）。

### 2.2 `lock_violations` —— 规范性台账（助理的"案底"）

| 列 | 说明 |
|---|---|
| `id` INTEGER PK | 自增 |
| `ts` TEXT | 服务端盖章 |
| `agent` / `pid` | 违规者 |
| `kind` TEXT | `ttl_expired_reaped` / `pid_dead_reaped` / `killed_by_assistant` / `force_takeover` / `no_renew_long_hold` |
| `detail` TEXT | 当时的锁信息 JSON |

### 2.3 `assistant_reg` —— 项目助理登记表（每项目至多一行有效）

| 列 | 说明 |
|---|---|
| `agent` TEXT PK | 助理身份 |
| `pid` INTEGER | 助理进程 PID |
| `registered_at` / `heartbeat_at` TEXT | 盖章 |
| `status` TEXT | `active` / `dead`（助理自己也判活：心跳超 TTL → 标记 dead，下一位可 claim） |

> 助理选举 = 首次 `assistant_claim` 直接成功；已有 active 且心跳新鲜 → 拒绝并回现任；active 但心跳死 → take_over（同 `rsv_action` 规则），旧助理记 `force_takeover` 违规（如果旧 PID 其实还活着——说明它占着位不干活，这正是警察要管的事）。

## 3. 工具面（新组 `lock_*` + `assistant_*`，9 件；既有 136 件不动）

### 3.1 锁三件套 + 等待建议

| 工具 | 语义 |
|---|---|
| `lock_acquire(project_dir, agent, pid, files[], ttl_sec?)` | 原子全有或全无。返回 `{granted, lock_id, batch_id, blocked_by?, wait_hint?, idle_suggestion?}`。**blocked 时附带 `idle_suggestion`**：由 `task_triage` 纯读计算给一件"可做其它事情"的建议（待领取任务中挑一件与 blocked 文件无关的）——把"只能等待先做其它事情"落成调用方循环：`lock_acquire → blocked → 做 idle_suggestion → 再 lock_acquire`。 |
| `lock_renew(project_dir, lock_id, agent)` | 心跳：刷 `heartbeat_at` + 顺延 `ttl_until`（限持有者可调，同 `rsv_release` 持有者校验）。 |
| `lock_release(project_dir, lock_id?, batch_id?, agent)` | 正常释放；持有者校验；缺参报全量（防误删）。 |

### 3.2 助理五件套（警察权）

| 工具 | 语义 | 硬门 |
|---|---|---|
| `assistant_claim(project_dir, agent, pid)` | 竞选助理（上述选举规则） | — |
| `assistant_status(project_dir)` | 查现任助理 + 当前锁全景（谁持锁/多久/哪些文件）+ 违规统计 | 纯读 |
| `assistant_sweep(project_dir)` | 清扫：扫 `file_locks`，TTL 过期→释放记 `ttl_expired_reaped`；心跳陈旧→**PID 判活**（win32 `tasklist /FI "PID eq N"` / posix `kill -0` 语义，固定 argv spawn）→ 死则释放记 `pid_dead_reaped`，活则仅警告记 `no_renew_long_hold` | 仅助理可调（agent 身份校验） |
| `assistant_kill(project_dir, pid, reason)` | **杀注册的 PID**：目标 PID 必须出现在 `file_locks` 或 `assistant_reg` 中（"注册的 PID"语义逐字落实）；先夺其全部锁再杀 | `force=true` 显式硬门 + `reason` 必填非空 + 落 `lock_violations(kind=killed_by_assistant)` + audit_log；固定 argv `taskkill /PID n /T /F`（win32）/ `kill -9 n`（posix），不经 shell、参数整型化 |
| `assistant_audit(project_dir)` | 规范性报告：持锁时长分布、逾期未续率、违规榜、无锁改文件的嫌疑线索（与 `call_log` 里 execute 记录交叉——只能给线索不能定罪，诚实标注） | 纯读 |

## 4. 兼容性矩阵（零破坏的证据面）

| 面 | 措施 |
|---|---|
| 既有 136 工具 | 一字不改；新 9 件纯追加 → `check_tools_sync`/`check_doc_surface` J3/J14 按既有流程同步计数 |
| `reservations` 表 / `rsv_*` | 不动；文件锁独立表，旧层行为不变 |
| 新表 × BUG-28 守卫 | 三张新表都有写入点（`check_store_tables_wired` 双向判据天然满足），或落 `schema-reserved:` 点名 |
| 双后端 | 内存后端同步实现同名方法（`store_locks.mbt` 仿 `store_rsv.mbt` 双后端同构，防"单测绿 SQLite 红"老坑 BUG-79/85） |
| 时间戳 | 全部服务端盖章（BUG-33）；`ttl_sec` 是相对秒数，无 now 注入面 |
| 路径安全 | `files[]` 走 `run_check` 同款的相对路径+子树校验（拒 `..`/盘符/绝对路径），防借锁路径遍历 |
| 守卫族 | cl7：改 server.mbt 后必重跑 `gen_plugins.py`；J9 返回契约描述闭表一次写对；`check_desc_enum_sync` 登记新 enum 字段（kind/status 闭集） |
| 测试 | 白盒锁 ≥6 把：全有或全无（部分占用整笔拒）/ 持有者 renew / 非持有者 release 拒 / TTL 过期清扫 / 助理选举 take_over / kill 硬门（force=false 拒、未注册 PID 拒） |
| 版本 | 0.3.8 → 0.3.9 minor（能力纯增量） |

## 5. 典型时序（两个 agent 改同一文件）

```
agent-A: lock_acquire(files=[src/x.mbt])           → granted L-1
agent-B: lock_acquire(files=[src/x.mbt])           → blocked_by=A, idle_suggestion=领任务T12
agent-B: claim T12 → 干完 → lock_acquire 重试       → granted（若 A 已 release）
agent-A: lock_renew（每 ≤ttl/3 心跳）→ 写文件 → lock_release

助理(每拍或定时): assistant_sweep
  - A 崩溃（PID 死、心跳停）→ 释放 L-1 记 pid_dead_reaped → B 下一轮即可拿到
  - B 恶意长占（心跳在但 TTL 过了 N 倍）→ 警告；再不释放 → assistant_kill(pid=B, force=true)
```

## 6. 分期落地（每期独立可验、可回滚）

- **阶段 1 · 锁核心**：`file_locks` 表 + 双后端 + `lock_acquire/renew/release` + 白盒锁。纯增量，落地即可用。
- **阶段 2 · 助理**：`assistant_reg` + `lock_violations` + `assistant_claim/status/sweep/audit`（kill 先只登记不执行）。
- **阶段 3 · 警察权**：`assistant_kill` 真执行（固定 argv 通道）+ `assistant_audit` 交叉线索。
- **阶段 4 · 生态接线**：`watchdog_tick` 可选 `sweep_locks=true` 分支（无人值守时助理自动清扫，仿 `flush_bug_queue` 的诚实标注先例 BUG-210）；client 侧 `lock wait → idle suggestion` 循环模板进 `templates/`。

## 7. 诚实的边界与风险

1. **PID 判活的固有局限**：PID 复用、同进程多 agent。故判活只作辅助，主判据是心跳+TTL；kill 只针对"已登记 PID"（需求原文即是"kill 注册的PID"），不开放任意 PID。
2. **助理自身也可能死**：`assistant_reg.status=dead` 检测 + 下次 claim take_over；助理无心跳时不阻塞锁功能（锁只靠 TTL+清扫拍，助理是增强不是依赖）。
3. **防滥用**：助理权大（kill），故每次 kill 强制 `force=true`+reason+落案底+audit；`assistant_kill` 的 argv 不接受调用方拼命令，彻底堵命令注入。
4. **不强制**：`lock_*` 是协作协议不是文件系统强制锁——不配合的 agent 绕过它不报错（同 `reserve_scope` 现状）。要做到"硬" Enforcement 需要 hook 编辑器/git，超出本仓范围；但 `assistant_audit` 会把"无锁改动嫌疑"摆上台面（纪律面约束）。这一点与用户需求"文件在写就不能被其它agent所有"的差距要明说：**互斥由协议+清扫+审计保证，不由内核保证**。
5. 与既有并发车道的协调：新文件落在 `src/store/store_locks.mbt`、`src/engine/engine_lock.mbt`、`src/server/locks_ops.mbt`（新文件，避开 `server.mbt` 尾部并发 WIP 密集区，减少合并冲突）。

## 8. 待用户拍板

1. 阶段 3 的 `assistant_kill` 真杀进程——是否批准？（不可逆操作，按 AGENTS.md 执行权留用户/指挥官确认）
2. 默认 TTL 600s / 心跳阈值 ttl/3 是否合适？
3. `idle_suggestion` 复用 `task_triage` 排序即可，还是只看"待领取且与 blocked 文件作用域不相交"的任务？
4. 助理是否允许"先斩后奏"（kill 后补 reason），还是 reason 必须先行？（建议先行，与 BUG-33 盖章精神一致）
