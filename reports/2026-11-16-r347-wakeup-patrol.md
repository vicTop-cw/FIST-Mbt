# 轮 347 唤醒巡检报告（ExploreWatchdog · 2026-11-16）

## 结果摘要

- **WIP 冻结判定**：`git status --short` = 6 M + 2 untracked（8 件），numstat 与 r326~r346 **逐字同**
  （bugs.md 216/0 零再增长、improvement-plan 7/1、target.md 1/1、README.md 2/1、
  run_guards.py 9/0、engine_circuit_test.mbt 5/0）⇒ **WIP 非冻结增长后静止第 28 轮**，
  R192 车道自 r318 后持续停摆、src/** + run_guards.py 仍 M ⇒ **巡检分支**。
- **Round C 三件**（BUG-527 治本 / BUG-530 修复 / check_usage_tool_count 注册）维持**过期不执行**（src/** 未解禁）。
- **换面巡检 `check_host_installable`**（宿主可装性判据：DSH manifest/patch 严格档——绝对路径 +
  toolCallTimeoutMs + dsh reconnect schema；宽松档 MCP JSON 合规；默认模板合法性；moon.mod 版本同源；
  字段白名单从真源反解）：
  - `--selftest` **rc=0**（DSH 严格档四形必红：相对路径/timeout_ms/reconnect 键名/未定义占位符；
    干净 DSH + 默认模板 + 宽松档不误红；输入面退化自拒；字段白名单反解自真源）
  - 实跑 **PASS rc=0**（DSH manifest/patch 合规；宽松档合规；默认模板合法；moon.mod 版本 0.3.11）
  - 信息级 WARN ×3：`.mcp.json` / `.mcp.dev.json` / `plugins/claude/.mcp.json` 的 fist-mbt 条目用
    `timeout_ms`（部分客户端按自身 schema 忽略该字段）——**既有信息级项，非新发现**，
    是否改真源由人终审，本轮不改。
- **零漂移判据**：`check_tools_sync` rc=0（183 工具真源一致、R8 清单 19 组 ΣN=183）/
  `check_instruction_budget` rc=0（AGENTS.md 50440/65536 全章节可见）。
- **无新发现（类型）、无新立账**。
- **禁区零碰**：8 WIP 文件（含 bugs.md）零改零提交。
- **FIST 闭环**：T0r103 六步全链（publish → agent_acl_grant → claim → execute → submit → verify，
  wd-r347 / ns watchdog / deliverable=本报告，后台串跑收口）。

## 资源消耗

| 项 | 读数 |
|---|---|
| 判据自跑 | check_host_installable --selftest rc=0 + 实跑 rc=0；check_tools_sync rc=0；check_instruction_budget rc=0 |
| FIST 闭环 | 1 任务（T0r103）六步 |
| 提交 | 1（本报告，scoped `--` 路径） |

## 任务分配记录

| 角色 | 动作 |
|---|---|
| 统帅（本实例） | git status/log/numstat 冻结判定、换面巡检选面与执行、零漂移复跑、报告撰写、FIST 闭环、scoped 提交 |
| 子代理 | 未派（巡检分支、全部为单命令判据、无并发收益） |

## 遗留风险

1. WIP 8 件仍冻结（第 28 轮），Round C 三件过期——需 owner/R192 车道收口 WIP 后才可执行。
2. `timeout_ms` 信息级 WARN ×3 悬而未决（是否改真源属人终审）。
3. 换面巡检队列余量：mcp_smoke / OFM 端点探活 等（同源收敛面短收尾即可，勿空转）。

## 后续建议

- 下轮继续巡检分支，换面队列推进（避免与 r344~r347 已巡面重复）。
- R192 车道若恢复，优先收口 Round C 三件。

## 超额内容

无。

## 来源

- `git status --short` / `git log --oneline -3` / `git diff --numstat`（2026-11-16 07:30 本机）
- `python scripts/check_host_installable.py --selftest` / 实跑
- `python scripts/check_tools_sync.py` / `python scripts/check_instruction_budget.py`
