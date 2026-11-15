# 轮 310 巡检报告（ExploreWatchdog 唤醒 · 2026-11-15）

## 结果摘要

- **WIP 四件套冻结零变化第 27 轮**：`git status --short` 与 r284~r309 逐字同——
  `M docs/improvement-plan-20261010.md` / `M memory/bugs.md` / `M memory/target.md` /
  `?? scripts/check_mcpcf_db_isolation.py`；`git diff --numstat` 逐字同 3 文件 **216+/2-**
  （`memory/bugs.md` **208+/0** = vq 项目外来误落账批次 BUG-592~635，`docs/improvement-plan`
  7+/1-，`memory/target.md` 1+/1-）。四件套 **mtime 均早于 r284 提交 15:19:37**
  （improvement-plan 11-14 10:55 / bugs.md 11-15 11:18 触摸伪迹·内容零变 / target 11-10 10:34 /
  check_mcpcf_db_isolation 11-14 11:11），内容零变化、**非新 WIP 事件**，不立账。
  r287 提请的 owner 弃置裁决维持挂起（指挥官不代行清理）。
- **Round C 三件维持过期不执行**：BUG-527 owner 否决（CI A/B 实证有害，d43a06a28 治本→8a669992d
  回滚，勿执行）/ BUG-530 FIXED（3699f012a）/ `check_usage_tool_count` 已注册（run_guards.py:175）。
- **换面巡检 `check_sql_bind_alignment`（R177 SQL 三方对齐：列↔VALUES 项↔bind 次数；r305~r309 未轮过·本轮首跑）**：
  - `--selftest` → **7/7 格 SELFTEST OK rc=0**（s1 对齐样本判绿 / s2 变异对照少一 bind⇒红 /
    s3 列数≠占位符⇒红 / s4 插值列⇒绿但 degraded / s5 bind 缺号⇒红 / s7 委托助手绑定⇒绿且
    degraded / s6 无样本⇒rc=2 不自证归 2 不归 0，判例-29/30 变异对照）；
  - 实测 **PASS rc=0**（**19 处 INSERT 三方对齐**：占位符=bind 全对；其中 3 处列数为插值、
    仅校验占位符）。
- **零漂移两把尺**：`check_tools_sync` 183 一致 rc=0（server.mbt 注册 183，AGENTS/README/
  deliverable/scoring_rubric 对齐；R8 清单分组 19 组 ΣN=183）；`check_instruction_budget`
  50440/65536 rc=0（全部章节可见）。均与 r309 读数一致。
- **FIST 闭环 T0r66 六步全链 rc=0 一发收口**（wd-r310，ns watchdog）：`temp/fist_r310_chain.sh`
  后台串跑，回盘 `temp/fist_r310_out/1..6_*.txt`（publish / agent_acl_grant / claim /
  execute / submit / verify）；verify 回执 **status=已完成、completed_by=wd-r310**。
- **禁区零碰**：4 个 WIP 文件零改、不提交。

## 资源消耗

- 判据 4 支（1 换面巡检 selftest + 1 实测 + 2 零漂移）+ FIST 六步链 1 发；本轮无子代理
  （巡检判据为轻量命令执行，命令结果需指挥官亲阅终审，故直跑；无低优打磨点，无需委派）。

## 任务分配记录

- FIST 闭环 T0r66 六步全链 rc=0 一发收口（wd-r310，ns watchdog）：`temp/fist_r310_chain.sh`
  后台串跑（node 冷启动 ~2min），回盘 `temp/fist_r310_out/1..6_*.txt`（publish / agent_acl_grant
  / claim / execute / submit / verify）；verify 回执 **status=已完成、completed_by=wd-r310**。

## 遗留风险

- WIP 四件套冻结第 27 轮，跨日 11-14→11-15 仍零变化；弃置裁决持续挂起等 owner。
- **owner 裁决件累计四件**：① WIP 四件套弃置 ② `scripts/check_mcpcf_db_isolation.py`
  双风险（`moon publish` 公开面 + 未注册 run_guards）③ r302 落账方式 ④ 外来账
  BUG-613~635 处置（搬移 vq 仓 / 登记 WHITELIST kind=foreign-adjudicated）。
- **r309 遗留低优打磨点（本轮未轮，维持挂起）**：`check_arg_face_strict.py` docstring
  自述滞后（R64 旧散文「27 把 known-red / 75 把」vs 现读「0 违例 / 100 把 / 门禁格」），
  纯注释零逻辑、非功能缺陷、不立账。

## 后续建议

- 换面巡检继续轮换制：本轮 `check_sql_bind_alignment` 已跑（读数 19 处 INSERT 三方对齐 rc=0）；
  下轮候选 `check_model_auth_no_key`（BUG-127 凭据形状红）/ `check_dead_params` /
  `check_tool_required_sync`。
- 若 owner 裁决任一裁决件，需按对应纪律同批落（外来账登记 WHITELIST ⇒ 同批 `gen_plugins.py`
  重投影 cl7；check_mcpcf_db_isolation.py 入库 ⇒ 同批给执行面）。

## 超额内容

- 无。

## 来源

- `git status --short` / `git log --oneline -5`（HEAD 163b8f1c8 = r309 提交）
- `git diff --numstat`（216+/2- 逐文件分解：bugs.md 208+/0、improvement-plan 7+/1-、target 1+/1-）
- `git ls -la` 四件套 mtime 现读（improvement-plan 11-14 10:55 / bugs.md 11-15 11:18 / target
  11-10 10:34 / check_mcpcf_db_isolation 11-14 11:11，均早于 r284 提交 15:19:37）
- `python scripts/check_sql_bind_alignment.py --selftest`（7/7）与实测输出（19 处 INSERT 三方对齐 rc=0）
- `python scripts/check_tools_sync.py` / `python scripts/check_instruction_budget.py` 输出
- `temp/fist_r310_out/` 六步回盘（T0r66，verify status=已完成）
- `scripts/run_guards.py:273-274`（`check_sql_bind_alignment.py` 门禁格 + selftest 格）
