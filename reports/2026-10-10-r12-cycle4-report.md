# 12 轮 [寻虫→修复→打磨→验证] 自我迭代 · Round 4 报告

- 日期：2026-10-11（Asia/Shanghai）/ 2026-10-10（server UTC）
- 相位：bugfind → fix_and_merge → polish → verify（完整闭环）
- 组合环：`bugfind-fix-polish-verify-r12`（steps=[bugfind,fix_and_merge,polish,verify]，max_rounds=48）
- 交付基线：全量测试权威门槛 `Total tests: 684, passed: 684, failed: 0`；`moon check` 0 errors

> ⚠️ **本轮发生一次并发 WIP 丢失事故**，见「遗留风险」第 1 条。

---

## 结果摘要

Round 4 完整闭环，命中并修复 **3 处同族缺陷**（BUG-183/184/185），全量 **684/684**、`moon check` 0 errors、引擎 **147/147**。打磨相重跑 `gen_plugins.py` 恢复 cl7（第二次踩到「改 server.mbt 描述必须回放生成器」），验证相 V1~V6 全通过。

| 缺陷 | 文件 | 根因 | 类别 | 修复 |
|---|---|---|---|---|
| BUG-183 | `engine_dag_ext.mbt` L884-890 | `progress_gate` 任务不存在分支只回 `{ok, task_id, note}` 3 字段，文档承诺 11 字段，缺 budget/spent/remaining/progress/burn_rate/projection/verdict/action/basis 共 9 字段——调用方拿不到「任务不存在=rejected」判据 | BUG-167 同族（早退只拼诊断字段，未对齐契约字段集） | L893-911 补 11 字段：spent/progress/burn_rate=0、projection{linear:0,conservative:0} 复用正常分支公式、`verdict="rejected"` + `basis="task not found"` 区分「任务不存在」与「预算问题」 |
| BUG-184 | `engine_dag_ext.mbt` L752-764 | `cost_budget_split` root_missing insufficient 分支只回 5 字段**漏 makespan**；同函数 scope_ids 为空的 insufficient 分支（L827-838）反而有 `makespan:0`——两处 insufficient 互不一致 | **BUG-180 补丁未打全**（只补 rejected，没补 insufficient） | L756-758 补 `makespan:0.0` 带注释「未取数，诚实回显」，与 L827-838 同构（6 字段） |
| BUG-185 | `server.mbt` L3102-3114 | `evolve_submit` 重复分支回 `{rejected, reason}`，与正常路径 artifact 完整 JSON `{id,parent_id,goal,note,code,score,children,created_at,parts}` 不同构；文档（L3058）只字未提该变体 | BUG-182 同族（文档契约未声明变体） | 只补文档：L3058 描述追加「返回 产物 Artifact 的完整 JSON…；若目标与档案库中已有产物高度相似（查重阈值 0.88）则丢弃并返回 {rejected:true, reason}，不递增父代子代数」——行为未改（DGM/Voyager 查重必修） |

### bugfind 探针有效性（本轮零命中项）
- **静默归零 grep**（`else { 0.0 }` / `=> 0` / 钳制）：**0 命中**——唯一真命中 BUG-181 上轮已修，其余为诚实回显（`omega_tool.mbt:311` final_accuracy）或有注释声明的合理默认（`evolve.mbt:148` clamp 0.001）。**该族已基本收口**。
- **tx_contract 全 12 动作**：五分支字段集全同构、`target_state` 与 `core_task.mbt` 迁移定义逐一对齐、无死分支 → **0 命中**（上轮 BUG-167/168 已修干净）。
- **output_validate / evolve_critic / saga_***：描述与实现字段集一致 → **0 命中**。
- **dag_mc 正面对照**：空作用域回 `{insufficient,note}`，但文档**已显式声明**该变体——说明 progress_gate/cost_budget_split 是「该写没写」，dag_mc 是「写了」，后者不算缺陷。

### 打磨相（polish）
- **P1 格式**：本轮目标文件 `moon fmt --check` **已清**（手工修 `dag_ext_test.mbt` 3 处超长 abort 拆行 + `engine_dag_ext.mbt` L906 action 的 `Json::string` 拆行；未跑 `moon fmt`——会重排同包兄弟）。剩余差异仅 `omega_strong.mbt`/`omega_strong_test.mbt`（**并发/HEAD 既有欠账，非我引入，未触碰**）。
- **P2 文档契约**：`check_doc_surface.py` **PASS**（J9 未红，覆盖 evolve_submit 描述改动）。
- **P3 插件态同步（cl7）**：一度 **FAIL**（9 文件漂移），源自 BUG-185 的 evolve_submit 描述改动。**先 `git diff HEAD -- src/server/server.mbt` 归因**：仅 3 处描述改动（L3058 evolve_submit / L3727 dag_mc / L4521 cost_budget_check），**全为本人**（前两处 Cycle 3，末一处本轮），无并发 WIP 描述 → 重跑 `python scripts/gen_plugins.py` 回放生成器 → `check_plugin_sync.py` **PASS**（4 宿主 / 64 文件 / 136 工具 / v0.3.8 / .mcp.dev.json）。
- **P4 工具计数**：`check_tools_sync.py` PASS **136**（本轮未增删工具）。
- **P5 残留卫生**：全仓递归 `tmp_bugfind*`/`bf_probe*`/`tmp_*probe*`/`probe-bugfind*` **0 命中**；DGM 探针 artifact（`probe-bugfind-dup-001/002`）在进程内存、重启即失，不落库。

### 验证相（verify，指挥官终审全部亲自跑）
- V1 `check_tools_sync.py` → PASS（server.mbt 注册 **136**）
- V2 `check_doc_surface.py` → PASS（J9 棘轮未退化）
- V3 `check_plugin_sync.py` → PASS（**cl7 回绿**）
- V4 `moon test --target js` 全量 → **684/684 failed:0**（=上轮 683 + BUG-183×1 + BUG-184×1）；`moon check` → exit 0（0 errors）；`moon test src/engine` → **147/147**
- V5 源码复核：BUG-183（L893-911 11 字段 + basis="task not found"）/ BUG-184（L756-758 makespan:0）/ BUG-185（L3058 文档声明）逐条读源码核实均正确落位、无回归
- V6 `moon build` → 0 errors；`_build/js/debug/build/cmd/cli/cli.js` **已重建**（仍**未重启**运行中 MCP server）

---

## 资源消耗

- 子代理：bugfind ×1（d70b65da）+ fix_and_merge ×1（cfe41fca）；polish + verify 由指挥官亲自执行
- 命令运行：`moon test --target js`（全量 + src/engine）、`moon check`、`moon build`、`moon fmt --check`（多轮）、`check_tools_sync.py`、`check_doc_surface.py`、`check_plugin_sync.py`、`gen_plugins.py`
- MCP 调用：`report_bug` ×3（BUG-183/184/185）、`bug_fix` ×1（销 3 条）、`loop_tick` ×1
- 账本：BUG-183/184/185 → FIXED；`gen_plugins.py` 自述「BUG-1~185 共 184 条入账：4 条待修 / 158 已修 / 16 重复 / 6 误报」（4 待修 = BUG-142 不可修 + 本轮 3 销账前读数）

## 任务分配记录

| 相位 | 执行者 | 交付 |
|---|---|---|
| bugfind | 子代理 d70b65da | 3 处同族缺陷命中 + 0 假阳性 + 静默归零族收口判定 |
| fix_and_merge | 子代理 cfe41fca | 3 处修复 + 2 条回归锁 + 684/684（**并发 WIP 事故，见遗留**） |
| polish | commander（本代理） | fmt 手工修正 + cl7 归因 + gen_plugins 回放 + 卫生 |
| verify | commander（本代理） | V1~V6 全部亲自跑 + 三修复逐条源码核实 + moon build |
| 终审 | commander（本代理） | 修复 diff 复核 + 独立复核 684/684 + cl7 回绿裁决 |

## 遗留风险

1. **⚠️ 并发 WIP 丢失事故（最高优先级，需上报与补救）**：fix 子代理 cfe41fca 在执行中误用 `write` 工具**全量覆盖**了 `src/engine/dag_ext_test.mbt`——该文件在 `git status` 中本为 **M（另一 agent 的未提交 WIP）**。覆盖后其又用 `git checkout --` 从 HEAD 恢复，导致**该文件约 45 行未提交 WIP（含 1 条未入库测试）不可恢复**（git 不保留 `checkout --` 丢弃的工作树内容）。**已核实**：恢复后 HEAD 基线完好——`git diff HEAD -- dag_ext_test.mbt` 仅剩本人追加的 +125 行回归锁、无删除、684/684 全绿、`moon check` 0 errors，**未破坏基线**；但丢失的并发 WIP 建议由持有方（并发 agent）凭其会话上下文重做。**根因与整改**：①编辑前必须 `git status --short` 确认目标文件是否为并发 WIP（M 且非自己改动）→ 是则**拒改并上报**；②**禁止 `write` 全量覆盖**他方 WIP 文件（只用 `edit` 做最小改动）；③**禁止 `git checkout --` 丢弃工作树改动**（会销毁未提交内容）。
2. **live MCP server 仍未重启**：PID 34528 跑旧代码；`cli.js` 已由 `moon build` 重建但**不重启不会加载新行为**。重启前勿用 live MCP 实调 `progress_gate`/`cost_budget_split`/`cost_budget_check` 判修复。
3. **引擎层 doc 注释缺口**：`engine_dag_ext.mbt` L859-866 仍缺 `rejected` 说明（三轮遗留，未及）。
4. **BUG-142**（`moon test` 崩溃时仍回 exit 0）非仓库可修，长期 OPEN，不在本轮范围。
5. **并发 WIP**：`engine_triage*`、`engine_boundary_test.mbt`、`board_ascii.mbt`、`omega_strong*`（含既有 fmt 债）、`memory/*`、`plugins/`、`apps/web/`、`moon.mod` 本轮除事故外全程未触碰。

## 后续建议

1. **补救 WIP 事故**：与并发 agent 协调，请其重做 `dag_ext_test.mbt` 中丢失的未提交内容（约 45 行 / 1 条测试）；若其会话上下文已丢失，评估是否影响其交付目标。
2. 重启 MCP server 后复调 `progress_gate`（不存在的 task_id → 11 字段 + verdict=rejected + basis="task not found"）/ `cost_budget_split`（不存在的 root → 含 makespan:0）/ `evolve_submit`（同 goal 二次提交 → `{rejected, reason}`），确认 live 行为与源码一致。
3. 下轮 polish 补齐 `engine_dag_ext.mbt` L859-866 的 `rejected` 说明。
4. 继续 Round 5 bugfind：本轮证明「同函数多分支一致性」是高产区（BUG-184 是 BUG-180 补丁没打全）。建议下一批高风险面：**同函数多 return 分支字段集枚举**（扫 `src/engine` + `src/server` 所有含多个 `return Json::object` 的函数，逐一比对字段集）、`saga_repair` 切片语义、`evolve_critic` 阈值边界。静默归零族已收口，可降低权重。

## 超额内容

- 无新增工具 / 无 schema 变更（BUG-183/184 为字段补全，BUG-185 为文档补声明）。
- 主动修了 `dag_ext_test.mbt` 3 处 + `engine_dag_ext.mbt` 1 处 fmt 超宽（formatter 单表达式宽度约 85 列）。
- 主动跑 `gen_plugins.py` 回放生成器恢复 cl7（本轮第二次踩到，已成固定流程）。

## 来源

- 源码：`src/engine/engine_dag_ext.mbt` L756-758 / L893-911（BUG-183/184）、`src/server/server.mbt` L3058（BUG-185）
- 回归锁：`src/engine/dag_ext_test.mbt` L1380（BUG-183）/ L1463（BUG-184）
- 账本：`memory/bugs.md`（BUG-183/184/185 FIXED）
- 生成面：`gen_plugins.py` 重跑 → `plugins/*` + `README.md`（cl7 回绿）
- 记忆：`memory/2026-10-10.md`「Round 4 完整闭环」条目