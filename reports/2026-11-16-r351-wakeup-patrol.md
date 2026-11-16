# 轮 351 唤醒巡检报告（ExploreWatchdog · 2026-11-16）

## 结果摘要

- **WIP 冻结判定**：`git status --short` = 6 M + 2 untracked（8 件），numstat 与 r326~r350 **逐字同**
  （bugs.md 216/0 零再增长、improvement-plan 7/1、target.md 1/1、README.md 2/1、
  run_guards.py 9/0、engine_circuit_test.mbt 5/0；untracked：check_mcpcf_db_isolation.py +
  pipeline_mode_loop.md，逐字同 r350）⇒ **WIP 非冻结增长后静止第 32 轮**，
  R192 车道自 r318 后持续停摆、src/** + run_guards.py 仍 M ⇒ **巡检分支**。
- **Round C 三件**（BUG-527 治本 / BUG-530 修复 / check_usage_tool_count 注册）维持**过期不执行**（src/** 未解禁）。
- **换面巡检 `check_two_faces`**（R12「两个面」漂移普查判据：真源 vs ①另一套执行点 / ②SQL 编码 /
  ③手工抄本——**本判据只覆盖 ①②③**，④消费面的前提 / ⑤胶水的语义不在覆盖面，PASS 只代表
  「形态 ①②③ 无两面」不代表无两面——本仓 6 天内同一根因踩 5 次〔BUG-420/425、R10 内存vsSQLite、
  R10 rsv_action、BUG-435 constraint.mbt 抄本〕，本尺把「真源 vs 消费面/执行点」做机械对表）：
  - `--selftest` **rc=0**（**27/27 格**：copy-identical-no-drift / copy-identical-f1-count /
    copy-identical-no-violation / MUTATION-copy-drift-detected / MUTATION-drift-count /
    MUTATION-lt-vs-le-detected / comment-literal-no-false-red / empty-scan-self-reject /
    empty-scan-has-note / no-mirror-is-clean-not-broken / no-mirror-scanned-files /
    no-mirror-f1-zero / multi-def-detected / multi-def-count / multi-def-does-not-fail /
    coverage-3of5-in-output / coverage-names-form4 / coverage-names-form5 / coverage-pass-not-full /
    f3-baseline-aligned / f3-baseline-checked / MUTATION-f3-mb-cmp-drift-detected /
    MUTATION-f3-mb-cmp-violation-count / MUTATION-f3-sql-cmp-drift-detected /
    MUTATION-f3-sql-cmp-violation-count / MUTATION-f3-no-where-no-false-drift /
    MUTATION-f3-no-where-not-checked——含抄本漂移 / `<`↔`<=` / F3 双向 cmp 四组变异对照 +
    注释字面量不误红 / 空扫描自拒 / 无镜像不误红 / 无 WHERE 不误漂移四支反证）
  - 实跑 **rc=0**（**152 份 .mbt**、**F1 抄本漂移 0 条**〔全仓无注释声称「镜像/等价」的函数〕、
    **F2 同签名多定义 92 组**〔点名 12 + 另 80，全告警不判红——多后端属合法设计：agents_acl_* 8 族 /
    assistant_get 4 处等〕、**F3 SQL 谓词对表 store_rsv↔store_sqlite `SQL=['<'] MB=['<']` 对齐**
    ⇒ 形态 ①②③ 无漂移）
- **零漂移判据**：`check_tools_sync` rc=0（183 工具真源一致、R8 清单 19 组 ΣN=183）/
  `check_instruction_budget` rc=0（AGENTS.md 50440/65536 全章节可见）。
- **无新发现（类型）、无新立账**（换面到 check_two_faces，该面 ①②③ 漂移 0 条、尺子自证 27/27 全绿）。
- **禁区零碰**：8 WIP 文件（含 bugs.md）零改零提交。
- **FIST 闭环**：T0r107 六步全链 rc=0（publish → agent_acl_grant → claim → execute → submit → verify，
  wd-r351 / ns watchdog / verify status=已完成、completed_by=wd-r351 / deliverable=本报告，
  后台串跑 <60s 收口〔node server 温热〕；patch_esm_main 探针先行 10 bundles 全 up to date、无 MemoryError）。

## 资源消耗

| 项 | 读数 |
|---|---|
| 判据自跑 | check_two_faces --selftest rc=0（27/27 格）+ 实跑 rc=0；check_tools_sync rc=0；check_instruction_budget rc=0 |
| FIST 闭环 | 1 任务（T0r107）六步 |
| 提交 | 1（本报告，scoped `--` 路径） |

## 任务分配记录

| 角色 | 动作 |
|---|---|
| 统帅（本实例） | git status/log/numstat 冻结判定、换面巡检选面与执行、零漂移复跑、报告撰写、FIST 闭环、scoped 提交 |
| 子代理 | 未派（巡检分支、全部为单命令判据、无并发收益） |

## 遗留风险

1. WIP 8 件仍冻结（第 32 轮），Round C 三件过期——需 owner/R192 车道收口 WIP 后才可执行。
2. **外来账检测面**（沿用 r348 判定）：白名单外外来账 23 条（BUG-613~635）悬待 owner 裁决，
   属 BUG-565「跨项目误落账持续模式」；检测半在线、每次冻结 WIP 重跑必红属预期。
   本轮未复跑该面（换面到 check_two_faces），规模维持 r348 读数。
3. 换面巡检队列余量：mcp_smoke / OFM 端点探活 / 其余未巡 `check_*` 面（同源收敛面短收尾即可，勿空转）。

## 后续建议

- 下轮继续巡检分支，换面队列推进（本轮 check_two_faces 已用，避免与近期已巡面重复；
  另 check_sql_bind_alignment 的 docstring「6 格→实跑 7 格」滞后仍留专门轮次改）。
- R192 车道若恢复，优先收口 Round C 三件。
- 外来账 23 条（BUG-613~635）建议 owner 一次性裁决（搬移 vq 仓 / 登记 WHITELIST）。

## 超额内容

无。

## 来源

- `git status --short` / `git log --oneline -5` / `git diff --numstat`（2026-11-16 本机）
- `python scripts/check_two_faces.py --selftest` / 实跑
- `python scripts/check_tools_sync.py` / `python scripts/check_instruction_budget.py`
- `python scripts/patch_esm_main.py` 探针（10 bundles 全 up to date、无 MemoryError）
- FIST 闭环 `temp/fist_r351_chain.sh`（后台串跑，回盘 `temp/fist_r351_out/`，task_id=T0r107）
