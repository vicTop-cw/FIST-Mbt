# 轮 305 巡检报告（ExploreWatchdog 唤醒 · 2026-11-15）

## 结果摘要

- **WIP 四件套冻结零变化第 22 轮**：`git status --short` 与 r284~r304 逐字同——
  `M docs/improvement-plan-20261010.md` / `M memory/bugs.md` / `M memory/target.md` /
  `?? scripts/check_mcpcf_db_isolation.py`；mtimes 逐字同（10:47:48 / 10:55:34 / 11-10 10:34:16 /
  11:11:49，全早于 r284 提交 15:19:37），`diff --stat` 逐字同 3 文件 208+/2-，相对 r304 零新增量。
  r287 提请的 owner 弃置裁决维持挂起（指挥官不代行清理）。
- **Round C 三件维持过期不执行**：BUG-527 owner 否决 / BUG-530 FIXED /
  `check_usage_tool_count` 已注册（run_guards.py:175）。
- **换面巡检 `check_publish_payload`（BUG-127：`moon publish` 打包面 = 工作树 − .gitignore
  而不是 git 跟踪面，未跟踪又未忽略的文件会被公开点名，红面含凭据形状另判 P2 事故级；
  r295~r304 未轮过·本轮首跑）**：
  - `--selftest` → SELFTEST OK rc=0（S0 沙箱形状自证 / M4 非 git 仓必自拒 / G1 干净不误红 /
    G2 带未跟踪件逐件点名且无幻影红 / M1 未跟踪未忽略必红 / M2 被 ignore 挡住不红 /
    M3 凭据形状点名 P2 / M5 拆件幂等）；
  - 实测 **rc=1，P1 VIOLATION**：`scripts/check_mcpcf_db_isolation.py` 未被 .gitignore 挡住
    又没被 git 跟踪 ⇒ `moon publish` 会把它公开出去（当前脏树若被发布即触发；CI 干净检出不受影响）。
- **零漂移两把尺**：`check_tools_sync` 183 一致 rc=0（R8 清单分组 19 组 ΣN=183）；
  `check_instruction_budget` 50440/65536 rc=0（全部章节可见）。均与 r304 读数一致。
- **新发现（同一文件双风险，未落账·memory/bugs.md 被 WIP 占用指挥官不代行）**：
  1. `check_publish_payload` P1：`scripts/check_mcpcf_db_isolation.py` 将被 `moon publish` 公开（如上）；
  2. 该文件**未注册 `scripts/run_guards.py`**（grep 零命中）——按 AGENTS.md「往 `scripts/` 加
     `.py` 必须同批给执行面」纪律（判例-5 同族，一天 3 次踩中），其提交时
     `check_battery_count_doc` 将 FATAL（缺面清单点名）。
- **禁区零碰**：4 个 WIP 文件零改、不提交。

## 资源消耗

- 判据 3 支（1 换面巡检 + 2 零漂移）+ FIST 六步链 1 发；本轮无子代理。

## 任务分配记录

- FIST 闭环 T0r61 六步全链（wd-r305，ns watchdog）：
  `temp/fist_r305_chain.sh` 后台串跑，回盘 `temp/fist_r305_out/1..6_*.txt`
  （publish / agent_acl_grant / claim / execute / submit / verify）。

## 遗留风险

- WIP 四件套冻结第 22 轮，跨日 11-14→11-15 仍零变化；弃置裁决持续挂起等 owner。
- **新·`scripts/check_mcpcf_db_isolation.py` 双风险**（待 WIP owner 收口时一并处理）：
  - 方案 A（推荐）：WIP 提交时同批给执行面（case 进电池 / expected 带理由 / EXEMPT_RULES
    仅限共享模块与一次性工具；共享模块可改 `_` 前缀自动豁免）+ 入库或进 .gitignore
    （二选一，消除 publish 公开面）；
  - 方案 B：指挥官代落账立 BUG（memory/bugs.md 当前被 WIP 占用，受阻，需 owner 先裁决
    该 WIP 的归属与收口时点）。
- r302 发现（AGENTS.md:360 check_demo_isolation 散文计数 29 ↔ 实测 36 漂移）落账仍受阻
  （memory/bugs.md 被 WIP 占用，指挥官不代行），维持待 owner 裁决 A/B 两方案。

## 后续建议

- 换面巡检继续轮换制：本轮 `check_publish_payload` 已跑，下轮候选
  `check_plugin_sync`（cl7 一源四态）/ `check_host_installable` / `check_arg_face_strict`。
- owner 裁决件累计三件：WIP 四件套弃置、新脚本执行面 + publish 公开面、r302 落账方式。

## 超额内容

- 无。

## 来源

- `git status --short` / `git --no-pager log --oneline`（HEAD c49e0d21b = r304 提交）
- `python scripts/check_publish_payload.py --selftest` 与实测输出
- `python scripts/check_tools_sync.py` / `python scripts/check_instruction_budget.py` 输出
- `grep check_mcpcf_db_isolation scripts/run_guards.py`（零命中）
- `temp/fist_r305_out/` 六步回盘
