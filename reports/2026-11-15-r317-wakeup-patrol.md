# 轮 317 唤醒巡检报告

**日期**：2026-11-15
**轮次**：r317
**执行者**：wd-r317（FIST-Mbt-ExploreWatchdog）

## 结果摘要

WIP 四件套冻结零变化第 34 轮（numstat 逐字同 3 文件 7+/1- 208+/0- 1+/1- = 216+/2-，非新 WIP 事件）。
换面巡检 `check_ci_step_position`（r300~r316 未轮过·本轮首跑）自检 9 格 SELFTEST PASS + 实测 PASS rc=0
（position-why 锚点面 8 份 workflow / 133 步骤 / 8 个 Migrate 基准，缺锚点违例 29 / 上限 34，只许降；
continue-on-error 6 处只报不判；无 Migrate workflow 的 gate 步骤 2 处出数）。
零漂移 check_tools_sync 183 / check_instruction_budget 50440/65536 均 rc=0。
**补轮 316 悬置报告**：r316 FIST 闭环 T0r72 六步全 rc=0、verify status=已完成、报告已写全，但该轮
scoped 落盘缺失（HEAD 停 r315）⇒ 本轮一并 scoped 提交收口（r308→r309 先例），双格齐。
无新发现、无新立账。

## 巡检明细

1. **WIP 状态**（`git status --short` + `git diff --numstat HEAD`）：
   - 3 个已跟踪 WIP 文件 numstat 逐字同 r284~r316（`docs/improvement-plan-20261010.md` 7+/1-、
     `memory/bugs.md` 208+/0-、`memory/target.md` 1+/1-，合计 216+/2-）；
   - 未跟踪 `scripts/check_mcpcf_db_isolation.py` 无变化 ⇒ **冻结零变化第 34 轮**，非新 WIP 事件。
   - 内容面：`memory/bugs.md` +208 行仍为 vq 项目（Python+Vue+Rust）外来账 BUG-592~635，
     与本纯 MoonBit 仓无关 ⇒ 持续挂 owner 裁决，**本轮不碰、不落账**
     （提交该文件会连带带走 208 行 WIP，触发 commit-discipline 的「窗口」事故）。

2. **换面巡检 `check_ci_step_position`**（CI gate 步骤位置纪律判据，r300~r316 未轮过·本轮首跑）：
   - 自检：`--selftest` **9 格 SELFTEST PASS**（T1 后置无锚必红 / T2 后置有锚不红 / T3 前置无锚不红 /
     T4 无 Migrate 豁免 / T5 continue-on-error 出数不判红 / T6 空文本零步骤 / T7 非 gate 步骤不抓 /
     T8 check_ 脚本引用也算 gate 必红 / T9 真源现状 rc=0）；
   - 实测：**PASS rc=0**——「position-why 锚点面 8 份 workflow / 133 步骤 / 8 个 Migrate 基准；
     缺锚点违例 29（上限 34，只许降）」+「continue-on-error 6 处（F2 只报不判）」+
     「无 Migrate workflow 的 gate 步骤 2 处（F3 豁免位置纪律，出数：gate.yml Run unified gate chain /
     Branch-ancestry gate R66/BUG-398）」；
   - 选面理由：CI 步骤位置纪律是「格式门/探针门不许被挪到 Migrate 之后」的守卫面，与 r311~r315
     轮过的判据零重叠，且近期未轮过。

3. **零漂移双检**：
   - `check_tools_sync` rc=0（server.mbt 注册 183，AGENTS/README/deliverable/scoring_rubric 对齐；
     R3b/R7 扫现状面 168 份、历史面豁免 25 份；R8 清单分组 19 组 ΣN=183 对表一致）；
   - `check_instruction_budget` rc=0（AGENTS.md 50440 / 65536 字节，全部章节可见）。

4. **Round C 三件**：维持过期不执行——BUG-527 摘 cc-link-flags 已 owner 否决（CI A/B 实证有害）、
   BUG-530 已 FIXED（3699f012a）、`check_usage_tool_count` 已注册（run_guards.py:175）。

5. **补轮 316 悬置报告收口**：r316 会话（wd-r316）FIST 闭环 **T0r72 六步全 rc=0**（`temp/fist_r316_out/`
   chain.log 六步 rc=0、verify status=已完成、completed_by=wd-r316），报告 `reports/2026-11-15-r316-
   wakeup-patrol.md` 已写全，但该轮 **scoped 落盘缺失**（HEAD 停 r315、报告仍 untracked）⇒ 与 r308
   同形。本轮把 r316 报告一并纳入 scoped 提交（见「任务分配记录」），使 r316 记账收口双格齐
   （FIST ✓ + 报告 scoped 提交 ✓）。

6. **新发现 / 新立账**：无。

## 资源消耗

- 判据 4 支（1 换面巡检 check_ci_step_position selftest + 实测 + 2 零漂移）+ WIP 核验 1 支 +
  FIST 六步链 1 发（后台）；
- 本轮无子代理（巡检判据为轻量命令执行 + 只读核验，命令结果需指挥官亲阅终审，故直跑）。

## 任务分配记录

- **r317 FIST 闭环 T0r73 六步全链**（wd-r317，ns watchdog）：`temp/fist_r317_chain.sh` 后台串跑
  （node 冷启动 ~2min/步），回盘 `temp/fist_r317_out/1..6_*.txt`
  （publish / agent_acl_grant / claim / execute / submit / verify）。
- **r316 补提交**：`reports/2026-11-15-r316-wakeup-patrol.md` 与本报告**同一笔 scoped 提交**
  （`git commit -F msg -- <两报告路径>`，只落这 2 份、不带走 4 个冻结 WIP 文件），使 r316 悬置报告
  收口（r308→r309 先例）。

## 遗留风险

- **WIP 四件套冻结第 34 轮**，`memory/bugs.md` +208 行仍为 vq 外来账（BUG-592~635），挂 owner 裁决。
- **BUG-636（临时号）待落账 + 待修复**：`check_tool_coverage` 未接线第 6 真源消费者、漏扫 18 工具
  （7 个零 A 面覆盖），修复规格见 `reports/2026-11-15-r315-wakeup-patrol.md`；落账推迟到
  `memory/bugs.md` WIP 解禁 / owner 裁决后。
- **owner 裁决件累计五件**（同 r315/r316）：① WIP 四件套弃置 ② `scripts/check_mcpcf_db_isolation.py`
  双风险（`moon publish` 公开面 + 缺执行面 / 未注册 run_guards，判例-5 同族）③ r302 落账方式
  ④ 外来账处置（搬移 vq 仓 / 登记 WHITELIST kind=foreign-adjudicated）⑤ BUG-636 known-red 登记口径。
- **换面巡检轮换面**：r317 轮到 `check_ci_step_position`；下一轮候选
  `check_effective_catch` / `check_ns_write_gate_coverage` / `check_desc_enum_sync`
  （本轮三把均自检绿、无实参自包含，可直接轮换）。`check_tool_coverage` 在 BUG-636 转正前退出候选。

## 后续建议

- 继续按注册面轮换，优先选近期未轮过且有 `--selftest` 的判据。
- Round C 三件维持过期（owner 已裁决面），唤醒轮继续非阻塞巡检。
- **最高优先仍为 BUG-636**：待 `memory/bugs.md` WIP 解禁后专门轮次委派（含「加进
  `_tool_registry.consumers()` 收口格」最易漏环节）。

## 超额内容

无。

## 来源

- `git status --short` / `git diff --numstat HEAD -- <3 WIP 文件>` / `git log --oneline`（2026-11-15 本轮实测）
- `python scripts/check_ci_step_position.py --selftest`（9 格）+ `python scripts/check_ci_step_position.py`（PASS rc=0）（本轮，证据 `temp/r317_cisp.txt`）
- `python scripts/check_tools_sync.py`（183 PASS）/ `python scripts/check_instruction_budget.py`（50440/65536 PASS）（本轮，证据 `temp/r317_ts.txt` `temp/r317_ib.txt`）
- `temp/fist_r316_out/chain.log` + `6_verify.txt` + `task_id.txt`（T0r72 六步 rc=0、verify status=已完成、completed_by=wd-r316）
- `temp/fist_r317_out/`（r317 FIST 六步链回盘）
- `reports/2026-11-15-r315-wakeup-patrol.md`（BUG-636 修复规格）/ `reports/2026-11-15-r316-wakeup-patrol.md`（补提交源）
