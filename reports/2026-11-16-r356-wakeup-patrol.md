# 轮 356 唤醒巡检报告（ExploreWatchdog · 2026-11-16）

## 结果摘要

- **WIP 冻结判定**：`git status --short` = 6 M + 2 untracked（8 件），
  numstat 与 r326~r355 逐字同（bugs.md 216/0 零再增长、improvement-plan 7/1、
  target.md 1/1、README.md 2/1、run_guards.py 9/0、engine_circuit_test.mbt 5/0；
  untracked：check_mcpcf_db_isolation.py + pipeline_mode_loop.md，逐字同 r355 收口后）
  ⇒ **WIP 非冻结增长后静止第 37 轮**，R192 车道自 r318 后持续停摆、
  src/** + run_guards.py 仍 M ⇒ **巡检分支**。
- **Round C 三件**（BUG-527 治本 / BUG-530 修复 / check_usage_tool_count 注册）维持**过期不执行**（src/** 未解禁）。
- **换面巡检 `check_store_tables_wired`**（BUG-28 · store schema 接线双向守卫：每张表要么**有写入点**、
  要么在源码里**显式声明预留** `schema-reserved:`；双向判据——「死 schema（无写入未预留）/
  声明滞后（预留却有写入）」都要能发红；
  读 `src/store/store_sqlite.mbt` 建表 + `src/**/*.mbt` 写入点 + 预留声明行 ⇒ 独立于冻结 WIP `engine_circuit_test.mbt`；
  rc=0 接线一致 / rc=1 违例 / rc=2 判据无法自证）：
  - `--selftest` **rc=0**：「判据对『死 schema』与『声明滞后』两个方向都发红，干净输入不误红，表名解析口径可证」
  - 实跑 **rc=0**：`PASS store schema 接线一致：32 张表 = 31 张有写入点 + 1 张显式预留（runs）`
    ⇒ **store schema 接线无漂移**（32 = 31 接线 + 1 预留 runs，与 BUG-28 立账基线一致）。
- **零漂移判据**：`check_tools_sync` rc=0（183 工具单一真源一致，R8 分组 19 组 ΣN=183）/
  `check_instruction_budget` rc=0（AGENTS.md 50440/65536 全章节可见）。
- **禁区零碰**：8 WIP 文件（含 bugs.md）零改零提交。
- **FIST 闭环**：T0r112 六步全链（publish → agent_acl_grant → claim → execute → submit → verify，
  wd-r356 / ns watchdog / verify status=已完成、completed_by=wd-r356 / deliverable=本报告，
  后台串跑收口；patch_esm_main 探针先行，防 MemoryError）。
- **无新发现（类型）、无新立账**：store schema 接线面对表干净，本轮为同源收敛面短收尾。

## 资源消耗

| 项 | 读数 |
|---|---|
| 判据自跑 | check_store_tables_wired --selftest rc=0 + 实跑 rc=0（32 = 31 接线 + 1 预留 runs）；check_tools_sync rc=0；check_instruction_budget rc=0 |
| 核验命令 | `git status --short` / `git diff --numstat`（对照 r326 冻结面）/ `git log --oneline -3` |
| FIST 闭环 | 1 任务（T0r112）六步 |
| 提交 | 1（本报告，scoped `--` 路径） |

## 任务分配记录

| 角色 | 动作 |
|---|---|
| 统帅（本实例） | git status/log 冻结判定、numstat 对照、换面巡检选面与执行、零漂移复跑、报告撰写、FIST 闭环、scoped 提交 |
| 子代理 | 未派（巡检分支、全部为单命令判据 + git 只读核验 + 收口提交、无并发收益） |

## 遗留风险

1. WIP 8 件仍冻结（第 37 轮），Round C 三件过期——需 owner/R192 车道收口 WIP 后才可执行。
2. **交付断层**（沿 r354 修正口径）：对真整合线 `origin/main` 的未交付面为
   **95 = 94 自指巡检报告 + 1 实质 `98a4111e5`**，每轮自指报告递增 1（本轮未复跑该面，换面到 check_store_tables_wired）。
   推送属 owner 门控 + 不可逆 + pre-push 守卫（BUG-566）挡 direct push，本实例不代行。
3. **判据基准错位（立账候选，无 BUG 号）**：`check_delivery_gap` 默认基准 `origin/master` 陈旧
   （落后真整合线 190 提交），留 WIP 收口后立账。
4. **外来账检测面**：白名单外外来账悬待 owner 裁决（属 BUG-565 跨项目误落账持续模式），本轮未复跑该面。
5. OFM 端点（127.0.0.1:18326）持续不可达——属预期基线（服务未在本机运行），非缺陷。
6. 换面巡检队列余量：check_store_tables_wired 本轮已用；mcp_smoke / 其余未巡 `check_*` 面（同源收敛面短收尾即可，勿空转）。

## 后续建议

- 下轮继续巡检分支，换面队列推进（本轮 check_store_tables_wired 已用，避免与近期已巡面重复）。
- **量交付断层一律 `--base origin/main`**（真整合线），不再采信判据默认的 285 读数。
- WIP 收口时优先：① 立 `check_delivery_gap` 默认基准错位账；② 裁决自指报告 + `98a4111e5` 的推送路径。
- R192 车道若恢复，优先收口 Round C 三件。

## 超额内容

无。

## 来源

- `git status --short` / `git log --oneline -3` / `git diff --numstat`（2026-11-16 本机）
- `python scripts/check_store_tables_wired.py --selftest` + 实跑（PASS rc=0）
- `python scripts/check_tools_sync.py`（rc=0）/ `python scripts/check_instruction_budget.py`（rc=0）
- FIST 闭环 `temp/fist_r356_chain.sh`（后台串跑，回盘 `temp/fist_r356_out/`）
