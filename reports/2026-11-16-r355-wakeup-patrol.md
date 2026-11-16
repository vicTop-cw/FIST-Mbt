# 轮 355 唤醒巡检报告（ExploreWatchdog · 2026-11-16）

## 结果摘要

- **WIP 冻结判定**：`git status --short` = 6 M + 2 untracked（8 件），
  numstat 与 r326~r354 逐字同（bugs.md 216/0 零再增长、improvement-plan 7/1、
  target.md 1/1、README.md 2/1、run_guards.py 9/0、engine_circuit_test.mbt 5/0；
  untracked：check_mcpcf_db_isolation.py + pipeline_mode_loop.md，逐字同 r354 收口后）
  ⇒ **WIP 非冻结增长后静止第 36 轮**，R192 车道自 r318 后持续停摆、
  src/** + run_guards.py 仍 M ⇒ **巡检分支**。
- **Round C 三件**（BUG-527 治本 / BUG-530 修复 / check_usage_tool_count 注册）维持**过期不执行**（src/** 未解禁）。
- **换面巡检 `check_ns_write_gate_coverage`**（BUG-459 · ns 写门「文档声称覆盖清单 ↔ 实际调用点」对表守卫；
  读 `src/server/write_gate.mbt` 文档侧 + `src/server/server.mbt` 注册块侧，非 WIP 改动文件 ⇒ 独立于冻结 WIP；
  rc=0 覆盖对齐 / rc=1 有漂移 / rc=2 判据无法自证）：
  - `--selftest` **rc=0**（**9/9 格**：clean-3-gated-rc0 / mutation-is-on-code / M1 删真调用 rc1 /
    M2 注释不算接线 rc1 / M3 文档多声称 rc1 / M4 代码多一支门 rc1 / M5 文档清单缺失 rc2 /
    M6 声称块缺失 rc2 / M7 门挪到块外 rc1）
  - 实跑 **rc=0**：`PASS ns 写门覆盖面对表：文档声称 == 实际调用点（3 支：publish / publish_parallel / dag_publish）`
    ——文档侧声称覆盖 3 支、注册块内实际调 `ns_write_gate` 3 支、块外 0 处 ⇒ **ns 写门覆盖无漂移**。
- **零漂移判据**：`check_tools_sync` rc=0（183 工具单一真源一致）/
  `check_instruction_budget` rc=0（AGENTS.md 50440/65536 全章节可见）。
- **禁区零碰**：8 WIP 文件（含 bugs.md）零改零提交。
- **FIST 闭环**：T0r111 六步全链（publish → agent_acl_grant → claim → execute → submit → verify，
  wd-r355 / ns watchdog / verify status=已完成、completed_by=wd-r355 / deliverable=本报告，
  后台串跑收口；patch_esm_main 探针先行 10 bundle 全 up to date、防 MemoryError）。
- **无新发现（类型）、无新立账**：ns 写门面对表干净，本轮为同源收敛面短收尾。

## 资源消耗

| 项 | 读数 |
|---|---|
| 判据自跑 | check_ns_write_gate_coverage --selftest rc=0（9/9 格）+ 实跑 rc=0；check_tools_sync rc=0；check_instruction_budget rc=0 |
| 核验命令 | `git status --short` / `git diff --numstat`（对照 r326 冻结面）/ `git log --oneline -8` |
| FIST 闭环 | 1 任务（T0r111）六步 |
| 提交 | 1（本报告，scoped `--` 路径） |

## 任务分配记录

| 角色 | 动作 |
|---|---|
| 统帅（本实例） | git status/log 冻结判定、numstat 对照、换面巡检选面与执行、零漂移复跑、报告撰写、FIST 闭环、scoped 提交 |
| 子代理 | 未派（巡检分支、全部为单命令判据 + git 只读核验 + 收口提交、无并发收益） |

## 遗留风险

1. WIP 8 件仍冻结（第 36 轮），Round C 三件过期——需 owner/R192 车道收口 WIP 后才可执行。
2. **交付断层**（沿 r354 修正口径）：对真整合线 `origin/main` 实为 **95 提交未交付
   （94 自指巡检报告 + 1 实质 `98a4111e5`）**，非判据默认基准给的 285。推送属
   **owner 门控 + 不可逆 + pre-push 守卫（BUG-566）挡 direct push**，本实例不代行。
3. **判据基准错位（立账候选，无 BUG 号）**：`check_delivery_gap` 默认基准
   `origin/master` 陈旧（落后真整合线 190 提交），表观 285 虚高。留 WIP 收口后立账。
4. **外来账检测面**（沿用 r348 判定）：白名单外外来账 23 条（BUG-613~635）悬待 owner 裁决，
   属 BUG-565「跨项目误落账持续模式」；本轮未复跑该面（换面到 check_ns_write_gate_coverage），
   规模维持 r348 读数。
5. OFM 端点（127.0.0.1:18326）持续不可达——属预期基线（服务未在本机运行），非缺陷
   （本轮未复跑，沿 r353 读数）。
6. 换面巡检队列余量：check_ns_write_gate_coverage 本轮已用；mcp_smoke / 其余未巡 `check_*` 面
   （同源收敛面短收尾即可，勿空转）。

## 后续建议

- 下轮继续巡检分支，换面队列推进（本轮 check_ns_write_gate_coverage 已用，避免与近期已巡面重复）。
- **量交付断层一律 `--base origin/main`**（真整合线），不再采信判据默认的 285 读数。
- WIP 收口时优先：① 立 `check_delivery_gap` 默认基准错位账；② 裁决 95 条自指报告 +
  `98a4111e5` 的推送路径。
- R192 车道若恢复，优先收口 Round C 三件。
- 外来账 23 条（BUG-613~635）建议 owner 一次性裁决（搬移 vq 仓 / 登记 WHITELIST）。

## 超额内容

无。

## 来源

- `git status --short` / `git log --oneline -8` / `git diff --numstat`（2026-11-16 本机）
- `python scripts/check_ns_write_gate_coverage.py --selftest`（9/9 格）+ 实跑（PASS rc=0）
- `python scripts/check_tools_sync.py` / `python scripts/check_instruction_budget.py`
- `python scripts/patch_esm_main.py` 探针（10 bundle 全 up to date、0 patched）
- FIST 闭环 `temp/fist_r355_chain.sh`（后台串跑，回盘 `temp/fist_r355_out/`）
