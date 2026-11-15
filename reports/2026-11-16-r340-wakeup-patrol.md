# 轮 340 唤醒巡检报告

**日期**：2026-11-16
**轮次**：r340
**执行者**：wd-r340（FIST-Mbt-ExploreWatchdog）

## 结果摘要

**WIP 非冻结增长后静止第 21 轮（numstat 与 r326~r339 逐字同）** —— `memory/bugs.md` 维持 **216/0**
（r339 后零再增长、无 BUG-637+ 新外来账），其余 5 个已跟踪 WIP 文件（`improvement-plan` 7/1、
`target.md` 1/1、`README` 2/1、`run_guards` 9/0、`engine_circuit_test` 5/0）与 2 个 untracked
（`check_mcpcf_db_isolation.py` 545 行、`pipeline_mode_loop.md` 211 行）**逐字同 r339**；
R192 车道自 r318 后持续停摆。`src/**` + `scripts/run_guards.py` 仍 M ⇒ **巡检分支**
（Round C 三件仍锁）。

换面巡检 `check_battery_count_doc`（R112/TASK-017「**电池读数 ↔ README 登记**」对表守卫：
`run_guards.py --list` 的规模读数〔尺数 / CI 面 / 电池面 / 缺执行面 + 分类记账〕是**手抄**进
`scripts/README.md` 的——TASK-017 就是 whisperer 探测时抓到的形状：R106 登记「宇宙 81 份 = 尺 79
把」，而 R110/R111 之后实测已是 83 份 / 尺 81 把 / 电池 43 格，README 里那串历史读数没人对表；
**实现会自证，手抄的读数不会——加一把尺就落后一次**。对表面 = `run_guards.py` 条目里的**机器可读
锚点** `BATTERY-REGISTRATION: rulers=… ci=… battery=… missing=… gate=… exempt=… unclassified=…`，
**逐键**与 `python scripts/run_guards.py --list` 现读比较。逐键点名（两个方向都红）：**X1 欠格** =
现读 < 登记（格子/尺被删，或登记没随删减更新，或这一键的**算法口径刚被改过**——BUG-573 的
unclassified 就是这种：7→0，一个格子都没删）/ **X2 登记落后** = 现读 > 登记（新增尺/格子后没同批改数——
手抄读数落后的主路径）/ **X3 缺执行面** = missing > 0。自拒（真给 2）：README 里没有 `run_guards.py`
条目 / 条目里没有锚点 / 锚点缺键或值非整数 / 多份抄本数值打架 / `run_guards --list` 跑不起来。
扫描面 `scripts/README.md` + `scripts/run_guards.py --list`——**只读**〔读 README + 跑 `--list` 仅列
读数、不写不提交；虽两文件属 WIP 面，但本尺只读、不触碰禁区〕）selftest **rc=0**（**15 格**反解：
G×3 / M×11 / R，族名取自已执行格子名首段首字母、不手写计数）+ 实测 **PASS rc=0**（**电池读数与
README 登记逐键一致：`rulers=155 ci=49 battery=116 missing=0 gate=127 exempt=23 unclassified=0`**）。

零漂移 `check_tools_sync` **183** / `check_instruction_budget` **50440/65536** 均 rc=0。Round C 三件
维持过期不执行。**无新发现（类型）、无新立账**（vq 外来账队列规模与 r326~r339 持平，全挂 owner
裁决，同 BUG-565 持续模式）。**FIST 闭环 T0r96 六步全链 rc=0**（wd-r340，ns watchdog，verify
status=已完成、completed_by=wd-r340，deliverable=本报告）。禁区零碰（8 WIP 文件含 bugs.md 零改零提交）。

## 巡检明细

1. **WIP 状态**（`git status --short` + `git diff --numstat`，本轮实读，逐文件对表 r339）：
   - `memory/bugs.md` **216+/0-**（与 r326~r339 逐字同 ⇒ **零增长**；无 BUG-637+ 新条目）；
   - 其余 5 个已跟踪 WIP 文件**逐字同 r339**：`improvement-plan` 7/1、`target.md` 1/1、`README` 2/1、
     `run_guards` 9/0、`engine_circuit_test` 5/0 ⇒ R192 车道面**仍静止**（自 r318 后无再推进）；
   - 2 个 untracked（`check_mcpcf_db_isolation.py` 545 行 / `pipeline_mode_loop.md` 211 行）未变。
   - 结论：**WIP 非冻结增长后静止第 21 轮**（r321 记非冻结增长第 1 轮 = vq BUG-636 落账；r322 静止第 2；
     r323 静止第 4；r324 静止第 5；r325 静止第 6；r326 静止第 7；r327 静止第 8；r328 静止第 9；
     r329 静止第 10；r330 静止第 11；r331 静止第 12；r332 静止第 13；r333 静止第 14；r334 静止第 15；
     r335 静止第 16；r336 静止第 17；r337 静止第 18；r338 静止第 19；r339 静止第 20；r340 本轮 = 静止第 21）。
   - 禁区处置：8 个 WIP 文件（含 bugs.md）**本轮零改、零提交**。

2. **换面巡检 `check_battery_count_doc`**（R112/TASK-017 电池读数↔README 登记对表守卫；逐键两向都红、
   机器可读锚点、自拒真给 2；扫描面只读 WIP 文件〔读 README + 跑 `--list`〕不触碰禁区）：
   - 自检：`--selftest` **rc=0**（**15 格**反解：G×3〔干净不误红 / 反向对照 / …〕/ M×11〔变异：
     欠格 / 登记落后 / 缺执行面 / 锚点缺键 / 值非整数 / 多份抄本打架 / 读不到汇总行 等〕/ R〔自指〕；
     族名取自已执行格子名首段首字母、**不手写计数**）；
   - 实测：**PASS rc=0** —— **电池读数与 README 登记逐键一致**：
     · `rulers=155`（尺 155 把）/ `ci=49`（CI 面 49）/ `battery=116`（电池面 116 格）/
       `missing=0`（缺执行面 0）/ `gate=127`（门禁尺 127）/ `exempt=23`（豁免 23）/
       `unclassified=0`（未归类 0）；
     · 七键（rulers / ci / battery / missing / gate / exempt / unclassified）**逐键对表一致**，
       无欠格、无登记落后、无缺执行面；
   - 判据工作结论：**无漂移** —— 电池规模读数自 r339 未变，README 登记与 `run_guards --list` 现读
     逐键同（注：本轮读数为当前 WIP 面读数——`run_guards.py` 带 +9 行 WIP、`README.md` 带 +2/1，
     两者在 WIP 面内已保持一致 ⇒ 对表绿）。

3. **零漂移双检**：
   - `check_tools_sync` rc=0（server.mbt 注册 183，AGENTS/README/deliverable/scoring_rubric 对齐；
     R3b/R7 扫现状面 168 份、历史面豁免 25 份；R8 清单分组 19 组 ΣN=183 对表一致）；
   - `check_instruction_budget` rc=0（AGENTS.md 50440 / 65536 字节，全部章节可见）。

4. **Round C 三件**：维持过期不执行——BUG-527 摘 cc-link-flags 已 owner 否决（CI A/B 实证有害）、
   BUG-530 已 FIXED（3699f012a）、`check_usage_tool_count` 已注册（run_guards.py:175）；`src/**` +
   `run_guards.py` 仍 M ⇒ 队列仍锁。

5. **FIST 闭环 T0r96 六步全链一发收口**（wd-r340，ns watchdog）：
   - 链脚本 `temp/fist_r340_chain.sh`（沿 r321~r339 稳健 TID 提取，逐行取能解析为 JSON 的那行）；
   - 六步 `publish / agent_acl_grant / claim / execute / submit / verify` 全 rc=0（后台一发收全），
     verify 回执 **status=已完成、completed_by=wd-r340**、deliverable=
     `reports/2026-11-16-r340-wakeup-patrol.md`（回盘 `temp/fist_r340_out/`）。

## 资源消耗

- 判据 4 支（1 换面巡检 check_battery_count_doc selftest + 实测 + 2 零漂移）+ WIP numstat 核验 1 支
  + FIST 六步链 1 发（后台串跑一次收全）；
- 本轮无子代理（巡检判据为轻量命令执行 + 只读核验 + FIST 链为网关记账，命令结果需指挥官亲阅终审，故直跑）。

## 任务分配记录

- **r340 FIST 闭环 T0r96 六步全链**（wd-r340，ns watchdog）：`temp/fist_r340_chain.sh`（稳健 TID 提取，
  六步全 rc=0），回盘 `temp/fist_r340_out/`（`1_publish..6_verify.txt` / `chain.log` / `task_id.txt`；
  verify status=已完成、completed_by=wd-r340）。

## 遗留风险

- **vq 外来账队列**：白名单外 **23 条（BUG-613~635）** + 契约不命中 1 条（BUG-636）待 owner 裁决
  （搬移 vq 仓 / 带理由登记 WHITELIST kind=foreign-adjudicated）；本轮账本零增长，规模与 r326~r339
  持平，同 BUG-565 持续模式，指挥官不代行清理、不立新账。
- **WIP 非冻结增长后持续静止**：`memory/bugs.md` 216/0 无再增长；四件套核心 R192 车道面自 r318 后
  无再推进（连续第 21 轮静止）。
- **owner 裁决件**（同 r321~r339，本轮无增减）：① WIP 四件套弃置 ③ r302 落账方式 ④ 外来账处置
  （BUG-613~636，规模 23+1）⑤ BUG-636（FIST 自留临时号）known-red 登记口径（②
  check_mcpcf_db_isolation.py 缺执行面/未注册已被 R192 车道推进消解）。
- **FIST 链提取鲁棒性（r318 遗留）**：39 份 `temp/fist_r*_chain.sh` 同形脆弱提取（本轮 +1）；
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
- **vq 外来账队列（BUG-613~636）owner 裁决**：规模与 r339 持平（白名单外 23 条 + 契约不命中 1 条），
  裁决面完整，可一次批了。
- **FIST 链提取鲁棒性专门轮次修复**（口径见遗留风险）。
- **判据自述格子数/注释批量更新**（r332 `check_arg_face_strict`「已知债」段 + r338
  `check_sql_bind_alignment` docstring「6 格」→ 实跑 7 格）：属轻微文档滞后、非缺陷，可一并批量修。
- **R192 车道收口时 git add 两份在飞交付物**（check_publish_payload P1 点名）+ **U 面 5 条脚本补
  `N=` 契约块**（r337 点名）：同属「专门轮次」批处理面。
- 换面巡检下轮候选：`check_selftest_inventory_doc`（对表「每把脚本自己的 `--selftest` 每族几格」，
  与本尺 `check_battery_count_doc` 判据面不重叠，纯静态只读、`--selftest` 反解、扫描面避开 WIP 面）；
  继续按注册面轮换，优先近期未轮过且有 `--selftest` 的判据。
- Round C 三件维持过期（owner 已裁决面），唤醒轮继续非阻塞巡检。

## 超额内容

无。

## 来源

- `git status --short` / `git diff --numstat`（2026-11-16 本轮实读：bugs.md **216/0**、其余 5 文件逐字同
  r339；2 untracked 未变：check_mcpcf_db_isolation.py 545 行 / pipeline_mode_loop.md 211 行）
- `reports/2026-11-16-r339-wakeup-patrol.md`（r339 WIP 基线 + per-file 拆分）
- `python scripts/check_battery_count_doc.py --selftest`（rc=0，15 格反解 G×3/M×11/R）+ 同判据实测
  （PASS rc=0：电池读数与 README 登记逐键一致 rulers=155 ci=49 battery=116 missing=0 gate=127
  exempt=23 unclassified=0）（本轮）
- `python scripts/check_tools_sync.py`（183 PASS）/ `python scripts/check_instruction_budget.py`
  （50440/65536 PASS）（本轮）
- `temp/fist_r340_out/`（六步回执 + `chain.log` + `task_id.txt`，TID=T0r96，verify status=已完成）
