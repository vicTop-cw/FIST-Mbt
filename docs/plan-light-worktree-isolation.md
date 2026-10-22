---
AIGC:
    Label: "1"
    ContentProducer: 001191440300708461136T1XGW3
    ProduceID: 9f2a11add43fbf12a546606fb2b962ab_01152c80c83811f1944f525400248c00
    ReservedCode1: UXx4zDSczF8hMgT3Y5dGGyA8/ctMojxCkljkpAOFmxyb/fhgUAdpXWxVaPB/WaCY82NmvPfHyAnRipTZhd0VhZPZKqflt4S6KpEaLj+TJndryBf4be74CYGBoGMbNe26VvVVPPHk0H4I0NZTEWO7VS3RWdiLZmxkP7QjPQPvt8NEVgWXBLuei4FyQPg=
    ContentPropagator: 001191440300708461136T1XGW3
    PropagateID: 9f2a11add43fbf12a546606fb2b962ab_01152c80c83811f1944f525400248c00
    ReservedCode2: UXx4zDSczF8hMgT3Y5dGGyA8/ctMojxCkljkpAOFmxyb/fhgUAdpXWxVaPB/WaCY82NmvPfHyAnRipTZhd0VhZPZKqflt4S6KpEaLj+TJndryBf4be74CYGBoGMbNe26VvVVPPHk0H4I0NZTEWO7VS3RWdiLZmxkP7QjPQPvt8NEVgWXBLuei4FyQPg=
---



# 三套机制整合计划：light worktree × worktree × 文件锁（多租户隔离闭环）

> 分支：`plan/light-worktree-isolation`（本 worktree 承载计划编写，后续实现也在此分支推进）
> 日期：2026-10-15
> 目标：把「文件锁（已落地）」「git worktree（F094 Phase 3 未排期）」「light worktree（新方案 zip 引入）」整合为
> 一套面向多租户隔离的执行沙箱体系，并闭环 BUG-157（跨进程单主击穿）。
> **本文件仅为实施计划，不含任何实现代码。**

---

## 1. 背景与目标

### 1.1 多租户隔离的欠账（现状）

| 面 | 现状 | 状态 |
|---|---|---|
| namespace 层 | `namespace` 多租户隔离 | ✅ BUG-23 已修（10-02） |
| 作用域预订 | `reserve_scope` / `reserve_check` / `reserve_release` | ✅ 已落地（store_rsv） |
| 分布式文件锁 | `lock_acquire` / `lock_renew` / `lock_release` / `lock_status` | ✅ 已落地（store_rsv），BUG-154 已修（拒绝型互斥） |
| 逻辑项互斥 | `src/claimguard/`（claim_all / blind_spot_holds / may_proceed） | 🟡 库已落地，未接入 MCP 生命周期 |
| 助理选举 | `assistant_claim` 等 | 🔴 **BUG-157 OPEN**：跨进程并发 claim 全当选，单主不变量击穿 |
| 文件绑定协调 | F094 `file_binds` / `file_bind` 三工具 | ⏸ 未排期（spec 态） |
| worktree 集成 | F094 Phase 3 | ⏸ 未排期（spec 态） |
| light worktree | zip 方案文档（light-worktree.md / light-worktree-drift.md） | 📄 仅文档，未落仓 |

### 1.2 为什么三套都要弄

- **文件锁**解决「同一物理作用域的并发写互斥」——协议级硬互斥的底座，已落地但缺 worktree 维度；
- **worktree** 解决「多个执行器在同一项目内物理并存」——空间隔离，F094 已设计未实现；
- **light worktree** 解决「worktree 的按需稀疏化 + 分钟级生命周期」——让 worktree 不再全量铺盘、不再长期存活，是
  worktree 在 agent 任务粒度上的正确打开方式。

三者不是替代关系，而是**互斥层 / 空间层 / 生命周期层**的互补：light worktree 是「空间层的轻量化实例」，
文件锁是「贯穿所有 worktree 的互斥层」，合并收口是「终态门禁」。

### 1.3 本计划的最终目标形态

```
多租户隔离闭环（单个目标项目内）
├── 命名空间隔离（已有）            → 谁和谁同一项目
├── 逻辑项互斥（claimguard 接入）   → 同一 BACKLOG 项只被一人认领
├── 文件锁（已有 + worktree 维度）  → 同一物理路径只被一人写入
├── light worktree（新）            → 每任务一个稀疏沙箱，分钟级存活
├── worktree 合并收口（新）         → PR 级门禁：diff-scope / drift-check / merge-predict
└── 助理选举单主（修 BUG-157）      → 跨进程只许一个主助理
```

---

## 2. 现状基线（复用清单，不重复造轮子）

### 2.1 可直接复用的已落地能力

| 能力 | 位置 | 复用方式 |
|---|---|---|
| 拒绝型互斥原语 | `store_sqlite.mbt:1238` `locks_try_acquire`（INSERT ... ON CONFLICT ... WHERE 单语句裁决） | 修 BUG-157 照抄此原语到 `assistant_claim` |
| 服务端盖章 | `rsv_action` + BUG-33 政策 | 所有新表时间戳照此 |
| 判活 + TTL 兜底 | `heal_stale_tasks_from_store` + `phi_accrual`（BUG-119 修复产物） | light-wt GC、lock sweep 复用 |
| 固定 argv 执行 | `cli_argv.mbt` + `run_check_guard` | 沙箱 spawn 一律固定 argv |
| 工具注册范式 | `server.mbt:4334` `instrumented_tool` | 新工具照搬 |
| 引擎层转发 | `engine_rsv.mbt` 纯转发范式 | `engine_worktree.mbt` 照搬 |
| schema 初始化 | `store_sqlite.mbt:91` `create_schema.sqls` 数组 | 新表追加 |
| 逻辑项互斥 | `src/claimguard/`（decide_claim 复用 rsv_action 同序） | 接入 claim/publish 生命周期 |

### 2.2 必须修的前置缺陷

- **BUG-157（OPEN，high）**：`assistant_claim` 跨进程并发全当选。根因：先读后写，无 `ON CONFLICT ... WHERE` 原子裁决。
  修法照 BUG-154：给 `assistant_reg` 增加 `ON CONFLICT(agent) DO UPDATE ... WHERE` 单语句裁决 + 写后回读，
  并补 `scripts/blackbox/e2e_assistant_xproc.py`（N 进程同库同时 claim，断言恰好 1 elected 且赛后 active primary 恰好 1）。

---

## 3. 三套机制的职责划分与协作时序

### 3.1 职责划分

| 机制 | 层级 | 职责 | 生命周期 |
|---|---|---|---|
| 文件锁（lock_* + reserve_scope） | 互斥层 | 同一物理路径/scope 的并发写互斥、TTL 防死锁、违例留痕 | 锁粒度：分钟~小时（TTL 默认 600s） |
| worktree | 空间层 | 执行器独立工作目录，共享 .git 对象库 | 任务粒度（小时~天） |
| light worktree | 空间层（轻量化） | sparse cone 按需铺盘、短命分支、自动回收 | 分钟级（建议 ≤2h） |

### 3.2 协作时序（单任务全景）

```
1. claimguard 接入后：agent 认领任务前 claim BACKLOG 项（逻辑互斥）
2. dispatcher 读取任务声明的 pkg/文件作用域 → 计算 sparse cone
3. 调用 light-wt 创建：git worktree add --sparse -b <task-branch> main
   + sparse-checkout set <cone...>
4. 执行器在沙箱内干活：文件写入前 lock_acquire（文件锁互斥）→ moon check/test
5. 交付：git add/commit → push 分支
6. 门禁：diff-scope（越界拒）→ drift-check（偏离阈值拒）→ merge-predict（离线冲突预检）
7. 收口：PR / merge queue → 合入 main → light-wt-teardown（焚沙箱）
8. 全流程：light-wt-collector 每 5 分钟兜底回收（fresh/stale/blocked/abandoned/merged 状态机）
```

### 3.3 文件锁 × worktree 的映射关系

- **锁的粒度仍是「相对项目根的物理路径」**，不因 worktree 改变；同一项目的 N 个 worktree 共享同一个
  `file_locks` 表（存根库），因此跨 worktree 的写互斥天然生效。
- 需要新增的只有：`lock_acquire` 的调用方上下文带 `worktree_id`（便于审计谁在哪个沙箱里写的），
  **锁语义本身零改动**——这是整合的最小侵入点。
- **文件头注释约定（ownership 标注，防先后写覆盖的廉价提示层，B 档）**：agent 修改文件时在**文件顶部块注释**
  记录 `last-modified / agent / task_id / scope`（例：`// [last-modified] 2026-10-15T10:30:00Z by T12(agent-03) task_id=T12 scope=src/x.mbt`）。
  只加文件头，禁止散落行内（避免污染 diff-scope 改动面）；注释是事后痕迹，不替代锁的事前互斥，
  与 `lock_*` / `assistant_audit` 的「无锁改动嫌疑」交叉互为佐证。格式约定入 AGENTS.md。

---

## 4. 分阶段实施计划

> 每阶段独立可验、可回滚。全部在 `plan/light-worktree-isolation` 分支（本 worktree）推进。
> 顺序依赖：P0（基线修复）→ P1（light worktree 工具链）→ P2（worktree 生命周期管理）→
> P3（文件锁 × worktree 映射）→ P4（合并收口门禁）→ P5（回收/监控/生态接线）。

### 阶段 P0 · 修 BUG-157 + claimguard 接入（约 300 行）

- 修 `assistant_claim`：`assistant_reg` 加原子裁决（照 `locks_try_acquire` 单语句模式）＋写后回读；
- 补 `scripts/blackbox/e2e_assistant_xproc.py`（跨进程并发 claim 黑盒判据，同 BUG-154 的 6 格硬门风格）；
- 决策：把 `src/claimguard/` 的 `claim_item` 挂到 `claim`/`publish` 流程前（逻辑项预订运行时拦截）；
- 验收：
  - [ ] `e2e_assistant_xproc.py` 全绿（N 进程同库同时 claim → 恰好 1 elected）；
  - [ ] 白盒：两进程并发 `assistant_claim` 恰好一成一拒；
  - [ ] `moon test --target js` 全量零回归。

### 阶段 P1 · light worktree 工具链落仓（约 400 行，脚本为主）

- 将 zip 内 `light-worktree.md` / `light-worktree-drift.md` 收入 `docs/`（含附录 A/B/C 目录与环境变量约定）；
- 新建 `bin/`：`light-wt`、`light-wt-teardown`、`light-wt-status`、`light-wt-drift-check`、
  `light-wt-age-check`、`light-wt-merge-predict`、`diff-scope`、`light-wt-integrate`、`light-wt-collector`；
  （Windows 优先 PowerShell 实现，Linux/macOS 保留 bash 版，双轨同语义）
- `FIST_BASE` / `LIGHT_WT_ROOT` 等环境变量接入 `memory/lock-config.json` 或启动配置；
- 验收：
  - [ ] 脚本全套本地可跑（至少 bash 轨 + PowerShell 轨任一）；
  - [ ] `light-wt` 创建出 sparse cone 沙箱，磁盘占用显著低于全量 checkout；
  - [ ] `light-wt-teardown` 幂等回收，`worktree prune` 后无残留。

### 阶段 P2 · worktree 生命周期管理（约 500 行）

- 新建 `src/engine/engine_worktree.mbt` + `src/store/store_worktree.mbt`（双后端同构，照 `store_rsv` 范式）；
- 新表 `worktrees`：`wt_id / task_id / branch / path / cone_json / base_commit / status / created_at / heartbeat_at / ttl_until`；
- 新工具（建议 6 件，纯追加）：`wt_create` / `wt_status` / `wt_rebase` / `wt_teardown` / `wt_list` / `wt_ledger_write`；
- dispatcher 集成：claim 被认领 → 读任务 pkg 声明 → `wt_create` 注入 agent cwd/env；
- 验收：
  - [ ] `wt_create` 在目标项目外开 sparse worktree，cone 来自任务声明；
  - [ ] `wt_status` 可列出全部存活沙箱 + 磁盘占用；
  - [ ] 双后端测试全绿；单 agent 场景零行为变化（不显式 wt_create 时无副作用）。

### 阶段 P3 · 文件锁 × worktree 映射（约 200 行）

- `lock_acquire` 增加可选 `worktree_id` 上下文（仅审计字段，不改互斥语义）；
- `assistant_status` / `lock_status` 增加 worktree 维度视图（谁在哪个沙箱里持哪些锁）；
- 文档约定：同一项目的 N 个 worktree 共享根库 `file_locks`，跨 wt 写互斥天然生效；
- AGENTS.md 增补**文件头注释约定**：agent 修改文件时在文件顶部写块注释（last-modified / agent / task_id / scope），
  禁止行内散落（B 档：防先后写覆盖 + 语义冲突预警 + 审计佐证；不替代锁的事前互斥）；
- 验收：
  - [ ] 两 worktree 内对同一路径 `lock_acquire` 恰好一成一拒（黑盒压测）；
  - [ ] `lock_status(worktree_id=?)` 过滤正确；
  - [ ] 既有 lock 四件套行为零回归；
  - [ ] AGENTS.md 文件头注释约定可查，示例块注释格式验证通过。

### 阶段 P4 · 合并收口门禁（约 300 行）

- CI 接入：`diff-scope`（越界 diff 直接 fail）、`drift-check`（偏离 main 超阈值 fail）、
  `merge-predict`（merge-tree 离线冲突预检，push 前先跑）；
- 契约文件清单（types / proto / pkg.json / migrations / moon.mod.json）写进 AGENTS.md，
  契约变更只走 main 或 contract PR，worker 改契约路径 → diff-scope 失败；
- integration worktree（`light-wt-integrate`）：多 PR 先合跑全量测试再进 merge queue；
- **先后写覆盖检测**：B 的 PR diff 若命中「A 刚合入 main 的文件」（以 merge-base 对比已合分支改动范围），
  强制 rebase origin/main 后重跑 `merge-predict`，禁止基于旧 base 直接 push/merge（文件头注释负责"看得见"，
  此门禁负责"合不丢"）；
- 验收：
  - [ ] 越界 diff 被 CI 拒（实证：故意改 cone 外文件 → 红）；
  - [ ] 偏离超阈值被拒（实证：落后 main 超过阈值 → 红）；
  - [ ] 契约路径改动被拒（实证：worker 改 `src/core/types.mbt` → 红）；
  - [ ] 覆盖检测生效（实证：B 基于旧 base 改动 A 已合入的文件 → 要求 rebase 重跑，不静默合并）。

### 阶段 P5 · 回收 / 监控 / 生态接线（约 300 行）

- `light-wt-collector` 接 crontab/计划任务：每 5 分钟扫一遍（merged 回收 / 超龄废弃 / drift 检查）；
- 磁盘水位告警：>80% 自动收紧并发池（`LIGHT_WT_POOL_SIZE` 动态下调）；
- `watchdog_tick` 加 `sweep_worktrees=true` 分支（无人值守自动回收，仿 `flush_bug_queue` 先例）；
- `templates/worktree_wait_loop.md`：client 侧等待/换单模板；
- 版本：0.3.x → 0.4.0 minor（能力纯增量，无破坏）；
- 验收：
  - [ ] collector 能识别 merged/stale/abandoned 并回收；
  - [ ] 模拟崩溃沙箱（kill 进程）→ TTL 到期自动回收；
  - [ ] 全量回归绿 + 文档闭集同步（J14 计数自述）。

---

## 5. 落地 checklist（对应 §4 各阶段验收项汇总）

- [ ] P0：BUG-157 修复 + e2e_assistant_xproc 全绿 + claimguard 接入决策
- [ ] P0：claimguard 挂 claim/publish（owner 决策后执行）
- [ ] P1：两份 light worktree 文档入库 + bin/ 脚本全套
- [ ] P1：FIST_BASE/LIGHT_WT_ROOT 环境变量接入配置
- [ ] P2：worktrees 表 + wt_* 六工具 + dispatcher 集成
- [ ] P3：lock_acquire 带 worktree_id + 视图补全
- [ ] P3：AGENTS.md 文件头注释约定（last-modified / agent / task_id / scope，仅文件头块注释）
- [ ] P4：diff-scope / drift-check / merge-predict 接入 CI
- [ ] P4：契约文件清单入 AGENTS.md + integration worktree
- [ ] P4：先后写覆盖检测（命中已合文件 → 强制 rebase 重跑 merge-predict）
- [ ] P5：collector 定时回收 + 磁盘水位告警 + watchdog 接线
- [ ] P5：全量回归 + 文档闭集 + 版本 bump

---

## 6. 风险与前置

| 风险 | 缓解 |
|---|---|
| BUG-157 未修就开并行 = 助理选举击穿放大 | **P0 硬前置**，先修再谈并行 |
| Windows 下 bash 脚本不可用 | 双轨实现：PowerShell 为主轨、bash 为跨平台轨；用 `scripts/` 统一入口 |
| sparse cone 漏文件导致 build 报错 | 报错即扩 cone 重跑，由 dispatcher 依 build error 自动推断缺失路径（文档约定） |
| light-wt 长活 → 分支森林/磁盘泄漏 | 分钟级 TTL + collector 强制回收 + 磁盘水位告警 |
| 契约路径被 worker 误改 | diff-scope CI 硬门 + 契约清单入 AGENTS.md |
| 逻辑项重复实现（软互斥盲区） | claimguard 接入认领流程，把 BACKLOG 项预订升级为运行时拦截 |
| 先后写覆盖 / 语义冲突 | 文件头注释预警（看得见）+ PR rebase 后重跑 merge-predict（合不丢）+ integration worktree 合跑 |
| 磁盘占用（N 个 sparse wt） | cone 只铺 1~3 个 pkg；并发池先 4 观察再上调 |

---

## 7. 验收总纲（端到端 demo）

- [ ] 3 个并发任务 × 3 个 light worktree × 同一项目：任务认领（claimguard 拦截重复项）→ 各自沙箱
      （sparse cone）→ 文件锁跨 wt 互斥 → moon test 全绿 → diff-scope/drift/merge-predict 门禁 →
      PR 合并 → 沙箱自动回收；
- [ ] 无人工干预全程，产出协作时间线 + 锁命中率报告（F094 Phase 4 旗舰演示的落地前提）。

---

## 8. 与既有文档的关系

| 文档 | 关系 |
|---|---|
| `docs/2026-10-11-multi-agent-lock-design-v3.md` | 文件锁设计基线，本计划 P3 只加 worktree_id 审计字段，不改语义 |
| `docs/features/F094-multi-butler-file-binds.md` | 本计划的**上位框架**：F094 Phase 2/3 在此计划 P2/P4 落地 |
| `docs/features/F094-multi-butler-file-binds-positioning.md` | 定位文档：三层锁关系 + 逻辑项盲区（P0 收口） |
| `fist-mbt-light-worktree.zip`（light-worktree.md / drift.md） | light worktree 方案原文，P1 落仓 |
| `memory/bugs.md` BUG-157 | P0 必修项 |
| `src/claimguard/` | 逻辑项互斥库，P0 接入决策 |

---

## 9. 一句话

> 文件锁管「能不能写」，worktree 管「在哪写」，light worktree 管「写得省、活得短、走得掉」；
> 三套整合 = 多租户隔离从「单机单进程的软锁」升级为「跨进程多沙箱的硬闭环」，BUG-157 是最后一块承重墙。
*（内容由AI生成，仅供参考）*
*（内容由AI生成，仅供参考）*
