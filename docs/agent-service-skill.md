# Agent 服务与会话内嵌 worker（agent-service-skill）

> 口径日期：2026-11-25。本文是**能力面说明 + 当前真实可用边界**，不是「已交付清单」。
> 计划真源：`fist-mbt/plan/active/2026-11-25-fist-agent-worker-issue1.md`（AtomGit issue #1）。
> 姊妹文档：`docs/fist-agent-principle.md`（常驻网关与注册表的工作原理）、
> `USAGE.md` §11 / §11.1 / §11.2（操作面）、`reports/2026-11-25-T0r87-executor-writeback-inventory.md`（P1 盘点）。
>
> **一句话现状**：「Agent 服务化」的**注册表 + 常驻网关**那一层已上线实弹；
> **会话内嵌 worker**（`fist agent serve`）这一层**只有 P0 骨架代码存在，尚未接进 CLI、尚未入库**，
> 因而**当前任何机器上都跑不起来**（实测 `node dist/fist-mbt.js agent status` → `未知子命令: agent`，rc=2）。

## 1. 这一层解决什么问题

`fist serve` 是 stdio MCP server，生命周期随客户端断开而退出；它**不会自己**去任务池里领活。
要让一个 agent「在会话内后台常驻、轮询任务池、领取、调用执行器、回写回执」，需要一条独立于
任何单一客户端的执行链——这就是「会话内嵌 worker」（issue #1 / 计划卡 P0-P2）。

它必须满足的三条红线（计划卡原文）：

| 红线 | 含义 |
|---|---|
| 执行器外置 | worker 不内置 LLM，只按模板调外部命令（P1） |
| server 保持被动 | **不改造 `fist serve`**：worker 零 spawn server，只操作状态文件 + SQLite |
| 不依赖 cron | 不用 cron/schtasks/systemd；随会话拉起，重启从池子 + 状态文件恢复 |

## 2. 三层结构与各自现状

```
┌─ P0 骨架（会话内嵌 worker 主干）────────────────────────────────┐
│  单实例锁 agent.lock → 心跳/状态 → 一轮{list → claim → packet}  │
│  状态：代码齐备（cmd/cli/agent.mbt，748 行）· 未接线 · 未入库    │
└─────────────────────────────────────────────────────────────────┘
┌─ P1 执行器 + 回写 ──────────────────────────────────────────────┐
│  --executor 模板 {packet}/{project}/{task_id} + 超时 + 收集      │
│  状态：不存在（全仓零命中，见 T0r87 报告 §一）                   │
└─────────────────────────────────────────────────────────────────┘
┌─ P2 仓库池 / 跨机接线 ──────────────────────────────────────────┐
│  fist-msg-pool 原子 rename + YAML backlog + 每轮 git pull        │
│  状态：不存在；跨机介质（GitCode 伴生仓）是空仓（T0r89 D2）      │
└─────────────────────────────────────────────────────────────────┘
```

### 2.1 P0 已备的部分（`cmd/cli/agent.mbt`，748 行，untracked）

模块自带完整词法与退出码契约（与 `subcmd.mbt` 同构），已实现：

| 件 | 落点 |
|---|---|
| 子命令词法 `serve/run/status/stop/help` | `parse_agent_cmd` |
| 旗标白名单 `--once` / `--dry-run`，**未知旗标回 Err** | `parse_agent_flags` / `AGENT_KNOWN_FLAGS` |
| 单实例锁：OS 级原子创建（js `flag:'wx'`）+ mtime stale 回收（30s）+ 三档可分辨结果 | `agent_lock_acquire` / `LockResult` |
| 状态机三态 `running / stopped / stale`，**不设隐式退出路径** | `AgentStatus` |
| `state.json` + `worker.log` 落 `<data_dir>/agent-service/`，改道针跟随 `FIST_DB_PATH` | `agent_service_dir()`（每次现算不缓存） |
| 一轮 `agent_run_once()`：list → claim → task-packet → 回执骨架；claim 失败**不假绿** | `agent_run_once` |
| `--dry-run` ⇒ 照读照算但不写状态、不改库 | `AgentFlags::should_mutate` |
| native 臂如实报未实现（不静默回 OK） | `cmd/cli/agent_native.mbt` |

**缺的只有接线**（三处，均不在本文件内）：

1. `cmd/cli/subcmd.mbt` 的 `Subcmd` 无 `Agent` 分支；
2. `cmd/cli/main.mbt` 的分发臂无 `Agent => run_agent(args)`；
3. `cmd/cli/help_topics.mbt` 的 `help_cli()` 无 agent 一行。

### 2.2 P1 / P2 尚不存在（不要据骨架推断可用）

| 面 | 实测结论 | 证据 |
|---|---|---|
| `--executor` 命令模板 | **全仓零命中** | 检索 `--once`/`agent.lock`/`FIST_AGENT`/`{packet}`/`task_packet` 在 `src/`、`cmd/`、`scripts/`、`services/` 零命中（T0r87 §一） |
| worker 侧 claim→execute→submit 链 | **不存在** | 同上 |
| 消息池读取 | **不存在** | `cmd/cli/agent.mbt` 对四条已知池路径正则全 `<none>`（T0r89 §2） |
| 跨机介质目录骨架 | **远端只有意图声明** | 伴生仓 clone 后仅 1 个 `README.md`，无 `inbox/`、`processed/`（T0r89 §4） |

> ⚠️ 因此 **`fist agent serve` 现在不能作为「云机器侧同一命令拉起 worker」的手段**——
> 那条命令在本机产物上 rc=2。云机器接线（P2+）依赖 P0 接线先落地。

## 3. 最小改动面（让 P0 可用；本轮不执行）

| 落点 | 改动 | 风险 |
|---|---|---|
| `cmd/cli/subcmd.mbt` | `Subcmd` 加 `Agent`；`parse_subcmd` 加 `"agent" => Agent`；`exit_code_of` 保持已知臂 0 | 低 |
| `cmd/cli/main.mbt` | 分发臂加 `Agent => run_agent(args)`；新增 `run_agent` 解析二级子命令并转 `agent.mbt` 的 `run_agent_serve` / `run_agent_status` / `run_agent_stop` | 中（要透传 `agent` 之后的参数） |
| `cmd/cli/help_topics.mbt` | `help_cli()` 补 agent 一行 | 低 |
| `cmd/cli/subcmd_wbtest.mbt` | **同批**补 agent 词法/旗标的白盒锁（现 0 处 agent 引用） | 必须，否则新入跟踪面的 `.mbt` 无行为锁 |

⚠️ `agent.mbt` 一旦入跟踪面即为**新增 `.mbt` 面**：按本仓纪律须同批给行为锁，
且提交前 `moon fmt` + js 门全绿（见 `AGENTS.md` 提交门禁）。

## 4. 当前真能用的替代路径

在 P0 接线之前，「让一个 agent 被长期调用」这件事**已有可用通道**，走的是
**注册表 + 常驻网关**那一层，而不是 worker：

```bash
# 1) 注册（MCP 工具）——建独立 ns 库 + ACL 授权，不拉起进程
#    tools/call agent_service_register {service_id, owner_agent, transport, exposure}
# 2) 手动拉起常驻网关（local 档 + API-key）
python scripts/fist_gateway.py --service-id svc-<name> --port 18640 \
  --db .fist-mbt/data/agent-services.db --host 127.0.0.1 \
  --api-key-file .fist-mbt/data/svc-<name>.apikey
# 3) 调用：POST http://127.0.0.1:18640/mcp，头 X-API-Key: <key>
```

要点：服务会话长期不中断、仅显式中断指令才终止（`running → draining → stopped`）；
`/health` 是最轻活体探针；子进程崩溃由 watchdog 自动重启（退避 1s/5s/30s）。
完整工作原理见 `docs/fist-agent-principle.md`，操作细节见 `USAGE.md` §11。

**两条路径的分工**：

| | 注册表 + 常驻网关（已上线） | 会话内嵌 worker（P0 未接线） |
|---|---|---|
| 谁发起调用 | 外部客户端经 HTTP `/mcp` | worker 自己轮询任务池 |
| 解决什么 | 「这个 agent 活着且可达」 | 「没人调它时它也去领活干」 |
| 现状 | 🟢 实弹在线（如 `svc-atomcode @ 127.0.0.1:18640`） | 🔴 入口不存在 |

## 5. 相关落点索引

| 面 | 路径 |
|---|---|
| worker P0 骨架（未接线） | `cmd/cli/agent.mbt`（+ target 臂 `agent_js.mbt` / `agent_native.mbt`） |
| 计划卡 | `fist-mbt/plan/active/2026-11-25-fist-agent-worker-issue1.md` |
| 工作原理（网关/注册表） | `docs/fist-agent-principle.md` |
| P1 只读盘点 | `reports/2026-11-25-T0r87-executor-writeback-inventory.md` |
| P2+ 跨机接线盘点 | `reports/2026-11-25-T0r89-crossmachine-pool-wiring-report.md` |
| 消息闭环口径 | `USAGE.md` §11.1 + `fist-mbt/plan/draft/2026-11-24-msg-loop-closed.md` |
| 本轮文档报告 | `reports/2026-11-25-T0r90-agent-service-doc-report.md` |

## 6. 边界声明

- 本文只描述**代码事实与实测读数**，不含「计划要做」的承诺；凡未实测的面均标注来源报告。
- `agent_service_*` 六工具的 `agent` / `owner_agent` / `created_by` 等身份字段是**调用方自报、服务端无法验证**的（BUG-430/S1 同族公告），本文不改变这一安全属性。
- 本机 `wsl.exe` 无发行版（T0r89 §4）⇒ 计划中「WSL 共享介质」那条路当前不可用。
