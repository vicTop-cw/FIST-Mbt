# Round 117 Report · BUG-157 修复独立验证 + 单主跨进程回归判据

**日期**：2026-10-15
**HEAD**：`9cb51bc`
**目标**：独立验证并发 agent 对 BUG-157（assistant_claim 跨进程并发单主击穿）的修复是否真正收口

## 结果摘要

**BUG-157 修复实测有效但非可证明原子**。

并发 agent 在 `src/store/store_sqlite.mbt` L1646-1667 的 `assistant_upsert` 加了清场 UPDATE（`UPDATE assistant_reg SET is_primary=0 WHERE is_primary=1 AND agent != ?`）+ 原有 ON CONFLICT upsert。我逐字读了完整函数体，发现**修复未用 `BEGIN IMMEDIATE` 事务包裹两条语句**——理论上仍是 TOCTOU 竞态。

我写独立跨进程判据 `scripts/blackbox/e2e_assistant_xproc.py` 实测：**8 进程 × 60 轮 60/60 单主成立**（最高压力）。SQLite 文件级写串行化 + UPDATE→INSERT 紧邻使理论窗口实际不击穿。

**结论**：修复在实测下稳健（当前负载），但若要"可证明原子"需把清场 + upsert 包进 `BEGIN IMMEDIATE` 事务。属强化项，非必需。

## 资源消耗

- 只读审阅：`src/store/store_sqlite.mbt` L1639-1667（并发 agent WIP）
- 新增 1 文件：`scripts/blackbox/e2e_assistant_xproc.py`（178 行，含 --selftest / --atomic）
- 修改 1 文件：`scripts/README.md`（登记新判据）
- 实测：4 组压力测试（5×20 / 8×40 / 8×60 / atomic 8×40），约 3 分钟
- 提交 1 个：`9cb51bc`（仅 2 文件，未掺和并发 WIP）

## 任务分配记录

| 阶段 | 执行 | 产物 | 状态 |
|---|---|---|---|
| 只读终审 BUG-157 修复 | 我 | TOCTOU 发现（非原子） | ✅ |
| 写跨进程单主判据 | 我 | `e2e_assistant_xproc.py` | ✅ |
| 压力实测 | 我 | 4 组全 PASS | ✅ |
| 登记 scripts/README.md | 我 | check_scripts_index 不再点名我的脚本 | ✅ |
| BUG-157 修复本体 | 并发 agent | `store_sqlite.mbt` 清场 UPDATE | ✅（并发负责） |
| BUG-157 账本标记 FIXED | 并发 agent | bugs.md（未提交 WIP） | ✅（并发负责） |

## 遗留风险

1. **BUG-157 可证明原子未做**：实测够稳健，但 `assistant_upsert` 仍是无事务两语句。若要"可证明原子"，应包 `BEGIN IMMEDIATE`。属并发 agent 的代码，我只留建议不擅动。
2. **check_plugin_sync FAIL**：bugs.md 未提交（含 BUG-156/157 FIXED 标记）。需并发 agent 提交后重生成插件投影。
3. **check_scripts_index FAIL**：并发 agent 的 `warn_stats.py` 未登记（非我责任，已在我的登记验证中确认只剩它被点名）。
4. **BUG-155**：dist/fist-mbt.js 148 vs 166，**仍待用户裁决**（金条四，删除类不可逆）。
5. **BUG-156 pattern 收窄**：`.set(` 仍报 62 条 low 噪声，收窄是独立决策（owner 未定）。

## 后续建议

1. **BUG-157**：当前修复已足够稳健。若追求可证明原子，可在 `store_sqlite.mbt` 的 `assistant_upsert` 加 `BEGIN IMMEDIATE` 事务包裹（我留建议，不擅动并发 agent 的代码）。加后可用 `e2e_assistant_xproc.py --atomic` 作对照验证。
2. **判据升级路径**：`e2e_assistant_xproc.py` 目前直测 SQL 形态。若要真正的完整回归锁（打真 MCP 进程），CLI 侧需先暴露 `assistant_claim` 子命令——这是独立增强项。
3. **2 守卫 FAIL 收敛**：等并发 agent 提交 bugs.md（含 FIXED 标记）+ 登记 warn_stats.py，check_plugin_sync 与 check_scripts_index 即可恢复。
4. **BUG-155**：待用户裁决是否 `git rm --cached dist/fist-mbt.js dist/patch_esm_main.py`（金条四不可逆，只出方案不执行）。

## 超额内容

- 发现并发 agent 的 BUG-157 修复**非原子**（TOCTOU），属其修复遗漏但实测稳健。
- 新增 `--atomic` 模式作为"可证明原子"的对照判据，为未来强化提供现成测试面。

## 来源

- `src/store/store_sqlite.mbt` L1639-1667（并发 agent WIP，只读）
- `scripts/blackbox/e2e_assistant_xproc.py`（新增）
- `scripts/README.md`（登记）
- `memory/2026-10-15.md`（Round 117 记录）
- `git log --oneline` HEAD=`9cb51bc`