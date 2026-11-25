# T0r94 · 注册表现实核对（守护器每轮 session_pid ↔ 端口真实监听 pid）

- 日期：2026-11-25
- 执行身份：codearts
- 需求真源：`fist-mbt/plan/active/2026-11-25-svc-registry-liveness.md` §工作项 3（三处口径缺陷之三：`status='running'` 与进程脱钩）
- 任务池：`autoplan`

## 一、结果摘要

**结论：需求已实现并落盘，两笔 scoped 提交；本轮实跑六服务全部 `reg=ok`（无漂移）。**

注册表此前只被网关心跳单向写入，守护器**完全不读它**（`gateway_guardian.py` 里 `AGENT_SERVICES_DB` 仅用于 spawn argv）⇒ 「端口活 / 注册表说 running」之间没有任何判据。本轮补上：

- `registry_liveness()`（纯函数，判定与写库分离）+ `check_registry_truth()`（每轮入口）：
  读 `agent_service.session_pid` / `session_listen_addr`，与 `psutil.net_connections` 在该端口的**真实 LISTEN pid** 比对。
  - **pid 不符** ⇒ 条件更新 `status='stopped'`，差异与时间戳 emit（落 `.fist-mbt/data/guardian-logs/guardian.log`）。
  - **地址漂移** ⇒ 记 `WARNING`，但**不**改 status（地址不是活体判据）。
  - 自动路径**只改 `status` 一个字段**（plan 红线二）：SQL 显式列 `status, updated_at`；
    条件更新 `WHERE service_id=? AND status='running'`，与网关心跳的 60s 回写形成「一致则不改、不一致则降级、下一发自愈」，不拉锯。
  - 读不到库 / 表不存在 ⇒ 跳过 + WARN，绝不猜。
- 接入 `check_once` 首步（异常只 `emit ERR`，不阻断整轮巡检）；`--status` 盘点表按 plan 门禁要求新增「实例」「注册」两列。
- `--selftest` 补 **R 族 8 格**（R1/R2 正常必绿含通配绑定归一；R3~R6 违例必红；**R7/R8 为变异对照**）。

## 二、产出物路径（本任务的交付面）

| 类别 | 路径 |
|---|---|
| 主改动（已入库，`506db07c5`） | `scripts/gateway_guardian.py`（新增约 130 行；该文件此前**未跟踪**） |
| 执行面登记（已入库，`a1f18ef8c`） | `scripts/run_guards.py`（电池 `case("gateway_guardian.py", "--selftest")`） |
| 脚本索引（已入库，`a1f18ef8c`） | `scripts/README.md`（`gateway_guardian.py` 条目） |
| 运行期日志（gitignore 面） | `scripts/gateway_guardian.py` emit → `.fist-mbt/data/guardian-logs/guardian.log` |
| 注册表库（gitignore 面） | `.fist-mbt/data/agent-services.db`（`agent_service` 单表；全程只读核对，写只在判出 pid 不符时） |
| 报告 | `reports/2026-11-25-T0r94-svc-registry-reality-check-report.md`（本文件） |
| 当日日志 | `memory/2026-11-25.md`（append） |

> 未跟踪/被忽略面不入提交：`agent-services.db`、`guardian-logs/` 均在 gitignore 面，报告与日志落盘即完成交付。

## 三、资源消耗

- 实跑命令：`--selftest` ×3、`--once` ×1、`--status` ×2、`run_guards.py --list` ×1、合成夹具探针 ×1（已删）、git 提交 ×2。
- 零新依赖（仍仅 stdlib + 既有可选 psutil）；零 `.mbt` 改动 ⇒ 无需 `moon fmt` / `moon test`。

## 四、任务分配记录

- 本任务由 `codearts` 单执行 agent 完成（中任务：单文件 + 两处登记面，未拆子代理）。
- 无子代理，无跨 agent 分派。

## 五、证据（实测读数）

| 读数 | 值 |
|---|---|
| `--selftest` | rc=0，**44 格全绿**（反解 B×2 / C×7 / G×2 / L×12 / M×10 / N×3 / R×8） |
| `--status` | rc=0，六行全 `ALIVE`，`实例=1`，`reg=ok` |
| 六端口真实 pid | svc-agent 11972 / svc-atomcode 10324 / svc-codearts 9144 / svc-freebuff 48764 / svc-marvis 33436 / svc-webai 41860（与注册表 `session_pid` 逐一相同） |
| `--once` 前后注册表快照 | 逐字未变（无误改、无多余 spawn） |
| 合成夹具（同构临时库副本） | `svc-atomcode.session_pid=43200`（真实缺陷值）⇒ 该行落 `stopped`，其余 8 行不动；**变异对照**（把 `_pid_matches` 改坏成「有人听就算」）⇒ 不再置 stopped |

落盘提交：

```
a1f18ef8c feat(guardian): 注册表现实核对：session_pid ↔ 端口真实监听 pid 每轮比对
        （scripts/run_guards.py + scripts/README.md）
506db07c5 feat(guardian): 六服务网关守护器入库 + 注册表现实核对每轮比对
        （scripts/gateway_guardian.py，1320 行新增）
```

## 六、缺口与风险

1. **`--selftest` 的写路径仍是合成面**：自检走纯函数 + 合成违例格（判例-29 要求的变异对照已具备），但「真写 SQLite」那一路由一次性夹具证明后即删除，**没有常驻锁**。常驻化需要给 `agent_service` 造一个合成表结构夹具，属可加可不加的一格；当前不冒充已覆盖。
2. **心跳拉锯的理论残留**：`stopped` 之后网关下一发心跳（≤60s）若确认真活体会把 pid 收敛回真值并重写 `running`——这是**期望行为**（自愈），但意味着「pid 不符」这一状态最长可见 60s。若将来要更快收敛，需要在网关侧加「核对前置」而不是在守护器侧加码。
3. **不在本任务内**（同一计划文件的另外两条工作项，本轮**未认领**）：陈旧端口扫描（如 svc-marvis 旧端口 18642 劫持形态）、多实例清理的人工闸门闭环。多实例**检出**已在既有 `--once` 的 `alert` 分支里（≥2 个 LISTEN 只告警 + 写哨兵，不自动杀）。
4. **共享文件混有他方 WIP**：`scripts/run_guards.py` / `scripts/README.md` 的工作树版本同时含他人改动（`test_plan_guards.py`、`check_underscore_ignore.py`、crosspool/pool_contact 等）。已按 T0r84 精确提交法（备份工作树 → 用 `HEAD + 只插我这一段` 替换 → `commit_scoped.sh` 原子提交 → 写回备份）隔离，**提交后哈希与备份逐字一致**（`be52f9c2…` / `afee4028…`），他方 WIP 零损失。
5. `scripts/gateway_guardian.py` 入库前**无任何执行面**（T0r83 报告 §四.3 点名）——本轮一并补齐；`run_guards.py --list` 的「缺面清单」当前仍报 `pack_exe_to_md.py` / `blackbox/e2e_web_agent_p1.py`，系**他方**未登记脚本，与本任务无关。

## 七、后续建议

- 若要把「真写库」变成常驻门，可在 `--selftest` 里加一格：用 `tempfile` 造一份带 `agent_service` 表的临时库，monkeypatch `AGENT_SERVICES_DB` 指向它，断言 `check_registry_truth` 真的把违例行改成 `stopped`（本次夹具已证明机制可行，差的是把它钉进自检）。
- 把「心跳自愈窗口 ≤60s」写进守护器 README 条目（现已在 `scripts/README.md` 条目里注明条件更新语义）。
- 顺带处理 `run_guards.py --list` 的两条他方缺面（谁的地盘谁认领）。

## 八、来源

- `fist-mbt/plan/active/2026-11-25-svc-registry-liveness.md`（§工作项 3、红线段）
- `reports/2026-11-25-T0r83-patrol-gate-report.md` §四.3（守护器未跟踪、未登记的取证）
- 现场实测：`agent-services.db` 直查、psutil `net_connections`、`--selftest`/`--status`/`--once`、合成夹具探针
