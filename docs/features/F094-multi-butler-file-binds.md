# F094: 多管家协作 · 同项目文件级并行协调层（未来扩展）

> Status: spec（未来扩展，未排期）｜ 提案人：Loomy ｜ 日期：2026-09-29
> 前置依赖：**BUG-119（心跳跨进程可见性）修复**——见 docs/improvement-plan-20260929.md §P0′ 第 1/2 条（该修复是多进程并行的硬前置）

---

## 一、动机

当前 FIST-Mbt 是「单拳长」模式：一个 agent 认领根任务 → 拆解 → 顺序执行全部叶。任务池虽可多任务并存，但**同一项目文件夹内的并行开发**缺三块能力：

1. **文件级冲突协调**——两个 agent 同时改同一文件 = last-write-wins 丢失；
2. **构建/测试互斥**——`moon test` / `cargo build` 并发互踩（构建缓存、端口、_build 目录）；
3. **多管家协作协议**——多个 Loomy/atomcode 管家各自认领根任务、各自拆解、共享同一项目与任务库，互不越界。

目标形态：「多个管家 + 各自拳长」并行开发同一个项目——任务池分派（已有）+ **文件绑定协调层**（本 Feature）+ 构建互斥（本 Feature）+ worktree 终态（本 Feature 末期）。

---

## 二、现有地基（不重复造轮子）

| 已有 | 与本 Feature 的关系 |
|---|---|
| `reserve_scope / reserve_check / reserve_release` 三件套 | **作用域软锁雏形**——本 Feature 把粒度从字符串 scope 细化为文件路径/目录，语义复用 |
| `conflicts_check`（认领前冲突检测） | 任务级冲突检测模式——扩展为文件级 |
| `task_plan_deep` 的 spec/laws | 拆解时声明 touches 的挂载点（laws 里带文件路径） |
| namespace 多租户 | 协作的「隔离档」：不想协调的 agent 用不同 ns（现状），想协作的同 ns（本 Feature） |
| SQLite + WAL（待开启） | 绑定关系的存储（file_binds 表） |
| watchdog/heal/heartbeat | TTL 防死锁的看护通道（注意与 BUG-119 修复联动，见 Risk） |

---

## 三、Phase 1 · 文件绑定 MVP（1~2 个版本位）

### 3.1 新表

```sql
CREATE TABLE file_binds (
  id INTEGER PRIMARY KEY,
  task_id TEXT NOT NULL,      -- 绑定到哪个任务（叶/根均可）
  agent TEXT NOT NULL,        -- 绑定者（执行器/管家身份）
  path TEXT NOT NULL,         -- 相对项目根；kind=dir 时为目录前缀
  kind TEXT NOT NULL,         -- file | dir
  scope TEXT NOT NULL,        -- edit | build（edit=内容写入；build=构建/测试互斥）
  bound_at TEXT NOT NULL,     -- 服务端盖章
  ttl_secs INTEGER,           -- 超时自动失效（防 agent 中断死锁）
  released_at TEXT            -- 非空 = 已释放
);
```

### 3.2 新工具三件

| 工具 | 参数 | 语义 |
|---|---|---|
| `file_bind` | task_id(必), agent(必), paths[](必, 相对项目根), kind(file/dir), scope(edit/build), ttl_secs(可选) | 绑定；**冲突时返回持锁者信息**（task_id/agent/bound_at），调用方决定等待/换单/协商 |
| `file_release` | task_id(必) | 释放该任务全部绑定（verify/archive 时服务端自动调用；reject/reopen 保留绑定） |
| `file_status` | path 或 task_id（二选一） | 查询占用：谁绑着、何时绑、ttl 剩余 |

### 3.3 生命周期挂钩（服务端自动，不靠 agent 自觉）

- **claim**：不强制绑定（绑不绑由 agent 按任务声明）；
- **execute**：要求该任务已有 file_bind（可选开关，默认 advisory）；
- **verify / archive**：自动 release 该任务全部 edit 绑定；
- **reject / reopen**：绑定保留（打回重做还要用）；
- **TTL 到期**：watchdog_tick 顺带清理过期绑定（复用看护通道，不新增 tick）。

---

## 四、Phase 2 · 构建互斥（0.5 个版本位）

- 新 scope：`build`——全局互斥（同一项目同时只允许一个构建/测试在跑）；
- 工具扩展：`file_bind(scope=build, ttl=构建超时)` 或独立 `build_acquire/build_release`；
- 挂钩：`run_check` 等构建类工具执行前自动 acquire（可选开关，默认 advisory——单 agent 场景零影响，多 agent 场景开 `enforce=true`）。

---

## 五、Phase 3 · git worktree 集成（1~2 个版本位，终态）

- 每执行器一个 worktree（`git worktree add`），文件锁仅在「合并前」约束；
- 分派协议升级：dispatch 时按执行器分配 worktree 路径，执行器在各自 worktree 干活；
- 合并收口：管家按完成顺序依次合并（fast-forward 优先），合并冲突由管家 reject 协调；
- 依赖：执行器会话具备基础 git 能力（worktree add/remove、分支操作）。

---

## 六、Phase 4 · 多管家协作协议（旗舰演示）

- 多个管家（Loomy/atomcode 会话）各自 publish 根任务（同 ns）→ 各自拆解 → 各自拳长执行；
- 管家间约定：**只通过任务库协调，不直接互改对方任务**（跨管家协商走 reject/reopen 消息）；
- 看板升级：board_ascii 按管家分组显示在途/完成；
- 旗舰演示：3 管家 × 各 3 任务 × 同一项目，全程无人干预，产出协作时间线与文件锁命中率报告——终审后/下一届参赛的核心 demo。

---

## 七、验收标准（Phase 1）

- [ ] file_bind 冲突时返回持锁者信息（task_id/agent/bound_at），不静默；
- [ ] TTL 到期自动失效（watchdog_tick 顺带清理）；
- [ ] verify/archive 自动 release；reject/reopen 保留；
- [ ] 单 agent 场景零回归（不开绑定时不改变任何现有行为）；
- [ ] 并发压测：两进程同时 bind 同一文件，恰好一成一拒（SQLite 事务保证）；
- [ ] 文档：pitfalls 增补「文件锁」节。

---

## 八、Risk 与前置

| 风险 | 缓解 |
|---|---|
| **BUG-119 未修前上并行 = 心跳误判放大**（heal 会回滚其他 agent 的在途任务） | **硬前置：BUG-119 修复**（improvement-plan §P0′ 已排） |
| SQLite 多进程写竞争 | WAL 模式 + busy_timeout（开并行前设置并压测） |
| 现有读写一致性 bug 放大（list ns 过滤/publish 幂等/pause 回滚） | 修复完成后才进入 Phase 3（多管家） |
| 文件锁粒度误用（dir 锁过大） | 文档约定 + file_status 可视化（谁占着哪些） |
| 粒度保守导致并行度不足（同文件不同函数） | MVP 接受；Phase 3 worktree 缓解 |

---

## 九、与 BUG-119 的关系（重要）

BUG-119（心跳跨进程不可见 → heal 误回滚他人任务）是**多 agent 并行的第一杀手**——它的修复（improvement-plan §P0′：成对常驻判据 + 四臂测试）是本 Feature 的**硬前置**。顺序：**BUG-119 修复 → Phase 1 → Phase 2 → Phase 3 → Phase 4**。
