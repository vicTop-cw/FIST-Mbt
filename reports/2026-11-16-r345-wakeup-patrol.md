# 轮 345 唤醒巡检报告

**日期**：2026-11-16
**轮次**：r345
**执行者**：wd-r345（FIST-Mbt-ExploreWatchdog）

## 结果摘要

**WIP 非冻结增长后静止第 26 轮（numstat 与 r326~r344 逐字同）** —— `memory/bugs.md` 维持 **216/0**
（r344 后零再增长、无 BUG-637+ 新外来账），其余 5 个已跟踪 WIP 文件（`improvement-plan` 7/1、
`target.md` 1/1、`README` 2/1、`run_guards` 9/0、`engine_circuit_test` 5/0）与 2 个 untracked
（`check_mcpcf_db_isolation.py` 545 行、`pipeline_mode_loop.md` 211 行）**逐字同 r344**；
R192 车道自 r318 后持续停摆。`src/**` + `scripts/run_guards.py` 仍 M ⇒ **巡检分支**
（Round C 三件仍锁）。

换面巡检 `check_entry_paths`（BUG-93「**入口清单守卫**」：要钉的失效形状 = 入口搬家〔`cmd/main` →
`cmd/cli`〕后，脚本/文档/CI 仍指旧入口——于是「E2E 全绿」测的是**不发布**的那棵入口、用户按文档跑
的是另一棵。**真源不是硬编码**：可执行入口清单 = 扫 `cmd/*/moon.pkg` 里带 `pkgtype(kind:"executable")`
的包 / 发布入口 = `scripts/blackbox/build_release.ps1` 里 `moon build --target … cmd/<pkg>` 的那个
`<pkg>` / 退役入口 = 清单里除发布入口之外的项。判据：现状面〔脚本/文档/CI/根 `.md`/`.mcp*.json`/
**根入库 `.py`**，历史面除外〕不得引用任何退役入口。**BUG-118**（本轮）：扫描面曾不含仓库根 `.py` ⇒
`watchdog_tick_cron.py`/`pipeline_tick_cron.py` 写死退役入口 `cmd/main/main.js`、本守卫却打印「退役
入口引用 0 处」——**判据盲区比违例更贵**，所以 `--selftest` 里给新扫面配了成对格子〔真代码行必红 /
只改注释不许红〕。判据三向：**R1** 退役入口引用 / **R2** `Popen([node, cli.js])` 的 argv 必须带
`serve`（缺 serve 成对）/ **R3** 裸相对产物寻址〔合法 join 不误红、cwd=ROOT 不误红、只改注释不误红〕。
**判例-17 / R183** 区分「讨论」与「指令」：`.py` 的非执行文本两种承载形式——行首 `#` 注释行〔
`PY_COMMENT_LINE` 豁免〕+ 三引号 docstring 块〔作用与注释完全等同、Python 不执行〕都豁免，但
**docstring 豁免不得削弱代码面**〔e2e-docstring-exempt-does-not-weaken-code-face〕。扫描面含 WIP 的
`docs/improvement-plan` + `scripts/README.md` + untracked `scripts/check_mcpcf_db_isolation.py` +
untracked `templates/pipeline_mode_loop.md`，但**均只读、不触碰禁区**）selftest **rc=0**（**17 格**：
R1 夹具命中 2 / 干净不误红 / 空清单报空转 / R2 成对 / 根 .py 选取〔入库留/未入库点名〕/ 根 .py 入面且
活代码必红 / 根 .py 只改注释不误红 / 取不到 git 反向兜底 / R3 裸相对产物必红 / R3 合法 join /
cwd=ROOT 不误红 / R3 只改注释不误红 / R3 扫描面计数承重 / e2e-retired-in-comment-not-flagged /
e2e-retired-in-code-flagged / e2e-docstring-exempt-does-not-weaken-code-face /
e2e-user-face-still-flagged / e2e-docstring-line-splitter）+ 实测 **PASS rc=0**（**入口清单**：
`cmd/cli, cmd/commissar, cmd/main`｜发布 `cmd/cli`｜退役 `cmd/commissar, main`｜**扫描面 391 份**〔历史面
除外〕；注：仓库根另有 1 份未入库的 `.py` 未判〔本机临时件 `execute_cron.py`、CI 检出里不存在〕——
守卫「盲区必须可见」纪律如实点名；**PASS R1 退役入口引用 0 处、R2 缺 serve 启动器 0 个、R3 裸相对产物
寻址 0 处**〔扫描面 391 份文件、历史面与守卫自身除外〕）。

零漂移 `check_tools_sync` **183** / `check_instruction_budget` **50440/65536** 均 rc=0。Round C 三件
维持过期不执行。**无新发现（类型）、无新立账**（`execute_cron.py` 为本机 gitignore 临时件、非 WIP 非
缺陷、守卫已如实点名）。**FIST 闭环 T0r101 六步全链 rc=0**（wd-r345，ns watchdog，verify
status=已完成、completed_by=wd-r345，deliverable=本报告）。禁区零碰（8 WIP 文件含 bugs.md 零改零提交）。

## 巡检明细

1. **WIP 状态**（`git status --short` + `git diff --numstat`，本轮实读，逐文件对表 r344）：
   - `memory/bugs.md` **216+/0-**（与 r326~r344 逐字同 ⇒ **零增长**；无 BUG-637+ 新条目）；
   - 其余 5 个已跟踪 WIP 文件**逐字同 r344**：`improvement-plan` 7/1、`target.md` 1/1、`README` 2/1、
     `run_guards` 9/0、`engine_circuit_test` 5/0 ⇒ R192 车道面**仍静止**（自 r318 后无再推进）；
   - 2 个 untracked（`check_mcpcf_db_isolation.py` 545 行 / `pipeline_mode_loop.md` 211 行）未变。
   - 结论：**WIP 非冻结增长后静止第 26 轮**（r321 记非冻结增长第 1 轮 = vq BUG-636 落账；r322 静止第 2；
     r323 静止第 4；r324 静止第 5；r325 静止第 6；r326 静止第 7；r327 静止第 8；r328 静止第 9；
     r329 静止第 10；r330 静止第 11；r331 静止第 12；r332 静止第 13；r333 静止第 14；r334 静止第 15；
     r335 静止第 16；r336 静止第 17；r337 静止第 18；r338 静止第 19；r339 静止第 20；r340 静止第 21；
     r341 静止第 22；r342 静止第 23；r343 静止第 24；r344 静止第 25；r345 本轮 = 静止第 26）。
   - 禁区处置：8 个 WIP 文件（含 bugs.md）**本轮零改、零提交**。

2. **换面巡检 `check_entry_paths`**（BUG-93 入口清单守卫；R1~R3 三向、真源非硬编码、判例-17/R183
   区分讨论与指令、扫描面只读含 WIP 文件不触碰禁区）：
   - 自检：`--selftest` **rc=0**（**17 格**：R1 夹具命中 2 / 干净不误红 / 空清单报空转 / R2 成对 /
     根 .py 选取〔入库留/未入库点名〕/ 根 .py 入面且活代码必红 / 根 .py 只改注释不误红 / 取不到 git
     反向兜底 / R3 裸相对产物必红 / R3 合法 join / cwd=ROOT 不误红 / R3 只改注释不误红 / R3 扫描面
     计数承重 / e2e-retired-in-comment-not-flagged / e2e-retired-in-code-flagged /
     e2e-docstring-exempt-does-not-weaken-code-face / e2e-user-face-still-flagged /
     e2e-docstring-line-splitter）；
   - 实测：**PASS rc=0** —— **入口清单**：`cmd/cli, cmd/commissar, cmd/main`｜发布 `cmd/cli`｜退役
     `cmd/commissar, main`｜**扫描面 391 份**〔历史面除外〕：
     · **R1** 退役入口引用 **0 处**；**R2** 缺 `serve` 启动器 **0 个**；**R3** 裸相对产物寻址 **0 处**
       （扫描面 391 份文件、历史面与守卫自身除外）；
     · **盲区如实点名**：仓库根另有 1 份未入库的 `.py` 未判〔本机临时件 `execute_cron.py`、CI 检出里
       不存在〕——守卫「盲区必须可见」纪律（BUG-118 同族：判据盲区比违例更贵）；
   - 判读：WIP 在飞面（`docs/improvement-plan` / `scripts/README.md` / `check_mcpcf_db_isolation.py` /
     `pipeline_mode_loop.md`）在入口面上**无退役入口引用、无缺 serve 启动器、无裸相对产物寻址** ⇒
     WIP 在飞面在入口清单面上**无新增风险**。

3. **零漂移双检**：
   - `check_tools_sync` rc=0（server.mbt 注册 183，AGENTS/README/deliverable/scoring_rubric 对齐；
     R3b/R7 扫现状面 168 份、历史面豁免 25 份；R8 清单分组 19 组 ΣN=183 对表一致）；
   - `check_instruction_budget` rc=0（AGENTS.md 50440 / 65536 字节，全部章节可见）。

4. **Round C 三件**：维持过期不执行——BUG-527 摘 cc-link-flags 已 owner 否决（CI A/B 实证有害）、
   BUG-530 已 FIXED（3699f012a）、`check_usage_tool_count` 已注册（run_guards.py:175）；`src/**` +
   `run_guards.py` 仍 M ⇒ 队列仍锁。

5. **FIST 闭环 T0r101 六步全链一发收口**（wd-r345，ns watchdog）：
   - 链脚本 `temp/fist_r345_chain.sh`（沿 r321~r344 稳健 TID 提取，逐行取能解析为 JSON 的那行）；
   - 六步 `publish / agent_acl_grant / claim / execute / submit / verify` 全 rc=0（后台一发收全），
     verify 回执 **status=已完成、completed_by=wd-r345**、deliverable=
     `reports/2026-11-16-r345-wakeup-patrol.md`（回盘 `temp/fist_r345_out/`）。

## 资源消耗

- 判据 4 支（1 换面巡检 check_entry_paths selftest + 实测 + 2 零漂移）+ WIP numstat 核验 1 支
  + FIST 六步链 1 发（后台串跑一次收全）；
- 本轮无子代理（巡检判据为轻量命令执行 + 只读核验 + FIST 链为网关记账，命令结果需指挥官亲阅终审，故直跑）。

## 任务分配记录

- **r345 FIST 闭环 T0r101 六步全链**（wd-r345，ns watchdog）：`temp/fist_r345_chain.sh`（稳健 TID 提取，
  六步全 rc=0），回盘 `temp/fist_r345_out/`（`1_publish..6_verify.txt` / `chain.log` / `task_id.txt`；
  verify status=已完成、completed_by=wd-r345）。

## 遗留风险

- **vq 外来账队列**：白名单外 **23 条（BUG-613~635）** + 契约不命中 1 条（BUG-636）待 owner 裁决
  （搬移 vq 仓 / 带理由登记 WHITELIST kind=foreign-adjudicated）；本轮账本零增长，规模与 r326~r344
  持平，同 BUG-565 持续模式，指挥官不代行清理、不立新账。
- **WIP 非冻结增长后持续静止**：`memory/bugs.md` 216/0 无再增长；四件套核心 R192 车道面自 r318 后
  无再推进（连续第 26 轮静止）。
- **owner 裁决件**（同 r321~r344，本轮无增减）：① WIP 四件套弃置 ③ r302 落账方式 ④ 外来账处置
  （BUG-613~636，规模 23+1）⑤ BUG-636（FIST 自留临时号）known-red 登记口径（②
  check_mcpcf_db_isolation.py 缺执行面/未注册已被 R192 车道推进消解——r341 已确认其 README 登记面
  自洽、r344 确认其 spawn 隔离面合规、注册面归 R192 收口时核）。
- **R192 车道收口清单（维持 5 项）**：① git add 两份在飞交付物（check_publish_payload P1 点名）+
  ② **修 `pipeline_mode_loop.md:86` 的 `run_check` 示例补 `cmd`+`task_id` 必填参数**（r342 J8 点名）+
  ③ 核 `check_mcpcf_db_isolation.py` 注册面（r341 确认 README 登记自洽、r344 确认 spawn 隔离合规、
  注册面归 R192 核）+ ④ **U 面 5 条脚本补 `N=` 契约块**（r337 点名）+ ⑤ **提交 `bugs.md` 时同批重跑
  `gen_plugins.py` 重投影插件态**（r343 J1 点名 9 文件、AGENTS.md 提交门禁既有义务，漂移即消解）。
  同属「专门轮次」批处理面。
- **FIST 链提取鲁棒性（r318 遗留）**：44 份 `temp/fist_r*_chain.sh` 同形脆弱提取（本轮 +1）；
  durable 修复在 `scripts/fist.py`（notice→stderr / stdout 纯 JSON）或 tracked 链脚本模板稳健取
  JSON 行，留专门轮次。本轮稳健提取是**临时绕过**，非 durable 修复。
- **判据自述格子数/注释文档滞后**（r332 起累计·非缺陷）：`check_arg_face_strict.py`「已知债」段
  （27 把已消解、注释仍写现状）+ r338 `check_sql_bind_alignment.py` docstring「6 格」实跑 7/7 格，
  留专门轮次批量更新（均属各尺本体、非 WIP 面）。
- **R192 在飞 WIP 的发布载荷暴露**（r334 check_publish_payload 实测确认）：`check_mcpcf_db_isolation.py`
  + `pipeline_mode_loop.md` 两 untracked 文件会在下一次 `moon publish` 被公开（P1）。R192 车道收口时
  应 `git add` 入库（属真交付物、不该 ignore）；在那之前若有人 `moon publish`，会把这两份在飞稿公开——
  发布前须先收口 R192 车道。

## 后续建议

- **最高优先仍为 BUG-636（FIST 自留临时号·check_tool_coverage 盲区修复规格）**：待 `memory/bugs.md`
  WIP 解禁后专门轮次委派（含「加进 `_tool_registry.consumers()` 收口格」最易漏环节）。
- **vq 外来账队列（BUG-613~636）owner 裁决**：规模与 r344 持平（白名单外 23 条 + 契约不命中 1 条），
  裁决面完整，可一次批了。
- **FIST 链提取鲁棒性专门轮次修复**（口径见遗留风险）。
- **判据自述格子数/注释批量更新**（r332 `check_arg_face_strict`「已知债」段 + r338
  `check_sql_bind_alignment` docstring「6 格」→ 实跑 7 格）：属轻微文档滞后、非缺陷，可一并批量修。
- **R192 车道收口清单**（维持 5 项）：git add 两份在飞交付物 / 修 pipeline_mode_loop.md:86 run_check
  示例 / 核 check_mcpcf_db_isolation.py 注册面 / U 面 5 条脚本补 N= 契约块 / 提交 bugs.md 同批重跑
  gen_plugins.py 重投影插件态。
- 换面巡检下轮候选：`check_release_asset_names`（BUG-103~117 发布资产名↔安装器↔moon.mod 三处同源 +
  R8 发布作业不顶掉分发 + R9 工具链 bootstrap 与 CI 同源 + R13 文档离线线资产名版本字面量 + R14 安装器
  内部两条 TLS 栈，纯静态只读、`--selftest` 反解、扫描面避开 WIP 面）；继续按注册面轮换，优先近期
  未轮过且有 `--selftest` 的判据。
- Round C 三件维持过期（owner 已裁决面），唤醒轮继续非阻塞巡检。

## 超额内容

无。

## 来源

- `git status --short` / `git diff --numstat`（2026-11-16 本轮实读：bugs.md **216/0**、其余 5 文件逐字同
  r344；2 untracked 未变：check_mcpcf_db_isolation.py 545 行 / pipeline_mode_loop.md 211 行）
- `reports/2026-11-16-r344-wakeup-patrol.md`（r344 WIP 基线 + per-file 拆分）
- `python scripts/check_entry_paths.py --selftest`（rc=0：17 格反解，含 R1 夹具命中 2 / 干净不误红 /
  空清单报空转 / R2 成对 / 根 .py 选取 / R3 裸相对产物 / 判例-17 docstring 豁免不削弱代码面 等）+
  同判据实测（PASS rc=0：入口清单 cmd/cli,cmd/commissar,cmd/main｜发布 cmd/cli｜退役 cmd/commissar,main｜
  扫描面 391 份；R1 退役入口引用 0 / R2 缺 serve 0 / R3 裸相对产物 0；盲区如实点名 execute_cron.py 本机
  临时件未判）（本轮）
- `python scripts/check_tools_sync.py`（183 PASS）/ `python scripts/check_instruction_budget.py`
  （50440/65536 PASS）（本轮）
- `temp/fist_r345_out/`（六步回执 + `chain.log` + `task_id.txt`，TID=T0r101，verify status=已完成）
