# 轮 318 唤醒巡检报告

**日期**：2026-11-15
**轮次**：r318
**执行者**：wd-r318（FIST-Mbt-ExploreWatchdog）

## 结果摘要

**WIP 非冻结增长第 1 轮** —— R192 车道（BUG-583 方向④）自 r317 之后推进：`run_guards.py` +9
（接线 `case("check_mcpcf_db_isolation.py")` 进 `SPECIAL_CASES`）、`scripts/README.md` +2（补该尺完整条目）、
`src/engine/engine_circuit_test.mbt` +5（"2026-11-15 校正复核 R192 车道 P2" Mem 后端 `circuit_breakers`
注释批驳对象更正）、**新增 untracked `templates/pipeline_mode_loop.md`**（r317 报告完全未提及）。
四件套核心仍冻结零变化（`memory/bugs.md` +208 vq 外来账 / `docs/improvement-plan-20261010.md` 7+/1- /
`memory/target.md` 1+/1- = 216+/2-）。R192 推进**消解了 owner 裁决件②「缺执行面 / 未注册 run_guards」半**。
换面巡检 `check_effective_catch`（r317 列名候选）自检 8/8 SELFTEST PASS + 实测 PASS rc=0（全仓无 unused_try）。
零漂移 `check_tools_sync` 183 / `check_instruction_budget` 50440/65536 均 rc=0。
**新发现（低危）**：21 份 `temp/fist_r*_chain.sh` 用 `json.load(open(整文件))['task_id']` 提取 task_id，
`fist.py` 任何 notice 行前缀（本轮被 R192 车道编辑触发 BUG-32 autobuild 提示行）都会破坏整文件 JSON 解析
⇒ 首轮 FIST 链 step1 publish 成功但 TID 空、2-6 级联 rc=1；已按「环境条件清除后重跑」先例补跑 steps 2-6 收口
T0r74（六步全链 rc=0，verify status=已完成、completed_by=wd-r318）。不碰任何 WIP 文件。

## 巡检明细

1. **WIP 状态**（`git status --short` + `git diff --numstat` + 逐文件 diff 核读）：
   - **增长判定（本轮与 r317 的关键差异）**：r317 报告第 1 节明确列「3 个已跟踪 WIP 文件」（bugs.md /
     improvement-plan / target.md = 216+/2-）+ 1 个 untracked（`check_mcpcf_db_isolation.py`），并在「遗留风险」
     把该脚本列为 owner 裁决件②「**缺执行面 / 未注册 run_guards**」。现 `git diff` 实读：
     - `scripts/run_guards.py` **+9** —— diff 里 `+    case("check_mcpcf_db_isolation.py"),` 是**新增行**
       （r317 committed 态无此行）⇒ 已注册进 `SPECIAL_CASES`；
     - `scripts/README.md` **+2** —— 新增 `check_mcpcf_db_isolation.py` 完整条目（BUG-583 方向④，R192，
       27 格 selftest、rc 0/1/2/4 四档、C1 碰撞格等）；
     - `src/engine/engine_circuit_test.mbt` **+5** —— 全 + 行，注释 "2026-11-15 校正复核（R192 车道 P2，真源
       现读）"：Mem 后端 `circuit_breakers` 实读实写（BUG-439 补），"no-op" 旧句仅作为批驳对象存在；
     - `templates/pipeline_mode_loop.md` **untracked 新增**（r317 报告未提及该文件）。
     ⇒ R192 车道在 r317 之后**推进了**（从"只有 untracked 脚本、未注册"到"脚本 + run_guards 接线 + README
     条目 + engine_circuit_test 注释校正 + 新增 pipeline_mode_loop 模板"），非「冻结零变化」。
   - **四件套核心仍冻结**：`memory/bugs.md` +208（vq 项目 Python+Vue+Rust 外来账 BUG-592~635，与本纯 MoonBit
     仓无关，持续挂 owner 裁决）/ `docs/improvement-plan-20261010.md` 7+/1- / `memory/target.md` 1+/1-
     三文件 numstat 逐字同 r284~r317。
   - **禁区处置**：R192 车道 WIP（run_guards/README/engine_circuit_test/pipeline_mode_loop/mcpcf_db_isolation）
     + vq 外来账（bugs.md）+ improvement-plan/target.md 共 8 文件 **本轮零改、零提交**（归 owner / 该车道）。

2. **换面巡检 `check_effective_catch`**（无效 catch 判据，BUG-465，用编译器算好的 `unused_try`；
   r317 列名候选、r300~r317 未轮过 · 本轮首跑）：
   - 自检：`--selftest` **8/8 格通过**（dirty-keeps-first-path / dirty-does-not-borrow-neighbor /
     MUTATION-keyword-removed-no-hits / MUTATION-unrecognizable-output-self-rejects / coverage-note-in-output /
     ffi-runtime-exception-explained 等），rc=0；
   - 实测：**PASS rc=0**——「全仓无 unused_try。这不等于『没有无效 catch』，只代表『编译器证明不了有』」，
     违例（无）。覆盖边界自述：FFI 面装饰性防线不判 / 「声明 raise 实际不 raise」不判 / 间接调 FFI 包装不判。
   - 选面理由：r317「下一轮候选」第一把（`check_effective_catch` / `check_ns_write_gate_coverage` /
     `check_desc_enum_sync` 三把均自检绿、无实参自包含），取第一把轮换。

3. **零漂移双检**：
   - `check_tools_sync` rc=0（server.mbt 注册 183，AGENTS/README/deliverable/scoring_rubric 对齐；
     R3b/R7 扫现状面 168 份、历史面豁免 25 份；R8 清单分组 19 组 ΣN=183 对表一致）；
   - `check_instruction_budget` rc=0（AGENTS.md 50440 / 65536 字节，全部章节可见）。

4. **Round C 三件**：维持过期不执行——BUG-527 摘 cc-link-flags 已 owner 否决（CI A/B 实证有害）、
   BUG-530 已 FIXED（3699f012a）、`check_usage_tool_count` 已注册（run_guards.py:175）。

5. **FIST 闭环 T0r74 六步全链收口**（wd-r318，ns watchdog）：
   - 首轮 `temp/fist_r318_chain.sh`：step1 publish **rc=0**（T0r74 发布成功、claim_ready=true）但 **TID 提取失败**
     （见「新发现」），⇒ steps 3-6 级联 rc=1（`--task-id ""` task not found）。
   - **根因**（systematic-debugging Phase 1）：publish 输出两行——行 1 `[fist.py] 入口产物早于源码（BUG-32）：
     cli.js < engine_circuit_test.mbt → 自动 moon build --target js cmd/cli`，行 2 才是 JSON
     `{"task_id":"T0r74",...}`。chain 脚本 `json.load(open(整文件))['task_id']` 把两行当**单一** JSON 文档解析
     ⇒ JSONDecodeError 被 `2>/dev/null` 吞掉 ⇒ TID 空。BUG-32 autobuild 由 R192 车道刚编辑 engine_circuit_test.mbt
     （源码 mtime 新于产物 cli.js）触发，**一次性**（autobuild 已刷新 cli.js，后续 fist.py 不再触发）。
   - **收口**：T0r74 已发布、claim_ready，无需重发（重发会孤儿 T0r74 + 重复任务）。按「环境条件清除后重跑」先例
     `temp/fist_r318_complete.sh` 用稳健提取（取能解析为 JSON 的那行）拿到 T0r74，补跑 steps 2-6：
     `2b acl rc=0 / 3b claim rc=0 / 4b execute rc=0 / 5b submit rc=0 / 6b verify rc=0`，
     **verify 回执 status=已完成、completed_by=wd-r318、deliverable=reports/2026-11-15-r318-wakeup-patrol.md**。

6. **新发现（低危判据鲁棒性缺口）**：21 份 `temp/fist_r*_chain.sh` 均用
   `TID=$(python -c "import json; print(json.load(open(r'$OUT/1_publish.txt',encoding='utf-8'))['task_id'])" 2>/dev/null)`。
   `fist.py` 在 JSON **之前**打印任何 notice 行（本轮为 BUG-32 autobuild 提示；其他 notice 同形）都会让整文件
   `json.load` 失败 ⇒ TID 空 ⇒ 六步级联假 rc=1（**链路看似崩，实则 step1 已发布成功**）。`2>/dev/null` 把根因
   JSONDecodeError 也吞了，链.log 只留 `TID=` 空行，排障不直观。
   - **为何不本轮修**：temp/ 链脚本是每轮重建的 gitignore 件，无可提交的 durable 修复点；真正修复在
     `scripts/fist.py`（notice 改走 stderr / 保证 stdout 纯 JSON）或一份 tracked 链脚本模板（稳健取 JSON 行），
     属对共享网关的代码改动，超出唤醒巡检边界，且 忌亲力亲为 ⇒ 留专门轮次。
   - **BUG-32 本身**（fist.py autobuild，FIXED 2026-09-27）是**按设计工作**（正确检出陈旧并重建），不是缺陷；
     缺陷在「notice 污染 JSON 提取通道」这一新形状，与既有 BUG-32 立账**不同源**，本轮**不新立 BUG 号**、不写
     memory/bugs.md（该文件在 WIP，提交会连带 208 行 vq 外来账，同 BUG-636「临时立账待 WIP 解禁」口径）。

## 资源消耗

- 判据 4 支（1 换面巡检 check_effective_catch selftest + 实测 + 2 零漂移）+ WIP 逐文件 diff 核读 1 支 +
  BUG-32/提取缺口排查 grep 1 支 + FIST 六步链 2 发（首轮 chain 1 发 + 补跑 complete 1 发，均后台）；
- 本轮无子代理（巡检判据为轻量命令执行 + 只读核验 + FIST 链为网关记账，命令结果需指挥官亲阅终审，故直跑）。

## 任务分配记录

- **r318 FIST 闭环 T0r74 六步全链**（wd-r318，ns watchdog）：`temp/fist_r318_chain.sh`（首轮，step1 publish 成功
  TID 提取失败）+ `temp/fist_r318_complete.sh`（补跑 steps 2-6 收口），回盘 `temp/fist_r318_out/`
  （`1_publish.txt` / `2b..6b_*.txt` / `chain.log` / `task_id.txt`；verify status=已完成、completed_by=wd-r318）。

## 遗留风险

- **WIP 非冻结增长第 1 轮**：R192 车道（BUG-583 方向④）推进中，其交付面（脚本 + run_guards 接线 + README +
  engine_circuit_test 注释 + pipeline_mode_loop 模板）仍未提交，归该车道 / owner 收口；本轮不代提交。
- **四件套核心仍冻结**：`memory/bugs.md` +208 行仍为 vq 外来账（BUG-592~635），挂 owner 裁决，不碰不落账。
- **owner 裁决件**：原五件中**②（check_mcpcf_db_isolation.py 缺执行面/未注册 run_guards）已被 R192 车道推进消解**
  （run_guards 已接线 + README 已补条目）；剩 ① WIP 四件套弃置 ③ r302 落账方式 ④ 外来账处置（搬移 vq 仓 /
  登记 WHITELIST kind=foreign-adjudicated）⑤ BUG-636 known-red 登记口径。
- **BUG-636（临时号）待落账 + 待修复**：`check_tool_coverage` 未接线第 6 真源消费者、漏扫 18 工具（7 个零 A 面
  覆盖），修复规格见 `reports/2026-11-15-r315-wakeup-patrol.md`；落账推迟到 `memory/bugs.md` WIP 解禁 / owner 裁决后。
- **新立（低危，待专门轮次）**：fist.py notice 行污染 FIST 链 task_id 提取通道（21 份 temp 链脚本同形），
  修复在 `scripts/fist.py`（notice→stderr / stdout 纯 JSON）或 tracked 链脚本模板稳健取 JSON 行。
- **换面巡检轮换面**：r318 轮到 `check_effective_catch`；下一轮候选 `check_ns_write_gate_coverage` /
  `check_desc_enum_sync`（r317 列名候选余下两把，均自检绿、无实参自包含，可直接轮换）。
  `check_tool_coverage` 在 BUG-636 转正前退出候选。

## 后续建议

- **最高优先仍为 BUG-636**：待 `memory/bugs.md` WIP 解禁后专门轮次委派（含「加进 `_tool_registry.consumers()`
  收口格」最易漏环节）。
- **建议专门轮次修 FIST 链提取鲁棒性**：给 `scripts/fist.py` 的 notice 走 stderr（或保证 stdout 只出 JSON 行），
  或在链脚本模板用「取能解析为 JSON 的行」稳健提取（本轮补跑脚本已验证该写法对真实两行输出有效）；
  修后 21 份历史 temp 链脚本失效但每轮重建件自动继承，无残留。
- **继续按注册面轮换**，优先选近期未轮过且有 `--selftest` 的判据。
- Round C 三件维持过期（owner 已裁决面），唤醒轮继续非阻塞巡检。

## 超额内容

无。

## 来源

- `git status --short` / `git diff --numstat` / 逐文件 `git diff`（run_guards.py +9 / README.md +2 /
  engine_circuit_test.mbt +5）+ `git show HEAD:memory/bugs.md`（2026-11-15 本轮实测）
- `reports/2026-11-15-r317-wakeup-patrol.md`（r317 WIP 基线 + owner 裁决件②「缺执行面/未注册」原文，增长判定对照）
- `python scripts/check_effective_catch.py --selftest`（8/8）+ `python scripts/check_effective_catch.py`（PASS rc=0）
  （本轮，证据 `temp/r318_ec_selftest.txt` / `temp/r318_ec_real.txt`）
- `python scripts/check_tools_sync.py`（183 PASS）/ `python scripts/check_instruction_budget.py`（50440/65536 PASS）
  （本轮，证据 `temp/r318_ts.txt` / `temp/r318_ib.txt`）
- `temp/fist_r318_out/1_publish.txt`（两行：BUG-32 提示 + JSON task_id=T0r74）/ `chain.log`（首轮 + 补跑 rc 分解）
  / `6b_verify.txt`（status=已完成、completed_by=wd-r318）/ `task_id.txt`（T0r74）
- `grep` 排查：`memory/bugs.md` BUG-32（FIXED 2026-09-27 autobuild）/ `temp/fist_r*_chain.sh` 21 份脆弱提取计数
