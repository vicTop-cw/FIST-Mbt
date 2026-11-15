# 轮 339 唤醒巡检报告

**日期**：2026-11-16
**轮次**：r339
**执行者**：wd-r339（FIST-Mbt-ExploreWatchdog）

## 结果摘要

**WIP 非冻结增长后静止第 20 轮（numstat 与 r326~r338 逐字同）** —— `memory/bugs.md` 维持 **216/0**
（r338 后零再增长、无 BUG-637+ 新外来账），其余 5 个已跟踪 WIP 文件（`improvement-plan` 7/1、
`target.md` 1/1、`README` 2/1、`run_guards` 9/0、`engine_circuit_test` 5/0）与 2 个 untracked
（`check_mcpcf_db_isolation.py` 545 行、`pipeline_mode_loop.md` 211 行）**逐字同 r338**；
R192 车道自 r318 后持续停摆。`src/**` + `scripts/run_guards.py` 仍 M ⇒ **巡检分支**
（Round C 三件仍锁）。

换面巡检 `check_store_tables_wired`（BUG-28「store 里每张表要么**有写入点**，要么在源码里**显式
声明为预留**」守卫：`runs` 建了表、注释写「供 Phase 2(Omega) / Phase 5(scheduler) 使用」，但全仓
零写入零读取〔实测 `select count(*) from runs` = 0、同库 `specs=451`/`tasks=1147` ⇒ 不是没初始化〕——
读源码的人和 AI 都会把「验收有 runs 记录可查」当成**已具备的能力**、规范 r1「文档即实现」在这里
断裂；光改注释只治这一次，本守卫治「再长出第二张 runs」。判据**双向**〔与 `check_doc_surface` J10
同一手法：声明滞后与幻影声明都要能发红〕：① **无写入点且未声明预留** → 红（第二张 runs）/
② **声明了预留却有写入点** → 红（声明滞后，能力已上线还挂着「未接线」）/ ③ **解析不到任何表** →
FATAL(2)（扫描面空转 ≠ 没有问题，绝不报绿）。预留声明用**机器可读行** `schema-reserved:` 写在 store
源文件里（注释改词不影响判据）。扫描面 `src/store/store_sqlite.mbt` + `src/**/*.mbt` **完全避开
WIP 面 `src/engine/`**）selftest **rc=0**（判据对「死 schema」与「声明滞后」两个方向都发红、干净
输入不误红、表名解析口径可证）+ 实测 **PASS rc=0**（**store schema 接线一致：32 张表 = 31 张有
写入点 + 1 张显式预留〔`runs`〕**）。

零漂移 `check_tools_sync` **183** / `check_instruction_budget` **50440/65536** 均 rc=0。Round C 三件
维持过期不执行。**无新发现（类型）、无新立账**（vq 外来账队列规模与 r326~r338 持平，全挂 owner
裁决，同 BUG-565 持续模式）。**FIST 闭环 T0r95 六步全链 rc=0**（wd-r339，ns watchdog，verify
status=已完成、completed_by=wd-r339，deliverable=本报告）。禁区零碰（8 WIP 文件含 bugs.md 零改零提交）。

## 巡检明细

1. **WIP 状态**（`git status --short` + `git diff --numstat`，本轮实读，逐文件对表 r338）：
   - `memory/bugs.md` **216+/0-**（与 r326~r338 逐字同 ⇒ **零增长**；无 BUG-637+ 新条目）；
   - 其余 5 个已跟踪 WIP 文件**逐字同 r338**：`improvement-plan` 7/1、`target.md` 1/1、`README` 2/1、
     `run_guards` 9/0、`engine_circuit_test` 5/0 ⇒ R192 车道面**仍静止**（自 r318 后无再推进）；
   - 2 个 untracked（`check_mcpcf_db_isolation.py` 545 行 / `pipeline_mode_loop.md` 211 行）未变。
   - 结论：**WIP 非冻结增长后静止第 20 轮**（r321 记非冻结增长第 1 轮 = vq BUG-636 落账；r322 静止第 2；
     r323 静止第 4；r324 静止第 5；r325 静止第 6；r326 静止第 7；r327 静止第 8；r328 静止第 9；
     r329 静止第 10；r330 静止第 11；r331 静止第 12；r332 静止第 13；r333 静止第 14；r334 静止第 15；
     r335 静止第 16；r336 静止第 17；r337 静止第 18；r338 静止第 19；r339 本轮 = 静止第 20）。
   - 禁区处置：8 个 WIP 文件（含 bugs.md）**本轮零改、零提交**。

2. **换面巡检 `check_store_tables_wired`**（BUG-28 store 表接线守卫；双向判据、机器可读 `schema-reserved:`
   声明行，扫描面与 WIP 面零交集）：
   - 自检：`--selftest` **rc=0**（判据对「死 schema」〔建了表无写入又没声明预留〕与「声明滞后」
     〔声明了预留却有写入点〕**两个方向都发红**、干净输入不误红、表名解析口径可证）；
   - 实测：**PASS rc=0** —— **store schema 接线一致：32 张表 = 31 张有写入点 + 1 张显式预留**：
     · 31 张表在 `src/**/*.mbt` 里有 `INSERT INTO`/`UPDATE`/`DELETE FROM`/`REPLACE INTO` 写入点；
     · 1 张（`runs`）无写入点，但在 `src/store/store_sqlite.mbt` 里以机器可读行 `schema-reserved: runs`
       **显式声明为预留**（注释改词不影响判据）⇒ 合规，不红；
   - 判据工作结论：**无漂移** —— 32 张表接线面自 r338 未变，无第二张 runs、无声明滞后。

3. **零漂移双检**：
   - `check_tools_sync` rc=0（server.mbt 注册 183，AGENTS/README/deliverable/scoring_rubric 对齐；
     R3b/R7 扫现状面 168 份、历史面豁免 25 份；R8 清单分组 19 组 ΣN=183 对表一致）；
   - `check_instruction_budget` rc=0（AGENTS.md 50440 / 65536 字节，全部章节可见）。

4. **Round C 三件**：维持过期不执行——BUG-527 摘 cc-link-flags 已 owner 否决（CI A/B 实证有害）、
   BUG-530 已 FIXED（3699f012a）、`check_usage_tool_count` 已注册（run_guards.py:175）；`src/**` +
   `run_guards.py` 仍 M ⇒ 队列仍锁。

5. **FIST 闭环 T0r95 六步全链一发收口**（wd-r339，ns watchdog）：
   - 链脚本 `temp/fist_r339_chain.sh`（沿 r321~r338 稳健 TID 提取，逐行取能解析为 JSON 的那行）；
   - 六步 `publish / agent_acl_grant / claim / execute / submit / verify` 全 rc=0（后台一发收全），
     verify 回执 **status=已完成、completed_by=wd-r339**、deliverable=
     `reports/2026-11-16-r339-wakeup-patrol.md`（回盘 `temp/fist_r339_out/`）。

## 资源消耗

- 判据 4 支（1 换面巡检 check_store_tables_wired selftest + 实测 + 2 零漂移）+ WIP numstat 核验 1 支
  + FIST 六步链 1 发（后台串跑一次收全）；
- 本轮无子代理（巡检判据为轻量命令执行 + 只读核验 + FIST 链为网关记账，命令结果需指挥官亲阅终审，故直跑）。

## 任务分配记录

- **r339 FIST 闭环 T0r95 六步全链**（wd-r339，ns watchdog）：`temp/fist_r339_chain.sh`（稳健 TID 提取，
  六步全 rc=0），回盘 `temp/fist_r339_out/`（`1_publish..6_verify.txt` / `chain.log` / `task_id.txt`；
  verify status=已完成、completed_by=wd-r339）。

## 遗留风险

- **vq 外来账队列**：白名单外 **23 条（BUG-613~635）** + 契约不命中 1 条（BUG-636）待 owner 裁决
  （搬移 vq 仓 / 带理由登记 WHITELIST kind=foreign-adjudicated）；本轮账本零增长，规模与 r326~r338
  持平，同 BUG-565 持续模式，指挥官不代行清理、不立新账。
- **WIP 非冻结增长后持续静止**：`memory/bugs.md` 216/0 无再增长；四件套核心 R192 车道面自 r318 后
  无再推进（连续第 20 轮静止）。
- **owner 裁决件**（同 r321~r338，本轮无增减）：① WIP 四件套弃置 ③ r302 落账方式 ④ 外来账处置
  （BUG-613~636，规模 23+1）⑤ BUG-636（FIST 自留临时号）known-red 登记口径（②
  check_mcpcf_db_isolation.py 缺执行面/未注册已被 R192 车道推进消解）。
- **FIST 链提取鲁棒性（r318 遗留）**：38 份 `temp/fist_r*_chain.sh` 同形脆弱提取（本轮 +1）；
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
- **vq 外来账队列（BUG-613~636）owner 裁决**：规模与 r338 持平（白名单外 23 条 + 契约不命中 1 条），
  裁决面完整，可一次批了。
- **FIST 链提取鲁棒性专门轮次修复**（口径见遗留风险）。
- **判据自述格子数/注释批量更新**（r332 `check_arg_face_strict`「已知债」段 + r338
  `check_sql_bind_alignment` docstring「6 格」→ 实跑 7 格）：属轻微文档滞后、非缺陷，可一并批量修。
- **R192 车道收口时 git add 两份在飞交付物**（check_publish_payload P1 点名）+ **U 面 5 条脚本补
  `N=` 契约块**（r337 点名）：同属「专门轮次」批处理面。
- 换面巡检下轮候选：`check_battery_count_doc`（电池计数文档守卫，纯静态只读、`--selftest` 反解、
  扫描面避开 WIP 面）；继续按注册面轮换，优先近期未轮过且有 `--selftest` 的判据。
- Round C 三件维持过期（owner 已裁决面），唤醒轮继续非阻塞巡检。

## 超额内容

无。

## 来源

- `git status --short` / `git diff --numstat`（2026-11-16 本轮实读：bugs.md **216/0**、其余 5 文件逐字同
  r338；2 untracked 未变：check_mcpcf_db_isolation.py 545 行 / pipeline_mode_loop.md 211 行）
- `reports/2026-11-16-r338-wakeup-patrol.md`（r338 WIP 基线 + per-file 拆分）
- `python scripts/check_store_tables_wired.py --selftest`（rc=0：死 schema 与声明滞后两向都发红、
  干净输入不误红、表名解析口径可证）+ 同判据实测（PASS rc=0：store schema 接线一致 32 张表 =
  31 张有写入点 + 1 张显式预留〔runs〕）（本轮）
- `python scripts/check_tools_sync.py`（183 PASS）/ `python scripts/check_instruction_budget.py`
  （50440/65536 PASS）（本轮）
- `temp/fist_r339_out/`（六步回执 + `chain.log` + `task_id.txt`，TID=T0r95，verify status=已完成）
