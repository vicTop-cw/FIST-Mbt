# 轮 319 唤醒巡检报告

**日期**：2026-11-15
**轮次**：r319
**执行者**：wd-r319（FIST-Mbt-ExploreWatchdog）

## 结果摘要

**WIP 增长后静止第 1 轮** —— numstat 与 r318 逐字同（R192 车道 BUG-583 方向④的增长自 r318 后停摆、无再推进）：
`run_guards.py` +9 / `scripts/README.md` 2+/1- / `src/engine/engine_circuit_test.mbt` +5，untracked
`scripts/check_mcpcf_db_isolation.py` / `templates/pipeline_mode_loop.md` 均未变；四件套核心
（`memory/bugs.md` +208 vq 外来账 / `docs/improvement-plan-20261010.md` 7+/1- / `memory/target.md` 1+/1-
= 216+/2-）仍冻结。`src/**` + `scripts/run_guards.py` 仍锁 ⇒ 巡检分支。

换面巡检 `check_stale_self_claim`（自述滞后判据，§4.1 常驻门，r300~r318 窗内首跑）自检 20/20 格 PASS
rc=0（含 2 处变异对照 + 1 处历史陈述反证 + 1 处真未实现反证）+ 实测 PASS rc=0（**421 份 .mbt · 负面句式
6 处 · 具名负面主张 0 条 · 无自述滞后**）。零漂移 `check_tools_sync` 183 / `check_instruction_budget`
50440/65536 均 rc=0。**无新发现、无新立账**。Round C 三件维持过期不执行。FIST 闭环 T0r75 六步全链 rc=0
一发收口（wd-r319，ns watchdog，verify status=已完成）——本轮链脚本从首发即用稳健 TID 提取（取能解析为
JSON 的那行），规避 r318 型「json.load 整文件失败 → TID 空 → 2-6 级联 rc=1」。

## 巡检明细

1. **WIP 状态**（`git status --short` + `git diff --numstat`）：
   - numstat 与 r318 **逐字同**：6 个已跟踪 WIP 文件（bugs.md 208/0、improvement-plan 7/1、target.md 1/1、
     README 2/1、run_guards 9/0、engine_circuit_test 5/0）+ 2 个 untracked（check_mcpcf_db_isolation.py、
     pipeline_mode_loop.md）均未变 ⇒ R192 车道增长**停摆**，非新 WIP 事件。
   - 四件套核心仍冻结 216+/2-（vq 外来账 BUG-592~635 持续挂 owner 裁决）。
   - `src/engine/engine_circuit_test.mbt` + `scripts/run_guards.py` 均为 M（未提交）⇒ 仍锁 ⇒ 巡检分支
     （非 Round C 队列）。
   - 禁区处置：8 个 WIP 文件（R192 车道 5 + vq 外来账 bugs.md + improvement-plan + target.md）**本轮零改、
     零提交**。

2. **换面巡检 `check_stale_self_claim`**（自述滞后判据，BUG-575/577 族，AI-DEVELOPMENT-STANDARD §4.1
   常驻门；r300~r318 窗内首跑）：
   - 自检：`--selftest` **20/20 格通过**（fixture-four-files / stale-claim-is-red / past-tense-not-red /
     genuinely-missing-not-red / test-face-not-consumer / history-only-face-is-clean-not-blind /
     empty-universe-refuses / claims-counted / phrase-hits-counted / runtime-string-face-S2 /
     mutation-history-skip-anchor-exactly-one / mutation-history-skip-really-fires /
     mutation-consumer-gate-anchor-exactly-one / mutation-consumer-gate-really-fires /
     stale-exemption-is-red / exemption-pointing-nowhere-is-red / call-face-violation-rc1 /
     call-face-clean-rc0 / call-face-empty-refuses-rc2 / call-face-unknown-flag-rc2），rc=0；
   - 实测：**PASS rc=0** —— 「421 份 .mbt · 负面句式 6 处 · 具名负面主张 0 条（其余为无具名对象的修辞或
     变更史陈述）」⇒ **无自述滞后**（判读边界自述：这不等于自述全都对，本判据只看「具名否定式 ↔
     非注释/非测试消费者」，S1 注释面 + S2 运行时字面量面两式分报）。
   - 选面理由：r318「下一轮候选」点名 `check_ns_write_gate_coverage` / `check_desc_enum_sync`（二者仍
     在候选队列未消费）；本轮改取 `check_stale_self_claim` —— 正对本仓核心命题「**自述滞后于现状**」
     （BUG-575 立规、BUG-577 同族），且自带 20 格 selftest + S1/S2 双面 + 豁免表反查（幻影豁免=无人认领
     的免检面），巡检价值最高；余下两把点名候选维持入列、留后续轮换。

3. **零漂移双检**：
   - `check_tools_sync` rc=0（server.mbt 注册 183，AGENTS/README/deliverable/scoring_rubric 对齐；R3b/R7
     扫现状面 168 份、历史面豁免 25 份；R8 清单分组 19 组 ΣN=183 对表一致）；
   - `check_instruction_budget` rc=0（AGENTS.md 50440 / 65536 字节，全部章节可见）。

4. **Round C 三件**：维持过期不执行——BUG-527 摘 cc-link-flags 已 owner 否决（CI A/B 实证有害）、
   BUG-530 已 FIXED（3699f012a）、`check_usage_tool_count` 已注册（run_guards.py:175）。

5. **FIST 闭环 T0r75 六步全链一发收口**（wd-r319，ns watchdog）：
   - 本轮链脚本 `temp/fist_r319_chain.sh` 从**首发**即用稳健 TID 提取（逐行取能解析为 JSON 的那行，先例
     `temp/fist_r318_complete.sh`），规避 r318 首轮 `json.load(open(整文件))` 被 notice 行前缀破坏的坑
     （BUG-32 autobuild 提示行本轮未触发——无 src 编辑，cli.js 产物未陈旧），六步无级联；
   - 六步 `publish / agent_acl_grant / claim / execute / submit / verify` 全 rc=0，verify 回执
     status=已完成、completed_by=wd-r319、deliverable=reports/2026-11-15-r319-wakeup-patrol.md。

## 资源消耗

- 判据 4 支（1 换面巡检 check_stale_self_claim selftest + 实测 + 2 零漂移）+ WIP numstat 核验 1 支 +
  FIST 六步链 1 发（后台串跑一次收全）；
- 本轮无子代理（巡检判据为轻量命令执行 + 只读核验 + FIST 链为网关记账，命令结果需指挥官亲阅终审，故直跑）。

## 任务分配记录

- **r319 FIST 闭环 T0r75 六步全链**（wd-r319，ns watchdog）：`temp/fist_r319_chain.sh`（首发即用稳健 TID
  提取，六步全 rc=0），回盘 `temp/fist_r319_out/`（`1_publish..6_verify.txt` / `chain.log` / `task_id.txt`；
  verify status=已完成、completed_by=wd-r319）。

## 遗留风险

- **WIP 增长后静止**：R192 车道（BUG-583 方向④）交付面（脚本 + run_guards 接线 + README + engine_circuit_test
  注释 + pipeline_mode_loop 模板）仍未提交，归该车道 / owner 收口；本轮不代提交。
- **四件套核心仍冻结**：`memory/bugs.md` +208 行仍为 vq 外来账（BUG-592~635），挂 owner 裁决，不碰不落账。
- **owner 裁决件**：① WIP 四件套弃置 ③ r302 落账方式 ④ 外来账处置（搬移 vq 仓 / 登记 WHITELIST
  kind=foreign-adjudicated）⑤ BUG-636 known-red 登记口径（② check_mcpcf_db_isolation.py 缺执行面/未注册
  已被 R192 车道推进消解）。
- **BUG-636（临时号）待落账 + 待修复**：`check_tool_coverage` 未接线第 6 真源消费者、漏扫 18 工具（7 个零
  A 面覆盖），修复规格见 `reports/2026-11-15-r315-wakeup-patrol.md`；落账推迟到 `memory/bugs.md` WIP 解禁 /
  owner 裁决后。
- **FIST 链提取鲁棒性（r318 遗留）**：21 份 `temp/fist_r*_chain.sh` 同形脆弱提取；durable 修复在
  `scripts/fist.py`（notice→stderr / stdout 纯 JSON）或 tracked 链脚本模板稳健取 JSON 行，留专门轮次。本轮
  首发稳健提取是**临时绕过**（本轮恰好未触发 notice 行，仍按稳健写法防御），非 durable 修复。
- **换面巡检轮换面**：r319 轮到 `check_stale_self_claim`；余下点名候选 `check_ns_write_gate_coverage` /
  `check_desc_enum_sync`（均自检绿、无实参自包含，可直接轮换）。`check_tool_coverage` 在 BUG-636 转正前
  退出候选。

## 后续建议

- **最高优先仍为 BUG-636**：待 `memory/bugs.md` WIP 解禁后专门轮次委派（含「加进 `_tool_registry.consumers()`
  收口格」最易漏环节）。
- **FIST 链提取鲁棒性专门轮次修复**（口径见遗留风险）。
- **继续按注册面轮换**，优先余下点名候选 `check_ns_write_gate_coverage` / `check_desc_enum_sync`。
- Round C 三件维持过期（owner 已裁决面），唤醒轮继续非阻塞巡检。

## 超额内容

无。

## 来源

- `git status --short` / `git diff --numstat`（2026-11-15 本轮实测，与 r318 逐字同）
- `reports/2026-11-15-r318-wakeup-patrol.md`（r318 WIP 基线 + 增长第 1 轮 + 下一轮点名候选）
- `python scripts/check_stale_self_claim.py --selftest`（20/20）+ `python scripts/check_stale_self_claim.py`
  （PASS rc=0）（本轮，证据 `temp/r319_ssc_selftest.txt` / `temp/r319_ssc_real.txt`）
- `python scripts/check_tools_sync.py`（183 PASS）/ `python scripts/check_instruction_budget.py`
  （50440/65536 PASS）（本轮，证据 `temp/r319_ts.txt` / `temp/r319_ib.txt`）
- `temp/fist_r319_out/`（六步回执 + `chain.log` + `task_id.txt`）
