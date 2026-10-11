# 12 轮 [寻虫→修复→打磨→验证] 自我迭代 · Round 5 报告

- 日期：2026-10-11（Asia/Shanghai）/ 2026-10-10（server UTC）
- 相位：bugfind → fix_and_merge → polish → verify（完整闭环）
- 组合环：`bugfind-fix-polish-verify-r12`（steps=[bugfind,fix_and_merge,polish,verify]，max_rounds=48）
- 交付基线：全量测试权威门槛 `Total tests: 685, passed: 685, failed: 0`（=上轮 684 + 1 锁）；`moon check` 0 errors

---

## 结果摘要

Round 5 完整闭环，探针重心转向「同函数多 return 分支字段集一致性」，命中并修复 **4 处同族缺陷**（BUG-186/187/188/189），全量 **685/685**、`moon check` 0 errors、引擎 **148/148**、cl7 回绿。本轮严格纪律执行（全程只用 `edit` 最小改动、改 server.mbt 后即跑 `gen_plugins.py`），**未再发生 WIP 丢失**。

| 缺陷 | 文件:行 | 根因 | 类别 | 修复 |
|---|---|---|---|---|
| **BUG-186** (medium) | `engine_dag_ext.mbt` L893-911 | `progress_gate` None 分支 12 字段但**无 remaining_work**；同函数 rejected（L956-979）与正常（L1015-1033）分支都带 remaining_work（=1-progress）——**None 是函数内唯一缺失者**。BUG-183 补丁只把 None 对齐到文档 11 字段，而**文档本身少报 remaining_work**（sibling 一直携带，文档一直没列） | **BUG-183 补丁残留**（BUG-184 那类「补丁没扫同函数所有兄弟分支」） | ①代码 L901-904 补 `"remaining_work": Json::number(0.0)` 带注释（无子树→progress=0→remaining_work 无意义→诚实回 0），三分支同构；②文档 server.mbt L4567 契约补列 remaining_work（12 字段），如实声明 sibling 实际携带字段 |
| **BUG-187** (medium) | `engine_dag_ext.mbt` L1202-1208 | `goal_drift_check` 根不存在分支仅 3 字段 `{ok:false, root_task_id, note}` vs 文档（server.mbt L3786）承诺 9 字段，**未声明变体** | 分支不同构 / 未声明变体（J9 契约） | 只补文档：server.mbt L3786 末尾追加「根任务不存在时返回 {ok:false, root_task_id, note}，不带 basis/hard_gate/threshold/calibration/counts/checks（无目标可校验）」 |
| **BUG-188** (medium) | `engine_dag_ext.mbt` L1050-1056 | `plan_revise` 根不存在分支仅 3 字段 vs 文档（server.mbt L3761）承诺 10 字段，**未声明变体** | 分支不同构 / 未声明变体（J9 契约） | 只补文档：server.mbt L3761 末尾追加「根任务不存在时返回 {ok:false, root_task_id, note}，不带 basis/keep_count/rework_count/ready_count/keep/rework/ready（无子树可修订）」 |
| **BUG-189** (low) | `engine_phi.mbt` L121-131 | `phi_accrual` insufficient 分支（win<=0）只回 4 字段 `{verdict, phi, note, basis}`，**缺 window/threshold**；rejected（L109-118）与正常（L179-190）分支都带——**insufficient 是唯一缺失者**。文档（server.mbt L4594）**只豁免了 rejected 变体**，未豁免 insufficient | 未声明变体（BUG-182 家族） | 只补文档：server.mbt L4594 在 rejected 段落后追加「insufficient 时只有 verdict/phi/note/basis，没有 window/threshold/mean/stddev（无间隔历史，窗口与阈值无意义）」 |

### bugfind 探针有效性（四方向）
- **方向 1（同函数多 return 分支字段集一致性）**：**4 命中**（C5-01~04），高产区再次验证。扫描 `src/engine/*.mbt` + `src/server/server.mbt` 所有含 ≥2 `return Json::object` 的函数，逐分支枚举字段集。
- **方向 2（saga_repair 切片语义）**：**0 命中真缺陷**。切片最小性成立——`saga_dependents_closure` `out.set(start,true)` 保证失败步骤必入闭包；affected 仅取 pending 且 task_id∈闭包者；keep=pending∖affected 且只 mark affected 为 done → keep 保持 pending；basis 区分 `depends_on`/`order` 与文档一致；重复调用 mark=true 后失败步骤不再 pending → 返回 Err（"已补偿步骤不重现"成立，doc 未承诺 Ok-on-repeat）。仅 low 注记：无 task_id 的后续 pending 步骤在 depends_on 分支必被排除（潜在欠补偿），但无 task_id 本就无法追溯，非缺陷。
- **方向 3（evolve_critic 阈值边界）**：**0 命中**。`critic_review` 单路径；空库→`critic_most_similar` 返 None→sim=0、top_hit 省略（doc 已声明可选）；score 越界有 `clamp(0,1)`；threshold 越界（≤0 恒 admit / >1 恒 reject）是**确定性退化**、非崩溃、非分支不一致，无文档承诺校验 → NON-DEFECT（仅 low 健壮性注记）。
- **方向 4（回归）**：BUG-184（cost_budget_split 四分支均 6 字段，makespan 齐）/ BUG-185（server.mbt L3058 已声明重复变体）/ BUG-181（cost_budget_check 单分支 7 字段齐）/ tx_contract（9 字段同构，BUG-167 落位）**落位正确**；**BUG-183 残留 = C5-01**。

### 打磨相（polish）
- **P1 格式**：本轮目标文件（`engine_dag_ext.mbt` / `dag_ext_test.mbt`）`moon fmt --check` **无 diff**（全程 `edit` 最小改动 + 手工对齐）；剩余差异仅 `omega_strong.mbt` / `omega_strong_test.mbt`（**并发/HEAD 既有欠账，非我引入，未触碰**）。
- **P2 文档契约**：`check_doc_surface.py` **PASS**（J9 返回契约未退化，覆盖 progress_gate 契约字段变更）。
- **P3 插件态同步（cl7）**：改 server.mbt 4 处描述 → **重跑 `python scripts/gen_plugins.py`**（已成固定流程，本轮第 3 次踩到并预防）→ `check_plugin_sync.py` **PASS**（4 宿主 / 64 文件 / 136 工具 / v0.3.8 / .mcp.dev.json）。
- **P4 工具计数**：`check_tools_sync.py` PASS **136**。
- **P5 残留卫生**：全仓递归 `tmp_bugfind*`/`bf_probe*`/`tmp_*probe*`/`probe-bugfind*` **0 命中**。

### 验证相（verify，指挥官终审独立复跑）
- 全量 `moon test --target js` → **685/685 failed:0**（=上轮 684 + BUG-186 锁×1）
- `moon check` → exit 0（1630 warnings, 0 errors）
- `moon build` → exit 0（0 errors）；`_build/js/debug/build/cmd/cli/cli.js` **已重建**
- `check_plugin_sync.py` → PASS（**cl7 回绿**）；`check_tools_sync.py` → PASS（136）；`check_doc_surface.py` → PASS（J9）
- `moon test --target js src/engine` → **148/148**（基线 147→148）
- **源码复核**：BUG-186（L901-904 remaining_work:0.0 + L4567 契约补列）/ BUG-187（L3786 变体声明）/ BUG-188（L3761 变体声明）/ BUG-189（L4594 insufficient 声明）逐条读源码核实均正确落位
- **回归锁**：`dag_ext_test.mbt` 末尾新增 `test "BUG-186：progress_gate 三分支字段集在 remaining_work 键上同构"`（断言 None=0.0、rejected 有键、正常有键且=2/3）

---

## 资源消耗

- 子代理：bugfind ×1（c9b2211f，全程只读）+ fix_and_merge ×1（fa7d1a91，纪律执行）；polish + verify 由指挥官独立复跑
- 命令运行：`moon test --target js`（全量 + src/engine）、`moon check`、`moon build`、`moon fmt --check`、`check_tools_sync.py`、`check_doc_surface.py`、`check_plugin_sync.py`、`gen_plugins.py`
- MCP 调用：`report_bug` ×4（BUG-186/187/188/189）、`loop_tick` ×1
- 账本：BUG-186/187/188/189 → 入账（4 条 OPEN，待本轮销账）；`task_ns=fist-iter`

## 任务分配记录

| 相位 | 执行者 | 交付 |
|---|---|---|
| bugfind | 子代理 c9b2211f | 4 CONFIRMED + 0 假阳性 + 4 方向逐项结论（saga_repair / evolve_critic 双 0 命中并给反面证据） |
| fix_and_merge | 子代理 fa7d1a91 | 4/4 修复 + 1 条回归锁 + 685/685 + gen_plugins 回放 + cl7 一次回绿 + **全程只用 edit、零 WIP 事故** |
| polish | commander（本代理） | fmt 复核 + cl7 复核 + tools_sync + 卫生 |
| verify | commander（本代理） | 全量 685/685 + moon check 0 + moon build + 四修复逐条源码核实 |
| 终审 | commander（本代理） | 4 缺陷独立核实 CONFIRMED + 修复 diff 复核 + 权威判据独立复跑 |

## 遗留风险

1. **live MCP server 仍未重启**（PID 34528 跑旧代码）：cli.js 已由 `moon build` 重建但**不重启不会加载新行为**。重启前勿用 live MCP 实调 `progress_gate`/`goal_drift_check`/`plan_revise`/`phi_accrual` 判修复。
2. **引擎层 doc 注释缺口**：`engine_dag_ext.mbt` L859-866 仍缺 `rejected` 说明（**四轮遗留**，未及）。
3. **既有 fmt 债**：`omega_strong.mbt` / `omega_strong_test.mbt`（并发/HEAD 既有欠账，非本轮引入，未触碰）。
4. **上轮 WIP 丢失事故未完成补救**：`dag_ext_test.mbt` 丢失的 ~45 行未提交 WIP（含 1 条未入库测试）仍建议由并发持有方凭会话上下文重做；本轮 fix 子代理已在新增锁时**只用 `edit` 追加到文件末尾**，未再触碰其历史内容。
5. **BUG-142**（`moon test` 崩溃时仍回 exit 0）非仓库可修，长期 OPEN，不在本轮范围。
6. **并发 WIP**：`engine_triage*`、`engine_boundary_test.mbt`、`board_ascii.mbt`、`engine_dag_mc.mbt`、`dag_mc_test.mbt`、`cost_tool_test.mbt`(?? 新增)、`memory/*`、`plugins/*`、`templates/tool_use_rubric.md` 本轮全程未触碰（只读）。

## 后续建议

1. 重启 MCP server 后补 live 回归：`progress_gate` 三态（不存在 task_id → 13 字段含 remaining_work / budget=0 → rejected / 正常）、`goal_drift_check`、`plan_revise`（不存在 root → `{ok:false, root_task_id, note}`）、`phi_accrual`（空 intervals → `{verdict:insufficient, phi, note, basis}` 无 window/threshold）。
2. 下轮 polish 补齐 `engine_dag_ext.mbt` L859-866 的 `rejected` 说明（四轮遗留，建议本轮收尾）。
3. 继续 Round 6 bugfind：本轮证明「同函数多 return 分支字段集」连续两轮高产区。建议下一批高风险面：**`src/server/server.mbt` 中所有 async fn 的 Ok 分支与其文档契约的字段集比对**（MCP 工具层返回契约，J9 覆盖面）；**`engine_saga.mbt` 的 saga_repair 无 task_id 欠补偿注记**（低优先）；**`evolve_critic` threshold 越界退化**（低优先，可加 range 校验或文档声明）。静默归零族与 progress_gate 族已收口。
4. **沉淀流程纪律**：①改 server.mbt 工具描述 → 必须跑 `gen_plugins.py`（已成固定流程）；②修一处前必须枚举该函数所有 return 分支（BUG-184→BUG-186 连锁教训）；③核对文档是否如实声明实现携带字段（BUG-186 揭示文档少报）。

## 超额内容

- 无新增工具 / 无 schema 变更（BUG-186 为代码字段补全 + 文档补列；BUG-187/188/189 为文档变体声明）。
- 主动把「补文档声明」作为自解释变体（ok:false / insufficient）的默认修向，避免编造无意义零值字段。
- 主动跑 `gen_plugins.py` 回放生成器，cl7 一次回绿（本轮第 3 次踩到，已成预防性流程）。

## 来源

- 源码：`src/engine/engine_dag_ext.mbt` L901-904（BUG-186 remaining_work）/ L1202-1208（BUG-187）/ L1050-1056（BUG-188）、`src/engine/engine_phi.mbt` L121-131（BUG-189）
- 文档：`src/server/server.mbt` L4567（BUG-186 契约补列）/ L3786（BUG-187）/ L3761（BUG-188）/ L4594（BUG-189）
- 回归锁：`src/engine/dag_ext_test.mbt` 末尾 `test "BUG-186：progress_gate 三分支字段集在 remaining_work 键上同构"`
- 账本：`memory/bugs.md`（BUG-186/187/188/189 入账 OPEN）
- 生成面：`gen_plugins.py` 重跑 → `plugins/*` + `README.md`（cl7 回绿）
- 记忆：`memory/2026-10-10.md`「Round 5 完整闭环」条目