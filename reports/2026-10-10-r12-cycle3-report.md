# 12 轮 [寻虫→修复→打磨→验证] 自我迭代 · Round 3 报告

- 日期：2026-10-11（Asia/Shanghai）/ 2026-10-10（server UTC）
- 相位：bugfind → fix_and_merge → polish → verify（完整闭环）
- 组合环：`bugfind-fix-polish-verify-r12`（steps=[bugfind,fix_and_merge,polish,verify]，max_rounds=48）
- 交付基线：全量测试权威门槛 `Total tests: 683, passed: 683, failed: 0`；`moon check` 0 errors

---

## 结果摘要

Round 3 完整闭环，在 `progress_gate`/`tx_contract` 的**兄弟工具**上命中并修复 **3 处同族缺陷**（BUG-180/181/182），新增 **5 条回归锁**（含 1 个新建测试文件 `cost_tool_test.mbt`），全量 **683/683**、`moon check` 0 errors、引擎 **146/146**。打磨相修了 1 处 cl7 插件态漂移（重跑 `gen_plugins.py` 回放生成器），验证相 V1~V6 全通过。

| 缺陷 | 文件 | 根因 | 类别 | 修复 |
|---|---|---|---|---|
| BUG-180 | `engine_dag_ext.mbt` L706-716 | `cost_budget_split` 的 `budget<=0` 早退只回 `{stages,total_budget,verdict,note}`，缺 `makespan`+`scope`；同工具 ok/insufficient 分支均回全，唯独 rejected 不同构 | BUG-166/167 同族（早退不同构） | L706-728 补 `makespan:0` + `scope:budget_scope_json(root,ns,0)` 四子字段；`reject_note` 区分 budget<0 vs ==0 |
| BUG-181 | `cost_tool.mbt` L10 | `budget_check` 的 `remaining` 超支时静默填 `0.0` 掩盖超支额；`limit<=0` 时 `current>=limit` 恒真 → 无条件 `exceeded=true + switch_free` | BUG-165 同族（静默归零） | L8-38 让 `remaining=limit-current`（可为负=超支额）、新增 `valid` 字段；`limit<=0` → valid=false/exceeded=false/action=rejected |
| BUG-182 | `engine_dag_mc.mbt` L138-147 | `dag_mc` 空作用域只回 `{insufficient:true,note}`，doc 说「空作用域返回 insufficient」但未声明该变体字段形状 | BUG-167 文档侧变体 | 实现未改；只补 `server.mbt` dag_mc 描述末尾 + `engine_dag_mc.mbt` doc 注释声明字段形状 |

### 打磨相（polish）
- **P1 格式**：本轮目标文件 `moon fmt --check` 全绿（手工修 `cost_tool_test.mbt` 两处超长 abort + 补尾换行、`engine_dag_ext.mbt` note 拼接拆行、`dag_mc_test.mbt` 两处 abort 拆行；未跑 `moon fmt`）。剩余差异仅在 `omega_strong*.mbt`（并发/既有欠账，未触碰）。
- **P2 文档契约**：J9 **PASS**。`cost_budget_check` 新增 `valid` 是**增键**（严格超集，棘轮只许升自然成立）；`remaining` 由「非负」变「可为负」是**语义**变更，J9 只比字段集合故不触碰。
- **P3 插件态同步（cl7）**：一度 **FAIL**——`server.mbt` 改了 `dag_mc`/`cost_budget_check` 两条描述，`gen_plugins.py` 投影到 README + 4 宿主 SKILL.md + instructions.append.md 共 **9 文件漂移**。终审判定跑 `python scripts/gen_plugins.py` 回放生成器（`README.md`/`plugins/` 在 git status 中干净、非并发 WIP，漂移完全由我的描述变更引起）→ `check_plugin_sync.py` 复跑 **PASS**（4 宿主 / 64 文件 / 136 工具 / v0.3.8 / .mcp.dev.json）。
- **P4 工具计数**：`check_tools_sync.py` PASS **136**（本轮未增删工具）。
- **P5 残留卫生**：全仓递归 `tmp_bugfind*`/`bf_probe*`/`tmp_*probe*` **0 命中**；`cost_tool_test.mbt` 为规范常驻黑盒测试。

### 验证相（verify）
- V1 `check_tools_sync.py` → PASS（server.mbt 注册 **136**）
- V2 `check_doc_surface.py` → PASS（J1~J15 全绿，J9 棘轮未退化）
- V3 `check_plugin_sync.py` → PASS（**cl7 回绿**，4 宿主/64 文件/136 工具/v0.3.8/.mcp.dev.json）
- V4 `moon test --target js` 全量 → **683/683 failed:0**（=上轮 678 + 本轮 5 条锁）；`moon check` → 0 errors（1608 warnings）；`moon test src/engine` → **146/146**
- V5 源码复核：BUG-180/181/182 三处修复**逐条读源码核实**均正确落位、无回归
- V6 `moon build` → `_build/js/debug/build/cmd/cli/cli.js` **已重建**（ran 80 tasks, 0 errors）；**未重启**运行中的 MCP server

---

## 资源消耗

- 子代理：bugfind ×1 + fix_and_merge ×1 + polish ×1 + verify ×1
- 命令运行：`moon test --target js`（全量 + src/engine）、`moon check`、`moon build`、`moon fmt --check`、`check_tools_sync.py`、`check_doc_surface.py`、`check_plugin_sync.py`、`gen_plugins.py`
- MCP 调用：`report_bug` ×3（BUG-180/181/182）、`bug_fix` ×1（销 3 条）、`loop_tick` ×1
- 账本：BUG-180/181/182 → FIXED；`gen_plugins.py` 自述「181 条入账：1 待修 / 158 已修 / 16 重复 / 6 误报」

## 任务分配记录

| 相位 | 执行者 | 交付 |
|---|---|---|
| bugfind | 子代理 b306b82d | 3 处同族缺陷命中 + 0 假阳性 + 临时探针用完即删 |
| fix_and_merge | 子代理 b932ce47 | 3 处修复 + 5 条回归锁 + 新建 cost_tool_test.mbt |
| polish | 子代理 6eb1ef92 | fmt 手工修正 + J9 PASS + cl7 FAIL 定位 + 卫生 |
| verify | 子代理 1939e4f6 | V1~V6 验证 + 三修复逐条源码核实 + moon build |
| 终审 | commander（本代理） | diff 复核 + 亲自跑全量 `moon test` 独立复核 683/683 + `moon check` exit 0 + cl7 回绿裁决 |

## 遗留风险

1. **live MCP server 仍未重启（首要）**：PID 34528（21:43:45 启动）仍在跑旧代码；`cli.js` 已由 `moon build` 重建，但**不重启不会加载新行为**。重启前勿用 live MCP 实调 `cost_budget_split`/`cost_budget_check`/`dag_mc` 判修复，会看到旧行为误判未修。行为正确性的权威证据是源码复核 + 单测（已锁定）。建议由 owner 协调重启时机（会影响并发 agent）。
2. **引擎层 doc 注释缺口**：`engine_dag_ext.mbt` L859-866 仍缺 `rejected` 说明（Round 2 遗留，本轮未及）。J9 只扫 `server.mbt` 不扫引擎层注释，故不红，属待补小缺口。
3. **并发 WIP**：`engine.mbt`、`engine_boundary_test.mbt`、`engine_triage*`、`board_ascii.mbt`、`memory/*`、`templates/tool_use_rubric.md`、`reports/2026-10-10-r12-cycle2-report.md` 全程未触碰。
4. **未锁行为**：BUG-180 rejected 分支 `makespan:0`/`scoped_task_count:0` 是「未取数」的诚实回显，靠注释 + 测试锁住；BUG-181 `limit=0` 与 `<0` 同判 rejected，未进一步细分。

## 后续建议

1. 重启 MCP server 后复调 `cost_budget_split`（负 budget → 回显 makespan+scope）/ `cost_budget_check`（超支 → remaining 为负 / limit<=0 → valid=false+rejected）/ `dag_mc` 空作用域文档契约，确认 live 行为与源码一致。
2. 下轮 polish 补齐 `engine_dag_ext.mbt` L859-866 的 `rejected` 说明。
3. 继续 Round 4 bugfind：本轮证明了「文档↔实现交叉比对」能跨工具挖出同族缺陷——下一批高风险面是 `saga_*`（LIFO/切片语义）、`evolve_*`（评分/阈值）、`phi_accrual`（已核对）、`output_validate`（artifacts 校验）、`tx_contract` 剩余动作分支（claim/execute/submit 等）。建议沿用同族模板 + 边界实调。

## 超额内容

- 修掉 `engine_dag_ext.mbt` `reject_note` 里「负预算只会切出负份额」对 `budget=0` 的文案自相矛盾（BUG-169 型轻量变体，非缺陷级但顺手修）。
- 主动跑 `gen_plugins.py` 回放生成器，恢复 cl7 绿——这是 polish 定位到漂移后的终审裁决，比留红待后续修更符合「增量零回归」。

## 来源

- 源码：`src/engine/engine_dag_ext.mbt`（BUG-180）、`src/engine/cost_tool.mbt`（BUG-181）、`src/engine/engine_dag_mc.mbt`（BUG-182 doc）、`src/server/server.mbt`（cost_budget_check/dag_mc 描述）
- 回归锁：`src/engine/dag_ext_test.mbt` L1226、**新建** `src/engine/cost_tool_test.mbt`（L8/L40/L69）、`src/engine/dag_mc_test.mbt` L132
- 账本：`memory/bugs.md`（BUG-180/181/182 FIXED）
- 生成面：`gen_plugins.py` 重跑 → `plugins/*` + `README.md`（cl7 回绿）
- 记忆：`memory/2026-10-10.md`「Round 3 完整闭环」条目