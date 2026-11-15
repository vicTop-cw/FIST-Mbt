# 轮 330 唤醒巡检报告

**日期**：2026-11-16
**轮次**：r330
**执行者**：wd-r330（FIST-Mbt-ExploreWatchdog）

## 结果摘要

**WIP 非冻结增长后静止第 11 轮（numstat 与 r326~r329 逐字同）** —— `memory/bugs.md` 维持 **216/0**
（r329 后零再增长、无 BUG-637+ 新外来账），其余 5 个已跟踪 WIP 文件（`improvement-plan` 7/1、
`target.md` 1/1、`README` 2/1、`run_guards` 9/0、`engine_circuit_test` 5/0）与 2 个 untracked
（`check_mcpcf_db_isolation.py` 545 行、`pipeline_mode_loop.md` 211 行）**逐字同 r329**；
R192 车道自 r318 后持续停摆。`src/**` + `scripts/run_guards.py` 仍 M ⇒ **巡检分支**
（Round C 三件仍锁）。

换面巡检 `check_entry_paths`（BUG-93 入口清单守卫：可执行入口清单 = 扫 `cmd/*/moon.pkg` 带
`pkgtype(kind: "executable")` 的包、发布入口 = `build_release.ps1` 的 `moon build … cmd/<pkg>`、
退役入口 = 清单除发布入口之外项；扫描面 scripts/docs/.github/templates/stories/plugins/source/cmd +
根 `.md`/`.mcp*`/根入库 `.py` 共 **391** 份·历史面除外，**完全避开 WIP 面 `src/engine/`**）
selftest **rc=0**（17 格反解：R1 夹具命中 2 / 干净不误红 / 空清单报空转 FATAL / R2 缺 serve 成对 /
根 .py 选取〔入库留·未入库点名〕/ 根 .py 入面且活代码必红 / 根 .py 只改注释不误红 / 取不到 git 反向兜底 /
R3 裸相对产物必红 / R3 合法 join / cwd=ROOT 不误红 / R3 只改注释不误红 / R3 扫描面计数承重 /
5 支 e2e〔退役引用在注释不标 / 在代码标 / docstring 豁免不弱化代码面 / 用户面照标 / docstring 行切分〕）
+ 实测 **PASS rc=0**（入口清单 `cmd/cli`+`cmd/commissar`+`cmd/main`｜发布 `cmd/cli`｜退役
`cmd/commissar`+`main`：**R1 退役入口引用 0 处 / R2 缺 serve 启动器 0 个 / R3 裸相对产物寻址 0 处**；
注：仓库根另有 1 份未入库 `.py` 未判〔本机临时件 `execute_cron.py`，CI 检出里不存在〕）。

零漂移 `check_tools_sync` **183** / `check_instruction_budget` **50440/65536** 均 rc=0。Round C 三件
维持过期不执行。**FIST 闭环 T0r86 六步全链 rc=0**（wd-r330，ns watchdog，verify status=已完成、
completed_by=wd-r330，deliverable=本报告）。禁区零碰（8 WIP 文件含 bugs.md 零改零提交）。

## 巡检明细

1. **WIP 状态**（`git status --short` + `git diff --numstat`，本轮实读，逐文件对表 r329）：
   - `memory/bugs.md` **216+/0-**（与 r326~r329 逐字同 ⇒ **零增长**；无 BUG-637+ 新条目）；
   - 其余 5 个已跟踪 WIP 文件**逐字同 r329**：`improvement-plan` 7/1、`target.md` 1/1、`README` 2/1、
     `run_guards` 9/0、`engine_circuit_test` 5/0 ⇒ R192 车道面**仍静止**（自 r318 后无再推进）；
   - 2 个 untracked（`check_mcpcf_db_isolation.py` 545 行 / `pipeline_mode_loop.md` 211 行）未变。
   - 结论：**WIP 非冻结增长后静止第 11 轮**（r321 记非冻结增长第 1 轮 = vq BUG-636 落账；r322 静止第 2；
     r323 静止第 4；r324 静止第 5；r325 静止第 6；r326 静止第 7；r327 静止第 8；r328 静止第 9；
     r329 静止第 10；r330 本轮 = 静止第 11）。
   - 禁区处置：8 个 WIP 文件（含 bugs.md）**本轮零改、零提交**。

2. **换面巡检 `check_entry_paths`**（BUG-93 入口清单守卫·真源反解不硬编码；纯静态只读，
   扫描面与 WIP 面零交集）：
   - 自检：`--selftest` **rc=0**（17 格反解打印，不手写计数：R1 夹具命中 2 / 干净不误红 /
     空清单报「判据空转」FATAL〔没有退役入口就没有可漏的东西，此时报绿是骗人〕/ R2 缺 serve 成对 /
     根 .py 选取〔入库才判·未入库点名·取不到 git 反向兜底〕/ 根 .py 入面且活代码必红 /
     根 .py 只改注释不误红 / R3 裸相对产物必红 / R3 合法 join / cwd=ROOT 不误红 / R3 只改注释不误红 /
     R3 扫描面计数承重 / e2e-retired-in-comment-not-flagged / e2e-retired-in-code-flagged /
     e2e-docstring-exempt-does-not-weaken-code-face / e2e-user-face-still-flagged /
     e2e-docstring-line-splitter）；
   - 实测：**PASS rc=0** —— 入口清单 `cmd/cli, cmd/commissar, cmd/main`｜发布 `cmd/cli`｜退役
     `cmd/commissar, main`；扫描面 **391** 份文件（历史面与守卫自身除外）：**R1 退役入口引用 0 处、
     R2 缺 serve 启动器 0 个、R3 裸相对产物寻址 0 处**；
   - 注：仓库根另有 1 份**未入库**的 `.py`（`execute_cron.py`）未判——本机临时件，CI 检出里不存在，
     判据按「入库才判、未入库点名」口径如实报出（盲区可见，非静默放过）。

3. **零漂移双检**：
   - `check_tools_sync` rc=0（server.mbt 注册 183，AGENTS/README/deliverable/scoring_rubric 对齐；
     R3b/R7 扫现状面 168 份、历史面豁免 25 份；R8 清单分组 19 组 ΣN=183 对表一致）；
   - `check_instruction_budget` rc=0（AGENTS.md 50440 / 65536 字节，全部章节可见）。

4. **Round C 三件**：维持过期不执行——BUG-527 摘 cc-link-flags 已 owner 否决（CI A/B 实证有害）、
   BUG-530 已 FIXED（3699f012a）、`check_usage_tool_count` 已注册（run_guards.py:175）；`src/**` +
   `run_guards.py` 仍 M ⇒ 队列仍锁。

5. **FIST 闭环 T0r86 六步全链一发收口**（wd-r330，ns watchdog）：
   - 链脚本 `temp/fist_r330_chain.sh`（沿 r321~r329 稳健 TID 提取，逐行取能解析为 JSON 的那行）；
   - 六步 `publish / agent_acl_grant / claim / execute / submit / verify` 全 rc=0（后台一发收全），
     verify 回执 **status=已完成、completed_by=wd-r330**、deliverable=
     `reports/2026-11-16-r330-wakeup-patrol.md`（回盘 `temp/fist_r330_out/`）。

## 资源消耗

- 判据 4 支（1 换面巡检 check_entry_paths selftest + 实测 + 2 零漂移）+ WIP numstat 核验 1 支
  + FIST 六步链 1 发（后台串跑一次收全）；
- 本轮无子代理（巡检判据为轻量命令执行 + 只读核验 + FIST 链为网关记账，命令结果需指挥官亲阅终审，故直跑）。

## 任务分配记录

- **r330 FIST 闭环 T0r86 六步全链**（wd-r330，ns watchdog）：`temp/fist_r330_chain.sh`（稳健 TID 提取，
  六步全 rc=0），回盘 `temp/fist_r330_out/`（`1_publish..6_verify.txt` / `chain.log` / `task_id.txt`；
  verify status=已完成、completed_by=wd-r330）。

## 遗留风险

- **vq 外来账队列**：白名单外 **23 条（BUG-613~635）** + 契约不命中 1 条（BUG-636）待 owner 裁决
  （搬移 vq 仓 / 带理由登记 WHITELIST kind=foreign-adjudicated）；本轮账本零增长，规模与 r326~r329
  持平，同 BUG-565 持续模式，指挥官不代行清理、不立新账。
- **WIP 非冻结增长后持续静止**：`memory/bugs.md` 216/0 无再增长；四件套核心 R192 车道面自 r318 后
  无再推进（连续第 11 轮静止）。
- **owner 裁决件**（同 r321~r329，本轮无增减）：① WIP 四件套弃置 ③ r302 落账方式 ④ 外来账处置
  （BUG-613~636，规模 23+1）⑤ BUG-636（FIST 自留临时号）known-red 登记口径（②
  check_mcpcf_db_isolation.py 缺执行面/未注册已被 R192 车道推进消解）。
- **FIST 链提取鲁棒性（r318 遗留）**：29 份 `temp/fist_r*_chain.sh` 同形脆弱提取（本轮 +1）；
  durable 修复在 `scripts/fist.py`（notice→stderr / stdout 纯 JSON）或 tracked 链脚本模板稳健取
  JSON 行，留专门轮次。本轮稳健提取是**临时绕过**，非 durable 修复。
- **根未入库 `.py`**：`execute_cron.py` 本机临时件（未入库 ⇒ 判据按口径点名不判）；若其长期滞留且
  入库，会进 `check_entry_paths` 判定面——入库前需自核退役入口引用（当前未入库，无 CI 影响）。

## 后续建议

- **最高优先仍为 BUG-636（FIST 自留临时号·check_tool_coverage 盲区修复规格）**：待 `memory/bugs.md`
  WIP 解禁后专门轮次委派（含「加进 `_tool_registry.consumers()` 收口格」最易漏环节）。
- **vq 外来账队列（BUG-613~636）owner 裁决**：规模与 r329 持平（白名单外 23 条 + 契约不命中 1 条），
  裁决面完整，可一次批了。
- **FIST 链提取鲁棒性专门轮次修复**（口径见遗留风险）。
- 换面巡检下轮候选：`check_release_asset_names`（BUG-103~120 发布资产名↔安装器↔moon.mod 三处同源，
  纯静态只读、`--selftest` 反解格子、扫描面避开 WIP 面）；继续按注册面轮换，优先近期未轮过且
  有 `--selftest` 的判据。
- Round C 三件维持过期（owner 已裁决面），唤醒轮继续非阻塞巡检。

## 超额内容

无。

## 来源

- `git status --short` / `git diff --numstat`（2026-11-16 本轮实读：bugs.md **216/0**、其余 5 文件逐字同
  r329；2 untracked 未变：check_mcpcf_db_isolation.py 545 行 / pipeline_mode_loop.md 211 行）
- `reports/2026-11-16-r329-wakeup-patrol.md`（r329 WIP 基线 + per-file 拆分）
- `python scripts/check_entry_paths.py --selftest`（rc=0，17 格反解）+ 同判据实测
  （PASS rc=0：入口清单 cmd/cli+cmd/commissar+cmd/main / 发布 cmd/cli / 退役 cmd/commissar+main /
  R1 退役引用 0 / R2 缺 serve 0 / R3 裸相对寻址 0 / 扫描面 391 份 / 根 1 份未入库 .py 点名）（本轮）
- `python scripts/check_tools_sync.py`（183 PASS）/ `python scripts/check_instruction_budget.py`
  （50440/65536 PASS）（本轮）
- `temp/fist_r330_out/`（六步回执 + `chain.log` + `task_id.txt`，TID=T0r86，verify status=已完成）
