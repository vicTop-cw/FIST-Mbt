# 轮 342 唤醒巡检报告

**日期**：2026-11-16
**轮次**：r342
**执行者**：wd-r342（FIST-Mbt-ExploreWatchdog）

## 结果摘要

**WIP 非冻结增长后静止第 23 轮（numstat 与 r326~r341 逐字同）** —— `memory/bugs.md` 维持 **216/0**
（r341 后零再增长、无 BUG-637+ 新外来账），其余 5 个已跟踪 WIP 文件（`improvement-plan` 7/1、
`target.md` 1/1、`README` 2/1、`run_guards` 9/0、`engine_circuit_test` 5/0）与 2 个 untracked
（`check_mcpcf_db_isolation.py` 545 行、`pipeline_mode_loop.md` 211 行）**逐字同 r341**；
R192 车道自 r318 后持续停摆。`src/**` + `scripts/run_guards.py` 仍 M ⇒ **巡检分支**
（Round C 三件仍锁）。

换面巡检 `check_doc_surface`（BUG-22/BUG-30「**文档面单一真源**」守卫·J1~J19 十九判：现有三守卫
〔`check_tools_sync`/`check_test_sync`/`check_badge`〕只校验**工具数**和**测试数**，于是两类漂移能一路
绿灯通过——① README 标题改对、正文分组表没跟上〔BUG-22：标题 116、正文只列 103、缺的正是 AGENTS 已
补录的那 10 工具〕/ ② 文档版本自述与 `moon.mod` 不一致〔BUG-30：USAGE 仍写 @0.2.3、README 说已发布
0.2.5 而 BACKLOG 说 0.2.4〕。本守卫补上这两类。纯静态、不 spawn。扫描面含 WIP 的 `README.md`〔M〕+
untracked 的 `templates/pipeline_mode_loop.md`，但**均只读、不触碰禁区**）selftest **rc=0**（真源
解析到 **183** 工具、J3/J4/J6/J7/J8/J9/J10/J11/J12/J13/J14/J15/J17/J18/J19 对合成违例均发红、
反向对照含「干净输入不误红 / 英文不算契约 / 分工写清不误红 / 两面一致不误红 / J11 合法态不误红 /
J12 注释 refs/heads 与 tag 守卫不误红」、防空转含「分工清单落空必红 / 空扫描必红 / 解析器饿死必红 /
J11 账本读不到那条单必红 / J12 一份 workflow 都没读到必自拒 / J13 标题戳早于权威 published 不误红 /
权威面没记这一版不作数 / release-fact 标记缺失或自相矛盾必红」）+ 全量 **FAIL rc=1 = 1 条 J8 违例**：
**`templates/pipeline_mode_loop.md:86 run_check(...) 缺必填参数 ['cmd', 'task_id']`**——点名文件正是
**untracked WIP**（R192 在飞）⇒ **在飞投影非回归**，R192 车道收口前应修该模板的 `run_check` 示例
（补 `cmd` + `task_id`）。

零漂移 `check_tools_sync` **183** / `check_instruction_budget` **50440/65536** 均 rc=0。Round C 三件
维持过期不执行。**新发现（WIP 在飞·非本仓已提交缺陷）**：untracked WIP 模板 `pipeline_mode_loop.md:86`
的 `run_check` 调用示例缺必填参数 `cmd`+`task_id`（J8 点名、属 R192 车道所有、指挥官不代行修、留 R192
收口时补）。**无新立账**（属 WIP 在飞缺陷、非本仓回归）。**FIST 闭环 T0r98 六步全链 rc=0**（wd-r342，
ns watchdog，verify status=已完成、completed_by=wd-r342，deliverable=本报告）。禁区零碰（8 WIP 文件含
bugs.md 零改零提交）。

## 巡检明细

1. **WIP 状态**（`git status --short` + `git diff --numstat`，本轮实读，逐文件对表 r341）：
   - `memory/bugs.md` **216+/0-**（与 r326~r341 逐字同 ⇒ **零增长**；无 BUG-637+ 新条目）；
   - 其余 5 个已跟踪 WIP 文件**逐字同 r341**：`improvement-plan` 7/1、`target.md` 1/1、`README` 2/1、
     `run_guards` 9/0、`engine_circuit_test` 5/0 ⇒ R192 车道面**仍静止**（自 r318 后无再推进）；
   - 2 个 untracked（`check_mcpcf_db_isolation.py` 545 行 / `pipeline_mode_loop.md` 211 行）未变。
   - 结论：**WIP 非冻结增长后静止第 23 轮**（r321 记非冻结增长第 1 轮 = vq BUG-636 落账；r322 静止第 2；
     r323 静止第 4；r324 静止第 5；r325 静止第 6；r326 静止第 7；r327 静止第 8；r328 静止第 9；
     r329 静止第 10；r330 静止第 11；r331 静止第 12；r332 静止第 13；r333 静止第 14；r334 静止第 15；
     r335 静止第 16；r336 静止第 17；r337 静止第 18；r338 静止第 19；r339 静止第 20；r340 静止第 21；
     r341 静止第 22；r342 本轮 = 静止第 23）。
   - 禁区处置：8 个 WIP 文件（含 bugs.md）**本轮零改、零提交**。

2. **换面巡检 `check_doc_surface`**（BUG-22/BUG-30 文档面单一真源守卫·J1~J19 十九判；纯静态、不 spawn；
   扫描面只读 WIP 文件〔README.md + untracked template〕不触碰禁区）：
   - 自检：`--selftest` **rc=0**（真源解析到 **183** 工具；**J3/J4/J6/J7/J8/J9/J10/J11/J12/J13/J14/
     J15/J17/J18/J19 对合成违例均发红**；反向对照：干净输入不误红 / 英文 `returns` 不算「返回」契约 /
     歧义键分工写清不误红 / 两面一致不误红 / J11 合法态〔单已 FIXED + 门已撤、文档不再点名〕不误红 /
     J12 注释里的 `refs/heads` 与 tag 守卫不误红；防空转：分工清单落空必红 / 空扫描必红 / 解析器饿死必红 /
     J11 账本读不到那条单必红 / J12 一份 workflow 都没读到必自拒 / J13 标题戳早于权威 published 不误红 /
     J13 权威面没记这一版不作数 / J13 release-fact 标记缺失或自相矛盾必红）；
   - 全量：**FAIL rc=1 = 1 条 J8 违例**（真源 **183** 工具 / `moon.mod` **0.3.11**）：
     · **J8 模板调用面契约**：`templates/pipeline_mode_loop.md:86` 的 `run_check(...)` 调用示例**缺必填
       参数 `cmd`、`task_id`**（`run_check` 在 `server.mbt` 声明的属性集里 `cmd`/`task_id` 为 required）；
     · **判定**：点名文件 `templates/pipeline_mode_loop.md` 是 **untracked WIP**（R192 车道在飞交付物）
       ⇒ **在飞投影非回归**——该 J8 违例是 WIP 模板自身的文档面缺陷、不是本仓已提交代码的回归；
     · **处置**：属 R192 车道所有、指挥官**不代行修**（改 untracked WIP 文件 = 触碰禁区）；留 R192 车道
       收口时给该 `run_check` 示例补 `cmd` + `task_id` 必填参数；在那之前该模板若被引用，`_instrument`
       会静默丢弃未知键、缺 required 会被拒（BUG-31 同族）；
   - 判据工作结论：**本仓已提交面零 J8 违例**（J1~J19 其余判据全绿、唯一违例落在 untracked WIP 模板），
     无漂移、无本仓回归。

3. **零漂移双检**：
   - `check_tools_sync` rc=0（server.mbt 注册 183，AGENTS/README/deliverable/scoring_rubric 对齐；
     R3b/R7 扫现状面 168 份、历史面豁免 25 份；R8 清单分组 19 组 ΣN=183 对表一致）；
   - `check_instruction_budget` rc=0（AGENTS.md 50440 / 65536 字节，全部章节可见）。

4. **Round C 三件**：维持过期不执行——BUG-527 摘 cc-link-flags 已 owner 否决（CI A/B 实证有害）、
   BUG-530 已 FIXED（3699f012a）、`check_usage_tool_count` 已注册（run_guards.py:175）；`src/**` +
   `run_guards.py` 仍 M ⇒ 队列仍锁。

5. **FIST 闭环 T0r98 六步全链一发收口**（wd-r342，ns watchdog）：
   - 链脚本 `temp/fist_r342_chain.sh`（沿 r321~r341 稳健 TID 提取，逐行取能解析为 JSON 的那行）；
   - 六步 `publish / agent_acl_grant / claim / execute / submit / verify` 全 rc=0（后台一发收全），
     verify 回执 **status=已完成、completed_by=wd-r342**、deliverable=
     `reports/2026-11-16-r342-wakeup-patrol.md`（回盘 `temp/fist_r342_out/`）。

## 资源消耗

- 判据 4 支（1 换面巡检 check_doc_surface selftest + 全量 + 2 零漂移）+ WIP numstat 核验 1 支
  + FIST 六步链 1 发（后台串跑一次收全）；
- 本轮无子代理（巡检判据为轻量命令执行 + 只读核验 + FIST 链为网关记账，命令结果需指挥官亲阅终审，故直跑）。

## 任务分配记录

- **r342 FIST 闭环 T0r98 六步全链**（wd-r342，ns watchdog）：`temp/fist_r342_chain.sh`（稳健 TID 提取，
  六步全 rc=0），回盘 `temp/fist_r342_out/`（`1_publish..6_verify.txt` / `chain.log` / `task_id.txt`；
  verify status=已完成、completed_by=wd-r342）。

## 遗留风险

- **vq 外来账队列**：白名单外 **23 条（BUG-613~635）** + 契约不命中 1 条（BUG-636）待 owner 裁决
  （搬移 vq 仓 / 带理由登记 WHITELIST kind=foreign-adjudicated）；本轮账本零增长，规模与 r326~r341
  持平，同 BUG-565 持续模式，指挥官不代行清理、不立新账。
- **WIP 非冻结增长后持续静止**：`memory/bugs.md` 216/0 无再增长；四件套核心 R192 车道面自 r318 后
  无再推进（连续第 23 轮静止）。
- **owner 裁决件**（同 r321~r341，本轮无增减）：① WIP 四件套弃置 ③ r302 落账方式 ④ 外来账处置
  （BUG-613~636，规模 23+1）⑤ BUG-636（FIST 自留临时号）known-red 登记口径（②
  check_mcpcf_db_isolation.py 缺执行面/未注册已被 R192 车道推进消解——r341 已确认其 README 登记面
  自洽、注册面归 R192 收口时核）。
- **R192 在飞 WIP 模板的 J8 文档面缺陷**（本轮 check_doc_surface 实测点名）：untracked WIP 模板
  `templates/pipeline_mode_loop.md:86` 的 `run_check(...)` 示例**缺必填参数 `cmd`、`task_id`**（J8
  违例）。属 R192 车道所有、指挥官不代行修；R192 车道收口时**必须补这两个必填参数**，否则该模板被
  引用时 `_instrument` 缺 required 会被拒（BUG-31 同族：`_instrument` 只校验 required、未知键静默丢弃）。
- **FIST 链提取鲁棒性（r318 遗留）**：41 份 `temp/fist_r*_chain.sh` 同形脆弱提取（本轮 +1）；
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
- **vq 外来账队列（BUG-613~636）owner 裁决**：规模与 r341 持平（白名单外 23 条 + 契约不命中 1 条），
  裁决面完整，可一次批了。
- **FIST 链提取鲁棒性专门轮次修复**（口径见遗留风险）。
- **判据自述格子数/注释批量更新**（r332 `check_arg_face_strict`「已知债」段 + r338
  `check_sql_bind_alignment` docstring「6 格」→ 实跑 7 格）：属轻微文档滞后、非缺陷，可一并批量修。
- **R192 车道收口清单（本轮 +1 项）**：① git add 两份在飞交付物（check_publish_payload P1 点名）+
  ② **修 `pipeline_mode_loop.md:86` 的 `run_check` 示例补 `cmd`+`task_id` 必填参数**（本轮 J8 点名）+
  ③ 核 `check_mcpcf_db_isolation.py` 注册面（r341 确认 README 登记自洽、注册面归 R192 核）+
  ④ **U 面 5 条脚本补 `N=` 契约块**（r337 点名）。同属「专门轮次」批处理面。
- 换面巡检下轮候选：`check_plugin_sync`（cl7 一源四态插件态逐字节 diff 守卫，纯静态只读、`--selftest`
  反解、扫描面避开 WIP 面）；继续按注册面轮换，优先近期未轮过且有 `--selftest` 的判据。
- Round C 三件维持过期（owner 已裁决面），唤醒轮继续非阻塞巡检。

## 超额内容

无。

## 来源

- `git status --short` / `git diff --numstat`（2026-11-16 本轮实读：bugs.md **216/0**、其余 5 文件逐字同
  r341；2 untracked 未变：check_mcpcf_db_isolation.py 545 行 / pipeline_mode_loop.md 211 行）
- `reports/2026-11-16-r341-wakeup-patrol.md`（r341 WIP 基线 + per-file 拆分）
- `python scripts/check_doc_surface.py --selftest`（rc=0：真源 183 工具、J3/J4/J6/J7/J8/J9/J10/J11/
  J12/J13/J14/J15/J17/J18/J19 对合成违例均发红 + 反向对照 + 防空转）+ 同判据全量
  （**FAIL rc=1 = 1 条 J8 违例**：templates/pipeline_mode_loop.md:86 run_check(...) 缺必填参数
  ['cmd','task_id']——untracked WIP〔R192 在飞〕⇒ 在飞投影非回归）（本轮）
- `python scripts/check_tools_sync.py`（183 PASS）/ `python scripts/check_instruction_budget.py`
  （50440/65536 PASS）（本轮）
- `temp/fist_r342_out/`（六步回执 + `chain.log` + `task_id.txt`，TID=T0r98，verify status=已完成）
