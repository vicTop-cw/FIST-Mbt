# 轮 308 巡检报告（ExploreWatchdog 唤醒 · 2026-11-15）

## 结果摘要

- **WIP 四件套冻结零变化第 25 轮**：`git status --short` 与 r284~r307 逐字同——
  `M docs/improvement-plan-20261010.md` / `M memory/bugs.md` / `M memory/target.md` /
  `?? scripts/check_mcpcf_db_isolation.py`；`diff --stat` 逐字同 3 文件 **216+/2-**
  （`memory/bugs.md` **208+/0** = vq 项目外来误落账批次 BUG-592~635，`docs/improvement-plan`
  7+/1-，`memory/target.md` 1+/1-）。四件套 **mtimes 逐字同 r307 记录**（bugs.md
  11-15 11:18:42 早于 r307 提交 11:55:16、improvement-plan 11-14 10:55:34 / target.md
  11-10 10:34:16 / check_mcpcf_db_isolation.py 11-14 11:11:49）⇒ 内容零变化、**非新 WIP 事件**，
  不立账。r287 提请的 owner 弃置裁决维持挂起（指挥官不代行清理）。
- **Round C 三件维持过期不执行**：BUG-527 owner 否决 / BUG-530 FIXED /
  `check_usage_tool_count` 已注册（run_guards.py:175）。
- **换面巡检 `check_foreign_ledger_entries`（外来账检测守卫 · BUG-565 检测半；
  r303~r307 未轮过、自 r281 后首跑）**：
  - `--selftest` → **15/15 格 SELFTEST OK rc=0**（clean-rc0 / MUT 外来 summary 必红 /
    MUT 外来 detail 必红 / 元条目 BUG-565 形不误红 / MUT 同文非白名单 id 必红 /
    reporter 署名不误红 / evidence 引用不误红 / ns cwd 上下文不误红 / 无条目 rc2 /
    空文本 rc2 / 缺文件 rc2 / 未知旗标拒 rc2 / 自检旗拼错拒 rc2 / 正则与 gen_plugins 同口径 /
    内联坏抬头不分裂条目）；
  - 实测 **rc=1**（脏树基线外投影，符合判据定位「只检测不处置」）：账本 **620** 条目、
    外来信号命中 **63**（白名单内 **40** / 白名单外 **23**）；
  - **新发现**：基线外 **23 条 = BUG-613~635**，较 r281 基线 **12 条（BUG-613~624）增长 11 条**
    vq-P7 批次（**BUG-625~635**）。逐条核验全为 vq 项目缺陷（`crates/vq-cli`、`vq-mcp`
    server.rs 18 工具、`vq-p7-commander`，路径 `E:/IDEProjects/AI/vq`，含
    `FIXED(2026-11-15T03:18:xxZ / BUG-625~635)` 两枚收口块），误落本纯 MoonBit 仓。
  - **处置**：属 owner 裁决项（BUG-565）——搬移 vq 仓 / 带理由登记 `WHITELIST`
    `kind=foreign-adjudicated`；**指挥官不代行清理、不立新账**（同族持续，挂 BUG-565 根因：
    server cwd 钉本树、调用方无出路）。r303~r307 未轮此守卫，故该增长此前未被正式点报。
- **零漂移两把尺**：`check_tools_sync` 183 一致 rc=0（server.mbt 注册 183，AGENTS/README/
  deliverable/scoring_rubric 对齐；R8 清单分组 19 组 ΣN=183）；`check_instruction_budget`
  50440/65536 rc=0（全部章节可见）。均与 r307 读数一致。
- **禁区零碰**：4 个 WIP 文件零改、不提交。

## 资源消耗

- 判据 4 支（1 换面巡检自检 + 1 实测 + 2 零漂移）+ FIST 六步链 1 发；本轮无子代理。

## 任务分配记录

- FIST 闭环 T0r64 六步全链 rc=0 一发收口（wd-r308，ns watchdog）：`temp/fist_r308_chain.sh`
  后台串跑，回盘 `temp/fist_r308_out/1..6_*.txt`（publish / agent_acl_grant / claim /
  execute / submit / verify）；verify 回执 status=已完成、completed_by=wd-r308。

## 遗留风险

- WIP 四件套冻结第 25 轮，跨日 11-14→11-15 仍零变化；弃置裁决持续挂起等 owner。
- **外来账待裁决队列增长（本轮新点报）**：`check_foreign_ledger_entries` 基线外 **23 条**
  （BUG-613~635），较 r281 的 12 条（BUG-613~624）新增 vq-P7 批次 BUG-625~635；处置
  （搬移 vq 仓 / 登记 WHITELIST kind=foreign-adjudicated）属 owner 裁决，指挥官不代行。
- r305 新发现（`scripts/check_mcpcf_db_isolation.py` 双风险：`moon publish` 公开面 +
  未注册 `run_guards.py`）仍待 owner 裁决（方案 A 推荐：WIP 提交时同批给执行面 +
  入库或进 .gitignore / 方案 B：指挥官代落账，当前 memory/bugs.md 被 WIP 占用受阻）。
- r302 发现（AGENTS.md:360 check_demo_isolation 散文计数 29 ↔ 实测 36 漂移）落账仍受阻
  （memory/bugs.md 被 WIP 占用，指挥官不代行），维持待 owner 裁决 A/B 两方案。

## 后续建议

- 换面巡检继续轮换制：本轮 `check_foreign_ledger_entries` 已跑（其基线外 23 条读数已
  刷新，下轮若再跑应为同 23 条 = 冻结投影、非回归）；下轮候选 `check_plugin_sync`
  （cl7 一源四态；脏树 rc=1 为 WIP 投影已知读数，r292 实证）/ `check_arg_face_strict` /
  `check_model_auth_no_key`。
- **owner 裁决件累计四件**：WIP 四件套弃置、新脚本执行面 + publish 公开面、r302 落账方式、
  **外来账 BUG-613~635 处置（搬移 vq 仓 / 登记 WHITELIST）**。
- 若 owner 采纳「登记 WHITELIST kind=foreign-adjudicated」，需同批跑 `python
  scripts/gen_plugins.py`（改 memory/bugs.md / 计数面 ⇒ 插件态重投影纪律，cl7 会拦漏跑）。

## 超额内容

- 无。

## 来源

- `git status --short` / `git log --oneline -5`（HEAD a8473c4d8 = r307 提交，2026-11-15 11:55:16）
- `stat` 四件套 mtime 对照 + `git diff --numstat`（216+/2- 逐文件分解）+ `git diff -- memory/bugs.md`（BUG-592~635 内容抽查）
- `python scripts/check_foreign_ledger_entries.py --selftest`（15/15）与实测输出（620 条目 / 命中 63 / 基线外 23）
- `python scripts/check_tools_sync.py` / `python scripts/check_instruction_budget.py` 输出
- `temp/fist_r308_out/` 六步回盘
