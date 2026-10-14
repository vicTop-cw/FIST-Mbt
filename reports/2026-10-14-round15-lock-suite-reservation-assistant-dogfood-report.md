# 2026-10-14 Round 15 · 锁机制全家族 live dogfood 报告（reserve_* + assistant_* 实证 · 开关全开）

> 目标：实现计划表未实现项 + 全程 dogfood fist-mbt 迭代自身（开关全开）+ 顺带看多 agent 同改一项目锁机制。
> 本回合为「锁机制实证·续」回合：R14 已实证 file-lock 家族（`lock_acquire/renew/release/status`）7/7，
> 本回合补齐其余两大家族——**作用域预订** `reserve_scope/reserve_check/reserve_release` 与
> **项目助理选举** `assistant_claim/status/heartbeat/resign/sweep`，使「锁机制那一套」在运行态全部过尺。

## 一、结果摘要

1. **计划表复核（本 lane 仍无可做项，且兄弟 lane 已推进）**：
   - `BACKLOG.md` 现状 **0 行 `pending`**（`| pending |` 精确匹配 0 行）；
   - L16 native 自驱：抬头仍带 owner 裁决「决定：现在不建」——**前置（BUG-133 两格）兄弟 lane 已实测达成**
     （账本抬头 FIXED + 干净树 native 807/807 rc=0 + 探针连发 crashes=0/12），但决策本身需 owner 复核，
     **不由旁观者代翻**（沿用 R14 边界，本回合同样不翻）；
   - L33 self_search：兄弟 lane 已翻 `done`（`self_search_evolve_bridge.mbt` IO 接线 L98/L104/L106 +
     `server.mbt` L3280-3284 注册，8 测 `self_search_evolve_bridge_wbtest.mbt`）；
   - F094 多管家文件绑定：owner 方向「Phase 1 不排期」。
   ⇒ 「实现计划表」维度在本 lane 与兄弟 lane 合计下已无可实现项，**未强行代翻他人账**。

2. **锁机制 live dogfood · 家族 A 作用域预订（`temp/lock_dogfood_r15.py`，gitignore、DB 改道 temp/、零仓库文件足迹）**：
   8 场景全过（rc=0），隔离库 `temp/lock_dogfood_r15_resv.db`：
   | # | 场景 | 结果 |
   |---|------|------|
   | A1 | A 预订 `src/x.mbt` | `reserved=true` / `action=reserved` |
   | A2 | B 查 `src/x.mbt` | `free=false` / `agent=A`（持有者可见） |
   | A3 | B 抢订 `src/x.mbt` | `reserved=false` / `action=conflict` / `held_by=A`（BUG-136 原子：只一者成） |
   | A4 | A 再查 `src/x.mbt` | `free=false` / `agent=A`（B 抢订失败未污染持有关系） |
   | A5 | A 释放 | `released=true` |
   | A6 | A 释放后 B 订 | `reserved=true` / `action=reserved`（空缺后可接管） |
   | A7 | B 持有期间查 | `free=false` / `agent=B` |
   | A7b | B 释放后查 | `free=true` / `agent=""` |
   ⇒ **拒绝型互斥在作用域预订层同样成立**：A 持有期间 B 的 `reserve_scope` 真返回 `reserved=false`/`conflict`/`held_by=A`，
   与 R14 file-lock 家族口径一致；释放→他人接管链路完整。

3. **锁机制 live dogfood · 家族 B 项目助理选举（同 harness，隔离库 `temp/lock_dogfood_r15_asst.db`）**：
   7 场景全过（rc=0）：
   | # | 场景 | 结果 |
   |---|------|------|
   | B1 | X 首次 `assistant_claim` | `elected=true` / `action=elected` / `is_primary=true` |
   | B2 | X 重复 claim | `elected=true` / `action=renewed`（续任不冲突） |
   | B3 | X 心跳新鲜时 Y claim | `elected=false` / `action=conflict` / `prev_agent=X` |
   | B4 | `assistant_status` | `primary.agent=X`（status=active）+ `takeover_count=0` + `violations_count=0` |
   | B5 | X `assistant_heartbeat` | `heartbeat_at` 刷新、`status=active` |
   | B6 | X `assistant_resign` | `resigned=true` |
   | B7 | X 退位后 Y claim | `elected=true` / `action=elected`（退位释放主位） |
   ⇒ **单主互斥 + 心跳仲裁 + 优雅退位**三件事在运行态全部成立：新鲜心跳期间 Y 抢不到主位（`conflict`），
   X 主动退位后主位真空可被 Y 合法当选——即「谁在干活」由心跳说话而非由先到先得硬抢。

4. **三家族合观（R14 + R15 合计 22 场景，rc=0 全过）**：
   | 家族 | 工具 | 互斥形状 | 接管形状 |
   |------|------|---------|---------|
   | file-lock（R14） | `lock_acquire/renew/release/status` | B 抢 A 已持锁 → `granted=false`/`conflict`/`violation_logged=true` | A 释放后 B 可接管 |
   | scope-reserve（R15） | `reserve_scope/check/release` | B 抢订 A 已订作用域 → `reserved=false`/`conflict`/`held_by=A` | A 释放后 B 可再订 |
   | assistant（R15） | `assistant_claim/status/heartbeat/resign/sweep` | 心跳新鲜时 Y claim → `elected=false`/`conflict` | X 退位后 Y 当选；主位陈旧则 `taken_over` |

## 二、harness 踩坑记录（可复用教训）

1. **仓库根 `cli.js` 不是可靠启动面**：R14 harness 直起 `node cli.js serve`，本回合再跑报
   `Error: Cannot find module '.../cli.js'`。查证：`git ls-files cli.js` **空**（根 `cli.js` 从未被 git 跟踪，是易失产物）。
   规范启动面是**构建产物** `_build/js/debug/build/cmd/cli/cli.js`（`scripts/mcp_smoke.py:47` 的 `MAIN_CANDIDATES[0]`
   与 `find_main()` 正是这个顺序）。
   ⇒ 教训：**启动面以 canonical 脚本反解，不沿用手写绝对路径**；AGENTS.md 亦明示 `Popen([node, cli.js])` 的 argv 必须带 `serve`
   且入口以 `check_entry_paths` 判据反解。R15 harness 已改起 build 产物（`_build/.../cmd/cli/cli.js`）。
2. **server 端已强制 `_meta.protocolVersion`**：首跑报 `-32602 Missing required _meta field:
   io.modelcontextprotocol/protocolVersion`。规范约定（`scripts/mcp_smoke.py:52-68`）是**每个请求**都带
   `_meta = {protocolVersion, clientCapabilities, clientInfo}`，而非只调一次 `initialize`。
   ⇒ 本回合笔记中「不调 initialize」仍对，但**不等于不传 `_meta`**；两件事被混为一谈是这次的坑。
3. **Windows cp936 会啃 UTF-8 响应**：`subprocess` 未指定编码时 `readline()` 抛
   `UnicodeDecodeError: 'gbk' codec can't decode byte 0xaf`。规范 harness 显式 `encoding="utf-8", errors="replace"`
   （`scripts/mcp_smoke.py:126-127`）。
4. **后台任务不要用 `| Out-String` 读进度**：管道会整体缓冲到进程退出，中途 `job_output` 只见空。
   改 `> file 2>&1` 重定向 + 轮询文件，才看得见逐场景 PASS 行。

## 三、资源消耗

- `python -u temp/lock_dogfood_r15.py`（起 fork MCP server ×2，21 次 tools/call，rc=0）；
- 只读 git 探活 + BACKLOG 复核若干次；`python scripts/patch_esm_main.py`（ESM shim，幂等，已就位）；
- 无子代理派发（轻量自办，金条四允许）。

## 四、任务分配记录

- 本 lane 自办：复核 BACKLOG（0 pending）→ 读 canonical harness 约定 → 修 R15 harness 三处启动面问题 →
  跑 reserve 家族 8 场景 + assistant 家族 7 场景（rc=0）→ 追加 R15 记忆 + 本报告。
- 兄弟 lane（不代劳）：`src/server/server.mbt` / `src/server/model_router_ops.mbt` / `src/router/*` 等 7 文件脏 +
  4 份未跟踪报告（router 增强 / file-lock 机制 / p2 guards / router 执行）。**本回合 `git add` 只含本报告与 memory，
  未 stage 兄弟任何文件**（谁提交谁翻账）。

## 五、遗留风险

1. **共享目标整体未达成**：BACKLOG 虽 0 pending，但 L16 仍是 owner 决策项（「现在不建」），
   需 owner 复核是否解冻；F094 Phase 1 不排期。
2. **兄弟 lane WIP 未收口**：router 增强在飞，`moon fmt` 门可能因并发 `.mbti` 漂移短暂红——非本 lane 责任，不修不 stage。
3. **锁机制的跨进程面尚未实测**：本套 harness 是**单进程内 fork 出的 server** 顺序调用，证明了协议层与状态机正确；
   真正的多 agent 跨进程并发抢锁（两个独立 server 进程同时 `lock_acquire`/`reserve_scope`）仍待实测——
   受当前「两 agent 各自跑、无共享 MCP 端口」的客观条件限制，列为后续。

## 六、后续建议

1. **补一条跨进程并发判据**：起两个独立 `serve` 进程指向**同一个** SQLite 库，同时 `reserve_scope` 同作用域，
   断言恰一者 `reserved=true`（BUG-136 原子性在跨进程面才是真考验）。
2. **LOCK-DOGFOOD 家族矩阵进 `src/store` 白盒**：把本 harness 的 15 场景翻成 `_wbtest.mbt` 常驻锁，
   避免「harness 在 temp/、判据不在仓里」的间断面。
3. **L16 解冻走 owner 通道**：前置已全绿（807/807 + 探针 0/12），把这两格读数 + 「是否现在建」的选项交给 owner 一句确认，
   而非旁观者代翻。

## 七、来源

- `scripts/mcp_smoke.py`（启动面 / `_meta` 约定 / 编码约定，L46-48 / L52-56 / L120-129）；
- `AGENTS.md`（`check_entry_paths` BUG-93/101：`Popen([node, cli.js])` 必须带 `serve`，入口从 `cmd/*/moon.pkg` 反解）；
- `src/server/server.mbt`（`reserve_*` L4324-4437、`lock_*` L4439+、`assistant_*` L4646-4805，只读未改）；
- R14 报告 `reports/2026-10-14-round14-lock-mechanism-live-dogfood-report.md`；
- 兄弟 lane 记录 `memory/2026-10-14.md` R110/R111（J14 扩面 / 1043 全绿 / L33 翻 done）。
