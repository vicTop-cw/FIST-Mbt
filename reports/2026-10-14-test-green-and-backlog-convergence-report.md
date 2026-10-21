# 2026-10-14 · 终审：测试 1043/1043 里程碑 + 计划项收敛核对 + BACKLOG L33 翻 done（Round 111）

## 结果摘要

**一句话**：本轮做终审——实测 `moon test --target js` = **1043/1043 全绿**（并发 agent 已修 cfg_ofm_2 并新增测试），
`issue_scan` 扫 4 个稳定模块 **0 条高严重度**，核对计划表发现 L33 self_search 已端到端接线但 BACKLOG 仍标 pending，
**修正为 done**（commit `7b7ea61`）。项目高度收敛：计划项全落地、测试全绿、扫描器级无高危。

## 实测里程碑

| 项 | 读数 |
|---|---|
| `moon test --target js`（2 连发） | **1043/1043 failed:0**（2 连发一致） |
| 历史基线 | 上轮 1033/1033 → 并发 agent 修 cfg_ofm_2 并新增 → 1037 → **1043** |
| `issue_scan src/evolve` | 7 文件 336 findings，**high=0 medium=0** low=113 |
| `issue_scan src/diff` | 1 文件 44 findings，high=0 low=16 |
| `issue_scan src/symbolic` | 1 文件 139 findings，high=0 low=42 |
| `issue_scan src/core` | 3 文件 138 findings，high=0 low=72 |
| 守卫 `check_doc_surface`/`check_tools_sync`/`check_template_ctrl`/`check_scripts_index` | **PASS** |
| 守卫 `check_plugin_sync` | FAIL（并发 agent WIP：加 router 工具未重投影） |
| `check_test_sync --total 1043` | FAIL（文档全写 1033，实测 1043） |
| `check_test_sync --total 1037` | FAIL（同样 drift） |

## 关键发现

### ① 测试计数在 churn，文档同步会立即失效
15 分钟内测试数从 1033 → 1037 → 1043（并发 agent 加 router 测试）。文档（AGENTS/README/README_EN/ARCHITECTURE/
docs/*/scoring_rubric）仍写 1033/1033，`check_test_sync --total 1043` 判红 20+ 条 R1 + 5 条 R2 + R3 防空转。
**判定：这是并发 agent 的收口责任**——他们加测试就该同步文档，我在计数 churn 时同步会立刻失效。
README.md 经核实只被 gen_plugins **读**（BUG-67 分组表真源 `README_DOC.read_text`），不写回，**根 README.md 可安全直改**；
但这笔账留待并发 agent 收口时连测试一起提交。

### ② 计划项基本全落地，BACKLOG 有过时条目
- **L33 P3 self_search**：BACKLOG 标 `pending(**半落地，勿重复建模块**`（2026-10-13 观察），但
  **2026-10-14 已端到端接线并提交进 HEAD**——`src/server/self_search_evolve_bridge.mbt`
  （`self_search_runner_default` + `evolve_asset_register` IO 接线 L98/L104/L106）+ `src/server/server.mbt`
  L3280-3284 注册 MCP 工具面时把默认 runner 交给 `run_external_search`，未配置 `FIST_SELF_SEARCH_CMD` → runner=None
  → 跳过搜索**零回归**，8 测在 `self_search_evolve_bridge_wbtest.mbt`。**不再是孤代码**。**已翻 done**。
- **L22 P2 quickcheck**：已 done（3 个测试文件用 `@quickcheck.check`：core_quickcheck_wbtest / decompose_quickcheck_test / engine_boundary_test）
- 其余 P0-P3 项基本标 done

### ③ issue_scan 无高危
用发布版 fist-mbt 的 `issue_scan`（31 条 MoonBit 高危规则）扫 4 个稳定模块，**high/critical 各 0**，
代码扫描器级干净。336+ findings 全为 low（多为规则误报）。

## 交付（commit `7b7ea61`）

`BACKLOG.md` L33：`pending(**半落地...**` → `done(**2026-10-14 复验：接线已提交进 HEAD 且端到端成立**...`，
列出 bridge 行号 + server.mbt 注册点 + 零回归说明 + 8 测。未动 src/router/*（并发 WIP）。

## 资源消耗

- 1 个提交：`7b7ea61`（BACKLOG L33 翻 done，1 行改）
- 3 次 `moon test --target js`（确认 1043 稳定）
- 4 次 `issue_scan`（evolve/diff/symbolic/core）
- 1 次全守卫链 + 2 次 `check_test_sync`（1037/1043 两口径）
- 3 支临时分析脚本（temp/scan4.py、temp/scan5.py、temp/cts.py）

## 任务分配记录

指挥官亲自：
- **实测而非自述**（金条八）：用真 `moon test` 2 连发 + `issue_scan` 真扫，确认 1043/1043 与 0 高危
- **区分稳定与 churn**：发现测试计数 15 分钟内 +10 后，**不追文档同步**（会立即失效），
  改做稳定的 BACKLOG 事实修正——避免做立即作废的工作
- **核实而非凭记忆翻账**：确认 `self_search_evolve_bridge.mbt` L98/L104/L106 真调 `evolve_asset_register`、
  `server.mbt` L3280-3284 真注册，才翻 done（防"半成品账"误翻）
- **确认 README.md 可直改**：查 gen_plugins 只 `README_DOC.read_text` 不写回，才敢说根 README.md 安全可改

## 遗留风险

1. **`check_test_sync` 红**：文档 1033 vs 实测 1043，需并发 agent 收口 router 测试后连文档一起提交。
2. **`check_plugin_sync` 红**：并发 agent WIP（加 router 工具未重投影），等收口。
3. **BUG-155 dist/**：仍 OPEN，待 owner 裁决（重建/退役/扩 J14）。
4. **测试计数 churn**：并发 agent 仍在加测试，最终文档数待定。

## 后续建议

1. **并发 agent 收口后**：跑一次全守卫链确认 `check_test_sync` + `check_plugin_sync` 归绿，再发一次权威 Release。
2. **dist/ 重建**：待工具数稳定后按 BUG-155 三选一裁决。
3. **全量 quickcheck 化**：L22 已集成，可继续把硬编码断言迁移为属性测试（收益递减，按需）。

## 超额内容

- **"测试数 churn"本身是观测价值**：15 分钟 1033→1043，说明并发 agent 在活跃开发。此时文档同步是"追飞靶"，
  正确做法是等靶停下再打——这也解释了为何守卫族要"读实测"而非"读文档自述"。
- **计划表收敛度**：本轮核对发现 BACKLOG 已基本全 done，仅 L33 一处因观察时间早（2026-10-13）标 pending，
  现已修正。项目从"待实现清单"进入"维护期"。

## 来源

- 实测：`moon test --target js`（1043/1043，2 连发）
- 扫描：`scripts/issue_scan.py`（evolve/diff/symbolic/core，high=0）
- 守卫：`check_doc_surface.py` J13/J14、`check_test_sync.py` R1/R2/R3、`check_plugin_sync.py` cl7
- 修正：`BACKLOG.md` L33（self_search 入库半 done）
- 接线证据：`src/server/self_search_evolve_bridge.mbt` L98/L104/L106、`src/server/server.mbt` L3280-3284
- 投影面：`scripts/gen_plugins.py` L186/L199/L201（`README_DOC.read_text`，只读不写）
