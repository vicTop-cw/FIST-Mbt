# T0r89 · P2+ 跨机云机器接线 · 只读盘点报告

- 任务号：`T0r89`（`autoplan`，`assignee=atomcode`，`status=执行中`，`created_by=human_steward`）
- 口径来源：`fist-mbt/plan/active/2026-11-25-fist-agent-worker-issue1.md` §P2+
- 约束：**只读盘点 / 最小改动**；本报告不动代码、不动池目录、不 push、不 merge
- 日期：2026-11-25
- 取证脚本：`temp/_t0r89_pool_paths_probe.py`（只读、只打 stdout，不入跟踪面）

## 1. 结果摘要

本轮把「P2+ 跨机云机器接线」从散文读成了可执行读数，结论是**当前不存在一条端到端可运行的跨机链路**，
卡在三个互不相关的断点上，且三处都已各有半成品件：

| # | 断点 | 实测证据 |
|---|---|---|
| D1 | **worker 侧命令未接线** | `cmd/cli/agent.mbt` 存在（604 行、P0 骨架完整）但**未被 git 跟踪**，且 `main.mbt` 的分发臂里没有 `Agent` 分支；用现有产物实跑 `node dist/fist-mbt.js agent status` → `未知子命令: agent`，rc=2 |
| D2 | **跨机介质是空仓** | 伴生仓 `https://gitcode.com/VictorTop/fist-msg-pool.git` `HEAD == refs/heads/main == b1992a0c…`，`git clone --depth 1` 后**只有 1 个文件 `README.md`**，正文仅一句「分项目区 inbox/processed」，无任何 `inbox/` `processed/` 实体目录 |
| D3 | **四池路径口径四处不一致** | 同一个「消息池」在仓内被四个不同路径声明（下表），桥与 worker 各读各的；`crosspool_bridge.py` 与 `cmd/cli/agent.mbt` 都是 `<none>` |

**一句话交付**：P2+ 的「真接线」在当前树上是 **0**——不是「做了但没验」，是三个面各自缺一块。
最小改动面 = ①把 `agent.mbt` 接进 `main.mbt` 并跟踪落库；②按 D3 选定**唯一**路径口径并把三份实现收敛到它；
③在伴生仓建出目录骨架（这一步默认不 push，留 owner）。

## 2. 四池路径口径：四处不一致（D3）

同一概念「消息池」在六个落点上被指到四个不同路径。下表由 `temp/_t0r89_pool_paths_probe.py`
按字面量正则扫出（`<none>` = 该文件不含任何已知池路径常量）：

| 落点 | 声明的路径 | 语义 |
|---|---|---|
| `scripts/git_pool_bridge.py` | `.fist-mbt/msg/{inbox,processed,.failed}` | T0r70 的 git 桥（export/import/--watch/msg sync） |
| `scripts/crosspool_bridge.py` | `<none>`（根由 `--a-root/--b-root` 现给，函数 `pool_root()` 内部拼 `<base>/pool/messages`） | T-XPOOL-1 shared-path 搬运 |
| `scripts/pool_contact.py` | `.fist-mbt/pool/messages/{inbox,outbox,archive}` + `.commissar/` | T-XPOOL-2 统一联系层（auto/pool/direct） |
| `cmd/cli/agent.mbt` | `<none>`（P0 骨架不碰消息池，只操作 SQLite + 状态文件） | issue #1 的会话内嵌 worker |
| `.fist-mbt/pool/README.md` §3/§3.2 | `.fist-mbt/pool/messages/{inbox,outbox,archive}` | 治理文档真源 |
| 计划卡（P2+ 原文） | `.fist-mbt/pool/messages`，并括注「**大写 F 实测口径**」 | 派单口径 |

> 「大写 F 实测口径」的含义已在读数里落实：`.gitignore` 同时有 `/.Fist-Mbt/`（:233，大写）与
> `/.fist-mbt/`（:234，小写）两条，而磁盘上的实际目录是小写 `.fist-mbt/pool/`——
> Windows 大小写不敏感使两条都命中，Linux CI/WSL 靠小写那条命中。计划卡的括注是在提醒
> 「真机盘上是哪个目录名」，不是两套池。

### 2.1 命名分歧清单（可逐条收敛的最小改动面）

| 维度 | 口径 A | 口径 B | 冲突点 |
|---|---|---|---|
| 顶层目录 | `.fist-mbt/msg/` | `.fist-mbt/pool/messages/` | 完全不同层级 |
| 出站目录 | `outbox/` | `processed/` | 语义不同（待搬 vs 已处理） |
| 失败目录 | `.failed/` | 无 | git 桥独有 |
| 归档目录 | 无 | `archive/` | 跨机桥独有 |
| 介质根 | `<项目名>/{inbox,processed}/`（伴生仓分区） | `<root>/pool/messages/`（本地池） | **跨机介质与本地池是两套物理布局** |

**裁决建议（留给 owner，不在本轮执行）**：把「跨机介质布局」与「本地池布局」**显式分成两个常量面**，
不要继续用同一个词指两处——这正是 `pool/README.md` §3 说的「两种介质、两套目录」，
但 `git_pool_bridge.py` 与 `pool_contact.py` 各自实现了其中一套，中间缺一个「谁把本地 outbox 搬进
伴生仓 `<项目名>/inbox`」的搬运步。

## 3. worker 侧断点：`agent` 子命令存在但未接线（D1）

### 3.1 文件态实测

| 检查 | 读数 |
|---|---|
| `cmd/cli/agent.mbt` 行数 | 604 行，含完整 P0 骨架（锁/心跳/状态机/一轮） |
| `git ls-files cmd/cli/agent.mbt` | **未跟踪**（`pathspec did not match any file(s) known to git`） |
| `cmd/cli/subcmd_wbtest.mbt` 内 agent 引用 | **0 处**（无白盒锁） |
| `cmd/cli/main.mbt` 分发臂 | `Serve/Version/Demo/Doctor/Upgrade/Help/NoArgs/Unknown` —— **无 `Agent` 分支** |
| `cmd/cli/help_topics.mbt` | 仅 `[Other 12]` 行里的 MCP 工具名 `agent_acl_grant` 等；**无 `fist agent` CLI 用法** |
| `node dist/fist-mbt.js agent status` | `未知子命令: agent` + help，**rc=2** |
| `node dist/fist-mbt.js agent serve --once --dry-run` | 同上 rc=2（产物构建于 11-17，早于本轮） |

⇒ **`fist agent serve` 这条「云机器侧按 issue 2.1 同一命令拉起 worker」的命令，当前在本机不可用**。
这是 D1 的直接证据：不是文档没写，是**入口不存在**。

### 3.2 `agent.mbt` 本身已就绪的部分

模块自带完整词法与退出码契约（与 `subcmd.mbt` 同构），并实现了：

- 单实例文件锁 `agent.lock`（`AGENT_LOCK_STALE_MS = 30_000`，取不到就退，`--once` 下不算失败）；
- 状态机三态 `running / stopped / stale`（不设隐式退出路径）；
- `state.json` + `worker.log` 落 `<data_dir>/agent-service/`，改道针跟随 `FIST_DB_PATH`
  （`agent_service_dir()` 每次现算不缓存）；
- 一轮 `agent_run_once()`：心跳 → list → claim → task-packet → 回执骨架，
  且 `--dry-run` 时 `mutate=false`（照读照算但不写状态文件、不改库）。

**⇒ 缺的只有「接线」**：`parse_subcmd` 加 `Agent` 分支 + `main.mbt` 分发 + `moon.pkg` 无需改（同包）+
`user_first_arg` 之后的参数透传（`agent` 之后还有二级子命令）。这是**最小改动面的第①块**。

> ⚠️ 注意 P0 骨架与派单口径的一个落差：`agent.mbt` 只读 **SQLite 任务池**（`engine.claim`），
> **完全不碰消息池**（对四条路径正则全 `<none>`）。而 P2+ 要的是「轮询仓库任务池/消息池」。
> 所以即便接线完成，P2+ 仍差「消息池读取」这一层——见 §5 末段与 §6 块①/②。

## 4. 跨机介质实况：伴生仓是空仓（D2）

| 检查 | 读数 |
|---|---|
| `git ls-remote --symref https://gitcode.com/VictorTop/fist-msg-pool.git` | `HEAD → refs/heads/main`，SHA `b1992a0c6f206b41f993d5a73399111ed1658d20` |
| `git clone --depth 1` 后文件清单 | **仅 `README.md`** |
| README 正文 | `# fist-msg-pool` + 「fist-agent 跨机消息转发池（非 git 项目伴生仓）：分项目区 inbox/processed」 |
| 实体目录 | **不存在** `inbox/`、`processed/`（clone 出的树里没有任何子目录） |

⇒ 「以 GitCode 伴生仓为跨机介质」在**远端侧只有意图声明，没有可投递的目录结构**。
在远端建出 `<项目名>/{inbox,processed}/` 之前，任何「真接线」都会因目标目录不存在而落空。

> 顺带核实的两条环境前提：`GITCODE_TOKEN=True`、`GITHUB_TOKEN=True` 均在场（凭据可用，本轮**未使用**）；
> 本机 `wsl.exe -l -q` 返回**空发行版列表**（rc=0 但无输出）⇒ 计划卡说的「WSL 共享」当前也不是可用介质，
> `pool/README.md` §3.2 记的「`wsl.exe` 存在但无发行版」在此刻复现成立。

## 5. 互操作判据现状（派单点名项）

派单要求「与 `crosspool_bridge.py` 互操作判据」。实测：

| 项 | 读数 |
|---|---|
| `scripts/run_guards.py` 电池格 | `case("crosspool_bridge.py", "--selftest")` 已在册（注释记 13 机制格 + 3 变异对照） |
| `scripts/crosspool_bridge.py --selftest` 自检存在 | 是（`run([...])` 合成双端池 + 幂等 + 完整性校验） |
| `scripts/pool_contact.py --selftest` | 在册（14 格），且 `blackbox/e2e_web_agent_pool.py` 提供 G1~G7 活体判据 |
| **`git_pool_bridge.py` 的自检** | **无 `--selftest`**（`argparse` 只有 `--watch/--once/--db/--interval/--workdir`），且 `run_guards.py` / `scripts/README.md` **均无它的登记条目** ⇒ 它既不在电池也不在 REGISTRY |
| **互操作判据覆盖 `git_pool_bridge` ↔ `crosspool_bridge`** | **无**（跨实现互操作只有 Go↔Python 那条，见 `.fist-mbt/data/reports/fist-agent-pool-contact-2026-11-24.md` G3） |

⇒ 派单点名的「互操作判据」目前**只覆盖 `crosspool_bridge` 自己**；
`git_pool_bridge` 是那个唯一指向 `.fist-mbt/msg/` 的件，**既无自检也无登记**，
是 D3 收敛时必须一起处理的落点。

## 6. 最小改动方案（三块，按依赖排序；本轮不执行）

> 红线对齐：不 push、不 merge、全程无窗、server 保持被动不改造、执行器外置。
> 三块都**不动 server.mbt、不动池目录实体**。

### 块① worker 入口接线（解 D1，纯本地可验）

| 落点 | 改动 |
|---|---|
| `cmd/cli/subcmd.mbt` | `Subcmd` 加 `Agent`；`parse_subcmd` 加 `"agent" => Agent` |
| `cmd/cli/main.mbt` | 分发臂加 `Agent => run_agent(args)`；新增 `run_agent` 解析二级子命令（`serve/status/stop/run` + `--once/--dry-run`）并转 `cmd/cli/agent.mbt` 的 `parse_agent_cmd` / `agent_run_once` |
| `cmd/cli/help_topics.mbt` | `help_cli()` 补一行 `fist agent serve\|status\|stop\|run`（否则 P3 文档项缺 CLI 面） |

验收（可本机跑）：`node <新产物> agent status` rc=0 且打状态；`--dry-run --once` 不改库不写状态文件；
锁冲突格（同一 `agent.lock` 两进程）必退；**`moon check` + js 门全绿**。

⚠️ 该块落地即产生**跟踪面新文件**（`cmd/cli/agent.mbt` 目前 untracked）⇒ 按本仓「往 scripts 加 .py 必须同批给执行面」
的同族纪律，`agent.mbt` 入库需**同批**给白盒锁（`subcmd_wbtest.mbt` 现 0 处 agent 引用）——
否则 `check_mbti_sync` / 覆盖判据类门会红。

### 块② 四池路径口径收敛（解 D3）

**裁决先行**：定一个唯一真源常量（建议 `.fist-mbt/pool/messages/{inbox,outbox,archive}`，
因为它是 `.fist-mbt/pool/README.md` §3.2 已写的治理口径，且 `pool_contact.py` 已按此实现），
然后把 `git_pool_bridge.py` 的 `.fist-mbt/msg/{inbox,processed,.failed}` **改为读配置面**
（不硬编码第二套）——或反向裁决为 `.fist-mbt/msg/`，把桥与文档一起改。**两个方向二选一，都由 owner 定。**

同批必做（否则就是判例-5 族「改了机制漏了锚」）：

- `scripts/git_pool_bridge.py` 补 `--selftest`（全程 tempfile 沙箱）+ 在 `run_guards.py`
  手写点名一格 `case(...)` + `scripts/README.md` 登记条目；
- 补一条**互操作判据**：`git_pool_bridge` 写出的信封被 `crosspool_bridge.py read/verify` 解开
  （复用后者的 KDF/token 口径），全程沙箱——这条正是派单点名的那格。

### 块③ 跨机介质骨架（解 D2，默认不 push）

在伴生仓建 `<项目名>/{inbox,processed}/`（`<项目名>` 取 worker 侧登记身份），
连同 README 的分区说明落成可投递结构。**默认不 push**（派单红线：P2 的 git push 可配置关闭）；
真要推时走 `GITCODE_TOKEN` 环境变量、由 owner 确认。

云机器侧拉起命令（issue 2.1 同一命令）：`fist agent serve --once`（或 `--watch` 变体），
依赖块①接线完成 + 块②口径统一。

## 7. 缺口与风险

| # | 缺口 / 风险 | 影响 |
|---|---|---|
| R1 | `agent.mbt` 未跟踪且未接线 ⇒ 云机器拿不到「同一命令」 | 块①不做则 P2+ 无法开工 |
| R2 | 伴生仓无目录骨架 ⇒ 跨机投递无处落 | 块③不做则真接线是空转 |
| R3 | 四池四处口径分歧，`git_pool_bridge` 无自检无登记 | 收敛前任何「跨机链路」结论都不可信 |
| R4 | 计划卡括注「大写 F 实测口径」易被误读成两套池 | 已在 §2 澄清；若 owner 另有定义需在裁决里推翻本报告 |
| R5 | 本机 `wsl.exe` 无发行版 ⇒ 「WSL 共享介质」路径当前不可用 | 真介质只剩 Git 远端或 UNC；UNC 实测 `//127.0.0.1/E$/...` 不可达 |
| R6 | 本轮为只读盘点，**未做任何改动**（无代码、无池目录、无远端） | 交付物 = 本报告 + 取证脚本；最小改动方案待 owner 裁决后另立任务 |

## 8. 来源

- 计划真源：`fist-mbt/plan/active/2026-11-25-fist-agent-worker-issue1.md`（P2+ 条）
- 取证脚本：`temp/_t0r89_pool_paths_probe.py`（本轮新建，只读；`temp/` 不入跟踪面）
- 实跑命令：`git ls-remote --symref` / `git clone --depth 1`（伴生仓）、
  `node dist/fist-mbt.js agent status|serve`、`python temp/_t0r89_pool_paths_probe.py`
- 对表件：`cmd/cli/{main,subcmd,agent}.mbt`、`scripts/{git_pool_bridge,crosspool_bridge,pool_contact,run_fist_task_pool}.py`、
  `scripts/run_guards.py`、`.fist-mbt/pool/README.md`、`.gitignore:233-234`
- 已有实证：`.fist-mbt/data/reports/crosspool-sim-report-2026-11-24.md`（T-XPOOL-1）、
  `.fist-mbt/data/reports/fist-agent-pool-contact-2026-11-24.md`（T-XPOOL-2）

