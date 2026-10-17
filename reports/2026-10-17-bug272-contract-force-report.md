# BUG-272 修复汇报（tx_contract 建模 archive force=true 强制归档路径）

- 时间：2026-10-17 19:25 (Asia/Shanghai)
- 分支：marvis-verify-20261017
- 提交：`b14eeb6`（`f2fde89` 之后）
- 指令来源：指挥官「只做推进，看看能推进什么」→ 识别本仓可推进的 OPEN 缺陷并落地

## 结果摘要

本仓 OPEN 缺陷中，可推进且源文件未被并发方占用的只有 **BUG-272**（tx_contract 未建模 BUG-227 强制归档路径），
已修复、加白盒锁、过全部门禁并提交。同时本轮把上一轮遗留的僵尸跟踪任务 **T0r7**（BUG-316 台账挂名）闭环归档，
`project_health` 由 attention 转为 **healthy**（blocked=0，done_no_artifact=0）。

## BUG-272 修了什么

- **缺陷**：`tx_contract(task_id, action="archive")` 对 `已暂停`/`已打回` 任务判 `rejected`（"要求状态 [已完成]"），
  而同一任务用 `archive(force=true)` 实际可归档成功。契约门挡在真工具之前，BUG-227 清扫路径形同虚设。
- **真源修复**：
  - `src/engine/engine_contract.mbt`：`contract_try` 与 `transition_contract` 增加 `force? : Bool = false`；
    archive 分支按 `force` 建模——`force=true` 走 `Task::archive_force(force~)`（放行 已暂停/已打回 非流态滞留，
    在流态仍拒）；`force=false` 与 `Task::archive` 完全同义（默认生命周期锚，零回归）。
  - `src/server/server.mbt`：MCP 工具 `tx_contract` 增加 `force` 布尔参数（`bool_prop` + `get_bool`），透传给引擎；
    工具描述同步说明 BUG-227 路径。
- **白盒锁**（`src/engine/engine_contract_test.mbt`）：
  - `tc_r109_t9`：已暂停任务 `force=false` 拒（precondition）/ `force=true` 放行（allowed + 目标 已归档）/
    契约只读不落库（库中仍 已暂停）。
  - `tc_r109_t10`：在流态（已领取）`force=true` 仍拒，force 不放宽在流态。

## 资源消耗

| 项 | 值 |
|---|---|
| moon check src/engine | 0 errors |
| moon check src/server | 0 errors |
| moon test --target js src/engine | 164/164 passed, failed 0 |
| moon test --target js src/server | 316/316 passed, failed 0 |
| gen_plugins.py | 170 工具 / v0.3.8 / BUG-1~317：13 OPEN / 282 FIXED / 11 DUPLICATE / 9 FP |
| check_tools_sync (cl3) | PASS |
| check_plugin_sync (cl7) | PASS |
| moon fmt --check | rc=0 |

## 任务分配记录

- T0r7（BUG-316 悬挂跟踪任务）：execute → submit → verify(verifier=marvis) → archive(by=human_steward)，交付物含台账证据（FIXED 小记 + Lz 侧修复清单）。
- BUG-272：由主助手（本会话）直接实施 + 自测 + 提交。

## 遗留风险

1. **并发 WIP 未落**：工作树仍持有约百个并发方未提交文件（`src/engine/*`、`src/server/*`、`memory/*`、`plugins/*` 等）。
   本次提交已精确暂存，仅纳入 5 个文件；并发方落地后需自行跑 `moon fmt --check` + `moon test --target js` 再提交。
2. **`plugins/*` 未随本提交入库**：工具描述变更后 `gen_plugins.py` 已在工作树重生成插件态（cl7 本地绿），
   但插件目录同时含并发方记忆内容，故不纳入本次提交；待并发 WIP 收口时一并提交。
3. **BUG-268（issue_scan substring-overrun 3/3 假阳性，medium）** 仍 OPEN，但其真源
   `src/server/issue_scan.mbt` 正被并发方持有，本轮不动。

## 后续建议

1. 并发 WIP 收口后：统一 `moon fmt` + `moon test --target js` 全仓绿，再处理 BUG-268。
2. `tx_contract` 的 `force` 语义建议同步进 AGENTS.md 工具表（并发方收口后）。
3. 其余 OPEN 缺陷（BUG-317 vools/fusion.py、BUG-267/273/274/275/276 Lz 侧）均在兄弟仓，需在对应仓修复。

## 来源

- `memory/bugs.md` BUG-272（L4742）+ FIXED 小记 `### FIXED(2026-10-17T11:23:14Z / BUG-272)`
- 提交 `b14eeb6` diff；`git log --oneline -2`