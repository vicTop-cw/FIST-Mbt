# 军衔等级接入真实输出 —— 交付报告

- 日期：2026-10-18
- 提交：`d010592`（Phase 2 接线），前置 `e3ecc91`（Phase 1 地基）+ `3c38e4b`（文档同步）
- 目标：把「默认连长级（level=6）」从死数据变成真实任务输出

## 结果摘要

`Task.level : Int`（默认 6）现在是军衔唯一来源，贯通三处：

| 层 | 改动 | 效果 |
|---|---|---|
| 引擎 `src/engine/engine.mbt` | `publish` / `publish_next_round` / `cold_publish` / `publish_parallel` / `publish_with_deps` 各加 `level? : Int = 6` 并透传 | 根任务默认连长级；上游可显式 `x级` 覆盖；越界由 core 内部 clamp |
| 引擎（子任务） | `plan`(L127) 与 `decompose_rec`(L1205) 注入 `level=child_level(父.get_level())` | 连长6 → 排长7 → 士兵封顶 7 |
| 看板 `src/server/board_ascii.mbt` L162-177 | 每行追加 `军衔[X]` 标注：叶→`@display.leaf_label`（士兵），非叶→`@display.rank_of(level)` | 看板直接可见军衔；缩进/`depth` 逻辑零改动 |
| 服务 `src/server/server.mbt` | `publish` / `dag_publish` 的 schema + handler 暴露 `level` 参数；`rank_of` 工具描述删旧口径「root depth=3 实际生效 4 档」 | MCP 调用方可声明 x级；文档即实现 |
| 测试 | 新增 13 条：`engine_rank_test.mbt`(9) + `board_ascii_rank_test.mbt`(4) | 默认6 / 显式2 / 越界9→7 / -1→0 / plan降级 / 封顶 / plan_deep / parallel / deps / 看板渲染 |

## 验收（独立复跑，不采信子代理自述）

- `moon check src/engine src/server` = **0 errors**（1235 warnings 全为存量 deprecated）
- `moon test --target js` = **Total tests: 1319, passed: 1319, failed: 0**（26.6s）
- 针对性：`-f "*level*"` = 6/6；`-f "*军衔*"` = 3/3
- `moon fmt --check` exit = 0

## Phase 1 落地 vs Phase 2 假设 —— 契约偏差

- 设计假设 `@display.rank_of(level, leaf=...)`；**落地签名是单参** `pub fn rank_of(level : Int) -> String`，无 leaf 参数。
- 叶子恒士兵由**独立** `@display.leaf_label(_level : Int) -> String` 承担（`src/display/rank.mbt` L77 / L101）。
- 接线采用 `if t.is_leaf() { @display.leaf_label(lv) } else { @display.rank_of(lv) }`，语义与设计意图一致、映射表未改、未触碰 display。
- `rank_of` MCP 工具描述里的 `leaf` 参数是 server 层工具包装参数，与底层单参函数是两层。

## 资源消耗

- 子代理 1 名（Phase 2 engine + board_ascii 接线 + 测试），未 commit
- 子代理 1 名（Phase 1 地基，早前），已 commit `e3ecc91`
- 主代理：docs 同步 + server.mbt 接线 + 终审复跑 + 提交卫生修正

## 遗留风险 / 后续项

1. **`src/engine/engine_challenge.mbt` L181 `challenge` 根任务未显式接线 level**。它走 `Task::new` 默认已得 level=6（连长级），行为已正确，只是无显式覆盖/继承 src 的入口。可选：a) 保留默认连长；b) 继承 src 军衔（语义更贴「更难变体」）。**本次未进提交**，待裁决。
   - ✅ **已裁决（2026-10-29 · human_steward）：取 a) 保留默认连长** —— `challenge` 派生的新根**固定 `level=6`，不继承源任务军衔**；`parent_id` 同样不指向源任务（新根就是新根，溯源只由 description 的 `from <id>` 承担）。即上句「行为已正确」的状态**被定为契约**，而不是「未接线的巧合」。
     裁决正文：[`docs/plans/decisions/2026-10-29-challenge-level.md`](plans/decisions/2026-10-29-challenge-level.md)。
     回归锁：`src/engine/engine_challenge_level_wbtest.mbt` —— 源任务 level=3/0/5/7 四档均断言新根 `level==6`、`parent_id==None`、溯源 `from <源 id>` 在；**变异对照**：把实现改成 `level=src.level`（继承）实测该文件 `Total tests: 2, passed: 0, failed: 2`，还原后 `2/2 passed`。
2. `execute` L262 兜底 `Task::new` 未改 —— 那是读库失败时的占位 Task，非持久化任务，保留默认 6 正确。
3. 新增 5 条 warning 属既有测试风格（`test_unqualified_package` + `json.value` deprecated），与 `fist-mbt_test.mbt` / `board_ascii_test.mbt` 同款，非本次回归。
4. USAGE.md 版本 `0.3.8` vs moon.mod `0.3.9`（并发 agent 改的 moon.mod），与本次军衔无关，J4 文档面守卫待并发侧同步。

## 提交卫生事件（已修正）

- 首次 `git commit -m $msg`（无路径约束）误把并发 agent 暂存的 `scripts/fix_esm_require.py` 扫进提交（`87c476d`，8 files）。
- 修正：`git reset HEAD~1` 撤销 → 显式 `git add <7 paths>` → `git commit -m $msg -- <7 paths>` → `d010592`（7 files，331+/13-）。
- 教训：并发工作树下 `git commit` **必须带路径约束**，否则会吞并发侧暂存内容。

## 来源

- 真源：`src/core/core_task.mbt`（level/get_level/clamp_level/child_level）、`src/display/rank.mbt`（rank_of/leaf_label）、`src/engine/engine.mbt`、`src/server/board_ascii.mbt`、`src/server/server.mbt`
- 测试：`src/engine/engine_rank_test.mbt`、`src/server/board_ascii_rank_test.mbt`
