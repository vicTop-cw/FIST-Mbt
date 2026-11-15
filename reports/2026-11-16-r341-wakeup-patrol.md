# 轮 341 唤醒巡检报告

**日期**：2026-11-16
**轮次**：r341
**执行者**：wd-r341（FIST-Mbt-ExploreWatchdog）

## 结果摘要

**WIP 非冻结增长后静止第 22 轮（numstat 与 r326~r340 逐字同）** —— `memory/bugs.md` 维持 **216/0**
（r340 后零再增长、无 BUG-637+ 新外来账），其余 5 个已跟踪 WIP 文件（`improvement-plan` 7/1、
`target.md` 1/1、`README` 2/1、`run_guards` 9/0、`engine_circuit_test` 5/0）与 2 个 untracked
（`check_mcpcf_db_isolation.py` 545 行、`pipeline_mode_loop.md` 211 行）**逐字同 r340**；
R192 车道自 r318 后持续停摆。`src/**` + `scripts/run_guards.py` 仍 M ⇒ **巡检分支**
（Round C 三件仍锁）。

换面巡检 `check_selftest_inventory_doc`（R104「**格子计数自述 ↔ 已执行格子反解**」对表守卫：本仓
自证纪律是「`--selftest` 的格子清单从**已执行格子反解**、不手写计数」，但**文档抄的是另一份手数字**——
R103 给 `check_release_asset_names` 的 R9 加了三格（`R9×2`→`R9×5`）、实现面自己改了读数，而
`scripts/README.md` 那行是**手工记得去改**的、改之前写「十九格（R9×2）」与真源差三格；**实现会自证、
文档不会**——下一位读者按「十九格」判覆盖面，多出的三格就永远没人知道存在。与 `check_doc_surface`
J10 同族但**非同一条尺**：J10 比「判据编号范围」（族在不在）、本尺比「每族几格 + 一共几格」（量对不对）、
判据面互不重叠。判定面逐条点名：**X1 计数漂移**（文档写 `R族×n`、实现清单同族不是 n）/ **X2 幻影族**
（文档写了某族格数、实现里这一族一格都没跑）/ **X3 总数滞后**（文档自述 N 格而 N≠对表族数合计）/
**X4 自述失联**（跑 `--selftest` 拿不到反解清单 ⇒ 走 2 号档不冒用 1）/ **X5 抄本打架**（同一把尺 README
里两份读数不同的同族自述——README 把整份条目列表重复 7 遍、R104 只改一份 ⇒ 6 份仍写「十七格」）。
口径三条实测逼出来：① 判定面只取 `scripts/README.md` 的 `` - `xxx.py` `` 条目语法（AGENTS 散文面**假红
比漏红更坏**、本轮不入）/ ② 只认带「格/支」计数单位、ASCII 斜杠分隔、至少两族、每族名 ≤3 大写字母、
至少一族带 `×数` 的清单（校准读数 / 单族 / 裸族名单三类必须解析成 0 条自述）/ ③ 实现面必须自带「反解」
锚点、没锚点的守卫不进判定面。**本尺不自判**（R105）：README 里本尺条目永不进判定面、自锁跳过份数写进
判定面读数。扫描面 `scripts/README.md` + 真跑每把在判定面尺的 `--selftest`〔只读 + hermetic 子进程、不
触碰禁区〕）selftest **rc=0**（**25 格**反解：G / M×24）+ 全量 **PASS rc=0**（**INVENTORY_SYNC=clean**：
判定面 **160 份条目 / 带族计数自述 11 份 / 自锁跳过本尺 1 份**，**判定族 64 条逐一对表通过**——
`check_backlog_status_staleness` 4 / `check_battery_count_doc` 3 / `check_deployment_freshness` 5 /
`check_mcpcf_db_isolation` 5 / `check_release_asset_names` 14 / `check_slave_task_list` 5 /
`check_text_control_chars` 3 / `check_unit_number_unique` 11 / `check_upgrade_installer` 4 /
`moon_env_probe` 3 / `run_light_wt` 7；**含 WIP 在飞 `check_mcpcf_db_isolation.py` 的 5 条自述已被 WIP
README 登记、其 `--selftest` 反解一致**）。

零漂移 `check_tools_sync` **183** / `check_instruction_budget` **50440/65536** 均 rc=0。Round C 三件
维持过期不执行。**无新发现（类型）、无新立账**（vq 外来账队列规模与 r326~r340 持平，全挂 owner
裁决，同 BUG-565 持续模式）。**FIST 闭环 T0r97 六步全链 rc=0**（wd-r341，ns watchdog，verify
status=已完成、completed_by=wd-r341，deliverable=本报告）。禁区零碰（8 WIP 文件含 bugs.md 零改零提交）。

## 巡检明细

1. **WIP 状态**（`git status --short` + `git diff --numstat`，本轮实读，逐文件对表 r340）：
   - `memory/bugs.md` **216+/0-**（与 r326~r340 逐字同 ⇒ **零增长**；无 BUG-637+ 新条目）；
   - 其余 5 个已跟踪 WIP 文件**逐字同 r340**：`improvement-plan` 7/1、`target.md` 1/1、`README` 2/1、
     `run_guards` 9/0、`engine_circuit_test` 5/0 ⇒ R192 车道面**仍静止**（自 r318 后无再推进）；
   - 2 个 untracked（`check_mcpcf_db_isolation.py` 545 行 / `pipeline_mode_loop.md` 211 行）未变。
   - 结论：**WIP 非冻结增长后静止第 22 轮**（r321 记非冻结增长第 1 轮 = vq BUG-636 落账；r322 静止第 2；
     r323 静止第 4；r324 静止第 5；r325 静止第 6；r326 静止第 7；r327 静止第 8；r328 静止第 9；
     r329 静止第 10；r330 静止第 11；r331 静止第 12；r332 静止第 13；r333 静止第 14；r334 静止第 15；
     r335 静止第 16；r336 静止第 17；r337 静止第 18；r338 静止第 19；r339 静止第 20；r340 静止第 21；
     r341 本轮 = 静止第 22）。
   - 禁区处置：8 个 WIP 文件（含 bugs.md）**本轮零改、零提交**。

2. **换面巡检 `check_selftest_inventory_doc`**（R104 格子计数自述↔已执行格子反解对表守卫；X1~X5 逐条
   点名、口径三条实测逼出来、本尺不自判、扫描面只读 README + hermetic 子进程跑各尺 `--selftest`）：
   - 自检：`--selftest` **rc=0**（**25 格**反解：G / M×24，清单从已执行格子反解、不手写计数）；
   - 全量：**PASS rc=0** —— **INVENTORY_SYNC=clean、判定族 64 条逐一对表通过**：
     · 判定面规模：**条目 160 份 / 带族计数自述 11 份 / 自锁跳过本尺 1 份**；
     · 11 把尺的族计数自述合计 64 条（4+3+5+5+14+5+3+11+4+3+7 = 64），每条文档自述与实现 `--selftest`
       反解清单**逐一对表一致**（无 X1 计数漂移 / 无 X2 幻影族 / 无 X3 总数滞后 / 无 X4 自述失联 /
       无 X5 抄本打架）；
     · **WIP 在飞的 `check_mcpcf_db_isolation.py`（5 条族计数自述）已被 WIP README 登记、其 `--selftest`
       反解一致** ⇒ R192 车道在 README 登记面上已自洽（注：这只证明「登记↔自述」对表一致，不证明该尺
       已进 `run_guards.py` 电池——注册面归 R192 车道收口时核，本轮只读不代劳）；
   - 判据工作结论：**无漂移** —— 格子计数自述面自 r340 未变，64 条逐一对表通过。

3. **零漂移双检**：
   - `check_tools_sync` rc=0（server.mbt 注册 183，AGENTS/README/deliverable/scoring_rubric 对齐；
     R3b/R7 扫现状面 168 份、历史面豁免 25 份；R8 清单分组 19 组 ΣN=183 对表一致）；
   - `check_instruction_budget` rc=0（AGENTS.md 50440 / 65536 字节，全部章节可见）。

4. **Round C 三件**：维持过期不执行——BUG-527 摘 cc-link-flags 已 owner 否决（CI A/B 实证有害）、
   BUG-530 已 FIXED（3699f012a）、`check_usage_tool_count` 已注册（run_guards.py:175）；`src/**` +
   `run_guards.py` 仍 M ⇒ 队列仍锁。

5. **FIST 闭环 T0r97 六步全链一发收口**（wd-r341，ns watchdog）：
   - 链脚本 `temp/fist_r341_chain.sh`（沿 r321~r340 稳健 TID 提取，逐行取能解析为 JSON 的那行）；
   - 六步 `publish / agent_acl_grant / claim / execute / submit / verify` 全 rc=0（后台一发收全），
     verify 回执 **status=已完成、completed_by=wd-r341**、deliverable=
     `reports/2026-11-16-r341-wakeup-patrol.md`（回盘 `temp/fist_r341_out/`）。

## 资源消耗

- 判据 4 支（1 换面巡检 check_selftest_inventory_doc show-face + selftest + 全量 + 2 零漂移）+
  WIP numstat 核验 1 支 + FIST 六步链 1 发（后台串跑一次收全）；
- 本轮无子代理（巡检判据为轻量命令执行 + 只读核验 + FIST 链为网关记账，命令结果需指挥官亲阅终审，故直跑）。

## 任务分配记录

- **r341 FIST 闭环 T0r97 六步全链**（wd-r341，ns watchdog）：`temp/fist_r341_chain.sh`（稳健 TID 提取，
  六步全 rc=0），回盘 `temp/fist_r341_out/`（`1_publish..6_verify.txt` / `chain.log` / `task_id.txt`；
  verify status=已完成、completed_by=wd-r341）。

## 遗留风险

- **vq 外来账队列**：白名单外 **23 条（BUG-613~635）** + 契约不命中 1 条（BUG-636）待 owner 裁决
  （搬移 vq 仓 / 带理由登记 WHITELIST kind=foreign-adjudicated）；本轮账本零增长，规模与 r326~r340
  持平，同 BUG-565 持续模式，指挥官不代行清理、不立新账。
- **WIP 非冻结增长后持续静止**：`memory/bugs.md` 216/0 无再增长；四件套核心 R192 车道面自 r318 后
  无再推进（连续第 22 轮静止）。
- **owner 裁决件**（同 r321~r340，本轮无增减）：① WIP 四件套弃置 ③ r302 落账方式 ④ 外来账处置
  （BUG-613~636，规模 23+1）⑤ BUG-636（FIST 自留临时号）known-red 登记口径（②
  check_mcpcf_db_isolation.py 缺执行面/未注册已被 R192 车道推进消解——本轮 check_selftest_inventory_doc
  实测确认其 README 登记面已自洽，注册面归 R192 收口时核）。
- **FIST 链提取鲁棒性（r318 遗留）**：40 份 `temp/fist_r*_chain.sh` 同形脆弱提取（本轮 +1）；
  durable 修复在 `scripts/fist.py`（notice→stderr / stdout 纯 JSON）或 tracked 链脚本模板稳健取
  JSON 行，留专门轮次。本轮稳健提取是**临时绕过**，非 durable 修复。
- **判据自述格子数/注释文档滞后**（r332 起累计·非缺陷）：`check_arg_face_strict.py`「已知债」段
  （27 把已消解、注释仍写现状）+ r338 `check_sql_bind_alignment.py` docstring「6 格」实跑 7/7 格，
  留专门轮次批量更新（均属各尺本体、非 WIP 面）。
- **R192 在飞 WIP 的发布载荷暴露**（r334 check_publish_payload 实测确认）：`check_mcpcf_db_isolation.py`
  + `pipeline_mode_loop.md` 两 untracked 文件会在下一次 `moon publish` 被公开（P1）。R192 车道收口时
  应 `git add` 入库（属真交付物、不该 ignore）；在那之前若有人 `moon publish`，会把这两份在飞稿公开——
  发布前须先收口 R192 车道。
- **U 面 5 条脚本补 `N=` 契约块**（r337 check_exit_code_contract 只报不判面点名）：`run_fist_mbt_http.py`
  / `run_fist_mbt_web.py` / `run_mcp_bug_loop.py` / `tmp_audit_preservation_scan.py` /
  `whisperer_patrol.py`——非红线、属文档完备性，留专门轮次补齐。

## 后续建议

- **最高优先仍为 BUG-636（FIST 自留临时号·check_tool_coverage 盲区修复规格）**：待 `memory/bugs.md`
  WIP 解禁后专门轮次委派（含「加进 `_tool_registry.consumers()` 收口格」最易漏环节）。
- **vq 外来账队列（BUG-613~636）owner 裁决**：规模与 r340 持平（白名单外 23 条 + 契约不命中 1 条），
  裁决面完整，可一次批了。
- **FIST 链提取鲁棒性专门轮次修复**（口径见遗留风险）。
- **判据自述格子数/注释批量更新**（r332 `check_arg_face_strict`「已知债」段 + r338
  `check_sql_bind_alignment` docstring「6 格」→ 实跑 7 格）：属轻微文档滞后、非缺陷，可一并批量修。
- **R192 车道收口时 git add 两份在飞交付物**（check_publish_payload P1 点名）+ **U 面 5 条脚本补
  `N=` 契约块**（r337 点名）：同属「专门轮次」批处理面。
- 换面巡检下轮候选：`check_doc_surface`（规范正文↔机器投影一致性 J1~J19，纯静态只读、`--selftest`
  反解、扫描面避开 WIP 面）；继续按注册面轮换，优先近期未轮过且有 `--selftest` 的判据。
- Round C 三件维持过期（owner 已裁决面），唤醒轮继续非阻塞巡检。

## 超额内容

无。

## 来源

- `git status --short` / `git diff --numstat`（2026-11-16 本轮实读：bugs.md **216/0**、其余 5 文件逐字同
  r340；2 untracked 未变：check_mcpcf_db_isolation.py 545 行 / pipeline_mode_loop.md 211 行）
- `reports/2026-11-16-r340-wakeup-patrol.md`（r340 WIP 基线 + per-file 拆分）
- `python scripts/check_selftest_inventory_doc.py --show-face`（判定面 160 份条目 / 带族计数自述 11 份 /
  自锁跳过本尺 1 份）+ `--selftest`（rc=0，25 格 G/M×24）+ 全量（PASS rc=0：INVENTORY_SYNC=clean 判定族
  64 条逐一对表通过，含 WIP 在飞 check_mcpcf_db_isolation.py 5 条自洽）（本轮）
- `python scripts/check_tools_sync.py`（183 PASS）/ `python scripts/check_instruction_budget.py`
  （50440/65536 PASS）（本轮）
- `temp/fist_r341_out/`（六步回执 + `chain.log` + `task_id.txt`，TID=T0r97，verify status=已完成）
