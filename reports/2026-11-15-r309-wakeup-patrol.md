# 轮 309 巡检报告（ExploreWatchdog 唤醒 · 2026-11-15）

## 结果摘要

- **WIP 四件套冻结零变化第 26 轮**：`git status --short` 与 r284~r308 逐字同——
  `M docs/improvement-plan-20261010.md` / `M memory/bugs.md` / `M memory/target.md` /
  `?? scripts/check_mcpcf_db_isolation.py`；`git diff --numstat` 逐字同 3 文件 **216+/2-**
  （`memory/bugs.md` **208+/0** = vq 项目外来误落账批次 BUG-592~635，`docs/improvement-plan`
  7+/1-，`memory/target.md` 1+/1-）。四件套 **mtime 全早于 r284 提交 15:19:37**，内容零变化、
  **非新 WIP 事件**，不立账。r287 提请的 owner 弃置裁决维持挂起（指挥官不代行清理）。
- **Round C 三件维持过期不执行**：BUG-527 owner 否决 / BUG-530 FIXED /
  `check_usage_tool_count` 已注册（run_guards.py:175）。
- **补 r308 悬置报告**：r308 会话 FIST 闭环 T0r64 六步全 rc=0、报告
  `reports/2026-11-15-r308-wakeup-patrol.md` 已写全，但该轮 scoped 提交未落盘
  （`git log` HEAD 停在 r307 a8473c4d8）⇒ 本轮补该笔提交（commit A），使 r308 记账收口双格齐。
- **换面巡检 `check_arg_face_strict`（参数面元判据 R64；r303~r308 未轮过·本轮首跑）**：
  - `--selftest` → **3/3 格 SELFTEST OK rc=0**（bad-arg-guard-is-flagged /
    good-arg-guard-not-flagged / empty-candidate-face-returns-zero-count，判例-29/30 变异对照）；
  - 实测 **PASS rc=0**（**扫描面 100 把 `check_*.py` 全严格**：遇未知旗标
    `--definitely-not-a-real-flag` 均拒绝出绿 rc≠0）。
  - **读数对照**：R64 实测 27 把中招 ⇒ R65 还 12 把 ⇒ R66 还 15 把清零（75/75），现扫描面
    扩到 **100 把仍全严格** ⇒ R64 债务自 R66 还完后**保持清零、扩面零回归**。
- **低优打磨点（本轮不内联改，记入遗留风险待下轮）**：`check_arg_face_strict.py` 的
  **docstring 残留 R64 时代旧散文**（「现读 27 把 known-red / 占 75 把的 36% / 以
  `kind=known-red` 登记在电池里」），而 `run_guards.py:234` 注册面**已是正确门禁格**
  （`case(...)` 而非 `expected(...,kind=known-red)`）、实测 0 违例 ⇒ **自述滞后于现状**
  （本仓 bug 家族：抄一个数就是下一颗漂移雷）。纯注释、零逻辑、不影响电池判定；下轮可改
  docstring 散文对齐现读（0 违例 / 100 把 / 门禁格），指挥官本轮不代行内联改。
- **零漂移两把尺**：`check_tools_sync` 183 一致 rc=0（server.mbt 注册 183，AGENTS/README/
  deliverable/scoring_rubric 对齐；R8 清单分组 19 组 ΣN=183）；`check_instruction_budget`
  50440/65536 rc=0（全部章节可见）。均与 r308 读数一致。
- **禁区零碰**：4 个 WIP 文件零改、不提交。

## 资源消耗

- 判据 4 支（1 换面巡检 selftest + 1 实测 + 2 零漂移）+ FIST 六步链 1 发；本轮无子代理
  （巡检判据为轻量命令执行，命令结果需指挥官亲阅终审，故直跑；低优 docstring 打磨点仅
  记录、未委派内联改，避免 30min 巡检窗口内一次注释改动引入新的漂移面）。

## 任务分配记录

- FIST 闭环 T0r65 六步全链 rc=0 一发收口（wd-r309，ns watchdog）：`temp/fist_r309_chain.sh`
  后台串跑，回盘 `temp/fist_r309_out/1..6_*.txt`（publish / agent_acl_grant / claim /
  execute / submit / verify）；verify 回执 **status=已完成、completed_by=wd-r309**，
  writable_agents 63→64。

## 遗留风险

- WIP 四件套冻结第 26 轮，跨日 11-14→11-15 仍零变化；弃置裁决持续挂起等 owner。
- **owner 裁决件累计四件**：① WIP 四件套弃置 ② `scripts/check_mcpcf_db_isolation.py`
  双风险（`moon publish` 公开面 + 未注册 run_guards）③ r302 落账方式 ④ 外来账
  BUG-613~635 处置（搬移 vq 仓 / 登记 WHITELIST kind=foreign-adjudicated）。
- **新记低优打磨点**：`check_arg_face_strict.py` docstring 自述滞后（R64 旧散文
  「27 把 known-red / 75 把」vs 现读「0 违例 / 100 把 / 门禁格」），纯注释零逻辑、非功能
  缺陷、不立账，下轮可改注释对齐现读。

## 后续建议

- 换面巡检继续轮换制：本轮 `check_arg_face_strict` 已跑（读数 100/100 全严格、零回归）；
  下轮候选 `check_plugin_sync`（cl7 一源四态；脏树 rc=1 为 WIP 投影已知读数，r292 实证）/
  `check_model_auth_no_key` / `check_dead_params`。
- 若 owner 裁决任一裁决件，需按对应纪律同批落（外来账登记 WHITELIST ⇒ 同批 `gen_plugins.py`
  重投影 cl7；check_mcpcf_db_isolation.py 入库 ⇒ 同批给执行面）。

## 超额内容

- 无。

## 来源

- `git status --short` / `git log --oneline -5`（HEAD a8473c4d8 = r307 提交，2026-11-15 11:55:16）
- `git diff --numstat`（216+/2- 逐文件分解：bugs.md 208+/0、improvement-plan 7+/1-、target 1+/1-）
- `python scripts/check_arg_face_strict.py --selftest`（3/3）与实测输出（扫描面 100 把全严格 rc=0）
- `scripts/run_guards.py:231-235`（R64/R66 注释 + `case("check_arg_face_strict.py")` 门禁格）
- `python scripts/check_tools_sync.py` / `python scripts/check_instruction_budget.py` 输出
- `temp/fist_r309_out/` 六步回盘（T0r65，verify status=已完成）
- `temp/fist_r308_out/`（补 r308 悬置报告依据：T0r64 六步全 rc=0、verify completed_by=wd-r308）
