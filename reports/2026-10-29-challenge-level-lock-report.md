# T0r6 交付报告：challenge 军衔「默认连长」回归锁（Lane lead · 2026-10-29）

> 任务：`T0r6`（ns `fist-plan-20261029`，P2）｜认领：`lead`｜执行：子代理 `f5d2b253`｜终审：lead
> 裁决真源：`docs/plans/decisions/2026-10-29-challenge-level.md`（owner 2026-10-29 定："默认连长"）

## 一、结果摘要

| 项 | 结果 |
|---|---|
| 新增回归锁 | `src/engine/engine_challenge_level_wbtest.mbt`（140 行 / 2 test / 2 helper） |
| 生产代码改动 | `src/engine/engine_challenge.mbt` **+5 行纯注释，0 行代码** |
| 文档收口 | `docs/2026-10-18-fist-mbt-rank-wiring-report.md` +3 行（「待裁决」追加已裁决标注，历史叙述未动） |
| 裁决口径订正 | `docs/plans/decisions/2026-10-29-challenge-level.md` 追加「订正」节（见 §四） |
| 测试读数 | 单文件 **2/2**；`src/engine` **353/353**；全仓观测 **1904/1904** |

锁断言（读字段/返回值，不断言源码字符串 —— 判例-30 防护）：
新根 `level==6`、`parent_id==None`、`children_of(源)==空`、description 含 `from <源 id>`、重要度仍升一档；
且自证**源任务 level==3**（若源本身是 6，"默认 6" 与 "继承源" 读数相同 ⇒ 变异不可能红，是经典假绿）。

## 二、变异对照（两发，都是实测）

| 变异 | 改哪里 | 读数 | 还原后 |
|---|---|---|---|
| 子代理：`Task::new` 里插 `level=src.level,`（真代码行） | 生产实现 | `Total tests: 2, passed: 0, failed: 2`（rc=1） | `2/2 passed` |
| **终审独立复验**：把 test1 期望值 `!= 6` 改成 `!= 3` | 只改测试文件 | `2/2 failed` | 逐字还原后 `2/2 passed` |

> 终审这发刻意改**测试**而不是实现：等价地证明"断言在真读值"，同时不给并发 lane 制造一段生产代码红窗。

## 三、资源消耗

- 子代理 1 个（约 19 分钟墙钟）；终审本地复跑 3 次 `moon_test_env`（基线 / 变异 / 还原）。
- 未触发全仓重建以外的额外构建；未改 `_build` 之外的产物。

## 四、缺口与风险

1. **裁决初稿口径有误（已订正）**：初稿写「`parent_id` 指向源任务仅作溯源」，而实现里 `challenge` 从不设
   `parent_id`（溯源靠 description 的 `from <id>`）。若照初稿去"补齐"，新根会在看板树/DAG 里变成源的子节点，
   违反裁决「依据 1」。已按真实语义落锁并在裁决文档追加「订正」节。
2. **计数锚点 1902 → 1904 未刷新**：本仓「两笔流程」要求同步 `AGENTS.md` / `README.md` / `README_EN.md` / `USAGE.md`
   的测试总数；这些文件超出本任务边界且属并发面，**未改**。另 `check_test_sync --total 1902` 在本改动前就有
   7 条 R1/R2 违例（README_EN 1850、docs/known-boundaries 1413/1426、scripts/README 1835、scoring_rubric 1765）
   ⇒ 该面本来就是陈的，非本单引入。
3. **并发 WIP**：本次所有读数都在含 34 项未提交改动的工作树上取得（含 `src/engine/engine.mbt`、`src/core/core_task.mbt`、
   `src/server/*` 多条 lane）⇒ **"绿"= 当前工作树绿，不等于 HEAD 绿**。期间一次 `Failed when discovering packages`
   瞬时失败，复核 `git status`/`git log` 与本次改动无因果关系（判例-34）。
4. **未覆盖**：`task_challenge` 的 critic 分支未单独起格（其 `Task::new` 调用点与主路径相同，但未逐格验证）；
   server 层（`server.mbt:3222` 仅转发）无独立 level 断言 —— `server.mbt` 是他人 WIP，按边界不可动。

## 五、后续建议

1. `memory/2026-10-29.md` 追加本单收口（已做）。
2. 落提交时同笔刷新测试计数锚点（1902 → 1904），按本仓两笔流程。
3. 若要更狠：补一格 `critic=Some` 时新根仍为 6 的用例（可选，非阻塞）。

## 六、超额内容

无（严格按任务边界；唯一"额外"是终审独立做了一次测试侧变异，属评审职责）。

## 七、来源

- 裁决：`docs/plans/decisions/2026-10-29-challenge-level.md`
- 关联报告：`docs/2026-10-18-fist-mbt-rank-wiring-report.md`（「待裁决」收口）
- 锁：`src/engine/engine_challenge_level_wbtest.mbt`
- 历史：2026-10-18 军衔接线报告 → 2026-10-29 owner 裁决 → 2026-10-29 回归锁落地
