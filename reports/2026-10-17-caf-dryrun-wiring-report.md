# CAF 验收标准 3：server 层 dry_run 接线 —— 汇报

- 日期：2026-10-17
- 主线：CAF（Context-Aware Filtering）四条验收标准中，标准 3「dry_run 可预览（返回建议模型 + 历史依据）」的**最后一格 —— server 层接线**
- 角色：指挥官（human_steward 指令「只做推进」→ 我提出并确认最小改动任务包）→ 子代理实施 + 自测 → 我终审实跑 + 精确暂存提交
- 提交：`c2feb31`（代码）/ `ffc7015`（文档）

## 结果摘要

**标准 3 从「纯计算已落地 / server 接线待做」变为「全链路已落地」。** `model_route` 新增 `dry_run`/`context` 参数：`config.use_caf_memory=true` 时从 `memory/model-router-caf-{ns}.json` 读 CAF 记忆 → `pick_caf_dry_run` → `caf_dry_run_to_json`，返回标准 3 形状 `{suggestion, base, reordered, top_k, basis:[{model,rate,avg_cost,count}]}` 且 `persisted=false`；`use_caf_memory=false` 时**显式拒绝**（不静默降级回普通查询）。默认路径逐字节不动。

## 资源消耗

- 子代理：1 个（实施 + 自测 + 探针法证明 caf_dr_* 真被执行）
- 代码改动：3 文件 / 273 插入 / 1 删除（纯新增）
  - `src/server/model_router_ops.mbt` +72（私有 helper `mr_caf_state_path`/`mr_caf_read` + dry_run 分支 L299-340）
  - `src/server/model_router_ops_wbtest.mbt` +190（helper `caf_cfg`/`caf_prep` + 5 条锁 `caf_dr_1~5`）
  - `src/server/server.mbt` +12/-1（schema `dry_run`/`context` + 工具描述）
- 文档改动：2 文件（验收对照表 R43 闭证 / 接线设计 Round 43 进度注）

## 终审实测读数（不靠自述）

| 门禁 | 读数 | 结论 |
|---|---|---|
| `moon fmt --check`（3 文件） | exit 0 | ✅ |
| `moon check src/server` | 890 warnings / **0 errors** | ✅ |
| `moon test --target js src/server` | `Total tests: 321, passed: 321, failed: 0.`，连跑 3 次全绿 | ✅ |
| 全仓 `moon test --target js` | `Total tests: 1297, passed: 1297, failed: 0.` | ✅ |
| `check_tools_sync`（cl3） | PASS，170 工具对齐 | ✅ |
| `check_plugin_sync`（cl7） | **FAIL**（9 文件）—— 见「遗留风险」 | ⚠ 非本轮引入 |

**首跑抖动**：`moon test --target js src/server` 第一次跑出 `caf_dr_1` failed（`mo_str(dec,"base")` 相关），随即 `moon fmt` + 复跑连续 3 次 321/321/0。判为 fmt/check 与 test 争抢构建产物的瞬态（`moon fmt` 同刻在跑），非测试逻辑竞态。已如实记录，未粉饰。

**子代理探针法**：向 `caf_dr_1` 注入 `abort("caf_dr_probe_should_never_reach")` → `failed:1`（证明该锁确在 321 条执行集内）→ 还原 → 321/321，还原后 `probe` 命中 0。

## 零回归 / 零副作用如何成立

- **零回归**：`dry_run=false`（默认）时 `if dry_run` 直接落空，控制流与改造前一致；dry_run 分支严格落在 Star 门（收于 L298）之后、`consuming`（L344）之前，短路返回，不触碰 `pick`/`record_call`/`mr_save`。
- **零副作用**：分支内无 `mr_save`、无记账、无游标推进；`mr_caf_read` 读不到文件/坏 JSON 一律回 `Json::null()` 交 `caf_memory_load` 降级（绝不创建文件、绝不 panic）。三重锁钉死：代码构造 + `caf_dr_4` 双调用 `decision`/`mode`/`persisted`/两条 state_path 逐字节一致 + 四路 `must_not_exist`（state_path / caf_state_path / 两份 `model-router-caf*` 文件）。

## 任务分配记录

- 子代理：实施 CAF dry_run 接线 + 5 条白盒锁 + 自测（moon check/test），**不 commit、不跑 gen_plugins**，回传格式五段式（结论/证据/分析/缺口/建议入档位置）—— 全部到位。
- 我（指挥官）：派单 → 实跑全部门禁终审 → 抓到首跑瞬态失败并复跑 3 次钉死确定性 → 核验 diff 纯属本次改动（273/1 精确吻合）→ 精确 `git add` 3 源文件 + 2 文档（排除被并发弄脏的 `src/server/pkg.generated.mbti` 与 `memory/bugs.md`）→ 分两次提交。

## 遗留风险

1. **cl7（check_plugin_sync）红**：根因**不是**本轮改动。plugins/README 漂移是「BUG-1~317 共 317 条入账：13 待修 / 282 已修 / 11 重复 / 9 误报」，来自**并发 agent 未提交的 `memory/bugs.md`**（+24 行）；此时跑 `gen_plugins.py` 会把并发方未定稿的账本 bake 进插件态（属扫他人工件）。**解除条件**：并发 agent 提交 `memory/bugs.md` 后跑 `python scripts/gen_plugins.py` 再复跑 cl7。（本轮我改了 `model_route` 工具描述，理论上也会触发 SKILL.md 漂移，但因 cl7 已红于账本漂移，需在并发收口后一并重生成。）
2. **标准 3 闭环后半未做**：`executor_run` 成功后 `caf_memory.push` 回写（接线设计 §2.3 下半）未实施。**后果**：CAF 状态文件若无写入源，dry_run 永远返回空 basis。建议单独子任务。
3. **空 `context`**：`caf_feature_hash("")` 会 hash 空串，可能命中别的空 context 记录；router 层既有语义，server 层未放大。
4. **坏 JSON 记忆文件**：`mr_caf_read` 已按降级处理且不崩溃，但未用白盒锁直接断言（建议补 `caf_dr_6`）。
5. **`moon fmt` 本地(0.1.20260920) vs CI nightly(0.1.20261012)**：全仓性已知差异，非本轮引入。
6. **并发 WIP 大**：`src/server` 有 37 个未提交文件（平台分拆 github/laya/ofm/stdio/run_check），我全程只精确暂存自己的文件，未 sweep。

## 后续建议

- 立即：补 `caf_dr_6`（坏 JSON / 空 context 边界）白盒锁。
- 下一步：另起子任务做 `executor_run` 后 `caf_memory.push` 回写，让标准 3 真正闭环（否则 dry_run 只有骨架）。
- 并发收口后：统一跑 `gen_plugins.py` 恢复 cl7，并跑一次 nightly `moon fmt` 全仓重排。

## 来源

- 计划：`docs/2026-10-14-fist-mbt-router-caf-learning-plan.md` 验收标准 §
- 设计：`docs/2026-10-15-fist-mbt-caf-p2c-wiring-design.md` §2.3
- 对照表：`docs/2026-10-15-fist-mbt-caf-acceptance-status.md` 标准 3