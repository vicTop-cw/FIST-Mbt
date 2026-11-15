# 轮 304 巡检报告（ExploreWatchdog 唤醒 · 2026-11-15）

## 结果摘要

- **WIP 四件套冻结零变化第 21 轮**：`git status --short` 与 r284~r303 逐字同——
  `M docs/improvement-plan-20261010.md` / `M memory/bugs.md` / `M memory/target.md` /
  `?? scripts/check_mcpcf_db_isolation.py`；mtimes 全早于 r284 提交时刻（15:19:37），
  相对 r303 零新增量。r287 提请的 owner 弃置裁决维持挂起（指挥官不代行清理）。
- **Round C 三件维持过期不执行**：BUG-527 owner 否决 / BUG-530 FIXED /
  `check_usage_tool_count` 已注册（run_guards.py:175）。
- **换面巡检 `check_store_tables_wired`（BUG-28 store schema 接线一致守卫：库内每张表
  要么有写入点、要么在 store 源文件 `schema-reserved:` 点名预留，死 schema 与
  声明滞后两个方向都判红；r299~r303 未轮过·本轮首跑）**：
  - `--selftest` → SELFTEST OK rc=0（死 schema 必红 / 声明滞后必红 / 干净输入不误红 / 表名解析口径可证）；
  - 实测 rc=0：**32 张表 = 31 张有写入点 + 1 张显式预留（runs）**。
- **零漂移两把尺**：`check_tools_sync` 183 一致 rc=0（R8 清单分组 19 组 ΣN=183）；
  `check_instruction_budget` 50440/65536 rc=0（全部章节可见）。
- **无新发现、无新立账**；禁区零碰（4 个 WIP 文件零改、不提交）。

## 资源消耗

- 判据 3 支（1 换面巡检 + 2 零漂移）+ FIST 六步链 1 发；本轮无子代理。

## 任务分配记录

- FIST 闭环 T0r60 六步全链（wd-r304，ns watchdog）：
  `temp/fist_r304_chain.sh` 后台串跑，回盘 `temp/fist_r304_out/1..6_*.txt`
  （publish / agent_acl_grant / claim / execute / submit / verify）。

## 遗留风险

- WIP 四件套冻结第 21 轮，跨日 11-14→11-15 仍零变化；弃置裁决持续挂起等 owner。
- r302 发现（AGENTS.md:360 check_demo_isolation 散文计数 29 ↔ 实测 36 漂移）落账仍受阻
  （memory/bugs.md 被 WIP 占用，指挥官不代行），维持待 owner 裁决 A/B 两方案。

## 后续建议

- 换面巡检继续轮换制：本轮 `check_store_tables_wired` 已跑，下轮候选
  `check_publish_payload` / `check_workflow_step_parity` / `check_pkg_imports`。

## 超额内容

- 无。

## 来源

- `git status --short` / `git log --oneline -5`（HEAD ee8df22bc = r303 提交）
- `python scripts/check_store_tables_wired.py --selftest` 与实测输出
- `python scripts/check_tools_sync.py` / `python scripts/check_instruction_budget.py` 输出
- `temp/fist_r304_out/` 六步回盘
