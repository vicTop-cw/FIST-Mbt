# 轮 320 唤醒巡检报告

**日期**：2026-11-15
**轮次**：r320
**执行者**：wd-r320（FIST-Mbt-ExploreWatchdog）

## 结果摘要

**WIP 增长后静止第 2 轮** —— numstat 与 r318/r319 逐字同（R192 车道 BUG-583 方向④的增长自 r318 后持续停摆、无再推进）：
6 个已跟踪 WIP 文件（`memory/bugs.md` 208/0、`docs/improvement-plan-20261010.md` 7/1、`memory/target.md` 1/1、
`scripts/README.md` 2/1、`scripts/run_guards.py` 9/0、`src/engine/engine_circuit_test.mbt` 5/0）+ 2 个 untracked
（`scripts/check_mcpcf_db_isolation.py`、`templates/pipeline_mode_loop.md`）均未变；四件套核心（216+/2-）仍冻结。
`src/**` + `scripts/run_guards.py` 仍锁 ⇒ 巡检分支。

换面巡检 `check_ns_write_gate_coverage`（ns 写门：`write_gate.mbt` 文档声称清单 ↔ `server.mbt` 实际调用点清单
对表，r319 点名候选首跑）自检 **9/9 格 PASS**（含 clean-3-gated + mutation-is-on-code + M1~M7 七支变异对照：删真
调用 rc=1 / 注释写调用串 rc=1 / 文档多声称 rc=1 / 代码多一门 rc=1 / 文档无清单 rc=2 / 注册块缺失 rc=2 / 门挪块外
rc=1）+ 实测 **PASS rc=0**（**3 支门 publish / publish_parallel / dag_publish**，文档声称 == 实际调用点）。零漂移
`check_tools_sync` 183 / `check_instruction_budget` 50440/65536 均 rc=0。**无新发现、无新立账**。Round C 三件维持
过期不执行。FIST 闭环 T0r76 六步全链一发收口（wd-r320，ns watchdog，verify status=已完成）——链脚本延续 r319 稳健
TID 提取（逐行取能解析为 JSON 的那行），规避 r318 型「json.load 整文件失败 → TID 空 → 2-6 级联 rc=1」。

## 巡检明细

1. **WIP 状态**（`git status --short` + `git diff --numstat`）：
   - numstat 与 r318/r319 **逐字同**：6 个已跟踪 WIP 文件（bugs.md 208/0、improvement-plan 7/1、target.md 1/1、
     README 2/1、run_guards 9/0、engine_circuit_test 5/0）+ 2 个 untracked（check_mcpcf_db_isolation.py、
     pipeline_mode_loop.md）均未变 ⇒ R192 车道增长**持续停摆**，非新 WIP 事件，**第 2 轮静止**。
   - 四件套核心仍冻结 216+/2-（vq 外来账 BUG-592~635 持续挂 owner 裁决）。
   - `src/engine/engine_circuit_test.mbt` + `scripts/run_guards.py` 均为 M（未提交）⇒ 仍锁 ⇒ 巡检分支
     （非 Round C 队列）。
   - 禁区处置：8 个 WIP 文件（R192 车道 5 + vq 外来账 bugs.md + improvement-plan + target.md）**本轮零改、
     零提交**。

2. **换面巡检 `check_ns_write_gate_coverage`**（ns 写门覆盖面对表判据；r319「换面巡检轮换面」点名候选之一，
   本轮首跑；`check_desc_enum_sync` 维持入列留后续轮换）：
   - 自检：`--selftest` **9/9 格通过**（clean-3-gated-rc0 / mutation-is-on-code / M1-drop-code-line-rc1 /
     M2-comment-is-not-wiring-rc1 / M3-doc-claims-more-rc1 / M4-code-extra-gated-rc1 / M5-doc-line-missing-rc2 /
     M6-claimed-block-missing-rc2 / M7-stray-outside-block-rc1），rc=0；清单从已执行格子反解 9 格；
   - 实测：**PASS rc=0** —— 「文档声称 == 实际调用点（**3 支：publish / publish_parallel / dag_publish**）」⇒
     写门声称面与接线面零漂移。
   - 选面理由：r319 点名候选 `check_ns_write_gate_coverage` / `check_desc_enum_sync`（二者均自检绿、无实参
     自包含，可直接轮换）；本轮取 `check_ns_write_gate_coverage` —— 正对本仓「自报 `created_by` 不可验证（S1）」
     安全公告面里**唯一**有门的那三支 publish 入口（`engine.publish` 硬检查 `created_by` 必须是
     human_steward/human），巡检「文档声称的门是否真接上」价值高；余下 `check_desc_enum_sync` 维持入列。

3. **零漂移双检**：
   - `check_tools_sync` rc=0（server.mbt 注册 183，AGENTS/README/deliverable/scoring_rubric 对齐；R3b/R7
     扫现状面 168 份、历史面豁免 25 份；R8 清单分组 19 组 ΣN=183 对表一致）；
   - `check_instruction_budget` rc=0（AGENTS.md 50440 / 65536 字节，全部章节可见）。

4. **Round C 三件**：维持过期不执行——BUG-527 摘 cc-link-flags 已 owner 否决（CI A/B 实证有害）、
   BUG-530 已 FIXED（3699f012a）、`check_usage_tool_count` 已注册（run_guards.py:175）。

5. **FIST 闭环 T0r76 六步全链一发收口**（wd-r320，ns watchdog）：
   - 链脚本 `temp/fist_r320_chain.sh` 延续 r319 稳健 TID 提取（逐行取能解析为 JSON 的那行），规避 r318 型
     `json.load(open(整文件))` 被 notice 行前缀破坏的坑（BUG-32 autobuild 提示行本轮未触发——无 src 编辑，
     cli.js 产物未陈旧），六步无级联；
   - 六步 `publish / agent_acl_grant / claim / execute / submit / verify` 全 rc=0，verify 回执
     status=已完成、completed_by=wd-r320、deliverable=reports/2026-11-15-r320-wakeup-patrol.md。

## 资源消耗

- 判据 4 支（1 换面巡检 check_ns_write_gate_coverage selftest + 实测 + 2 零漂移）+ WIP numstat 核验 1 支 +
  FIST 六步链 1 发（后台串跑一次收全）；
- 本轮无子代理（巡检判据为轻量命令执行 + 只读核验 + FIST 链为网关记账，命令结果需指挥官亲阅终审，故直跑）。

## 任务分配记录

- **r320 FIST 闭环 T0r76 六步全链**（wd-r320，ns watchdog）：`temp/fist_r320_chain.sh`（稳健 TID 提取，
  六步全 rc=0），回盘 `temp/fist_r320_out/`（`1_publish..6_verify.txt` / `chain.log` / `task_id.txt`；
  verify status=已完成、completed_by=wd-r320）。

## 遗留风险

- **WIP 增长后静止（第 2 轮）**：R192 车道（BUG-583 方向④）交付面（脚本 + run_guards 接线 + README +
  engine_circuit_test 注释 + pipeline_mode_loop 模板）仍未提交，归该车道 / owner 收口；本轮不代提交。
- **四件套核心仍冻结**：`memory/bugs.md` +208 行仍为 vq 外来账（BUG-592~635），挂 owner 裁决，不碰不落账。
- **owner 裁决件**：① WIP 四件套弃置 ③ r302 落账方式 ④ 外来账处置（搬移 vq 仓 / 登记 WHITELIST
  kind=foreign-adjudicated）⑤ BUG-636 known-red 登记口径（② check_mcpcf_db_isolation.py 缺执行面/未注册
  已被 R192 车道推进消解）。
- **BUG-636（临时号）待落账 + 待修复**：`check_tool_coverage` 未接线第 6 真源消费者、漏扫 18 工具（7 个零
  A 面覆盖），修复规格见 `reports/2026-11-15-r315-wakeup-patrol.md`；落账推迟到 `memory/bugs.md` WIP 解禁 /
  owner 裁决后。
- **FIST 链提取鲁棒性（r318 遗留）**：21 份 `temp/fist_r*_chain.sh` 同形脆弱提取；durable 修复在
  `scripts/fist.py`（notice→stderr / stdout 纯 JSON）或 tracked 链脚本模板稳健取 JSON 行，留专门轮次。本轮
  稳健提取是**临时绕过**（本轮恰好未触发 notice 行，仍按稳健写法防御），非 durable 修复。
- **换面巡检轮换面**：r320 轮到 `check_ns_write_gate_coverage`；余下点名候选 `check_desc_enum_sync`
  （自检绿、无实参自包含，可直接轮换）。`check_tool_coverage` 在 BUG-636 转正前退出候选。

## 后续建议

- **最高优先仍为 BUG-636**：待 `memory/bugs.md` WIP 解禁后专门轮次委派（含「加进 `_tool_registry.consumers()`
  收口格」最易漏环节）。
- **FIST 链提取鲁棒性专门轮次修复**（口径见遗留风险）。
- **继续按注册面轮换**，优先余下点名候选 `check_desc_enum_sync`。
- Round C 三件维持过期（owner 已裁决面），唤醒轮继续非阻塞巡检。

## 超额内容

无。

## 来源

- `git status --short` / `git diff --numstat`（2026-11-15 本轮实测，与 r318/r319 逐字同）
- `reports/2026-11-15-r319-wakeup-patrol.md`（r319 WIP 基线 + 下一轮点名候选）
- `python scripts/check_ns_write_gate_coverage.py --selftest`（9/9）+ `python scripts/check_ns_write_gate_coverage.py`
  （PASS rc=0）（本轮，证据 `temp/r320_gate_selftest.txt` / `temp/r320_gate_real.txt`）
- `python scripts/check_tools_sync.py`（183 PASS）/ `python scripts/check_instruction_budget.py`
  （50440/65536 PASS）（本轮，证据 `temp/r320_ts.txt` / `temp/r320_ib.txt`）
- `temp/fist_r320_out/`（六步回执 + `chain.log` + `task_id.txt`）
