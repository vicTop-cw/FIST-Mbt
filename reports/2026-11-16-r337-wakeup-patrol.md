# 轮 337 唤醒巡检报告

**日期**：2026-11-16
**轮次**：r337
**执行者**：wd-r337（FIST-Mbt-ExploreWatchdog）

## 结果摘要

**WIP 非冻结增长后静止第 18 轮（numstat 与 r326~r336 逐字同）** —— `memory/bugs.md` 维持 **216/0**
（r336 后零再增长、无 BUG-637+ 新外来账），其余 5 个已跟踪 WIP 文件（`improvement-plan` 7/1、
`target.md` 1/1、`README` 2/1、`run_guards` 9/0、`engine_circuit_test` 5/0）与 2 个 untracked
（`check_mcpcf_db_isolation.py` 545 行、`pipeline_mode_loop.md` 211 行）**逐字同 r336**；
R192 车道自 r318 后持续停摆。`src/**` + `scripts/run_guards.py` 仍 M ⇒ **巡检分支**
（Round C 三件仍锁）。

换面巡检 `check_exit_code_contract`（BUG-369 建议①②「**退出码契约 承诺面 ↔ 实现面**」守卫：
R40/R41 实测抓到 `check_plan_landing` 自述 `2=判据无法自证` 而代码 `raise SystemExit("中文串")`
**实给 1**（`SystemExit` 带字符串 ⇒ 退出码 1）⇒ 「判据空转」与「有落点未落地」在退出码面同色，
而电池与 CI 期望文本按 2 写；入账 BUG-369 后用 **ast 重扫全仓 `scripts/`**，真相是没有任何一面
机器核过 `scripts/` 里自述契约的脚本——承诺与实现之间没有门。本尺核**自述契约与实给码是否一致**，
用 ast 不读文本。扫描面 `scripts/*.py` **完全避开 WIP 面 `src/engine/`**）selftest **rc=0**
（**28 格**反解：合成夹具 + **标注集校准 5 格按名字现数**〔`check_plan_landing`/`check_template_ctrl`/
`check_mbti_sync`/`check_pkg_imports`/`simulate_head_commit` 修过必归零、再红即尺子回退〕+ 分类面
〔承诺与条目切片 / 实现面 / 判定 R1·R2·R3 / 只报不判与让位 / 棘轮 / 承重对照 / 自指
`own-fatal-exit-is-2` / `empty-universe-fatal-rc-2`〕）+ 实测 **PASS rc=0**（**判定面 R1+R2+R3 归零
〔上限 0〕**——BUG-369 立案那批存量已清完、没有容忍带、任何一条新假契约都必红；只报不判面 **U 5 条**
〔有出口站点但整份没有 `N=` 契约块〕/ **O 7 条**〔不透明出口含 `sys.exit(p.returncode)` 外部件透传、
R1 主动让位但留名〕如实出数不判红）。

零漂移 `check_tools_sync` **183** / `check_instruction_budget` **50440/65536** 均 rc=0。Round C 三件
维持过期不执行。**无新发现（类型）、无新立账**（vq 外来账队列规模与 r326~r336 持平，全挂 owner
裁决，同 BUG-565 持续模式）。**FIST 闭环 T0r93 六步全链 rc=0**（wd-r337，ns watchdog，verify
status=已完成、completed_by=wd-r337，deliverable=本报告）。禁区零碰（8 WIP 文件含 bugs.md 零改零提交）。

## 巡检明细

1. **WIP 状态**（`git status --short` + `git diff --numstat`，本轮实读，逐文件对表 r336）：
   - `memory/bugs.md` **216+/0-**（与 r326~r336 逐字同 ⇒ **零增长**；无 BUG-637+ 新条目）；
   - 其余 5 个已跟踪 WIP 文件**逐字同 r336**：`improvement-plan` 7/1、`target.md` 1/1、`README` 2/1、
     `run_guards` 9/0、`engine_circuit_test` 5/0 ⇒ R192 车道面**仍静止**（自 r318 后无再推进）；
   - 2 个 untracked（`check_mcpcf_db_isolation.py` 545 行 / `pipeline_mode_loop.md` 211 行）未变。
   - 结论：**WIP 非冻结增长后静止第 18 轮**（r321 记非冻结增长第 1 轮 = vq BUG-636 落账；r322 静止第 2；
     r323 静止第 4；r324 静止第 5；r325 静止第 6；r326 静止第 7；r327 静止第 8；r328 静止第 9；
     r329 静止第 10；r330 静止第 11；r331 静止第 12；r332 静止第 13；r333 静止第 14；r334 静止第 15；
     r335 静止第 16；r336 静止第 17；r337 本轮 = 静止第 18）。
   - 禁区处置：8 个 WIP 文件（含 bugs.md）**本轮零改、零提交**。

2. **换面巡检 `check_exit_code_contract`**（BUG-369 退出码契约承诺面↔实现面守卫；ast 重扫不读文本，
   扫描面与 WIP 面零交集）：
   - 自检：`--selftest` **rc=0**（**28 格**反解：合成夹具 + 标注集校准 5 格按名字现数——
     `check_plan_landing`〔emit_fatal 返 2 + `sys.exit(main())` 透传，真契约〕/ `check_template_ctrl`
     〔R42 已修必归零〕/ `check_mbti_sync`〔R43 已修必归零〕/ `check_pkg_imports`〔R44 已修必归零〕/
     `simulate_head_commit`〔R45 已修必归零〕；分类面：承诺与条目切片 / 实现面 / 判定 R1·R2·R3 /
     只报不判与让位 / 棘轮 / 承重对照 / 自指 `own-fatal-exit-is-2`〔emit_fatal 恒返 2，本判据不用被抓
     者的缺陷给自己开门〕/ `empty-universe-fatal-rc-2`〔非 git 仓拒绝出读数〕）；
   - 实测：**PASS rc=0** —— **判定面 R1+R2+R3 归零（上限 0）**：
     · **R1 模块面幻影**：承诺面声明码 N（N≥2）而 ast 实现面给不出 ⇒ **0 条**（刻意不判 N∈{0,1}——
       0 恒可得、1 是 Python 未捕获异常默认码，判它必假红）；
     · **R2 站点类指派矛盾**：出口站点文本属「判据失灵」类而承诺面指派给码 M、站点实给码集无 M ⇒
       **0 条**；
     · **R3 站点自述码不符**：站点文本自写 `rc=N` 而实给码集无 N ⇒ **0 条**；
     · **判定面归零 = BUG-369 立案那批存量已清完**，没有容忍带，任何一条新假契约都必红；
   - 只报不判面（**必出数、不判红**——静默丢弃 = 数字凭空少，下轮无人能查少的是噪音还是缺陷）：
     · **U 5 条**：`run_fist_mbt_http.py` / `run_fist_mbt_web.py` / `run_mcp_bug_loop.py` /
       `tmp_audit_preservation_scan.py` / `whisperer_patrol.py` 有出口站点但整份没有 `N=` 契约块；
     · **O 7 条**：`check_badge.py`/`check_bug_refs.py`/`check_ci_step_position.py`/`check_two_faces.py`/
       `cleanup_artifacts.py`/`fist.py`/`fist_gate.py` 不透明出口（ast 给不出确定码，含
       `sys.exit(p.returncode)` 外部件透传——R1 对此类主动让位但留名）；
   - 判据工作结论：**无漂移** —— 判定面归零自 r336 未变，U/O 只报面如实出数。

3. **零漂移双检**：
   - `check_tools_sync` rc=0（server.mbt 注册 183，AGENTS/README/deliverable/scoring_rubric 对齐；
     R3b/R7 扫现状面 168 份、历史面豁免 25 份；R8 清单分组 19 组 ΣN=183 对表一致）；
   - `check_instruction_budget` rc=0（AGENTS.md 50440 / 65536 字节，全部章节可见）。

4. **Round C 三件**：维持过期不执行——BUG-527 摘 cc-link-flags 已 owner 否决（CI A/B 实证有害）、
   BUG-530 已 FIXED（3699f012a）、`check_usage_tool_count` 已注册（run_guards.py:175）；`src/**` +
   `run_guards.py` 仍 M ⇒ 队列仍锁。

5. **FIST 闭环 T0r93 六步全链一发收口**（wd-r337，ns watchdog）：
   - 链脚本 `temp/fist_r337_chain.sh`（沿 r321~r336 稳健 TID 提取，逐行取能解析为 JSON 的那行）；
   - 六步 `publish / agent_acl_grant / claim / execute / submit / verify` 全 rc=0（后台一发收全），
     verify 回执 **status=已完成、completed_by=wd-r337**、deliverable=
     `reports/2026-11-16-r337-wakeup-patrol.md`（回盘 `temp/fist_r337_out/`）。

## 资源消耗

- 判据 4 支（1 换面巡检 check_exit_code_contract selftest + 全量 + 2 零漂移）+ WIP numstat 核验 1 支
  + FIST 六步链 1 发（后台串跑一次收全）；
- 本轮无子代理（巡检判据为轻量命令执行 + 只读核验 + FIST 链为网关记账，命令结果需指挥官亲阅终审，故直跑）。

## 任务分配记录

- **r337 FIST 闭环 T0r93 六步全链**（wd-r337，ns watchdog）：`temp/fist_r337_chain.sh`（稳健 TID 提取，
  六步全 rc=0），回盘 `temp/fist_r337_out/`（`1_publish..6_verify.txt` / `chain.log` / `task_id.txt`；
  verify status=已完成、completed_by=wd-r337）。

## 遗留风险

- **vq 外来账队列**：白名单外 **23 条（BUG-613~635）** + 契约不命中 1 条（BUG-636）待 owner 裁决
  （搬移 vq 仓 / 带理由登记 WHITELIST kind=foreign-adjudicated）；本轮账本零增长，规模与 r326~r336
  持平，同 BUG-565 持续模式，指挥官不代行清理、不立新账。
- **WIP 非冻结增长后持续静止**：`memory/bugs.md` 216/0 无再增长；四件套核心 R192 车道面自 r318 后
  无再推进（连续第 18 轮静止）。
- **owner 裁决件**（同 r321~r336，本轮无增减）：① WIP 四件套弃置 ③ r302 落账方式 ④ 外来账处置
  （BUG-613~636，规模 23+1）⑤ BUG-636（FIST 自留临时号）known-red 登记口径（②
  check_mcpcf_db_isolation.py 缺执行面/未注册已被 R192 车道推进消解）。
- **FIST 链提取鲁棒性（r318 遗留）**：36 份 `temp/fist_r*_chain.sh` 同形脆弱提取（本轮 +1）；
  durable 修复在 `scripts/fist.py`（notice→stderr / stdout 纯 JSON）或 tracked 链脚本模板稳健取
  JSON 行，留专门轮次。本轮稳健提取是**临时绕过**，非 durable 修复。
- **`check_arg_face_strict.py` 头注释「已知债」段文档滞后**（r332 新发现·非缺陷）：27 把债已消解、
  注释仍写现状，留专门轮次更新（注释属该尺本体、非 WIP 面）。
- **R192 在飞 WIP 的发布载荷暴露**（r334 check_publish_payload 实测确认）：`check_mcpcf_db_isolation.py`
  + `pipeline_mode_loop.md` 两 untracked 文件会在下一次 `moon publish` 被公开（P1）。R192 车道收口时
  应 `git add` 入库（属真交付物、不该 ignore）；在那之前若有人 `moon publish`，会把这两份在飞稿公开——
  发布前须先收口 R192 车道。

## 后续建议

- **最高优先仍为 BUG-636（FIST 自留临时号·check_tool_coverage 盲区修复规格）**：待 `memory/bugs.md`
  WIP 解禁后专门轮次委派（含「加进 `_tool_registry.consumers()` 收口格」最易漏环节）。
- **vq 外来账队列（BUG-613~636）owner 裁决**：规模与 r336 持平（白名单外 23 条 + 契约不命中 1 条），
  裁决面完整，可一次批了。
- **FIST 链提取鲁棒性专门轮次修复**（口径见遗留风险）。
- **`check_arg_face_strict.py` 头注释「已知债」段更新**（r332 新发现·轻微文档滞后）。
- **R192 车道收口时 git add 两份在飞交付物**（check_publish_payload P1 点名）：`check_mcpcf_db_isolation.py`
  + `pipeline_mode_loop.md` 属真交付物应入库而非 ignore。
- **U 面 5 条脚本补 `N=` 契约块**（check_exit_code_contract 只报不判面点名：`run_fist_mbt_http.py` /
  `run_fist_mbt_web.py` / `run_mcp_bug_loop.py` / `tmp_audit_preservation_scan.py` /
  `whisperer_patrol.py` 有出口站点但整份没有退出码契约块）——非红线、属文档完备性，留专门轮次补齐；
  `tmp_audit_preservation_scan.py` 若按仓内惯例属一次性工具应 `_` 前缀或补豁免理由。
- 换面巡检下轮候选：`check_sql_bind_alignment`（SQL 绑定参数对齐守卫，纯静态只读、`--selftest`
  反解、扫描面避开 WIP 面）；继续按注册面轮换，优先近期未轮过且有 `--selftest` 的判据。
- Round C 三件维持过期（owner 已裁决面），唤醒轮继续非阻塞巡检。

## 超额内容

无。

## 来源

- `git status --short` / `git diff --numstat`（2026-11-16 本轮实读：bugs.md **216/0**、其余 5 文件逐字同
  r336；2 untracked 未变：check_mcpcf_db_isolation.py 545 行 / pipeline_mode_loop.md 211 行）
- `reports/2026-11-16-r336-wakeup-patrol.md`（r336 WIP 基线 + per-file 拆分）
- `python scripts/check_exit_code_contract.py --selftest`（rc=0，28 格反解含标注集校准 5 格）+ 同判据
  全量（PASS rc=0：判定面 R1+R2+R3 归零上限 0、BUG-369 存量已清完；只报不判面 U 5 条 / O 7 条如实出数）
  （本轮）
- `python scripts/check_tools_sync.py`（183 PASS）/ `python scripts/check_instruction_budget.py`
  （50440/65536 PASS）（本轮）
- `temp/fist_r337_out/`（六步回执 + `chain.log` + `task_id.txt`，TID=T0r93，verify status=已完成）
