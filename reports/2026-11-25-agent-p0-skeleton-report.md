# T0r86 · cmd/cli agent 子命令 P0 骨架报告

日期：2026-11-25 ｜ 任务号：T0r86 ｜ namespace：autoplan

## 结果摘要

`cmd/cli` 新增 `agent` 子命令族（serve / run / status / stop）+ `--once` 单轮语义 + `--dry-run`
结构性零落盘观测面 + OS 级单实例锁 + `<data_dir>/agent-service/` 状态/日志落点。
未改 server（保持被动）、未内置执行器（P0 只做 claim-only 观测）。

产出物路径（7 份，全部新增于 `cmd/cli/`）：

| 路径 | 作用 |
|---|---|
| `cmd/cli/agent.mbt` | 主体：词法、旗标、路径口径、状态六键、锁三态、一轮、快照、调度 |
| `cmd/cli/agent_js.mbt` | js 臂：同步 IO dispatcher + extern（唯一 IO 实现面） |
| `cmd/cli/agent_native.mbt` | native/llvm 臂如实 `abort(...)`（不假绿，P1 再接） |
| `cmd/cli/main.mbt` | dispatch + `run_agent` 四子命令统一旗标面 + 用法错出口 rc=2 |
| `cmd/cli/subcmd.mbt` | `Agent` 变体 + `parse_subcmd("agent")` |
| `cmd/cli/moon.pkg` | import `@fs`；`targets` 分 target 声明两臂 |
| `cmd/cli/agent_wbtest.mbt` | 白盒锁 5 格（词法 / 旗标拒绝 / 改道 / 状态机 / 回执） |

生成物：`cmd/cli/pkg.generated.mbti` 已随 `moon info` 同步。

**未纳入本笔提交**：`cmd/cli/help_topics.mbt`（他方 WIP，同时推进 `FIST_VERSION`
0.3.11→0.3.15 与工具计数 183→188，与本任务无关），按「不碰他方未提交 WIP」红线留置工作树。

## 关键设计决定（含被实测推翻的初版）

1. **`--once` = 跑一轮即退**；`run` 是其别名（语义固定 once，仍接受 `--dry-run`）。
2. **单实例锁用 OS 原子创建**（`flag:'wx'`），**不用 `@store.FileLock`** —— 后者是库内
   逻辑锁记录（scope/agent/status，供权限门读），无跨进程排他能力，用它会得到
   「两个进程都说自己持有」。
3. **先建服务目录再取锁**：直接对锁文件做原子创建会因父目录缺失回 ENOENT，而那会被
   误报成「取锁失败」（实测踩中）。
4. **`stop` 无条件删锁**：初版复用 `agent_lock_release`（只在内容==自己 pid 时删），
   而 `stop` 是另一进程 ⇒ 锁永远删不掉 ⇒ 常驻 worker 永不退出 ⇒ **stop 形同虚设**。
   实测抓到后新增 `agent_lock_stop_release()`：删锁即停止的全部作用，worker 下一轮
   `is_mine` 读到无锁即退出（实测：stop 后 worker 自行退出，rc=0）。
5. **三档可分辨**：`Acquired` / `HeldBy(pid)` / `Failed(err)`。锁冲突回 rc=0 并明说持有者，
   不报错误（`--once` 下冲突是正常出口）。
6. **dry-run 不得取锁**：取锁本身写 lock 文件 ⇒ 无法成立「零落盘」。`run_agent_serve`
   在 dry-run 下整段跳过取锁；`agent_mark_stopped` dry-run 为 no-op。
7. **读回失败不回默认对象**：状态读失败回 None，禁伪造 running。初始态抽
   `agent_state_default(now)`，dry-run 与实跑共用同一格。
8. **native 臂如实 abort**：`fn[T] agent_native_unsupported() -> T` 一律 abort，
   禁止「编译过但不干活」的假绿。

## 证据（实测读数）

| 验证项 | 读数 |
|---|---|
| `moon check --target js cmd/cli` | 0 error（43 warnings，均为既存 unused_*） |
| `moon check --target native cmd/cli` | 0 error（62 warnings） |
| `python scripts/check_fmt_gate.py` | PASS（`moon fmt --check rc=0`） |
| `moon info` | Finished, 0 errors（生成接口已同步） |
| `cmd/cli` 白盒测试 | **Total tests 15 / passed 15 / failed 0** |
| 全仓 JS 回归 | **Total tests 2117 / passed 2116 / failed 1** |

端到端行为矩阵（真产物 `_build/js/debug/build/cmd/cli/cli.js`）：

| 场景 | 期望 | 实测 |
|---|---|---|
| `agent help` | rc=0，四行用法 | ✅ rc=0 |
| `agent serve --onse`（拼错） | rc=2，未知参数提示 | ✅ rc=2 |
| `agent run --dry-run` | 零落盘 | ✅ 目录仅剩 `db.sqlite`（CLI 自身构造 store 产生） |
| `agent run` | 落 state/log、rc=0 | ✅ state.json + worker.log |
| `serve --once` 真取锁 | 落 lock/state/log | ✅ 三者齐 |
| 并发第二发 | rc=0 + 「已有 worker 持锁（pid …）」 | ✅ rc=0 |
| `status`（只读） | 显示 holder、rounds、心跳、日志尾 | ✅ |
| `stop --dry-run` | **不放锁** | ✅ lock 仍在 |
| `stop` 真停 | 删锁 + 标 stopped | ✅ 锁消失，state=stopped |
| `stop` 后常驻 worker | 随之退出 | ✅ worker 打印「停止」后 rc=0 |

## 缺口与风险（P0 边界，需 P1/P2 收口）

1. **`stop` 不杀进程**：只做状态面（删锁即让 worker 自行退出）。若 worker 卡在长任务
   （P1 的执行器超时阶段）或 `is_mine` 读锁被 IO 阻塞，停止意图不会立即生效。
2. **stale 回收阈值硬编码 30s**（`AGENT_LOCK_STALE_MS`）：过短会把慢启动的合法持有者判死；
   过长会让真死锁残留。P1 应接 `--interval`/可配置阈值。
3. **无执行器**：claim-only（`note=no_pending` / 无包可发）。回执缺 executor 相关字段，
   留 P1 的 `--executor` 模板 + 失败不假绿。
4. **native 臂未实现**：所有 IO 原语 abort。CI native 臂能编不能跑 agent 子命令。
5. **单实例锁仅文件级**：多主机/共享文件系统场景未覆盖（issue 的跨机云机器接线属 P2+）。
6. **`@store.FileLock` 未被使用**：本次刻意绕开，故权限门看不到 agent 的持锁关系；
   S1/S3 身份面未定前，这是已知边界而非缺陷。

## 资源消耗

- 会话轮次：约 40（含多次实测与 1 次缺陷修复往返）
- 主要开销：两次全仓编译 + 一次全仓 JS 测试（2117 格）+ 多次增量 build
- 未跑 WSL/native 全量（本机 native 全量受 BUG-527 阻断，见 AGENTS.md）

## 后续建议

1. P1：接外置执行器（`--executor` 模板 + 超时 + stdout/exit 收集 + 失败写 failure_reason
   不假绿），并把 stale 阈值做成 `--interval` 一族配置。
2. P1：native 臂补齐 IO（否则 agent 子命令在 Linux 部署侧完全不可用）。
3. P2：仓库池（msg-pool 原子 rename / YAML backlog / git pull --rebase 失败跳本轮）。
4. 建议把 `help_topics.mbt` 的版本号+计数变更由该 WIP 的归属方单独收口（本笔未碰）。

## 超额内容（超出任务包的部分）

- `agent_wbtest.mbt` 5 格白盒锁（计划只要求「测试含锁冲突与 rc 契约」，
  实测补充了改道/状态机/回执三格反向对照）
- 删除两处死代码（`AgentStatus` enum、`agent_io_field`）—— 它们是「同一规则两份实现」
  的漂移源，且新增即带 unused 告警

## 来源

- 任务单：T0r86（autoplan ns）
- 计划：`fist-mbt/plan/active/2026-11-25-fist-agent-worker-issue1.md`（P0 条目）
- 先例：`reports/2026-11-21-agent-service-p0-report.md`、`docs/fist-agent-principle.md`
