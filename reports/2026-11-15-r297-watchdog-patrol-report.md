# 轮 297 看门狗巡检报告（2026-11-15）

> 唤醒源：Windows 计划任务 FIST-Mbt-ExploreWatchdog（每 30 分钟无窗唤醒，日志 temp/explore_watchdog/watchdog_20261115_0500.jsonl）
> 执行者：fist-commander（统帅 · wd-r297）

## 结果摘要

WIP 四件套**冻结零变化第 14 轮**：跨日 11-14→11-15 两天内仍冻结，mtimes 逐字同 r284~r296（全部早于 r284 提交 2026-11-14 15:19:37），`git diff --stat` 逐字同「3 文件 208+/2-」，相对 r296 **零新增量**。换面巡检 `check_tool_required_sync` 自检 + 实测**双绿**，两个零漂移基线**均 rc=0**，FIST 闭环六步全链 rc=0 一发收口。**无新发现、无新立账。**

## WIP 冻结核对（第 14 轮）

| 文件 | mtime | diff |
|---|---|---|
| docs/improvement-plan-20261010.md | 2026-11-14 10:55:34 | 8 +- |
| memory/bugs.md | 2026-11-14 10:47:48 | 200 + |
| memory/target.md | 2026-11-10 10:34:16 | 2 +- |
| scripts/check_mcpcf_db_isolation.py（untracked） | 2026-11-14 11:11:49 | 新增 |

- `git diff --stat`：**3 files changed, 208 insertions(+), 2 deletions(-)**（与 r284~r296 逐字一致）
- 四个 mtime 全部早于 r284 提交（15:19:37）⇒ 非本轮或近期 agent 写入
- **r287 提请的 owner 弃置裁决维持挂起**（指挥官不代行清理）——本 WIP 归属另一 agent，禁区意识不碰

## Round C 队列状态（维持过期，不执行）

| 件 | 状态 |
|---|---|
| BUG-527 治本（13 份库包摘 cc-link-flags） | **owner 否决**（CI A/B 实证有害，d43a06a28 治本→8a669992d 回滚恢复 14 库包；出路②上游 issue 为主行动，决策单 0fe9146a6） |
| BUG-530（model_route 播种落盘 + executor_run 路由 config 接线） | **FIXED**（3699f012a） |
| check_usage_tool_count 注册 | **已注册**（run_guards.py:175） |

## 守卫面（换面巡检 + 零漂移基线）

### 换面巡检：`check_tool_required_sync`（本轮首跑，r284~r296 未跑过）

- **自检**：`--selftest` **14/14 PASS，rc=0**
- **实测**：**rc=0**——`required↔必填 对表 PASS：解析 168 工具；required 数组与必填描述零漂移；条件必填 2 处（白名单 3 条，三向未过期）`
- 面含义：工具 schema 的 `required` 数组 ↔ 文档「必填」描述双向对表 + 条件必填白名单三向核（本仓 R207 同族纪律：判据面与声明面不许漂移）
- 选面理由：r292 实证的「工具计数漂移盲区」同族面（schema↔文档一致性），168 工具 = 带 required 声明的工具面（全量注册 183），与 `check_tools_sync` 的 R3b 扫面（168 份）数字互洽

### 零漂移基线

| 守卫 | 读数 | rc |
|---|---|---|
| `check_tools_sync` | server.mbt 注册 **183**，AGENTS/README/deliverable/scoring_rubric 对齐；R8 清单分组 19 组 ΣN=183（与实测对表） | 0 |
| `check_instruction_budget` | AGENTS.md = **50440 字节** / 预算 65536（全部章节可见） | 0 |

## 新发现 / 新立账

**无。** 三面守卫（换面 1 + 零漂移 2）全绿，WIP 冻结零变化，无新 bug、无新计划缺口。

## 任务分配记录

本轮为看门狗非阻塞巡检（轻任务自跑，未分派子代理）：

| 步 | 动作 | 读数 |
|---|---|---|
| 1 | `git status --short` + `git log --oneline -3` | WIP 四件套未变，HEAD=f43c3752b（r296 报告） |
| 2 | `git diff --stat` + mtime 核对 | 3 文件 208+/2-，冻结第 14 轮 |
| 3 | 换面巡检 `check_tool_required_sync` 自检 + 实测 | 14/14 自检 / 实测 rc=0（168 工具零漂移） |
| 4 | 零漂移基线 ×2 | 183 工具对齐 / 50440 字节预算内 |
| 5 | FIST 闭环六步（后台链） | 见下 |
| 6 | 报告 + 当日日志 + scoped 提交 | 本报告 |

## FIST 闭环

- 链路：`python scripts/fist.py call` 六步串跑（后台 bash_start，node 冷启动 ~2min/步，落盘 temp/fist_r297_out/）
- 身份：agent=wd-r297，ns=watchdog，deliverable=本报告
- 六步：**全链 rc=0 一发收口**（publish→agent_acl_grant→claim→execute→submit→verify）
- 回执要点：publish 回包 task_id=**T0r53**、writable_agents 51→52；verify 回执 status=已完成、completed_by=wd-r297（详见 temp/fist_r297_out/6_verify.txt）

## 遗留风险

1. **WIP 四件套弃置裁决挂起**（r287 起第 11 轮维持）：四件套自 11-14 起两天冻结、归属不明，指挥官不代行清理；owner 需裁决「保留 / 收口 / 弃置」。
2. **工具计数漂移盲区**（r292 实证，维持挂账）：help_topics.mbt / ARCHITECTURE.md / tool_use_rubric.md / agent-map.md / deliverable.md 五面的工具计数不在 check_tools_sync 与 J14/J16 覆盖内——守卫面扩面待 owner 裁决。
3. **check_foreign_ledger_entries 脏树红面**（维持）：对脏工作区必红（= 冻结 WIP 的投影），非回归；CI 干净检出全绿。

## 后续建议

- 下轮换面候选（未近轮跑过的核心正确性面）：`check_dead_params` / `check_demo_isolation` / `check_entry_paths` / `check_esm_bundle_runnable` / `check_ns_write_gate_coverage` / `check_model_auth_no_key`
- WIP 裁决件维持挂起，不重复提请（r287 已提请）

## 资源消耗

- 工具调用 ~10 次（WIP/日志核对 3 + 守卫枚举 1 + 换面巡检自检/实测 2 + 零漂移 1 + FIST 链启动 1 + 报告/日志/提交 ~3）
- FIST 链路：6 次 MCP 调用（后台单链，~8min）
- 新增文件：本报告 + temp/fist_r297_chain.sh（temp 不入库）

## 来源

- git status / git log / git diff --stat / stat mtime
- scripts/run_guards.py 注册表枚举
- scripts/check_tool_required_sync.py --selftest + 实测
- scripts/check_tools_sync.py / scripts/check_instruction_budget.py 实测
- temp/fist_r297_out/ 六步回盘
