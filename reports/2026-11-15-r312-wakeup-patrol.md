# 轮 312 巡检报告（ExploreWatchdog 唤醒 · 2026-11-15）

## 结果摘要

- **WIP 四件套冻结零变化第 29 轮**：`git status --short` 与 r284~r311 逐字同——
  `M docs/improvement-plan-20261010.md` / `M memory/bugs.md` / `M memory/target.md` /
  `?? scripts/check_mcpcf_db_isolation.py`；`git diff --numstat` 逐字同 3 文件 **216+/2-**
  （`memory/bugs.md` **208+/0** = vq 项目外来误落账批次，`docs/improvement-plan` 7+/1-，
  `memory/target.md` 1+/1-）。相对 r311 零新增量、**非新 WIP 事件**。r287 提请的
  owner 弃置裁决维持挂起（指挥官不代行清理）。
- **Round C 三件维持过期不执行**：BUG-527 owner 否决（CI A/B 实证有害，d43a06a28 治本→
  8a669992d 回滚，勿执行）/ BUG-530 FIXED（3699f012a）/ `check_usage_tool_count` 已注册
  （run_guards.py:175）。
- **换面巡检 `check_two_faces`（两面漂移判据；r307~r311 未轮过·本轮首跑）**：
  - `--selftest` → **27/27 格 SELFTEST OK rc=0**（含 MUTATION-copy-drift-detected /
    MUTATION-f3-mb-cmp-drift-detected / MUTATION-f3-sql-cmp-drift-detected /
    empty-scan-self-reject 等变异对照）；
  - 实测 **PASS rc=0**：**152 个 .mbt / F1 可判对象 0 条**（F1 抄本漂移无、F3
    `store_rsv ↔ store_sqlite` SQL 谓词 `<` 对表一致）；F2 同签名多定义 **83 组**
    （engine.mbt vs store_sqlite.mbt 双后端等）——**仅告警不判红**（多后端是合法设计）。
  - **关键判读**：本判据覆盖面 3/5 种「两面」形态（①同语言多实现 / ②真源 vs SQL 编码 /
    ③真源 vs 手工抄本），④消费面前提 / ⑤胶水语义不在覆盖面内（BUG-433 / BUG-431 /
    BUG-429）⇒ PASS 只代表「形态 ①②③ 无漂移」，**不代表无两面**。
- **补跑两把轻量尺**：`check_registration_numbers` PASS rc=0（文档条数声明 0 处、实测
  1 条一致）/ `check_doc_paths` PASS rc=0（8 份文档 / 47 处引用全部存在）。
- **零漂移两把尺**：`check_tools_sync` 183 一致 rc=0（server.mbt 注册 183，AGENTS/README/
  deliverable/scoring_rubric 对齐；R8 清单分组 19 组 ΣN=183）；`check_instruction_budget`
  50440/65536 rc=0（全部章节可见）。均与 r311 读数一致。
- **FIST 闭环 T0r68 六步全链**（wd-r312，ns watchdog）：`temp/fist_r312_chain.sh` 后台串跑，
  回盘 `temp/fist_r312_out/1..6_*.txt`（publish / agent_acl_grant / claim / execute / submit /
  verify）；verify 回执 status=已完成、completed_by=wd-r312（见下「任务分配记录」实测回填）。
- **禁区零碰**：4 个 WIP 文件零改、不提交。

## 资源消耗

- 判据 5 支（1 换面巡检 selftest + 1 实测 + 2 轻量补跑 + 2 零漂移）+ FIST 六步链 1 发；
  本轮无子代理（巡检判据为轻量命令执行，命令结果需指挥官亲阅终审，故直跑；无低优打磨点，
  无需委派）。

## 任务分配记录

- FIST 闭环 T0r68 六步全链（wd-r312，ns watchdog）：`temp/fist_r312_chain.sh` 后台串跑
  （node 冷启动 ~2min），回盘 `temp/fist_r312_out/1..6_*.txt`（publish / agent_acl_grant /
  claim / execute / submit / verify）；verify 回执 **status=已完成、completed_by=wd-r312**。

## 遗留风险

- WIP 四件套冻结第 29 轮，跨日 11-14→11-15 仍零变化；弃置裁决持续挂起等 owner。
- **owner 裁决件累计四件**：① WIP 四件套弃置 ② `scripts/check_mcpcf_db_isolation.py`
  双风险（`moon publish` 公开面 + 未注册 run_guards；r311 `check_battery_count_doc` 确认该
  未跟踪文件在跟踪扫描面外、缺执行面风险潜伏）③ r302 落账方式 ④ 外来账处置（搬移 vq 仓 /
  登记 WHITELIST kind=foreign-adjudicated）。
- **r309 遗留低优打磨点（本轮未轮，维持挂起）**：`check_arg_face_strict.py` docstring
  自述滞后（R64 旧散文「27 把 known-red / 75 把」vs 现读「0 违例 / 100 把 / 门禁格」），
  纯注释零逻辑、非功能缺陷、不立账。

## 后续建议

- 换面巡检继续轮换制：本轮 `check_two_faces` 已跑（152 .mbt / F1 0 / F2 83 组仅告警 /
  F3 对齐，rc=0）；下轮候选 `check_model_auth_no_key`（BUG-127 凭据形状红）/
  `check_dead_params` / `check_tool_required_sync`。
- 若 owner 裁决任一裁决件，需按对应纪律同批落（外来账登记 WHITELIST ⇒ 同批 `gen_plugins.py`
  重投影 cl7；check_mcpcf_db_isolation.py 入库 ⇒ 同批给执行面，否则 `check_battery_count_doc`
  转 FATAL）。

## 超额内容

- 无。

## 来源

- `git status --short` / `git log --oneline -5`（HEAD d1bfac1cf = r311 提交）
- `git diff --numstat`（216+/2- 逐文件分解：bugs.md 208+/0、improvement-plan 7+/1-、target 1+/1-）
- `python scripts/check_two_faces.py --selftest`（27/27 SELFTEST OK rc=0）与实测输出
  （152 .mbt / F1 0 / F2 83 组多定义仅告警 / F3 store_rsv↔store_sqlite `<` 对齐 PASS rc=0）
- `python scripts/check_registration_numbers.py` / `python scripts/check_doc_paths.py` 输出（均 rc=0）
- `python scripts/check_tools_sync.py` / `python scripts/check_instruction_budget.py` 输出
- `temp/fist_r312_out/` 六步回盘（T0r68，verify status=已完成）
