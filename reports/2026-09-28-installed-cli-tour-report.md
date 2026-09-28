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
