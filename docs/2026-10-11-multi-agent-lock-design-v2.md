# 多 Agent 同项目文件锁 + 项目助理 · 详细设计 v2（2026-10-11）

> 命令源：[docs/2026-10-11-multi-agent-lock-design.md](2026-10-11-multi-agent-lock-design.md) 初版 + 用户补充（角色拆细、调研复用、不伤本体）。
> 调研结论：本仓已有 lease+TTL 原子裁决、判活体系、固定 argv 执行通道三件套，**全部复用，零新造轮子**。
> 约束：纯增量、零回归、双后端同构、时间戳服务端盖章（BUG-33）、路径子树校验、kill 走硬门。

---

## 0. 调研摘要（可复用的现成能力）

| 能力 | 现成位置 | 复用方式 |
|---|---|---|
| **租约+TTL 原子裁决** | `src/store/store_rsv.mbt:77` `rsv_action` + `store_sqlite.mbt:776` `ON CONFLICT(scope) DO UPDATE SET ... WHERE agent=excluded.agent OR ttl_until<excluded.created_at` | `file_locks` 表完全照搬 `reservations` 的 SQL 模式，`lock_action` 函数仿 `rsv_action` 写后回读 |
| **判活：心跳+TTL 兜底** | `src/ops/ops_heal.mbt:91` `heal_stale_tasks_from_store`（无心跳退 `updated_at`，BUG-119） | `assistant_sweep` 仿它：锁无心跳退 `acquired_at+ttl`，不首拍即死 |
| **判活：Phi 概率判活** | `src/ops/ops_heal.mbt:195` `phi_accrual` 集成（R89） | 助理 sweep 可选 `phi_gate=true`，心跳间隔历史算 φ，避免长任务被误杀 |
| **固定 argv 执行通道** | `src/executor/cli_argv.mbt` + `src/server/run_check_guard.mbt` 子树约束 | `assistant_kill` 仿 `executor_run`：argv 纯计算构造、不经 shell、参数整型化、目标 PID 必须在登记表内 |
| **审计面** | `audit_log`（进程内）+ `call_log`（跨进程，`call_log` 表） | 所有治理动作（强取/释放/kill/助理接管）双写 |
| **作用域预订软锁** | `reserve_scope/check/release`（136 工具之一） | **不动**。新文件锁是强制互斥层，旧软锁仍可用于非文件类作用域，两层并存 |

外部方案对照（不直接引入依赖，只吸收思想）：
- **Redis Redlock**：租约 + 随机 token + 释放校验 token → 我们用 `agent` 身份 + 持有者校验等价。
- **py-filelock**：跨进程文件锁，但只单文件 → 我们的 `lock_acquire(files=[...])` 是**多文件 all-or-nothing**（一次 SQL 事务），能力更强。
- **Anthropic 多 agent 协作**：软预订 + 冲突提示 → 本仓 `reserve_scope` 已实现，新层是它的加强版。

---

## 1. 角色体系（拆分过重的"项目助理"）

> 用户要求：任务过重不好，多添加几个角色。
> 设计：**项目助理本体唯一（有 kill 权），下设 4 个可独立启停的子职能 mode**。这样既保证 kill 权唯一性（不能多个角色都能杀），又避免一个角色扛所有活。

### 1.1 角色总览

```
                    ┌─────────────────────────┐
                    │   项目助理（每项目唯一）   │  ← 有 kill 权，选举制
                    │  assistant_claim 产生    │
                    └────────────┬────────────┘
                                 │ 下设 4 个 mode（可兼任/可委托）
            ┌──────────┬─────────┼─────────┬──────────┐
            ▼          ▼         ▼         ▼          ▼
        锁管家     清道夫      警察      审计员      （助理本体）
       LockKeeper  Reaper    Sheriff   Auditor
       管锁/续期   扫死锁    kill PID  规范性报告
```

| 角色 | 职责 | 权限 | 是否需要唯一 |
|---|---|---|---|
| **执行者（Worker）** | 写文件前 `lock_acquire`、定期 `lock_renew`、完成 `lock_release` | 只能操作自己的锁 | 否（多个） |
| **项目助理（Assistant）** | 选举产生，持有 kill 权，统领 4 个子职能 | kill 注册 PID、强取锁、罢免 | **是**（每项目唯一） |
| └ 锁管家（LockKeeper） | 维护 `file_locks`、续期检查、死锁检测（等待图） | 读锁表、记违规 | 助理兼任/委托 |
| └ 清道夫（Reaper） | 扫过期锁、心跳陈旧+PID 死→释放 | 释放过期锁 | 助理兼任/委托 |
| └ 警察（Sheriff） | 长占不释放→kill PID | kill（硬门 force+reason） | 助理兼任/委托 |
| └ 审计员（Auditor） | 持锁时长分布、逾期率、无锁改动嫌疑线索 | 纯读 `call_log` 交叉 | 助理兼任/委托 |
| **协调者（Coordinator）** | 已有 `watchdog_tick`/`selfdrive_dispatch`，blocked 时给 `idle_suggestion` | 调度（已有） | 否 |
| **规划者（Planner）** | 已有 `plan`/`task_plan_deep`，拆任务时标注文件作用域 | 拆任务（已有） | 否 |

### 1.2 为什么 kill 权只在助理本体

kill 是不可逆操作（按 AGENTS.md 执行权留用户/指挥官）。如果 4 个子职能各自能 kill，等于有 4 个警察，权责不清、审计困难。故 **kill 工具只有助理本体能调**（身份校验），子职能 mode 只是行为开关，不分裂 kill 权。

### 1.3 子职能 mode 的启停

`assistant_claim(mode="all" | "lock_keeper" | "reaper" | "sheriff" | "auditor")`——助理可以声明自己只干哪几件事，其余 mode 可以由**其它 agent 以"副助理"身份 claim**（`assistant_deputy_claim`，无 kill 权）。这样小项目一个助理全包，大项目可以拆成"主助理（kill）+ 副助理（清扫/审计）"并行。

---

## 2. 数据模型（3 张新表，随 store 初始化）

存放位置：与 `reservations`/`tasks` 同库（每目标项目一个 `fist-mbt.db`，锁天然按项目隔离）。

### 2.1 `file_locks` —— 文件互斥锁（仿 `reservations`）

```sql
CREATE TABLE IF NOT EXISTS file_locks (
  lock_id     TEXT PRIMARY KEY,              -- L-<ulid>，服务端生成
  path        TEXT NOT NULL,                 -- 相对项目根，拒绝对路径/..（run_check 同款校验）
  agent       TEXT NOT NULL DEFAULT '',      -- 持有者身份
  pid         INTEGER NOT NULL DEFAULT 0,    -- 持有者进程 PID
  batch_id    TEXT NOT NULL DEFAULT '',      -- 同笔多文件锁共享，all-or-nothing
  acquired_at TEXT NOT NULL DEFAULT '',      -- 服务端盖章（BUG-33）
  ttl_until   TEXT NOT NULL DEFAULT '',      -- acquired_at + ttl_sec
  heartbeat_at TEXT NOT NULL DEFAULT '',     -- 最近一次 lock_renew
  status      TEXT NOT NULL DEFAULT 'held'   -- held | reaped | killed（治理面标记）
);
CREATE INDEX IF NOT EXISTS idx_file_locks_path ON file_locks(path);
CREATE INDEX IF NOT EXISTS idx_file_locks_agent ON file_locks(agent);
CREATE INDEX IF NOT EXISTS idx_file_locks_batch ON file_locks(batch_id);
```

**多文件 all-or-nothing 实现**：`lock_acquire(files=[a,b,c])` 在一个 SQLite 事务里：
1. `BEGIN IMMEDIATE`（写锁，防止并发）
2. 对每个 path 查 `file_locks` 中 `status='held'` 的行
3. 若**全部**空闲（或全部归本 agent）→ 插入所有行，`COMMIT`
4. 若**任一**被占 → `ROLLBACK`，回 `blocked_by`
5. 不存在部分持锁状态 → **从根上排除多锁顺序死锁**

### 2.2 `lock_violations` —— 规范性台账（助理的"案底"）

```sql
CREATE TABLE IF NOT EXISTS lock_violations (
  id      INTEGER PRIMARY KEY AUTOINCREMENT,
  ts      TEXT NOT NULL DEFAULT '',          -- 服务端盖章
  agent   TEXT NOT NULL DEFAULT '',
  pid     INTEGER NOT NULL DEFAULT 0,
  kind    TEXT NOT NULL DEFAULT '',          -- 闭集：ttl_expired_reaped | pid_dead_reaped | killed_by_assistant | force_takeover | no_renew_long_hold | unowned_write_suspect
  detail  TEXT NOT NULL DEFAULT ''           -- 当时锁信息 JSON
);
```

### 2.3 `assistant_reg` —— 助理登记表（每项目至多一行有效）

```sql
CREATE TABLE IF NOT EXISTS assistant_reg (
  agent        TEXT PRIMARY KEY,
  pid          INTEGER NOT NULL DEFAULT 0,
  mode         TEXT NOT NULL DEFAULT 'all',  -- all | lock_keeper | reaper | sheriff | auditor（逗号分隔多值）
  registered_at TEXT NOT NULL DEFAULT '',
  heartbeat_at TEXT NOT NULL DEFAULT '',
  status       TEXT NOT NULL DEFAULT 'active' -- active | dead | deputy
);
```

---

## 3. 工具面（新组 `lock_*` + `assistant_*`，共 12 件；既有 136 件不动）

### 3.1 锁四件套

| 工具 | 参数 | 返回 | 硬门 |
|---|---|---|---|
| `lock_acquire` | project_dir, agent, pid, files[], ttl_sec?(默认600) | `{granted, lock_id, batch_id, blocked_by?, wait_hint?, idle_suggestion?}` | files[] 路径子树校验；ttl_sec 钳 [10, 7200] |
| `lock_renew` | project_dir, lock_id, agent | `{renewed, ttl_until}` | 限持有者 |
| `lock_release` | project_dir, lock_id?, batch_id?, agent | `{released: n}` | 限持有者；缺参报全量（防误删） |
| `lock_status` | project_dir, path?, agent? | `{locks:[...]}` | 纯读 |

**`idle_suggestion`**：blocked 时由 `task_triage` 纯读算一件"可做其它事"——待领取任务中挑一件其声明文件作用域与 blocked 文件**不相交**的（`team_task` 的 `write_scopes` 可复用；若任务无声明则按 description 关键词粗匹配）。把"等待先做其它事"落成调用方循环。

### 3.2 助理八件套

| 工具 | 参数 | 权限 | 说明 |
|---|---|---|---|
| `assistant_claim` | project_dir, agent, pid, mode?(默认all) | 任意 | 选举：无 active 直选；active 心跳新鲜→拒；active 死→take_over |
| `assistant_deputy_claim` | project_dir, agent, pid, mode | 任意 | 副助理：只能 claim 主助理未占的 mode，无 kill 权 |
| `assistant_status` | project_dir | 任意 | 现任助理 + 锁全景 + 违规统计（纯读） |
| `assistant_sweep` | project_dir, phi_gate?(默认false) | 助理/副助理(reaper mode) | 清扫：TTL过期→放；心跳陈旧→PID判活→死则放；活则警告 |
| `assistant_kill` | project_dir, pid, reason | **仅主助理(sheriff mode)** | kill 注册 PID：force=true 硬门 + reason 必填 + 落案底 + audit；固定 argv |
| `assistant_audit` | project_dir, since? | 助理/副助理(auditor mode) | 规范性报告：持锁时长分布、逾期率、违规榜、无锁改动嫌疑线索 |
| `assistant_resign` | project_dir, agent | 助理/副助理 | 主动退位（不阻塞功能，锁靠 TTL+清扫） |
| `assistant_heartbeat` | project_dir, agent | 助理/副助理 | 助理自身心跳（防助理自己死了占着位） |

### 3.3 `assistant_kill` 的硬门细节（仿 `executor_run`）

```
argv 构造（src/executor/kill_argv.mbt，纯计算零 IO）：
  win32: ["taskkill", "/PID", "<pid>", "/T", "/F"]
  posix: ["kill", "-9", "<pid>"]
  - pid 必须是正整数（拒绝 0/负数/非数字）
  - pid 必须出现在 file_locks.pid 或 assistant_reg.pid（"注册的 PID"逐字落实）
  - 不经 shell（spawn(cmd, args)，同 executor_run）
  - 先夺其全部锁（UPDATE file_locks SET status='killed' WHERE pid=?）再 spawn kill
  - 落 lock_violations(kind=killed_by_assistant, detail=...)
  - 落 audit_log + call_log
  - native 构建返回明确拒绝（同 executor_run）
```

---

## 4. 兼容性矩阵（零破坏证据面）

| 面 | 措施 | 守卫 |
|---|---|---|
| 既有 136 工具 | 一字不改；新 12 件纯追加 | `check_tools_sync` 计数同步 |
| `reservations`/`rsv_*` | 不动；文件锁独立表 | 旧行为不变 |
| 新表 × BUG-28 | 3 张表都有写入点（`lock_acquire`/`assistant_sweep`/`assistant_kill`） | `check_store_tables_wired` 双向满足 |
| 双后端同构 | 内存后端同步实现 `locks_*`/`assistant_*`（仿 `store_rsv.mbt`） | 防"单测绿 SQLite 红"老坑 BUG-79/85 |
| 时间戳 | 全部服务端盖章（`acquired_at`/`ttl_until`/`heartbeat_at`/`ts`） | BUG-33 政策；无 now 注入面 |
| 路径安全 | `files[]` 走 `run_check` 同款相对路径+子树校验 | 拒 `..`/盘符/绝对路径 |
| kill 安全 | 固定 argv、PID 整型化、必须登记、force 硬门 | 防命令注入；不可逆操作留审计 |
| 文档面 | 新工具描述闭集一次写对 | J9 返回契约、`check_desc_enum_sync` 登记 kind/status 闭集 |
| 插件态 | 改 server.mbt 后重跑 `gen_plugins.py` | cl7 `check_plugin_sync` |
| 测试 | 白盒锁 ≥10 把（见 §6） | `moon test --target js` |
| 版本 | 0.3.8 → 0.3.9 minor | 能力纯增量 |

---

## 5. 典型时序

### 5.1 两 agent 改同一文件

```
agent-A: lock_acquire(files=[src/x.mbt])              → granted L-1, batch=B1
agent-B: lock_acquire(files=[src/x.mbt])              → blocked_by=A, idle_suggestion=领T12
agent-B: claim T12（其 write_scopes 不含 src/x.mbt）→ 干完 → lock_acquire 重试 → granted
agent-A: lock_renew（每 ≤ttl/3 心跳）→ 改 src/x.mbt → lock_release
```

### 5.2 助理清扫崩溃 agent

```
agent-A 崩溃（PID 死、心跳停）
助理: assistant_sweep
  - L-1 的 ttl_until 过期 → 释放，记 ttl_expired_reaped
  - 或：心跳陈旧 → PID 判活（tasklist / kill -0）→ 死 → 释放，记 pid_dead_reaped
agent-B 下一轮 lock_acquire → granted
```

### 5.3 助理 kill 长占者

```
agent-A 持锁超过 3×ttl 仍不释放（心跳在但不干事）
助理: assistant_sweep → 记 no_renew_long_hold 警告
      若 A 仍不释放 → assistant_kill(pid=A.pid, force=true, reason="长占不释放")
        → 先夺锁（status='killed'）→ taskkill /PID A /T /F → 记 killed_by_assistant
agent-B 下一轮 lock_acquire → granted
```

---

## 6. 白盒测试清单（≥10 把锁，双后端同构）

| # | 测试 | 断言 |
|---|---|---|
| lk1 | 单文件锁授予 | `lock_acquire` → granted=true |
| lk2 | 同文件二次锁拒绝 | A 持锁后 B `lock_acquire` → granted=false, blocked_by=A |
| lk3 | 多文件 all-or-nothing | a 空闲 b 被占 → 整笔拒绝，a 不被占 |
| lk4 | 多文件全授予 | a/b 全空闲 → 都授予，同 batch_id |
| lk5 | 持有者 release | A release → 锁消失；B 可拿 |
| lk6 | 非持有者 release 拒 | B release A 的锁 → released=0 |
| lk7 | TTL 过期清扫 | 锁 ttl_until 过期 → sweep 释放，记 ttl_expired_reaped |
| lk8 | 助理选举 take_over | 旧助理心跳死 → 新助理 claim 成功，记 force_takeover |
| lk9 | kill 硬门 force=false 拒 | `assistant_kill(force=false)` → 拒绝 |
| lk10 | kill 未登记 PID 拒 | kill 一个不在 file_locks/assistant_reg 的 PID → 拒绝 |
| lk11 | kill 落案底 | kill 成功后 `lock_violations` 有 killed_by_assistant 行 |
| lk12 | idle_suggestion 不相交 | blocked 时 suggestion 的 write_scopes 不含 blocked 文件 |

---

## 7. 分期落地（每期独立可验、可回滚）

### 阶段 1 · 锁核心（约 400 行）
- 文件：`src/store/store_locks.mbt`（双后端 `locks_*`）+ `src/engine/engine_lock.mbt`（引擎层）+ `src/server/locks_ops.mbt`（server 工具）
- 工具：`lock_acquire`/`lock_renew`/`lock_release`/`lock_status`
- 表：`file_locks`
- 测试：lk1~lk6
- 验收：双后端测试全绿；`lock_acquire` 多文件 all-or-nothing 实测

### 阶段 2 · 助理选举 + 清扫（约 500 行）
- 文件：`src/store/store_assistant.mbt` + `src/engine/engine_assistant.mbt` + `src/server/assistant_ops.mbt`
- 工具：`assistant_claim`/`assistant_deputy_claim`/`assistant_status`/`assistant_sweep`/`assistant_resign`/`assistant_heartbeat`
- 表：`assistant_reg`、`lock_violations`
- 复用：`heal_stale_tasks_from_store` 的判活逻辑、`phi_accrual`
- 测试：lk7、lk8 + 助理选举/退位/副助理
- 验收：助理 sweep 能释放过期锁；助理死亡后新助理能 take_over

### 阶段 3 · 警察权 kill（约 200 行）
- 文件：`src/executor/kill_argv.mbt`（纯计算 argv）+ `src/server/kill_exec.mbt`（spawn）
- 工具：`assistant_kill`
- 复用：`executor_run` 的固定 argv 模式、`run_check_guard` 的 spawn 封装
- 测试：lk9、lk10、lk11
- **用户确认点**：kill 真杀进程需你批准（不可逆）

### 阶段 4 · 审计员 + idle_suggestion（约 300 行）
- 工具：`assistant_audit`
- `lock_acquire` 的 `idle_suggestion` 接 `task_triage`
- 测试：lk12 + 审计报告格式

### 阶段 5 · 生态接线（约 200 行）
- `watchdog_tick` 加 `sweep_locks=true` 分支（无人值守自动清扫，仿 `flush_bug_queue` 先例）
- `templates/lock_wait_loop.md`：client 侧等待循环模板
- `task_plan_deep` 可选标注 `write_scopes`（供 idle_suggestion 过滤）

---

## 8. 文件落点（避开并发 WIP 密集区）

| 新文件 | 职责 | 避免冲突点 |
|---|---|---|
| `src/store/store_locks.mbt` | 双后端 `locks_*` | 新文件，不改 `store.mbt`/`store_sqlite.mbt` 主体（只在 init 加 CREATE TABLE） |
| `src/store/store_assistant.mbt` | 双后端 `assistant_*` | 同上 |
| `src/engine/engine_lock.mbt` | 引擎层锁编排 | 新文件 |
| `src/engine/engine_assistant.mbt` | 引擎层助理编排 | 新文件 |
| `src/server/locks_ops.mbt` | server 锁工具 impl | 新文件，不改 `server.mbt` 尾部（只加注册） |
| `src/server/assistant_ops.mbt` | server 助理工具 impl | 同上 |
| `src/executor/kill_argv.mbt` | kill argv 纯计算 | 新文件，仿 `cli_argv.mbt` |

**修改既有文件**（最小侵入）：
- `src/store/store_sqlite.mbt`：init 加 3 条 `CREATE TABLE IF NOT EXISTS`（已有 16 条，加在末尾）
- `src/store/store.mbt`：`MemoryStore` 加 `file_locks`/`lock_violations`/`assistant_reg` 字段（仿 `reservations`/`executors`）
- `src/server/server.mbt`：加 12 个工具注册（已有 136 个，追加在末尾）

---

## 9. 诚实的边界与风险

1. **互斥是协议级，非内核级**：不配合的 agent 绕过 `lock_acquire` 直接改文件不报错（同 `reserve_scope` 现状）。补偿是 `assistant_audit` 把"无锁改动嫌疑"从 `call_log` 交叉出来。要做到内核强制需 hook 编辑器/git，超出本仓范围。
2. **PID 判活局限**：PID 复用、同进程多 agent。故判活**心跳为主、PID 为辅**；kill 只针对"已登记 PID"（你原话），不开放任意 PID。
3. **助理自身也可能死**：`assistant_reg.status=dead` 检测 + 下次 claim take_over；助理无心跳时**不阻塞锁功能**（锁靠 TTL+清扫拍，助理是增强不是依赖）。
4. **防滥用**：助理权大（kill），故每次 kill 强制 `force=true`+reason+落案底+audit；argv 不接受调用方拼命令。
5. **与并发车道协调**：新文件避开 `server.mbt` 尾部 WIP 密集区；改既有文件时用 `edit` 精确替换、不用 `git add -A`。

---

## 10. 待你拍板

1. **阶段 3 的 `assistant_kill` 真杀进程是否批准？**（不可逆，按规矩执行权留你）
2. 默认 TTL 600s、心跳阈值 ttl/3，合适吗？
3. 助理 kill 的 reason 必须先行（先斩后奏不允许），同意吗？
4. 子职能 mode 的副助理机制（主助理+副助理并行）是否需要？还是简化为"助理只能一个，全包"？
5. 确认后我按指挥官模式拆 5 个阶段任务、派子代理实现，阶段 1 先落地。
