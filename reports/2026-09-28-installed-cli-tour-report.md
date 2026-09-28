---
AIGC:
    Label: "1"
    ContentProducer: 001191440300708461136T1XGW3
    ProduceID: installed-cli-tour-report
    ContentPropagator: 001191440300708461136T1XGW3
    PropagateID: installed-cli-tour-report
---

# 2026-09-28 · 安装面自证：以用户身份装，再用装好的全局命令把 129 工具打一遍

盖章时间：`2026-09-28T05:08:42Z`（写这份汇报时的 UTC 瞬间，非本地钟点换算）
承接目标（逐字）：「fist-mbt 有更新，说是全弄好了，你现在作为用户的身份 使用 irm 命令安装，并测试验证，验证方式：用新安装的fist-mbt 全局命令对 本项目 做遗漏补缺，使其更完善，需要验证各个功能都能够使用」
被测产物身份：`C:\Users\victo\AppData\Local\FIST-Mbt\fist-mbt.js`（安装器落点），巡回时 sha256:99beda11（tools/list 自证=129）

## 结果摘要

- **一句话**：「说是全弄好了」在发布/安装面上不成立；本轮把它装到了能自证的程度，并且**用装好的全局命令**
  （`%LOCALAPPDATA%\FIST-Mbt\fist-mbt.js`，非仓库构建）对本仓做了一遍全工具调用面巡回，
  当场打死服务的两处（BUG-90/91）已修，另三处（BUG-92/93/94）带活证据入账待裁决。
- **安装（用户视角）**：`irm … | iex` 的两条下载源当时**双双 404**——GitHub 没有任何 release
  （`releases/latest` 404）、`release.yml` 对已打的 `v0.3.0`/`v0.3.0-beta` 标签 **0 次运行**、
  兜底 raw URL 写的是 `main` 而本仓 GitHub 默认分支是 `master`。⇒ 补了离线入口
  （`install_onecmd.ps1 -LocalZip` / `install.sh FIST_LOCAL_ZIP`），用**仓库内已提交的安装器**
  从本地 zip 装成 v0.3.1-beta，`fist-mbt help / doctor / demo / --version` 全过
  （doctor = 5/5 checks，含 SQLite 闭环 `pub=Ok(T0r4)`）。
- **调用面巡回（安装版 sha256:99beda11，tools/list 自证=129）**：
  - 写面（临时 box + 独立库）：**129/129 全部打到调用面** = `ok 81 / refused 42 / skipped 6 / crashed 0`，
    播种链 `publish → claim → plan(["T0.1","T0.2"]) → claim → execute → submit` 六步全 ok。
  - 读面（cwd=仓库根，真源码树 + 独立库）：`ok 78 / refused 44 / skipped 6 / crashed 1`，
    崩溃点是 `cost_stats` 无参调用（→ BUG-94），驱动复活 server 后把剩余工具跑完。
  - `skipped` 是本驱动的授权边界，不是产品缺口：`github_flush_execute / github_issue_close /
    github_issue_comment`（真出网）、`heal`（无 ns 全库回滚，历史事故 396 单/23 ns）、`delete`（不可逆）、
    `watchdog_tick`（会真派单）；`executor_run` 只 `dry_run=true`。
  - 逐字拒绝文案与参数留档：`temp/tour_evidence.txt`（42+6 条写面明细 + 读面崩溃行原文）。
- **修掉的两个 critical**：
  1. **BUG-90 存储隔离是假的**：`store_open(scratch=true)` 回 `data_dir=temp` 并建出 `temp/<ns>.db`，
     但那库是**空库**（tasks=0/call_log=0），任务行仍落仓库根 `fist-mbt.db`
     （实测行 `T0r496` + 8 条 call_log，ns='goalverify0928'）。根因：模块级 `engine` 写死
     `SqliteStore::open("fist-mbt.db")`，`MultiStore::get()` 全仓零调用。
     修法：`FIST_DB_PATH` 运维侧环境变量（与 `FIST_RUN_CHECK_ALLOW` 同族，调用方不能自我扩权）
     + 3 条白盒 + 新判据 `scripts/store_isolation_probe.py`。
     **承重对照（两态实测）**：修复前产物 9771abf9 → C1 RED / C2 GREEN；修复后 f24be5be → C1+C2 GREEN；
     `--selftest` 合成违例格也发红。
  2. **BUG-91 一次调用打死整个会话**：`run_check` 无上限累积子进程输出（`stdout += d`）。
     实测两态：同一无限输出夹具，修前 2.1s `RangeError: Invalid string length` 进程死；
     修后 6.6s 正常回执 `status=failed`、进程存活。修法：每流末 1 MiB + `stdout_capped/stderr_capped` 旗。
- **PowerShell 编码面（用户首屏）**：新增 `scripts/check_ps_encoding.py`（无 BOM + 非 ASCII ⇒ 违例，
  扫描面为空即 FATAL 不出假绿）。PS 5.1 的 `Parser::ParseFile` 实测：`native-env.ps1` **12 处**、
  `showcase.ps1` **5 处**解析错误，`demo.ps1` 0 处（能解析但中文输出乱码）；补 BOM 后**三档全部 0 处**。
  判据 + `--selftest` 现均 rc=0。
- **发布链**：`release.yml` 标签过滤 `v[0-9]+.[0-9]+.[0-9]+`（GitHub ref 过滤器不支持 `[0-9]` 类，
  实测 0 runs）→ `v*`；版本源改为正则读 `moon.mod`（本仓没有 `moon.mod.json`，上一版我自己写错过）；
  4 处入口路径 `cmd/main` → `cmd/cli`；`prerelease` 按标签是否含 `-` 推导。
- **全量面**：JS 后端 **529/529**（HEAD 基线 526 + 本轮 3 条新白盒），在 `git archive HEAD` 快照树
  `temp/relbuild` 里跑（避开并行改动面），`rc=0` 落 `temp/relbuild_test_r3.log`。native 本轮未复跑，不宣称。

## 资源消耗

- MCP 调用（安装版 server 侧，落独立库）：写面 129 + 播种 ~20，读面 129，探针/复现矩阵 ~14 次 server 起停；
  合计工具调用 ≈ 300，server 进程 spawn ≈ 14。
- 构建/测试：`moon test --target js` × 3（含一次失败重跑）、`moon build --target js` × 2、
  打包 zip × 2、安装 × 2（`-LocalZip` 离线）。
- 凭据面：全程未读 `.env`、未探测/回显任何 key；`github_*` 只打到 `env_check/queue_status/flush_plan`
  这一类纯读面（`force=false`，不发包）。

## 任务分配记录

- 本轮**未走 FIST 流水线**（用户先前指令：已知缺陷独立修，不走流水线），全程指挥官亲自执行 + 本地实测。
- 共享状态守护：仓库根 `fist-mbt.db`（6.6 MB，多轮共用）在巡回改判为"每轮独立库"后不再被写入；
  本轮早期那次（12:16 的 `mcp_sweep.py`）留下的 `ns=goalverify0928` 行与 call_log 行**照实入账**（BUG-90 正文），
  不做无痕抹除——它是该缺陷的活证据。
- 并行改动面未碰：`cmd/cli/*`、`src/ops/ops_loop*`、`scripts/gen_help_docs.py`、`scripts/patch_esm_main.py`、
  README 的 `fist help tools` 段落均属他人未提交工作，本轮只读不写。

## 遗留风险

1. **BUG-94（high，OPEN）**：`cost_stats` 无参调用在仓库根树 + 独立库上触发未捕获 `ERR_SQLITE_ERROR` 并杀死会话；
   同调用在 box 树上 ok。具体 SQL 未定位，第三棵树未复跑（归因边界已写进账）。
2. **BUG-92（medium，OPEN）**：状态机拒绝文案「split 要求状态 [待领取]，当前是 [待领取]」把调用方指回它已满足的那一档；
   实测真实前置是"根任务先 claim"。修在 `src/engine` 报错拼装，与并行面重叠，交裁决。
3. **BUG-93（medium，OPEN）**：15+ 处脚本/文档仍指退役入口 `cmd/main` 且不带 `serve`（清单见账本）；
   `cmd/main.js`(2,681,667) 与 `cmd/cli.js`(2,779,308) 两棵入口并存、产物不同 ⇒ 旧 E2E 的绿证明不了发布产物可用。
4. **两条既有文档红（归因不到本轮）**：`check_doc_surface` J4 与 `check_tools_sync` R3b 都点名
   `docs/SHIP-PLAN-BLACKBOX-v2.md`（:45/:52/:60）。该文件相对 HEAD **未修改**（`git status` 清单级证据），
   本轮没动它也没替它改。口径修法（删第二处版本自述 / 把"3 个工具"改成指向 BACKLOG 的相对表述）写在建议里。
5. **并行改动未登记**：`check_scripts_index` 在活树红于 `scripts/gen_help_docs.py`（他人未进索引的新脚本），
   不在本轮责任面内，不代登记。
6. **BUG-91 的锁还不在仓库里**：崩溃对照目前只活在 `temp/runaway_repro.py`（js-only 执行面没有 MoonBit 单测）。
   建议把 `store_isolation_probe.py` 同形的"输出上限判据"补成一条 `scripts/` 判据 + CI 步，是否升级交裁决。

## 后续建议

1. 真发一次 Release：`git push` 后打 `v0.3.1`，让 `release.yml`（已改 `v*` + `moon.mod` 版本源 + `cmd/cli`）
   产出 `fist-mbt-js-v0.3.1.zip`， then 用**字面** `irm https://…/install_onecmd.ps1 | iex` 做一次零参数安装。
   （推送与发布未获授权，本轮没做。）
2. 修 BUG-94：store 层 JS 桥把 sqlite 异常包成 `Err`；server 侧给工具分发加 catch-all，
   任何 handler 异常回 JSON-RPC error 而不是让进程退出——这条是"服务面鲁棒性"，值得单独一条判据
   （任意畸形调用后会话必须仍可响应）。
3. 修 BUG-93 时顺手加一条**入口清单守卫**：扫 `scripts/` 与 README 里的 `cmd/main` 字面 ⇒ 红，
   历史陈述文件豁免（照 J7 禁词判据同形，成本极低）。
4. 修 BUG-92 时给拒绝文案立一条成对判据：`要求态 != 当前态`，相等即判文案坏了（本项目对拒绝文案的一贯要求）。
5. 把 `mcp_tool_tour.py` 挂进 CI（它已经把"发布产物 + 129 工具 + 三面分栏"做成了一条命令）。

## 超额内容（本可以不做）

- 顺手把安装器的下载失败路径改成打印 HTTP 状态与候选 URL 清单（上一版吞异常，用户只能看到"换源"）。
- 巡回驱动第一版把崩溃后的 94 个工具全记成 `broken`——本轮把它改成"分诊 + 复活 + 继续数 + 基数自证"
  （`len(rows) != len(tools)` 直接 rc=2），并因此才发现我自己的明细表曾经丢过 123 行而结论仍报绿。

## 来源

- 判据/修复：`src/store/store_sqlite.mbt`、`src/store/store_db_path_wbtest.mbt`（新）、
  `src/store/moon.pkg`（+`moonbitlang/core/env`）、`src/server/run_check_js.mbt`、
  `scripts/check_ps_encoding.py`（新）、`scripts/store_isolation_probe.py`（新）、
  `scripts/mcp_tool_tour.py`（新）、`scripts/blackbox/install_onecmd.ps1`、`scripts/blackbox/install.sh`、
  `scripts/blackbox/install.ps1`、`.github/workflows/release.yml`、`.github/workflows/ci.yml`、
  `AGENTS.md`（守卫族 7→9）、`scripts/README.md`、`memory/bugs.md`（BUG-90~94 + FIXED 小记）。
- 证据：`temp/relbuild_test_r3.log`（529/529）、`temp/store_isolation_probe_*.json|.log`、
  `temp/runaway_repro_3d397a.log`、`temp/runcheck_repro_1ff69c.log`、`temp/tour_evidence.txt`、
  `temp/mcp_tool_tour_{write,read}_*.json`、`temp/install_r5.log`、`temp/install_r6.log`、
  `temp/tool-tour-*/tour-*.stderr.log`（4 GB OOM 原文）、`temp/goalverify0928.db`（空库）vs 根库行 `T0r496`。
- 上游对照：`scripts/blackbox/build_release.ps1:38`（发布入口 = `cmd/cli/cli.js`）、
  `scripts/mcp_smoke.py:29-46`（`params._meta` 协议契约真源）、`src/engine/omega_gate.mbt:136`（`output_truncated`）。


---

## 续段（盖章 2026-09-28T05:29:54Z）：BUG-94 定位到根因并修掉，读面复跑到绿

第一段把 BUG-94 记成"读面崩、写面 ok"的**归因边界**。本段把它推到底：

- **根因**：`executions` 表从来不在 `src/store/store_sqlite.mbt` 的 `create_schema` 清单里，
  只在**写**路径 `record_execution` 里 ensure。读路径 `StoreBackend::cost_stats` →
  `aggregate_stats` → `list_all_executions` 直接 prepare `FROM executions`，而 js 桥的
  `Database.prepare` 缺表时**抛异常**（不是返回 None）⇒ 未捕获异常打死 server。
- **第一段那条"写面 ok / 读面崩"的差别不是树，是顺序**：写面播种链里先跑过 `execute`（把表建出来了）。
  单独起 server 只读时，仓库根/无参、仓库根/带 ns、临时 box/无参 **三格全复现**
  `Error: no such table: executions`（`temp/cost_stats_repro_3c39fd.log`）。
- **修法两层**：① `executions_table_sql()` 进建表清单（新库开库即有表）；
  ② `cost_stats` 读前 ensure（**存量老库**没这张表时也能自保——只补①对老库无效）。
- **承重对照（同一判据两态实测）**：白盒 `src/store/cost_stats_executions_wbtest.mbt` 两条
  （开库即查表 / `DROP TABLE` 后只读聚合回零值）。HEAD 源码 + 该判据 ⇒
  `Total tests: 23, passed: 21, failed: 2`，两条红信息逐字 `Error: no such table: executions`
  （`temp/cs_lock_head2.log`）；修复后 ⇒ 该包 23/23、全量 JS 后端 **531/531**（`temp/relbuild_test_r4.log`）。
- **调用面复验（安装版 eb18f4f0）**：三种形态全部 `alive_after=True` 且回执
  `{"total_records":0,...,"by_executor":{}}`（`temp/cost_stats_repro_e51bb6.log`）；
  巡回两面 **129/129 打到调用面**：写面 ok 81 / refused 42 / skipped 6 / crashed 0，
  读面 ok 76 / refused 41 / skipped 12 / crashed 0。

## 续段自报的一个自身缺陷（BUG-98，已修）

读面把 `project_dir="."` 当探针项目，而 `.` 就是仓库根 ⇒ 驱动里的 `report_bug` **直接写进了真账本**
`memory/bugs.md`，一天内两发；其中 05:01 那一把编号推到了 90，而我 05:04 手写台账时按"89 条"的旧读数
分配 90~94 ⇒ **BUG-90 出现两个抬头**。处置：
- 两条垃圾条目改判 `FALSE_POSITIVE` 并逐条立据（重编号为 BUG-96/BUG-97，消除撞号）；
- 缺陷本体另立 **BUG-98（FIXED）**：`mcp_tool_tour.py` 增加 `READ_PLANE_SKIP`
  （report_bug / bug_fix / bug_mark_status / memory_consolidate / memory_gc / memory_link），
  读面一律 skipped 并写明理由；
- 判据：读面跑前跑后 `memory/bugs.md` 的 sha256 必须逐字相等 —— 实测
  `63cd8b2593587b63` == `63cd8b2593587b63`（`temp/ledger_hash_before_read.txt`）。
- 教训入档：**手写台账编号与工具发单不能并行数号**；改完脚本要先重新反解上界再落笔。

账本现状：97 条抬头、无重复 id = 83 FIXED / 9 DUPLICATE / 3 FALSE_POSITIVE / 2 OPEN（BUG-92 拒绝文案自相矛盾、
BUG-93 退役入口 `cmd/main` 散落 15+ 处）。仍未做：服务面级 catch-all（任何 handler 异常应回 JSON-RPC error
而不是让进程退出）——那是"一个工具打死会话"的总闸，本轮只堵住了具体通路。

## 补遗（2026-09-28T06:31:07Z）· 三件新收口与一处改判

| 项 | 结论 | 证据（逐字可回溯） |
|---|---|---|
| BUG-92 改判 | 误报（引用文案出自 cp936 乱码猜测）；真缺陷重报为 BUG-99 并修 | `temp/bug92_probe.log` 的 \u 转义回执 |
| BUG-93 修复 | 104 处 cmd/main→cmd/cli + 26 个启动点补 serve + 守卫 `check_entry_paths.py`（守卫族 9→10）| `temp/bug93_apply.log`、`temp/eg_prefix_run.log`(HEAD 树 119 违例)、`temp/eg_full3.log`(0 违例) |
| BUG-100 修复 | 读面 project_dir/data_dir 指向 temp/ 草稿项目 + 外溢硬门 | `temp/tour_read_plane_r2.log`(rc=2 抓到仓库根 ns 库)、`temp/tour_read_plane_r3.log`(GREEN 0 新建 0 改动) |
| BUG-101 修复 | run_serve 不再往 JSON-RPC stdout 打横幅（3 处）| `temp/smoke_e2e_proof.log`→`temp/smoke_e2e_proof3.log` MCP-SMOKE PASS |
| 全量 | JS `moon test --target js` **533/533** rc=0 | `temp/verify_eng_full.log` |
| 提交树自证 | `git archive` 327bb7a 干净树 **531/531** rc=0 | `temp/verify_327bb7a_test.log` |
| 账本 | 账本 100 条 = 87 已修 / 9 重复并入 / 4 误报 / 0 待修 | `memory/bugs.md` 抬头计数 |
| BUG-102 修复 | cl7 比较侧行尾归一 + `drift_keys` 分栏 + `gen_plugins --selftest` 四格进 CI；同一新克隆漂移 55 → 1（那 1 份是真未重生成），重生成后 rc=0 | `temp/cl_check_plugin_sync.out`（旧守卫 55 条）、提交 da47806 后复跑 cl7 PASS |
| BUG-103 修复 | 安装器版本真源改绑 moon.mod（空值即 exit 1）+ 新守卫 check_release_asset_names.py（守卫族 11）；不带参数时 URL 由 v0.3.0-beta 变 v0.3.0/fist-mbt-js-v0.3.0.zip；离线装完 doctor 5/5、serve 第一行 JSON、129 工具 |
| 已知红 | `gen_help_docs.py` 未登记（并行改动面的文件，本环不代改）| `temp/g_check_scripts_index.log` |

来源：本轮以用户身份安装的 `fist`（sha256:eb18f4f0）+ 仓库 `git archive HEAD` 派生树实测；
所有临时件在 `temp/`，历史面（memory/ reports/ CHANGELOG.md 既有段落）只追加未改写。

## 再补遗 · 自述面判据（BUG-104）（盖章 2026-09-28T07:31:34Z）

上一条补遗之后又追问了一件事：**「129 工具」有人钉着，「3 resources + 2 prompts」没有人钉**。

| 项 | 结论 | 证据（逐字可回溯） |
|---|---|---|
| 缺陷定位 | BUG-104（medium，入账即 FIXED）：AGENTS.md 自述的 resources / prompts 两面与 `serverInfo.version ↔ moon.mod` 无任何判据认领 | `AGENTS.md` 的 `Resources:` / `Prompts:` 两行 vs `scripts/check_doc_surface.py` 覆盖面（只解 tools 表） |
| 判据 | `scripts/mcp_tool_tour.py::surface_probe()`：期望值从 AGENTS.md 两行反解、与服务端实回**双向**对表；反解失败即自拒不报绿 | `temp/surf2_read_1790580101.log` 第 3 行、`temp/surf2_write_1790580144.log` 第 3 行（两行逐字相同） |
| 判据自证 | `--surface-selftest` 12 支对照：10 违例必红 + 干净支必绿 + 无声明行必自拒 ⇒ `SURFACE-SELFTEST: OK … 不符 0 支`；已作为独立一步进 `ci.yml`（`check-and-test-js` job） | `python scripts/mcp_tool_tour.py --surface-selftest` rc=0 |
| 调用面（安装态产物 sha256:**616b7632**） | read 面 129 工具 ok=76 refused=41 skipped=12 crashed=0 自述面红=0，且外溢判据取证面 172 项 0 新建 0 改动 | `temp/surf2_read_1790580101.log` |
| 调用面（同上） | write 面 129 工具 ok=81 refused=42 skipped=6 crashed=0 自述面红=0（临时 box + 隔离库，仓库根 `fist-mbt.db` 未动） | `temp/surf2_write_1790580144.log` |
| 实测自述面 | `resources=3(声明 3)[map=2182 overview=212 principles=606] prompts=2(声明 2)[check_in=1消息 verify=1消息] serverInfo=0.3.0 moon.mod=0.3.0` | 同上两份日志第 3 行 |
| 投影复算 | `gen_plugins` 重生成 + cl7 PASS（4 宿主 / 56 文件 / v0.3.0）；`check_doc_surface` J1-J10 PASS；账本 103 条 = 90 已修 / 9 重复并入 / 4 误报 / 0 待修 | `python scripts/check_plugin_sync.py` rc=0 |

两处对旧文字的**改判（不改写原文，只在此点名）**：
1. 上一段「来源」写的是 `fist`（sha256:eb18f4f0）；本段两条巡回跑的是**重装后**的产物 sha256:616b7632
   （含 BUG-101 的 stdout 净化与 serve 语义），旧 identity 只描述它当时那一批证据，不外推到本段。
2. 上一段表格 `BUG-103 修复` 行只有 2 格（缺第三格证据列），本表按 3 列补齐；
   那一行的证据其实存在（`temp/b103_*.log`），是当时漏排版 ⇒ 教训：**表格列数也是主张**，
   少一格的行在渲染时会被静默补空，正好看不到"这条没有证据"。

来源：本轮以用户身份安装的 `fist`（sha256:616b7632）+ 仓库工作树；临时件在 `temp/`，历史面只追加。
