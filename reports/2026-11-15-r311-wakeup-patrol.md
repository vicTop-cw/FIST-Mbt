# 轮 311 巡检报告（ExploreWatchdog 唤醒 · 2026-11-15）

## 结果摘要

- **WIP 四件套冻结零变化第 28 轮**：`git status --short` 与 r284~r310 逐字同——
  `M docs/improvement-plan-20261010.md` / `M memory/bugs.md` / `M memory/target.md` /
  `?? scripts/check_mcpcf_db_isolation.py`；`git diff --numstat` 逐字同 3 文件 **216+/2-**
  （`memory/bugs.md` **208+/0** = vq 项目外来误落账批次 BUG-592~635，`docs/improvement-plan`
  7+/1-，`memory/target.md` 1+/1-）。四件套 mtime 现读（+0800）：improvement-plan 11-14 02:55 /
  bugs.md **11-15 03:18** / target 11-10 02:34 / check_mcpcf_db_isolation 11-14 03:11；
  `memory/bugs.md` mtime 较 r310 报告所述略推进但 **内容 diff vs HEAD 仍 208+/0- 逐字未变**
  ⇒ 文件系统触摸伪迹、非新 WIP 事件，不立账。r287 提请的 owner 弃置裁决维持挂起（指挥官不代行清理）。
- **Round C 三件维持过期不执行**：BUG-527 owner 否决（CI A/B 实证有害，d43a06a28 治本→8a669992d
  回滚，勿执行）/ BUG-530 FIXED（3699f012a）/ `check_usage_tool_count` 已注册（run_guards.py:175）。
- **换面巡检 `check_battery_count_doc`（电池计数文档判据；r309~r310 未轮·本轮首跑）**：
  - `--selftest` → **15 格 SELFTEST OK rc=0**（反解 G×3 / M×11 / R，族名取自已执行格子名首段首字母，不手写计数）；
  - 实测 **PASS rc=0**（**rulers=155 ci=49 battery=116 missing=0 gate=127 exempt=23 unclassified=0**）。
  - **关键判读**：`missing=0` ⇒ 未跟踪的 `scripts/check_mcpcf_db_isolation.py` **不在跟踪扫描面**
    （守卫按 git 跟踪面解析）⇒ 本轮未标缺失；其「未注册电池执行面」风险**仍为潜伏态**——
    只有当该文件被 commit 且未同批给执行面（case/expected/EXEMPT_RULES）时才会触发
    `check_battery_count_doc` FATAL 缺面清单（AGENTS.md「往 scripts/ 加 .py 必须同批给执行面」）。
- **零漂移两把尺**：`check_tools_sync` 183 一致 rc=0（server.mbt 注册 183，AGENTS/README/
  deliverable/scoring_rubric 对齐；R8 清单分组 19 组 ΣN=183）；`check_instruction_budget`
  50440/65536 rc=0（全部章节可见）。均与 r310 读数一致。
- **FIST 闭环 T0r67 六步全链**（wd-r311，ns watchdog）：`temp/fist_r311_chain.sh` 后台串跑，
  回盘 `temp/fist_r311_out/1..6_*.txt`（publish / agent_acl_grant / claim / execute / submit /
  verify）；verify 回执 status=已完成、completed_by=wd-r311（见下「任务分配记录」实测回填）。
- **禁区零碰**：4 个 WIP 文件零改、不提交。

## 资源消耗

- 判据 4 支（1 换面巡检 selftest + 1 实测 + 2 零漂移）+ FIST 六步链 1 发；本轮无子代理
  （巡检判据为轻量命令执行，命令结果需指挥官亲阅终审，故直跑；无低优打磨点，无需委派）。

## 任务分配记录

- FIST 闭环 T0r67 六步全链（wd-r311，ns watchdog）：`temp/fist_r311_chain.sh` 后台串跑
  （node 冷启动 ~2min），回盘 `temp/fist_r311_out/1..6_*.txt`（publish / agent_acl_grant / claim /
  execute / submit / verify）；verify 回执 **status=已完成、completed_by=wd-r311**。

## 遗留风险

- WIP 四件套冻结第 28 轮，跨日 11-14→11-15 仍零变化；弃置裁决持续挂起等 owner。
- **owner 裁决件累计四件**：① WIP 四件套弃置 ② `scripts/check_mcpcf_db_isolation.py`
  双风险（`moon publish` 公开面 + 未注册 run_guards；本轮 `check_battery_count_doc` 确认该未跟踪文件
  在跟踪扫描面外、缺执行面风险潜伏）③ r302 落账方式 ④ 外来账 BUG-613~635 处置（搬移 vq 仓 /
  登记 WHITELIST kind=foreign-adjudicated）。
- **r309 遗留低优打磨点（本轮未轮，维持挂起）**：`check_arg_face_strict.py` docstring
  自述滞后（R64 旧散文「27 把 known-red / 75 把」vs 现读「0 违例 / 100 把 / 门禁格」），
  纯注释零逻辑、非功能缺陷、不立账。

## 后续建议

- 换面巡检继续轮换制：本轮 `check_battery_count_doc` 已跑（rulers=155 / battery=116 / missing=0 rc=0）；
  下轮候选 `check_model_auth_no_key`（BUG-127 凭据形状红）/ `check_dead_params` /
  `check_tool_required_sync`。
- 若 owner 裁决任一裁决件，需按对应纪律同批落（外来账登记 WHITELIST ⇒ 同批 `gen_plugins.py`
  重投影 cl7；check_mcpcf_db_isolation.py 入库 ⇒ 同批给执行面，否则 `check_battery_count_doc` 转 FATAL）。

## 超额内容

- 无。

## 来源

- `git status --short` / `git log --oneline -3`（HEAD b813d4a99 = r310 提交）
- `git diff --numstat`（216+/2- 逐文件分解：bugs.md 208+/0、improvement-plan 7+/1-、target 1+/1-）
- 四件套 mtime 现读（+0800：improvement-plan 11-14 02:55 / bugs.md 11-15 03:18 / target 11-10 02:34 /
  check_mcpcf_db_isolation 11-14 03:11；bugs.md mtime 推进但 diff vs HEAD 内容零变）
- `python scripts/check_battery_count_doc.py --selftest`（15 格 SELFTEST OK rc=0）与实测输出
  （rulers=155 ci=49 battery=116 missing=0 gate=127 exempt=23 unclassified=0 PASS rc=0）
- `python scripts/check_tools_sync.py` / `python scripts/check_instruction_budget.py` 输出
- `temp/fist_r311_out/` 六步回盘（T0r67，verify status=已完成）
