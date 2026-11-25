# T0r91 · 门禁：issue #1 验收标准 1-10 逐条对表报告

- 任务号：`T0r91`（ns `autoplan`）
- 对表对象：AtomGit issue #1《【实现】会话内嵌 fist-agent worker》§三 验收标准 1-10
  原文取自 `GET /repos/VictorTop/Fist-Mbt/issues/1`（2026-11-25 拉取，issue `updated_at=13:32:02+08:00`）
- 口径来源：`fist-mbt/plan/active/2026-11-25-fist-agent-worker-issue1.md`
- 约束：**只读盘点 / 最小改动**。本轮未改任何源码、未提交、未 push；全部 git 操作仅读
- 工作树：dirty（会话起始即 116 处改动，含他方 WIP）⇒ 零 git 写操作
- 日期：2026-11-25

---

## 一、结果摘要

**结论：验收标准 1-10 中，无一条可判为 PASS（0/10）。**

不是「做了但没验」，而是**入口本身不存在**：`cmd/cli/agent.mbt` 的 P0 骨架代码在场，
但它**既未接进 CLI 分发、也未进入 git 跟踪面**，因此发布产物里没有 `agent` 子命令——
本轮实测两份产物（发布快照与本机构建缓存）都是 `未知子命令: agent` / **rc=2**。

| 标准 | 主题 | 判定 | 一句话 |
|---|---|---|---|
| 1 | 会话内可拉起 + status 显示 running/pid/last_tick | ❌ FAIL | 命令不存在（rc=2）；status 文本渲染器在骨架里有，但取不到 state.json |
| 2 | YAML 任务池轮询（TASK-999） | ❌ FAIL | 骨架不读 YAML 池，且 `docs/tasks/backlog/` 实体存在但不在候选面 |
| 3 | 消息池轮询 inbox→processing→processed | ❌ FAIL | 骨架对池路径零引用；跨机介质是空仓 |
| 4 | fake executor 调用 + marker + 待验收回执 | ❌ FAIL | `--executor` 全仓零命中，无执行链 |
| 5 | 幂等（同任务两轮一次 / 第二实例因锁退） | ❌ FAIL | 锁机制齐备**但无测试**；claim 轮询面为空数组 |
| 6 | 失败不假绿（blocked + failure_reason + failed/） | ❌ FAIL | 无执行器 ⇒ 无失败路径；`failure_reason` 字段属 MCP execute 工具，worker 侧未接 |
| 7 | 黑盒 dist 可拉起 + Node≥24 门 + `--once` 跑通 | ❌ FAIL | `dist` 里无 agent；dist 版本落后（0.3.11 vs moon.mod 0.3.15）且无 Node 门 |
| 8 | 不依赖 cron | ✅ PASS（附条件） | 全仓无 schtasks/systemd/crontab 引用，无违例可建 |
| 9 | 会话关闭行为（随会话退出 + 重启不重复领取） | ⚠️ N/A / 不可验 | 无进程可观测；状态恢复逻辑在骨架里，缺测试 |
| 10 | CI 新增 agent_service 白盒/黑盒 + 变异对照 | ❌ FAIL | 白盒 0 引用、CI 0 登记；且无 entity 可测 |

**门禁结论：不通过。** 卡点是**同一个**：P0「接线」未完成（骨架 → CLI 分发 → 跟踪面）。
前置缺口两格已由同族单各自收口一半，见 §三。

---

## 二、逐条对表（1-10）

### 标准 1 · 会话内可拉起 —— ❌ FAIL

> 原文：在当前会话后台执行 `fist agent serve ...`，5 秒内 `fist agent status` 显示 `running`、pid、last_tick。

| 证据 | 读数 |
|---|---|
| `node dist/fist-mbt.js agent status`（2026-11-25 实跑） | 首行 `未知子命令: agent` + help；**rc=2** |
| `node _build/js/debug/build/cmd/cli/cli.js agent status` | 同上，**rc=2**（该产物 11-25 11:21 构建，晚于骨架落盘 13:27？否——见下行） |
| `cmd/cli/subcmd.mbt` 的 `Subcmd` 变体 | `Serve / Version / Demo / Doctor / Upgrade / Help / NoArgs / Unknown(String)`，**无 `Agent`** |
| `cmd/cli/main.mbt:44-58` 分发臂 | `match parse_subcmd(sub)` 无 `Agent =>` 分支；命中即落 `Unknown` ⇒ rc=2 |
| 骨架内的 status 渲染器 | `run_agent_status()`（`agent.mbt:667`）、`agent_snapshot_text()`（`:705`）**存在**，能打 `state/pid/rounds/last_task/heartbeat` |
| 为何 status 取不到 running | `agent_service_dir()` 落 `<data_dir>/agent-service/`，而该目录从未被创建（唯一写入点 `agent_write_state` 只由 `agent_round_and_record` 调，而后者无 CLI 入口） |

⇒ **渲染器就绪、入口缺失**。「5 秒内 status 显示 running」这一条当前**无法观测**。

### 标准 2 · YAML 任务池轮询 —— ❌ FAIL

> 原文：向 `--project-dir` 的 `docs/tasks/backlog/` 放一条 `TASK-999`，服务在 ≤ interval 秒内领取并生成 task-packet。

| 证据 | 读数 |
|---|---|
| 骨架的一轮候选面 | `agent_run_once`（`agent.mbt:452-488`）：`let pending : Array[String] = []`，随后 `for t in engine.list_all()` 取 `is_pending()` 的**内存 store** 任务 |
| YAML 池读取 | **零**。骨架无任何 `docs/tasks/backlog` / `run_fist_task_pool` 引用 |
| 实体存在性 | `docs/tasks/backlog/TASK-001-…yaml` ~ `TASK-005-…yaml` 在场（可读），但不在候选面 |
| task-packet 落盘 | `agent_packet_for()`（`:435`）只把 packet **作为字符串放进 stdout 文本**，不落 `task-packet.json/.md` 文件 |
| `--project-dir` / `--interval` 旗标 | **未接线**（`parse_agent_flags` 只认 `--once` / `--dry-run`，未知即 Err） |

⇒ 即便接线完成，候选面仍空 ⇒ 验收 2 必失败。差的是「YAML 池 + 项目根 + interval」三层。

### 标准 3 · 消息池轮询 —— ❌ FAIL

> 原文：向 `fist-msg-pool/projects/Tnr/inbox/` 放一条 JSON，服务领取后出现在 `processing/`，完成后 `processed/` 且带回执。

| 证据 | 读数 |
|---|---|
| 骨架对池路径的引用 | 四条已知池路径正则全 `<none>`（`agent.mbt` 只操作 SQLite + 状态文件） |
| 跨机介质实况 | 伴生仓 `gitcode.com/VictorTop/fist-msg-pool` clone 后**仅 1 个 `README.md`**，无 `inbox/`/`processed/`（T0r89 §4） |
| 四池路径口径 | 六处声明指向四个不同路径（`.fist-mbt/msg/` / `.fist-mbt/pool/messages/` / `<root>/pool/messages` / 无），未收敛 |
| 本地实体 | 磁盘上无 `fist-msg-pool` 目录（`find` 零命中） |

⇒ 验收 3 的两半（worker 读取 + 介质存在）**都不成立**。

### 标准 4 · 执行器调用 —— ❌ FAIL

> 原文：fake executor 被调用一次，`fake-done.marker` 生成，任务进入 `待验收`，回执含 task_id/结果/证据。

| 证据 | 读数 |
|---|---|
| `--executor` 旗标 | 全仓零命中（T0r87 §一逐项检索 `{packet}`/`task_packet`/`--executor` 在 `src/` `cmd/` `scripts/` `services/` 均无） |
| spawn + 超时 + stdout/exit 收集 | 现成件齐备但未被 worker 用：`run_check_external`（`src/server/run_check_js.mbt:121`）、`CliFailure` 归因（`src/executor/cli_argv.mbt:182-236`） |
| claim→execute→submit 链 | 骨架止于 `engine.claim(...)`（`:469`），无后续 |
| `commissar_send` 回执 | 引擎侧有（`src/ops/ops_commissar.mbt:157`），worker 侧未接 |

⇒ 验收 4 的四个观测点（marker / 待验收 / 回执内容）**全部无落点**。

### 标准 5 · 幂等 —— ❌ FAIL

> 原文：同一任务连续两轮只执行一次；第二个实例启动必须因锁退出。

| 证据 | 读数 |
|---|---|
| 单实例锁机制 | **齐备**：OS 级原子创建（js `flag:'wx'`）+ mtime stale 回收（`AGENT_LOCK_STALE_MS=30_000`）+ 三档可分辨 `LockResult{Acquired,HeldBy(String),Failed(String)}` |
| 锁冲突行为 | `run_agent_serve`（`:607-620`）持锁冲突时回 **rc=0** 并明说「已有 worker 持锁（pid N）」——按 issue 语义「第二个实例必须明确退出」，rc=0 的取值需 owner 裁决（见 §五 R2） |
| 测试 | `cmd/cli/subcmd_wbtest.mbt` 对 `agent` 的引用数 = **0**；全仓无 `agent.mbt` 的行为锁 |
| 「同任务两轮只执行一次」 | 不可验：一轮只领一条（`--max-tasks-per-tick` 未接）；claim 后无执行，第二轮会再次 claim 同一任务（状态机在 `待领取→已领取`，而 claim 谓词是 `is_pending()`）——**这里有个真实的行为风险**：claim 后若任务未推进到非 pending，下一轮会重复领取 |

⇒ 锁本身合格；**幂等语义未闭合**（claim 成功但无 execute/submit 推进 ⇒ 同一任务可被反复领取），且无测试。

### 标准 6 · 失败不假绿 —— ❌ FAIL

> 原文：executor 非 0 ⇒ 任务 `blocked` + `failure_reason`，消息进 `failed/`，不回 inbox。

| 证据 | 读数 |
|---|---|
| 失败路径 | 不存在（无执行器 ⇒ 无非 0 退出可发生） |
| `failure_reason` 字段 | 属 MCP `execute` 工具的 schema/实现（`src/server/server.mbt:3089`/`:3118`），**worker 侧未填** |
| `failed/` 目录移动 | 不存在（同标准 3） |
| 骨架里唯一的「不假绿」 | `claim_failed:<e>` 如实记进 `note`（`:476-478`），且不再试下一条——**这是合格的一半**，但离验收 6 的完整链路还差执行与回写 |

⇒ 验收 6 的触发条件不可达。

### 标准 7 · 黑盒可拉起 —— ❌ FAIL

> 原文：只用 `dist/fist-mbt.js` + Node≥24，不装 MoonBit，`fist agent serve --once` 可跑通。

| 证据 | 读数 |
|---|---|
| `node dist/fist-mbt.js agent serve --once --dry-run` | `未知子命令: agent`，**rc=2** |
| dist 是否含 agent | `grep -c "agent-service"` = **0**；`grep -c "fist agent"` = **0** |
| dist 版本 | `FIST-Mbt v0.3.11`（实跑 `version`），而 `moon.mod:14` = **`0.3.15`** ⇒ 落后 4 个版本 |
| dist 构建时间 | `2026-11-17 10:32`，早于骨架落盘（11-25） |
| dist 快照守卫 | `python scripts/check_dist_snapshot.py` 实跑 **REAL_RC=1**，报「描述面：判定 190 条 · 命中 169 · 旧句 21」（src 已改口、dist 烤着旧句） |
| Node 门 | 门只注入 `_build` 目标 bundle（T0r84 §3.2）；**dist 顶部无 `FIST_MBT_MIN_NODE_MAJOR`**（T0r84 §四缺口 1） |
| `refresh_dist.py` 能否现在刷 | **不能**：脚本要求 WIP 已全部提交，当前工作树 116 处脏 |

⇒ 「不装 MoonBit 也能跑通」这条黑盒验收**当前不可能通过**：产物里根本没有这个子命令。

### 标准 8 · 不依赖 cron —— ✅ PASS（附条件）

> 原文：验收过程不得创建 schtasks/systemd/cron；会话内后台进程即可。

| 证据 | 读数 |
|---|---|
| `schtasks` / `systemd` / `crontab` 在 `cmd/` `src/` 的 `.mbt` 面 | **零命中** |
| 骨架自身 | 零命中；它用「取锁 + 轮询循环」实现常驻（`agent_io_sleep(AGENT_POLL_INTERVAL_MS)`，默认 15s） |
| 计划卡/安装器面 | 无定时器注册动作（`install.ps1` 只有版本门与下载） |

⇒ **无违例**。这是唯一一条在骨架设计层面就满足的标准。附条件：**这不代表 issue 闭环**——它只是「没做被禁止的事」。

### 标准 9 · 会话关闭行为 —— ⚠️ N/A（不可验）

> 原文：进程随会话结束而退出；重启后能读回状态，不重复领取。

| 证据 | 读数 |
|---|---|
| 进程随会话退出 | 无进程可起（标准 1 已 FAIL）⇒ 不可观测 |
| 重启读回状态 | `agent_load_state_or_new()`（`:514-528`）**存在**，能从 `state.json` 恢复 rounds/status |
| 「不重复领取」 | 同标准 5 的风险点：claim 谓词只认 `is_pending()`，骨架无 execute/submit 推进 |
| 测试 | 无 |

⇒ 机制存在、**行为不可验且幂等语义存疑**。判 N/A 而非 FAIL，以免把「测不了」写成「做错了」。

### 标准 10 · CI 新增 agent_service 白盒/黑盒测试 + 变异对照 —— ❌ FAIL

> 原文：新增 `agent_service` 白盒/黑盒测试，含变异对照（去掉锁/去掉领取/去掉失败回写必须红）。

| 证据 | 读数 |
|---|---|
| 白盒锁 | `cmd/cli/subcmd_wbtest.mbt` 的 agent 引用 = **0**；无 `agent_wbtest.mbt` |
| CI 登记 | `.github/workflows/*.yml` 内 `agent_service_wbtest` / `agent.mbt` / `subcmd_wbtest` 引用 = **0** |
| 电池登记 | `scripts/run_guards.py` 有 `blackbox/e2e_agent_service_http.py`（:183）等 **agent 网关/注册表**族，但那是 `agent_service_*` **MCP 工具**（另一物），**不是**本 worker |
| 易混淆点（诚实标注） | `src/engine/agent_service_wbtest.mbt` 与 `engine.mbt` 的 `agent_service_*` 是**服务登记表**测试，与 issue #1 的会话内嵌 worker **不是同一个 entity** |
| 变异对照 | 无从谈起：被测机制（锁/领取/失败回写）在可运行产物里不存在 |

⇒ 验收 10 要求的「去掉锁必红 / 去掉领取必红 / 去掉失败回写必红」三格变异对照**一格都没有**。

---

## 三、前置缺口两格的现状（issue 附录点名，逐格核）

| 前置缺口 | 现状 | 证据 |
|---|---|---|
| Node 版本门（`dist/fist-mbt.js serve` 在 Node<24 应有明确拒绝） | **半收口**：`_build` 目标 bundle 已带门并被判据锁死；**dist 快照无门** | T0r84 实测合成两向 22→rc=1 / 24→rc=0，`check_esm_bundle_runnable.py --selftest` 42 格全绿；`dist` 顶部无 `FIST_MBT_MIN_NODE_MAJOR`（T0r84 §四-1） |
| HTTP 桥识别 dist（`scripts/run_fist_mbt_http.py`） | **已收口（HEAD 版即含）** | HEAD 版 `run_fist_mbt_http.py` 有 `DIST_SERVER_JS`(:78) / `resolve_server_js()`(:85) / 解析链 `_build > target > dist`；`git status` 对该文件**干净** ⇒ 已入库 |

⇒ 前置缺口 2 完成；前置缺口 1 剩 dist 那一半（受「脏树不可刷新」阻塞）。

---

## 四、最小改动面（让标准 1 可达；本轮不执行）

按依赖排序，三块均**不动 server、不动池目录实体**：

| 块 | 落点 | 改动 | 解什么 |
|---|---|---|---|
| ① 接线 | `cmd/cli/subcmd.mbt` | `Subcmd` 加 `Agent`；`parse_subcmd` 加 `"agent" => Agent` | 入口存在（标准 1/7） |
| ① 接线 | `cmd/cli/main.mbt` | 分发臂加 `Agent => run_agent(args)`；新增 `run_agent` 透传 `agent` 之后的二级子命令与旗标 | 同上 |
| ① 接线 | `cmd/cli/help_topics.mbt` | **无需再改**——`help_cli()` 的 agent 行已在工作树版（`:50`），但随该文件的版本号/计数改动一起卡在未提交态（见 R9） | P3 文档面（已完成一半） |
| ① 接线 | `cmd/cli/subcmd_wbtest.mbt` | **同批**补 agent 词法/旗标白盒锁（现 0 引用） | 标准 10 的前置 |
| ② 旗标 | `cmd/cli/agent.mbt` | `parse_agent_flags` 加 `--project-dir/--namespace/--msg-pool/--task-pool/--interval/--agent-id/--executor/--auto-verify`（保持未知即拒） | 标准 2/3/4 的入口参数 |
| ③ 池源 | `cmd/cli/agent.mbt` | `agent_run_once` 候选面从「内存 store Pending」扩到「消息池 → YAML backlog → MCP」 | 标准 2/3 |
| ④ 执行链 | `cmd/cli/agent.mbt` | `--executor` 模板替换 + 超时 + stdout/exit 收集 + `execute/submit` + `failure_reason` | 标准 4/6 |
| ⑤ 黑盒 | `scripts/refresh_dist.py` | 在 WIP 收口后刷新 dist（连带修好 21 条旧句 + Node 门） | 标准 7 |

⚠️ **两个必须同批的纪律项**（本仓既有教训，写在这里避免下一个人踩）：

1. `agent.mbt` 一旦入跟踪面即为**新增 `.mbt` 面** ⇒ 同批给行为锁（否则覆盖判据类门会红）。
2. `help_topics.mbt` 的 agent 行**已在工作树未提交**（`git status` = ` M cmd/cli/help_topics.mbt`）——接线时须确认这行是他方 WIP 还是前序轮的遗留，避免局部提交带走他人 hunk（判例：`git commit -- <file>` 落 working-tree 整份版本）。

---

## 五、缺口与风险

| # | 缺口 / 风险 | 影响 |
|---|---|---|
| R1 | 骨架未接线 + 未跟踪 ⇒ 10 条标准里 8 条直接 FAIL | 门禁不通过的单一主因 |
| R2 | 锁冲突返回 **rc=0**（`:610-615`），而 issue 说「第二个实例必须明确退出」——退出码语义需 owner 裁决（rc=0 在 CI 并发下更稳，但与「失败可见」冲突） | 影响验收 5 的判读 |
| R3 | claim 谓词只认 `is_pending()`，骨架无 execute/submit 推进 ⇒ **同一任务可被反复领取** | 幂等语义存疑（比「没测试」更实质） |
| R4 | `--once` 收尾会 `agent_mark_stopped()`（`:630-635`）⇒ `--once` 后 status 显示 stopped，与标准 1 的「running」不同场景，判读时勿混 | 验收判读口径 |
| R5 | `docs/agent-service-skill.md`（8905B，13:30 落盘）**未跟踪**；USAGE §11.2 已入库且已如实标注「尚未接线」 | P3 文档面半成品 |
| R6 | 跨机介质空仓 + 四池四处口径分歧（T0r89 D2/D3） | 验收 3 与 P2+ 的真接线 |
| R7 | `check_dist_snapshot.py` 现 **RC=1**（21 条旧句 + 版本落后）⇒ 任何「dist 可拉起」验收前必须先刷新 | 验收 7 的硬前置 |
| R8 | 本轮只读，未做任何改动、未提交、未跑 `moon test`（无编译面改动） | 交付物 = 本报告 |
| R9 | `cmd/cli/help_topics.mbt` 的工作树版**已含** agent 行（`:50`），但同文件还带着 `FIST_VERSION 0.3.11→0.3.15`、`183→188 工具`、Query/Board-DAG 分组等多处他方计数改动 ⇒ **agent 行与版本号耦合在同一 hunk 里**，接线提交时若 `git commit -- cmd/cli/help_topics.mbt` 会把这些一并落盘 | 局部提交须先甄别该 hunk 归属（判例：working-tree 整份版本落盘） |

---

## 六、资源消耗

- 读取面：issue #1 正文（REST）、计划卡、`cmd/cli/{agent,subcmd,main,help_topics,moon.pkg}`、
  `scripts/{run_fist_mbt_http,refresh_dist,check_dist_snapshot,run_guards}.py`、
  `docs/agent-service-skill.md`、`USAGE.md §11.2`、`reports/2026-11-25-T0r8{4,5,7,8,9}-*.md`
- 实跑命令：`node dist/fist-mbt.js {version,agent status,agent serve --once --dry-run}`、
  `node _build/.../cli.js agent status`、`python scripts/check_dist_snapshot.py`
- **未跑**：`moon test` / `moon check`（本轮零代码改动，无编译面）

---

## 七、来源

- 对表原文：`GET https://atomgit.com/api/repos/VictorTop/Fist-Mbt/issues/1`（issue id 4607262，state=open，`updated_at=2026-11-25T13:32:02+08:00`）
- 计划真源：`fist-mbt/plan/active/2026-11-25-fist-agent-worker-issue1.md`（7 个工作项全 `[ ]`）
- 骨架：`cmd/cli/agent.mbt`（771 行，untracked）、`cmd/cli/agent_js.mbt`、`cmd/cli/agent_native.mbt`
- 接线落点：`cmd/cli/subcmd.mbt`、`cmd/cli/main.mbt:40-59`、`cmd/cli/moon.pkg:19-21`、`cmd/cli/subcmd_wbtest.mbt`
- 产物：`dist/fist-mbt.js`（11-17，v0.3.11）、`_build/js/debug/build/cmd/cli/cli.js`（11-25 11:21）
- 同族报告（本轮结论与其一致，互为佐证）：
  `reports/2026-11-25-T0r87-executor-writeback-inventory.md`（P1 不存在）、
  `reports/2026-11-25-T0r89-crossmachine-pool-wiring-report.md`（D1/D2/D3）、
  `reports/2026-11-25-T0r84-node-version-gate-report.md`（前置 1）、
  `reports/2026-11-25-T0r85-http-bridge-dist-report.md`（前置 2）、
  `reports/2026-11-25-T0r88-msg-pool-atomic-rename-report.md`（P2 消息池）
