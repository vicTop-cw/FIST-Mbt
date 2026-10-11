# 12 轮 [寻虫→修复→打磨→验证] 自我迭代 · Round 2 报告

- 日期：2026-10-10（server UTC）/ 2026-10-11（Asia/Shanghai）
- 相位：bugfind → fix_and_merge → polish → verify（完整闭环）
- 组合环：`bugfind-fix-polish-verify-r12`（steps=[bugfind,fix_and_merge,polish,verify]，max_rounds=48）
- 交付基线：全量测试权威门槛 `Total tests: 678, passed: 678, failed: 0`；`moon check` 0 errors

---

## 结果摘要

Round 2 完整跑完四相，命中并修复 **5 处真实缺陷**（BUG-165~169，progress_gate ×3 + tx_contract ×2），0 假阳性；新增 **5 条回归锁**（算术精确 671+5=676，首次干净运行 676/676，后 678/678）；打磨相补一条 J9 文档契约；验证相三守卫全 PASS。

| 缺陷 | 文件 | 根因 | 修复 |
|---|---|---|---|
| BUG-165 | `engine_dag_ext.mbt` | `progress=0` 时 `burn` 无条件归零 → `linear=0 ≤ remaining` 恒真 → verdict 恒 OK，掩盖「已开工未完成但已烧预算」 | burn 三态 + sentinel `-1.0`（未定义），阶梯前置 `progress<=0&&spent>0 → ESCALATE(燃尽率不可计算)` |
| BUG-166 | `engine_dag_ext.mbt` | budget<=0 在统计前 return 且把 `budget` 硬编码 `0.0`，rejected 分支与其它分支不同构 | 移到统计后，回显实收 budget + 补 spent/remaining/progress/burn_rate/projection/verdict=rejected |
| BUG-167 | `engine_contract.mbt` | 任务不存在分支只回 `{ok, task_id, action, note}`，缺契约件五字段 | None 分支补 phase=precondition/verdict=rejected/reasons/target_state/state_stable |
| BUG-168 | `engine_contract.mbt` | `contract_try` 未知 action 提前 `Err("未知动作")`，把未知动作拦成 precondition，postcondition-None 分支成不可达死代码 | `_ => Ok(task)`（身份副本），控制流到达 postcondition；reason 补「动作无契约定义: <action>」 |
| BUG-169 | `engine_dag_ext.mbt` | progress>=1 无条件 OK，与 action 文案「负为超支」自相矛盾 | progress>=1 内嵌 `remaining<0 → ESCALATE(已完成但预算超支)` else OK |

### 打磨相（polish）
- 4 个目标文件与 `moon fmt` 输出**逐字一致**（手工修 3 处，未跑 `moon fmt`，避免连带重排同包兄弟）。
- **J9 判定：需要改**。`progress_gate` 新增 `verdict=rejected` 但 `server.mbt` L4567 描述只写 OK/CAUTION/ESCALATE；做**最小纯字符串追加**「；非法预算(budget<=0) 整笔拒绝并回 verdict=rejected(ok=false)」，未改 schema/工具数。
- 残留卫生：`tmp_bugfind_probe_test.mbt` / `bf_probe*.db` 全仓递归无残留。

### 验证相（verify）
- V1 `check_tools_sync.py` → PASS（server.mbt 注册 136）
- V2 `check_doc_surface.py` → PASS（J9 未退化，新增 rejected 符合棘轮只许升）
- V3 `check_plugin_sync.py` → PASS（4 宿主 / 64 生成文件 / 136 工具 / v0.3.8）
- V4 `moon test --target js` → 678/678 failed:0；`moon check` → 0 errors；引擎 141/141

---

## 资源消耗

- 子代理：bugfind ×1 + fix_and_merge ×1 + polish ×1 + verify ×1
- 命令运行：`moon test --target js`（全量 + src/engine）、`moon check`、`check_tools_sync.py`、`check_doc_surface.py`、`check_plugin_sync.py`、`moon fmt --check`、`git status/diff`
- MCP 调用：`loop_tick`、`bug_fix`（1 笔销 5 条）、`bug_mark_status`（BUG-171 → DUPLICATE）、`bug_list`、verify 子代理 5 次只读实调（progress_gate/tx_contract）
- 账本：BUG-165~169 → FIXED；BUG-171 → DUPLICATE→BUG-165；净 OPEN = 2

## 任务分配记录

| 相位 | 执行者 | 交付 |
|---|---|---|
| bugfind | 子代理 c89ddcc3 前身 | BUG-165~169 命中 + 临时探针（用完即删） |
| fix_and_merge | 子代理 c89ddcc3 | 4 文件修复 + 5 单测，`git diff +56/-15 +16/-2 +131 +52` |
| polish | 子代理 910e873d | fmt 逐字一致 + J9 从句 + 卫生 |
| verify | 子代理 9248d710 | V1~V4 验证 + 5 缺陷实调 + stale binary 定位 |
| 终审 | commander（本代理） | diff 复核 + `moon check` 0 errors + 独立跑测试复核 676/676 + bug_fix 销账 |

## 遗留风险

1. **MCP server stale binary（首要）**：运行中 server PID 34528 于 21:43:45 启动，早于 HEAD `0635f55`（23:43:04）；`.mcp.json` 指向的 `_build/js/debug/build/cmd/cli/cli.js` 已不存在。故 5 缺陷实调中 BUG-166/168/169 三项 live MCP 仍见旧行为。**根因是源码已修 + 单测锁住（引擎 141/141），但 live server 未重启**——属操作层部署滞后，非代码缺陷。修复动作：`moon build` 重建 cli.js + 重启 MCP server 后复调。server 归并发方运营，本轮未擅自重启。
2. **BUG-146 留账**：`src/ops/ops_pipeline.mbt`（fail-closed 注释 vs fail-open 实现）为并发 agent WIP，等其收敛。
3. **BUG-142 非仓内可修**：`moon test` 在测试进程 SIGABRT 时仍回 exit 0（判绿以 `Total tests: N, passed: N, failed: 0` 汇总行为准）。
4. **引擎层 doc 注释缺口**：`engine_dag_ext.mbt` L859-866 仍缺 `rejected` 说明；J9 只扫 `server.mbt` 工具描述、不扫引擎层注释，故不红，属待补小缺口。
5. **并发工作树共享**：`memory/*`、`engine_triage*.mbt`、`engine_boundary_test.mbt`、`board_ascii.mbt` 等为并发方未提交改动，本轮未触碰。

## 后续建议

1. 在并发方 MCP server 重启后，复调 `progress_gate`（负 budget → budget 回显负数 + verdict=rejected）与 `tx_contract`（非法 action → phase=postcondition）确认 live 行为与源码一致。
2. 下一轮 polish 补齐 `engine_dag_ext.mbt` L859-866 的 `rejected` 说明，保持引擎层与 server 层文档同构。
3. 继续 Round 3 bugfind：随源码演进，`progress_gate`/`tx_contract` 的 sibling 工具（`cost_budget_split`、`saga_*`、`dag_mc`）是下一批高风险探针面（同样存在「统计前 return」「分支不同构」「死代码」三类旧模式）。

## 超额内容

- 修复了 polish 子代理点名的 J9 契约缺口（`rejected` 枚举未列全），成本为一行纯字符串，`check_tools_sync` 仍 136 PASS。
- 把并发方对 progress_gate progress=0 的重复上报 BUG-171 判为 DUPLICATE→BUG-165，账本净 OPEN 从 3 降至 2。

## 来源

- 源码：`src/engine/engine_dag_ext.mbt`（BUG-165/166/169）、`src/engine/engine_contract.mbt`（BUG-167/168）
- 回归锁：`src/engine/dag_ext_test.mbt`（+3）、`src/engine/engine_contract_test.mbt`（+2）
- 文档：`src/server/server.mbt` L4567（J9 `rejected` 从句）
- 账本：`memory/bugs.md`（BUG-165~169 FIXED / BUG-171 DUPLICATE）
- 记忆：`memory/2026-10-10.md`「Round 2 完整闭环」条目
- 全部改动已并入并发方 HEAD `0635f55`。