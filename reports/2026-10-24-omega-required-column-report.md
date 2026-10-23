# 汇报：BUG-389 方向② omega_required 元数据列（PR#29）

## 结果摘要
- **缺陷**：`task_plan_deep(omega_strong_verify=true)` 把 `[omega:required]` 只写进子任务 description 文本；`supervisor_task_upsert` 覆盖描述时标记被静默覆盖丢失，`omega_spec_create` 误报「任务未开启 Omega 强验证」。
- **根修**：把 Omega 门禁判据从「可被合法覆盖的描述文本」迁到「不可覆盖的 `tasks.omega_required` 元数据列」，描述只是展示层 + 旧数据兜底（取或，向后兼容）。
- **交付**：commit `8bd46a56`（分支 `fix/omega-required-column`，父 origin/main `9e6b196f`），7 文件 +207/−30。
- **PR**：#29 <https://github.com/vicTop-cw/FIST-Mbt/pull/29>（已推送、已开 PR，未合并——合并由 merge agent/fist-bot 处理）。
- **终审（lead 亲自复跑）**：`src/engine` 205/205；全仓 `Total tests: 1421, passed: 1421, failed: 0`（基线 1417 + 4 新白盒锁），**零回归**。

## 改动清单
| 文件 | 改动 |
|---|---|
| `src/store/store_sqlite.mbt` | tasks 幂等加列 `omega_required INTEGER NOT NULL DEFAULT 0`（PRAGMA table_info + ALTER，仿 level 列先例）；`task_columns`/`bind_task_values`(19)/`bind_task_update_values`(17)/`row_to_task`(column_int 18) 全链路 18→19 列索引对齐 |
| `src/core/core_task.mbt` | `Task` +`omega_required:Bool` + `get_omega_required()`；`Task::new(omega_required~:Bool=false)` 带默认；`from_db` 加位置参；`to_json` 补字段 |
| `src/engine/engine.mbt` | `decompose_rec` 写子任务 `omega_required=omega_strong_verify` |
| `src/engine/omega_strong.mbt` | `omega_enabled = t.get_omega_required() \|\| t.description.contains(omega_mark())` |
| `src/engine/omega_required_column_wbtest.mbt`（新） | 4 条白盒锁：① upsert 覆盖描述后 omega_required 仍 true（**核心回归，精确复现原形**）② 默认路径零回归 ③ 旧数据描述兜底 ④ plan_deep 真路径子任务 omega_required=true |
| `engine_execute_r2_test.mbt` / `board_ascii_test.mbt` | `from_db` 末参补 `false`（全仓构造点适配） |

## 资源消耗
- 子代理 1b1b878d 一次交付通过（无打回）。
- lead 终审 3 次 moon test 复跑（1 次命令参数重复失败 + src/engine 205/205 + 全仓 1421/1421）。

## 任务分配记录
- 目标：BUG-389 方向② omega_required 元数据列根修。
- 边界：仅 7 文件（store_sqlite / core_task / engine / omega_strong / omega_required_column_wbtest / 2 个测试构造点适配）。
- 回传格式：结论 / 证据 / 分析 / 缺口与风险 / 建议入档位置（子代理五段式完整）。
- 验收：全仓 `moon test --target js` 汇总行 `Total tests: N, passed: N, failed: 0`（lead 亲自复跑同值）。

## 遗留风险
1. **BUG-388 未修**：本机 `moon fmt --check` 工具链缺陷（rc=-1），`check_fmt_gate.py` 报 `DEGRADED(2)`（拒判红也拒判绿）。格式权威面以 CI（Linux nightly）为准；PR#26 已在 CI 侧加 `moon fmt` 预热绕过（该 PR 的 unified gate chain 五项判据已全 PASS 验通）。
2. **fmt 世代差异**：`Some(s) => ...` 单行化等属 moon fmt 世代重排，语义不变；CI nightly 重跑可能再收敛一次。
3. **`.mbti` 未随 commit**：跑 `moon info` 会全仓刷 `.mbti`，风险大于收益；CI/nightly 自行同步（子代理已验 `pkg.generated.mbti` 会正确体现 `Task::new(omega_required?)` / `Task::from_db(..., Bool)` / `Task::get_omega_required`）。
4. **native 后端未验**（BUG-133 + BUG-142，JS 口径为准，仓库门禁同此口径）。

## 后续建议
1. **合并优先级**：#29（方向② 根修）与 #18（方向① 现象修）共同关闭 BUG-389，建议合并 agent 尽快处理；两者文件不重叠，可独立合并。
2. **js test 基线红**（`check_ci_step_position` 棘轮 35>34 + `check_mbti_sync` 44>25，观测臂）会挡住 `wait_gate` 自动合并 → 需 owner 裁棘轮上限，或 fist-bot 收口；我不绕过。
3. BUG-394（本批修复）、BUG-390/398/399（ghost 回填 #20）、BUG-397（fist-bot 已修）账本仍标 OPEN，待 bug_fix 流程盖章（fist-bot 职责）。

## 超额内容
- 新增 4 条白盒锁测试（`omega_required_column_wbtest.mbt`），把 BUG-389 方向② 的验收固化为机器可回归的判据。
- 幂等加列走 `ensure_task_columns` 探测 + ALTER，与 level 列先例同构，旧库自动回填 0 无破坏。

## 来源
- 缺陷：`memory/bugs.md` BUG-389（2026-10-23 起，方向②「tasks 无 omega 列」）。
- 前置：PR#18（方向① 描述标记保留）`fix/omega-mark-keep`。
- 终审基线：origin/main `9e6b196f`（本地 main `72905304` 更领先，我的分支一律基于 origin/main，合并冲突由 fist-bot 处理）。