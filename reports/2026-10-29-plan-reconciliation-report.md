# 计划↔实现对表 + 任务池 in_review 裁决清单（T0 交付 · 2026-10-29）

> 任务：`T0`（ns `fist-plan-20261029`，P0）｜执行 + 终审：`lead`｜纯文档，未动 `src/`
> 目的：把「计划里写着没做、其实已实现」的项逐条消账；把 17 条 `in_review` 整理成 owner 可裁决的清单。

## 一、结论（三句）

1. **「未实现」大多是过期叙述**：本轮实测的 5 个"未落地"面里，**3 个已落地**（项目助理 / 提醒者 / worktree 空间层）、**1 个部分落地**（Agent 分级只剩 G3 杀门里的近似）、**2 个真未做**（claimguard 接线、文件绑定三工具）。
2. **17 条 `in_review` 不是"状态陈旧"**：`check_backlog_status_staleness.py` 机器读数 **落差 0 条 / 上限 0 条**（扫描 `gitcode/main`）⇒ 它们**不是**「已点名却仍写 backlog」那一类，而是**活已交付、等 owner 盖 `done`**。
3. **真正欠账只有 3 项**：claimguard 接线（T0r2）、消息池接收侧（T0r3）、文件绑定（T0r5），另有 rhop native（T0r4）卡在兄弟仓边界。

## 二、计划 ↔ 实现 对表

| # | 计划/文档 | 文档声称 | 2026-10-29 实测 | 结论 |
|---|---|---|---|---|
| 1 | `docs/features/F094-multi-butler-file-binds.md` | spec，未排期 | worktree 终态**已落地**（`wt_create/wt_destroy/wt_status`）；`file_bind` 注册数 **0** | **部分**：空间层已做，协调层真未做（T0r5） |
| 2 | `docs/features/F094-*-positioning.md` | `file_bind` 未实现 | 同 #1 | **属实**（T0r5 承接） |
| 3 | `docs/plan-light-worktree-isolation.md` §1.1 | BUG-157 OPEN；worktree 未排期；light-wt 仅文档 | BUG-157 **FIXED**；`wt_*` 三工具已落；`run_light_wt.py` 535 行已落仓；claimguard 仍零接线 | **已勘误**（489c8524） |
| 4 | `docs/plans/2026-10-26-4pools-rhop-roadmap-proposal.md` | rhop「仅实现一点点」；4 池均未落地 | rhop **29 .mbt / 12 787 行**；`.fist-mbt/pool/` 空壳、`.commissar/` 不存在、`fist-mbt/pool/` 不存在；`commissar_send` 已接出（只发不收） | **已勘误**（489c8524）；缺口重定义为「跨机传输 + native + 0 测试」 |
| 5 | `docs/2026-10-12-fist-mbt-supervisor-role-design.md` §1.2「已设计、未落地」 | 项目助理 / 提醒者 / Agent 分级 未落地 | **项目助理**：`assistant_claim/heartbeat/resign/status/sweep` 5 工具已在；**提醒者**：`supervisor_reminder_tick` 已在 `src/server/supervisor_tools.mbt:619`；**Agent 分级**：仅 `engine_supervisor.mbt` 的 `G3_protected_planner` 近似，无 planner/sublead/worker 三档实体 | **前两项已落地、第三项部分** → 本轮补勘误 |
| 6 | `docs/plans/2026-10-29-commissar-poll-proposal.md` | 仅设计，未实现 | `.commissar/` 不存在；仅有 `commissar_send` | **属实**（T0r3 承接） |
| 7 | `docs/2026-10-15-fist-mbt-caf-acceptance-status.md` | 读半✅ / 写半⏳ | `use_caf_memory` 开关 + `model_router_caf.mbt` 已在；**但判据 3 的写半闭环未逐条复验** | **需复核**（本轮不下结论，避免又造一条假绿） |
| 8 | `docs/SHIP-PLAN-BLACKBOX-v2.md` G7/G4 | 仍未实现，「刻意不盲落 / 存疑设计」 | 未实现属实 | **非欠账**：文档已写明是**有意不做**，不应计入待办 |
| 9 | `docs/2026-10-20-slave-tasks.md` SHIP-02 | 未开工 | 无对应主线提交 | **需 owner 定**（是否仍要） |
| 10 | `docs/plans/2026-10-24-wt03-sparse-scripts-proposal.md` | （已驳回） | 能力已被 `run_light_wt.py` 覆盖 | **已关**（`docs/plans/decisions/2026-10-29-wt03.md`）；仅剩「终态计划该移 `archived/`」这条归档动作待 owner |

## 三、17 条 `in_review` 裁决清单（owner 用）

> 证据列 = 主线（`--all`）里第一个点名该 TASK id 的提交。`commits=0` 的两条**主线无任何点名**，需人工取证。

| TASK | 优先级 | 主线点名 | 证据首笔 | 建议动作 |
|---|---|---|---|---|
| TASK-002 | P1 | 4 | `a0240bf01` cherry-pick 黑名单 | 盖 `done` |
| TASK-003 | P2 | 5 | `d5dedd2f3` gate 步骤位置棘轮 | 盖 `done` |
| TASK-004 | P3 | 7 | `3e59ae52f` fist-gate 去串接副本 | 盖 `done` |
| TASK-005 | P1 | 2 | `6165944bf` fist-gate --scan 普查 | 盖 `done` |
| TASK-006 | P2 | 4 | `4e4ce5d27` Merge r93 交付 | 盖 `done` |
| TASK-008 | P3 | 1 | `d5dedd2f3`（同笔顺带） | 盖 `done`（证据偏弱，可加追记） |
| TASK-009 | P2 | 6 | `ebe46005f` docs(r101) 追记 | 盖 `done` |
| TASK-010 | P1 | 4 | `ee17be696` 任务池对账 | 盖 `done` |
| **TASK-011** | P1 | **0** | —（分支清理类） | **人工取证**：远端分支是否已不存在 + 本地 tip 是否已并入 |
| **TASK-012** | P1 | **0** | —（同上） | **人工取证**；若已并入则 `dropped` 或 `done` |
| TASK-013 | P1 | 3 | `e557fb262` docs(R123) 交付报告 | 盖 `done` |
| TASK-014 | P1 | 1 | `86f48d84f` backlog 尺补 R4 | 盖 `done` |
| TASK-015 | P1 | 1 | `86f48d84f`（同笔） | 盖 `done` |
| TASK-018 | P1 | 6 | `39792c60d` docs(R114) | 盖 `done` |
| TASK-019 | P1 | 1 | `7a5bdfc99` Merge r85 任务池交付 | 盖 `done` |
| TASK-021 | P1 | 3 | `733f16b44` pr-automator 默认关 | 盖 `done` |
| TASK-022 | P1 | 1 | `33e742357` 四支同伴分支 × r94 | 盖 `done` |

**机器旁证**：`check_backlog_status_staleness.py` → `落差 0 条 / 上限 0 条`（现状面没有「已点名却仍 backlog」的条目）；
即这 17 条**不违反**判据，只是流程上停在「等盖章」。

## 四、需 owner 裁决的点（我不代裁）

1. **TASK-011 / TASK-012**：主线零点名，需 `ls-remote` + `merge-base` 取证后定 `done` 还是 `dropped`。
2. **TASK-008**：只有 1 笔「顺带」提及，证据强度弱于其它条 —— 接受还是补追记？
3. **`wt03` 提案归档**：`status=已驳回` 但仍在 `plans/` 根，按 `docs/plans/README.md` 应移 `archived/`（`check_plan_location` 的 P6 告警就是它）。
4. **CAF 写半**：需要一次专门的判据 3 复验，再决定文档写 ✅ 还是继续 ⏳。
5. **SHIP-PLAN G7/G4**：确认它们属于「有意不做」而非欠账，如是则从待办面彻底划掉。

## 五、本轮已完成的勘误（避免重复劳动）

- `489c8524`：4pools 提案、light-worktree 计划、F094 三份的事实勘误（只订现状，不动 status）。
- `86ae3af4`：challenge 裁决口径订正（parent_id 错误说法）。
- `607e414e`：测试总数锚点对齐实测 1904（含一条历史豁免）。

## 六、建议入档

- 本报告 → `reports/2026-10-29-plan-reconciliation-report.md`（已落此文件）。
- `docs/2026-10-12-fist-mbt-supervisor-role-design.md` §1.2 → 补「已落地」勘误（本轮同批提交）。
- `memory/2026-10-29.md` → 追加 T0 收口一条。
