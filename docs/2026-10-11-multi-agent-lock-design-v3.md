# 多 Agent 同项目文件锁 + 项目助理 · 详细设计 v3（2026-10-11）

> 相对 v2 的升级：落实用户 5 条确认（kill 只能杀执行者 / TTL 可配置 / reason 先行 / 副助理机制 / 业界调研对照）。
> 命令源：[docs/2026-10-11-multi-agent-lock-design-v2.md](2026-10-11-multi-agent-lock-design-v2.md) + 用户第 2 轮确认。
> 工作目录：`E:\workspace\AI\FIST-Mbt`。

---

## 0. 业界调研对照（"看看别人怎么做到"）

调研对象：Aider、OpenAI Swarm / Agents SDK、Continue、Cline、Anthropic 多 agent 协作、Redis Redlock、py-filelock。

### 0.1 业界怎么做多 agent 并发编辑

| 方案 | 并发编辑冲突处理 | 本质 |
|---|---|---|
| **Aider** | 单 agent 工具，无原生多 agent 锁；靠 **git commit 为回滚单位**，多 agent 串行或各自分支后 merge | 不解决同时写同一文件，靠 VCS 兜底 |
| **OpenAI Swarm / Agents SDK** | **状态无关**的 `handoff`（一个 agent 把对话交给另一个），同一时刻只有一个 agent 在干活 | 根本不允许多 agent 同时改同一项目 |
| **Continue / Cline** | 单 agent 编辑循环；多实例靠用户手动分区 | 不解决 |
| **Anthropic 多 agent 协作** | 软预订（`reserve_scope` 式）+ 冲突时提示等待或做其它事 | 协议级，非强制 |
| **Redis Redlock** | 租约 + 随机 token + 释放校验 token，跨节点互斥 | 分布式锁通用方案，但只锁"资源名"不锁"文件" |
| **py-filelock** | 单文件跨进程锁（`fcntl`/`msvcrt.locking`），阻塞获取 | 只锁单个文件，无多文件 all-or-nothing |

### 0.2 结论：本方案的定位

**业界多 agent 协作主要靠"分工 + handoff"，同目标项目的强制文件锁是空白。**
- Swarm 的 stateless handoff 印证：要让多 agent 真正并行改同一项目，必须有**共享状态层**（我们的 `file_locks` 表）+ **强制互斥**（协议级锁）。
- Redlock 的租约+token 模式 → 我们用 `agent` 身份 + 持有者校验等价，且服务端盖章（BUG-33）比客户端 token 更安全。
- py-filelock 的单文件锁 → 我们升级为**多文件 all-or-nothing**（一次 SQLite 事务），能力更强、且从根上排除多锁顺序死锁。
- Aider 的 git 回滚单位 → 我们保留：锁是"软强制"（协议级，不配合的 agent 仍可绕过），补偿面是 `assistant_audit` 从 `call_log` 交叉"无锁改动嫌疑"。

**可复用的现成能力（本仓已有，不新造轮子）**：

| 能力 | 现成位置 | 复用方式 |
|---|---|---|
| 租约+TTL 原子裁决 | [src/store/store_rsv.mbt:77](src/store/store_rsv.mbt#L77) `rsv_action` + [store_sqlite.mbt:776](src/store/store_sqlite.mbt#L776) `ON CONFLICT(scope) DO UPDATE SET ... WHERE agent=excluded.agent OR ttl_until<excluded.created_at` | `file_locks` 表完全照搬 `reservations` 的 SQL 模式，`lock_action` 仿 `rsv_action` |
| 判活（心跳+TTL 兜底+Phi 概率） | [src/ops/ops_heal.mbt:91](src/ops/ops_heal.mbt#L91) `heal_stale_tasks_from_store` + `phi_accrual`（R89）+ BUG-119 兜底时钟 | `assistant_sweep` 仿它：锁无心跳退 `acquired_at+ttl`，不首拍即死 |
| 固定 argv 执行通道 | [src/executor/cli_argv.mbt](src/executor/cli_argv.mbt) + `run_check_guard` 子树约束 | `assistant_kill` 仿 `executor_run`：argv 纯计算、不经 shell、参数整型化 |
| 工具注册范式 | [src/server/server.mbt:4334](src/server/server.mbt#L4334) `instrumented_tool` + `schema` + `async fn` | 新 12 件工具照搬此范式 |
| 引擎层转发 | [src/engine/engine_rsv.mbt](src/engine/engine_rsv.mbt) `FistEngine::rsv_*` 纯转发 | `engine_lock.mbt`/`engine_assistant.mbt` 照搬 |
| schema 初始化 | [src/store/store_sqlite.mbt:91](src/store/store_sqlite.mbt#L91) `create_schema` 的 `sqls` 数组 | 追加 3 条 `CREATE TABLE IF NOT EXISTS` |

---

## 1. 角色体系（v2 升级版：Agent 分级 + 副助理）

> 用户确认：①杀只能杀执行者，上层任务拆分者的拳长、拳节不能杀；④副助理机制需要（大型项目有用）。

### 1.1 Agent 分级（kill 白名单的依据）

| 层级 | 身份标识 | 职责 | 可否被 kill |
|---|---|---|---|
| **拳长（Planner/Lead）** | `role=planner` | 拆任务、派单、终审 | ❌ 不可杀（战略层，杀了整条链断） |
| **拳节（Sub-Lead）** | `role=sublead` | 子树拆解、局部协调 | ❌ 不可杀（战术层） |
| **执行者（Worker）** | `role=worker` | 写文件、跑命令 | ✅ 可杀（战术执行层，可重派） |

**实现**：`lock_acquire` 时 `agent` 携带 `role`（或从 `assistant_reg` / `executors` 表反查）。`assistant_kill` 硬门：目标 PID 对应的 `role` 必须是 `worker`，否则拒绝并记 `lock_violations(kind=kill_rejected_non_worker)`。

**登记方式**：执行者在 `executor_register` 时带 `role=worker`；拳长/拳节不进 `executors` 表（它们不直接写文件），或进 `assistant_reg` 时 `role=planner/sublead`。kill 白名单 = `file_locks.pid` 且 `role=worker`。

### 1.2 项目助理本体（唯一，有 kill 权）

每目标项目至多一个**主助理**，通过 `assistant_claim` 选举产生（仿 `rsv_action` take_over）。主助理统领 4 个子职能 mode：

```
项目助理（主，唯一，有 kill 权）
 ├ 锁管家 LockKeeper  — 管锁/续期/死锁检测（等待图）
 ├ 清道夫 Reaper      — 扫过期锁、心跳死→释放
 ├ 警察 Sheriff       — kill 长占 PID（硬门：仅 worker）
 └ 审计员 Auditor     — 持锁时长/逾期率/无锁改动嫌疑
```

### 1.3 副助理机制（大型项目并行）

主助理可以声明自己只干哪几个 mode（`assistant_claim(mode="sheriff,auditor")`），**其余 mode 可由副助理 claim**（`assistant_deputy_claim(mode="lock_keeper,reaper")`）。

- 副助理**无 kill 权**（kill 只在主助理的 sheriff mode）。
- 同一 mode 只能被一个助理（主或副）占据（`assistant_reg.mode` 互斥校验）。
- 主助理死亡 → 副助理可通过 `assistant_claim` 晋升为主（take_over），接管 kill 权。
- 小项目：主助理 `mode="all"` 全包，无副助理。
- 大项目：主助理（kill+审计）+ 副助理 A（锁管家）+ 副助理 B（清道夫）并行。

### 1.4 角色权限矩阵

| 动作 | 拳长 | 拳节 | 执行者 | 主助理 | 副助理 |
|---|---|---|---|---|---|
| `lock_acquire` | ❌（不直接写文件） | ❌ | ✅ | ❌（不直接写） | ❌ |
| `lock_release`（自己的） | — | — | ✅ | — | — |
| `lock_status` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `assistant_sweep` | — | — | — | ✅ | ✅（reaper mode） |
| `assistant_kill` | ❌ | ❌ | ❌ | ✅（sheriff mode，仅 worker） | ❌ |
| `assistant_audit` | — | — | — | ✅ | ✅（auditor mode） |
| `assistant_resign` | — | — | — | ✅ | ✅ |

---

## 2. 数据模型（3 张新表，随 store 初始化）

### 2.1 `file_locks` —— 文件互斥锁（仿 `reservations`，新增 `role` 字段）

```sql
CREATE TABLE IF NOT EXISTS file_locks (
  lock_id      TEXT PRIMARY KEY,              -- L-<ulid>，服务端生成
  path         TEXT NOT NULL,                 -- 相对项目根，拒绝对路径/..（run_check 同款校验）
  agent        TEXT NOT NULL DEFAULT '',      -- 持有者身份
  pid          INTEGER NOT NULL DEFAULT 0,    -- 持有者进程 PID
  role         TEXT NOT NULL DEFAULT 'worker',-- worker | sublead | planner（kill 白名单依据）
  batch_id     TEXT NOT NULL DEFAULT '',      -- 同笔多文件锁共享，all-or-nothing
  acquired_at  TEXT NOT NULL DEFAULT '',      -- 服务端盖章（BUG-33）
  ttl_until    TEXT NOT NULL DEFAULT '',      -- acquired_at + ttl_sec
  heartbeat_at TEXT NOT NULL DEFAULT '',      -- 最近一次 lock_renew
  status       TEXT NOT NULL DEFAULT 'held'   -- held | reaped | killed（治理面标记）
);
CREATE INDEX IF NOT EXISTS idx_file_locks_path ON file_locks(path);
CREATE INDEX IF NOT EXISTS idx_file_locks_agent ON file_locks(agent);
CREATE INDEX IF NOT EXISTS idx_file_locks_batch ON file_locks(batch_id);
```

### 2.2 `lock_violations` —— 规范性台账（助理的"案底"）

```sql
CREATE TABLE IF NOT EXISTS lock_violations (
  id      INTEGER PRIMARY KEY AUTOINCREMENT,
  ts      TEXT NOT NULL DEFAULT '',          -- 服务端盖章
  agent   TEXT NOT NULL DEFAULT '',
  pid     INTEGER NOT NULL DEFAULT 0,
  kind    TEXT NOT NULL DEFAULT '',          -- 闭集（见下）
  detail  TEXT NOT NULL DEFAULT ''           -- 当时锁信息 JSON
);
```

`kind` 闭集（J9 返回契约、`check_desc_enum_sync` 登记）：
- `ttl_expired_reaped` — TTL 过期被清扫
- `pid_dead_reaped` — PID 判活死亡被清扫
- `killed_by_assistant` — 被助理 kill
- `force_takeover` — 助理选举 take_over
- `no_renew_long_hold` — 持锁超 3×ttl 不释放（警告）
- `unowned_write_suspect` — 无锁改动嫌疑线索
- `kill_rejected_non_worker` — 尝试 kill 非执行者被拒

### 2.3 `assistant_reg` —— 助理登记表（主助理至多一行 active）

```sql
CREATE TABLE IF NOT EXISTS assistant_reg (
  agent         TEXT PRIMARY KEY,
  pid           INTEGER NOT NULL DEFAULT 0,
  role          TEXT NOT NULL DEFAULT 'assistant', -- assistant | planner | sublead
  mode          TEXT NOT NULL DEFAULT 'all',       -- all | lock_keeper | reaper | sheriff | auditor（逗号分隔）
  is_primary    INTEGER NOT NULL DEFAULT 0,        -- 1=主助理（有 kill 权），0=副助理
  registered_at TEXT NOT NULL DEFAULT '',
  heartbeat_at  TEXT NOT NULL DEFAULT '',
  status        TEXT NOT NULL DEFAULT 'active'     -- active | dead | resigned
);
```

---

## 3. 工具面（新组 `lock_*` + `assistant_*`，共 12 件；既有 136 件不动）

### 3.1 锁四件套

| 工具 | 参数 | 返回 | 硬门 |
|---|---|---|---|
| `lock_acquire` | project_dir, agent, pid, role?(默认worker), files[], ttl_sec?(默认600, 可配置) | `{granted, lock_id, batch_id, blocked_by?, wait_hint?, idle_suggestion?}` | files[] 路径子树校验；ttl_sec 钳 [10, 7200]；role∈{worker,sublead,planner} |
| `lock_renew` | project_dir, lock_id, agent | `{renewed, ttl_until}` | 限持有者 |
| `lock_release` | project_dir, lock_id?, batch_id?, agent | `{released: n}` | 限持有者；缺参报全量（防误删） |
| `lock_status` | project_dir, path?, agent? | `{locks:[...]}` | 纯读 |

**TTL 可配置实现**：`lock_acquire` 的 `ttl_sec` 缺省读 store 级配置（`memory/lock-config.json` 或环境变量 `FIST_LOCK_TTL_SEC`），默认 600。心跳阈值 = ttl/3（由助理 sweep 端算，不存库）。

**`idle_suggestion`**：blocked 时由 `task_triage` 纯读算一件"可做其它事"——待领取任务中挑一件其声明文件作用域与 blocked 文件**不相交**的（复用 `team_task.write_scopes`；若任务无声明则按 description 关键词粗匹配）。把"等待先做其它事"落成调用方循环。

### 3.2 助理八件套

| 工具 | 参数 | 权限 | 说明 |
|---|---|---|---|
| `assistant_claim` | project_dir, agent, pid, role?(默认assistant), mode?(默认all) | 任意 | 选举：无 active 主直选；active 主心跳新鲜→拒；active 主死→take_over；副助理 mode 不能与主冲突 |
| `assistant_deputy_claim` | project_dir, agent, pid, mode | 任意 | 副助理：只能 claim 主助理未占的 mode，`is_primary=0`，无 kill 权 |
| `assistant_status` | project_dir | 任意 | 现任主助理 + 副助理列表 + 锁全景 + 违规统计（纯读） |
| `assistant_sweep` | project_dir, phi_gate?(默认false) | 主/副助理(reaper mode) | 清扫：TTL过期→放；心跳陈旧→PID判活→死则放；活则警告 |
| `assistant_kill` | project_dir, pid, reason | **仅主助理(sheriff mode)** | kill 注册 worker PID：force=true 硬门 + reason 必填 + role=worker 校验 + 落案底 + audit；固定 argv |
| `assistant_audit` | project_dir, since? | 主/副助理(auditor mode) | 规范性报告：持锁时长分布、逾期率、违规榜、无锁改动嫌疑线索 |
| `assistant_resign` | project_dir, agent | 主/副助理 | 主动退位（不阻塞功能，锁靠 TTL+清扫） |
| `assistant_heartbeat` | project_dir, agent | 主/副助理 | 助理自身心跳（防助理自己死了占着位） |

### 3.3 `assistant_kill` 的硬门细节（落实用户确认 1+3）

**用户确认 1**：杀只能杀执行者，拳长/拳节不能杀。
**用户确认 3**：reason 必须先行（先斩后奏不允许）。

```
硬门链（任一不满足即拒绝，记 lock_violations + audit）：
  1. force == true（显式硬门，仿 github_flush_execute）
  2. reason 非空（reason 先行，不允许空 reason）
  3. 调用者 is_primary == 1 且 mode 含 sheriff（主助理警察权）
  4. 目标 pid 出现在 file_locks.pid（"注册的 PID"逐字落实）
  5. 目标 pid 对应锁的 role == 'worker'（执行者才可杀，拳长/拳节拒）
  6. 目标 pid 未被标记 killed（幂等）

通过后：
  a. UPDATE file_locks SET status='killed' WHERE pid=? AND role='worker'（先夺锁）
  b. spawn 固定 argv：
       win32: ["taskkill", "/PID", "<pid>", "/T", "/F"]
       posix: ["kill", "-9", "<pid>"]
     - pid 必须是正整数（拒绝 0/负数/非数字）
     - 不经 shell（spawn(cmd, args)，同 executor_run）
  c. 落 lock_violations(kind=killed_by_assistant, detail={reason, lock_id, agent, role})
  d. 落 audit_log + call_log
  e. native 构建返回明确拒绝（同 executor_run）
```

**argv 构造文件**：`src/executor/kill_argv.mbt`（纯计算零 IO，仿 `cli_argv.mbt` 的 `prompt_ok`/`external_executors` 模式）。

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
| kill 安全 | 固定 argv、PID 整型化、必须登记、role=worker、force 硬门、reason 先行 | 防命令注入；不可逆操作留审计 |
| 文档面 | 新工具描述闭集一次写对 | J9 返回契约、`check_desc_enum_sync` 登记 kind/status 闭集 |
| 插件态 | 改 server.mbt 后重跑 `gen_plugins.py` | cl7 `check_plugin_sync` |
| 测试 | 白盒锁 ≥14 把（见 §6） | `moon test --target js` |
| 版本 | 0.3.8 → 0.3.9 minor | 能力纯增量 |

---

## 5. 典型时序

### 5.1 两 agent 改同一文件

```
agent-A(worker): lock_acquire(files=[src/x.mbt])              → granted L-1, batch=B1
agent-B(worker): lock_acquire(files=[src/x.mbt])              → blocked_by=A, idle_suggestion=领T12
agent-B: claim T12（其 write_scopes 不含 src/x.mbt）→ 干完 → lock_acquire 重试 → granted
agent-A: lock_renew（每 ≤ttl/3 心跳）→ 改 src/x.mbt → lock_release
```

### 5.2 助理清扫崩溃 agent

```
agent-A(worker) 崩溃（PID 死、心跳停）
助理(reaper): assistant_sweep
  - L-1 的 ttl_until 过期 → 释放，记 ttl_expired_reaped
  - 或：心跳陈旧 → PID 判活（tasklist / kill -0）→ 死 → 释放，记 pid_dead_reaped
agent-B 下一轮 lock_acquire → granted
```

### 5.3 助理 kill 长占者（落实用户确认 1+3）

```
agent-A(worker) 持锁超过 3×ttl 仍不释放（心跳在但不干事）
助理(sheriff): assistant_sweep → 记 no_renew_long_hold 警告
              若 A 仍不释放 → 先警告一次（给 reason 先行的机会）
              A 仍不释放 → assistant_kill(pid=A.pid, force=true, reason="持锁超3×ttl不释放")
                硬门：force=true ✓ / reason 非空 ✓ / 主助理sheriff ✓ / pid 已登记 ✓ / role=worker ✓
                → 先夺锁（status='killed'）→ taskkill /PID A /T /F → 记 killed_by_assistant
agent-B 下一轮 lock_acquire → granted
```

### 5.4 尝试 kill 拳长（被拒）

```
agent-X(planner) 持有某锁（理论上拳长不写文件，但若误登记了）
助理: assistant_kill(pid=X.pid, force=true, reason="...")
  硬门：role=planner ≠ worker → 拒绝，记 kill_rejected_non_worker
```

### 5.5 副助理晋升主助理

```
主助理 A 心跳超时（PID 死）
副助理 B: assistant_claim(mode="all")
  - 检测主助理 A 心跳死 → take_over，is_primary=1，接管 kill 权
  - 记 lock_violations(kind=force_takeover)
B 成为新主助理，可执行 sheriff 职责
```

---

## 6. 白盒测试清单（≥14 把锁，双后端同构）

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
| lk10 | kill 未登记 PID 拒 | kill 一个不在 file_locks 的 PID → 拒绝 |
| lk11 | kill 非 worker 拒 | kill role=planner 的 PID → 拒绝，记 kill_rejected_non_worker |
| lk12 | kill reason 空拒 | `assistant_kill(reason="")` → 拒绝 |
| lk13 | kill 落案底 | kill 成功后 `lock_violations` 有 killed_by_assistant 行 |
| lk14 | idle_suggestion 不相交 | blocked 时 suggestion 的 write_scopes 不含 blocked 文件 |
| lk15 | 副助理 mode 互斥 | 主占 sheriff → 副 claim sheriff → 拒绝 |
| lk16 | 副助理无 kill 权 | 副助理调 assistant_kill → 拒绝 |

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
- 测试：lk7、lk8、lk15 + 助理选举/退位/副助理
- 验收：助理 sweep 能释放过期锁；助理死亡后新助理能 take_over；副助理 mode 互斥

### 阶段 3 · 警察权 kill（约 200 行）
- 文件：`src/executor/kill_argv.mbt`（纯计算 argv）+ `src/server/kill_exec.mbt`（spawn）
- 工具：`assistant_kill`
- 复用：`executor_run` 的固定 argv 模式、`run_check_guard` 的 spawn 封装
- 测试：lk9、lk10、lk11、lk12、lk13
- **用户已批准**：kill 真杀进程（仅 worker，拳长/拳节不可杀）

### 阶段 4 · 审计员 + idle_suggestion（约 300 行）
- 工具：`assistant_audit`
- `lock_acquire` 的 `idle_suggestion` 接 `task_triage`
- 测试：lk14 + 审计报告格式

### 阶段 5 · 生态接线（约 200 行）
- `watchdog_tick` 加 `sweep_locks=true` 分支（无人值守自动清扫，仿 `flush_bug_queue` 先例）
- `templates/lock_wait_loop.md`：client 侧等待循环模板
- `task_plan_deep` 可选标注 `write_scopes`（供 idle_suggestion 过滤）
- `executor_register` 加 `role` 参数（worker/sublead/planner）

---

## 8. 文件落点（避开并发 WIP 密集区）

| 新文件 | 职责 | 避免冲突点 |
|---|---|---|
| `src/store/store_locks.mbt` | 双后端 `locks_*` | 新文件，不改 `store.mbt`/`store_sqlite.mbt` 主体 |
| `src/store/store_assistant.mbt` | 双后端 `assistant_*` | 同上 |
| `src/engine/engine_lock.mbt` | 引擎层锁编排（仿 `engine_rsv.mbt` 纯转发） | 新文件 |
| `src/engine/engine_assistant.mbt` | 引擎层助理编排 | 同上 |
| `src/server/locks_ops.mbt` | server 锁工具 impl（仿 `server.mbt:4334` 范式） | 新文件，不改 `server.mbt` 尾部 |
| `src/server/assistant_ops.mbt` | server 助理工具 impl | 同上 |
| `src/executor/kill_argv.mbt` | kill argv 纯计算（仿 `cli_argv.mbt`） | 新文件 |

**修改既有文件**（最小侵入）：
- [src/store/store_sqlite.mbt:91](src/store/store_sqlite.mbt#L91) `create_schema`：`sqls` 数组追加 3 条 `CREATE TABLE IF NOT EXISTS`（已有 14 条，加在末尾）
- [src/store/store.mbt](src/store/store.mbt)：`MemoryStore` 加 `file_locks`/`lock_violations`/`assistant_reg` 字段（仿 `reservations`/`executors`），`clear()` 加清空
- [src/server/server.mbt](src/server/server.mbt)：加 12 个工具注册（追加在 `reserve_*` 之后，避免尾部 WIP）

---

## 9. 诚实的边界与风险

1. **互斥是协议级，非内核级**：不配合的 agent 绕过 `lock_acquire` 直接改文件不报错（同 `reserve_scope` 现状）。补偿是 `assistant_audit` 把"无锁改动嫌疑"从 `call_log` 交叉出来。要做到内核强制需 hook 编辑器/git，超出本仓范围。
2. **PID 判活局限**：PID 复用、同进程多 agent。故判活**心跳为主、PID 为辅**；kill 只针对"已登记 PID 且 role=worker"（你原话），不开放任意 PID。
3. **助理自身也可能死**：`assistant_reg.status=dead` 检测 + 下次 claim take_over；助理无心跳时**不阻塞锁功能**（锁靠 TTL+清扫拍，助理是增强不是依赖）。
4. **防滥用**：助理权大（kill），故每次 kill 强制 `force=true`+reason+role=worker+落案底+audit；argv 不接受调用方拼命令。
5. **与并发车道协调**：新文件避开 `server.mbt` 尾部 WIP 密集区；改既有文件时用 `edit` 精确替换。

---

## 10. 待你确认（v3 相对 v2 的差异点）

1. **Agent 分级 `role` 字段**：执行者(worker)/拳节(sublead)/拳长(planner)，kill 仅 worker。`executor_register` 加 `role` 参数。✅ 已按你要求设计
2. **TTL 可配置**：`lock_acquire(ttl_sec=?)` 缺省读 `FIST_LOCK_TTL_SEC` 环境变量或 `memory/lock-config.json`，默认 600。✅ 已按你要求设计
3. **reason 先行**：`assistant_kill(reason=)` 必填，空 reason 拒绝。✅ 已统一
4. **副助理机制**：`assistant_deputy_claim(mode=)`，主助理可让渡部分 mode 给副助理并行。✅ 已按你要求设计
5. **阶段 3 kill 已批准**（仅 worker），可直接落地。

**确认后我按指挥官模式拆 5 个阶段任务、派子代理实现，阶段 1 先落地。**
