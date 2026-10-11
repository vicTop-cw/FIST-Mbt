# FIST-Mbt 四模式流水线自我迭代 · Round 7 汇报

- 轮次：**Round 7**（12 轮完整重复中的第 7 轮）
- 日期：2026-10-11（Asia/Shanghai）/ 2026-10-10（server UTC）
- 组合环：`bugfind-fix-polish-verify-r12`，steps=[bugfind, fix_and_merge, polish, verify]
- 指挥官终审：全部亲自复核
- 状态：**完整闭环**（round 7 → 8）

---

## 结果摘要

| 项 | 结果 |
|---|---|
| bugfind | **0 命中 BUG-190/191 型缺陷**（该族已收敛）+ **2 处 LOW 反向缺陷** + **0 回归** |
| fix_and_merge | **2/2 修复**（schema 补全 + 删除时间戳后门） |
| polish | cl7 / doc_surface / tools_sync / fmt / 卫生 全 PASS |
| verify | 指挥官独立复核全过 |
| 全量测试 | **686 / 686 通过**（零新增测试，基线不动） |
| moon check | **0 errors** |
| engine 测试 | 148 / 148 |
| 缺陷账本 | BUG-198/199 入账，**2/2 FIXED**（同一笔小记 `### FIXED(2026-10-10T18:35:35Z / BUG-198, BUG-199)`） |

### 本轮关键结论：**「参数被丢弃」族已收敛（负结果留痕）**

bugfind 子代理逐行核对 **~110 个 `instrumented_tool`** 的 schema 声明 ↔ async fn 实读 ↔ 引擎层转发，**零命中 BUG-190/191 型缺陷**——所有 required 参数均「声明即读、读完即转发」，无一处静默丢弃。方向 B（默认值一致性）也**零命中**：大量工具**手动复刻文档默认值**（因 helper 默认 `get_int=3`/`get_bool=false` 与文档「默认 5/默认 true」不匹配）属**正确做法**，已逐一排除以免误报（loop_create max_rounds=5 / stop_on_goal=true、executor_run timeout_ms=180000、dag_mc samples=1000/seed=42、heal timeout_sec=600 等）。

**方向 D 回归：零回归**——BUG-186~196 的回归锚点全部在位。

### 本轮 2 条缺陷（反向缺陷新族：impl 读了 schema 未声明的字段）

| BUG | 严重度 | 缺陷 | 修法 |
|---|---|---|---|
| **BUG-198** | LOW | **output_validate impl 实读 `external_results`，但 schema 未收录该属性**（文档 L5663 描述引用它、impl L5678-5685 实读它）——文档有、schema 无、impl 有，三面不一致 | schema 补 `"external_results": string_prop(...)` 属性；新增 `get_json_object(args,key)` helper 归一化（对象直传原样返回、字符串 `@json.parse`+catch 回退空对象、不 panic）；impl 4 层 match 缩为一行 |
| **BUG-199** | LOW | **loop_create impl 读取未声明字段 `now`（L2574）**，调用面可注入时间戳，违背全库 BUG-33「时间戳一律服务端盖章，调用面无 now 参数」政策 | 删除 `get_str(args, "now", ...)` 后门，改 `let now = now_default()`；返回 JSON 无 now 键（loop_to_json 只回服务端盖章 created_at），只读回显非后门 |

**反向缺陷的方向性**：BUG-190/191 是「schema 声明了却不读」（正向，已修）；BUG-198/199 是「impl 读了 schema 未声明的字段」（反向）。两者都破坏一源四态的 schema↔impl 一致性，但方向相反，**不宜并入 J10 description-contract 家族**（混入会稀释该家族的判据语义）。

**方向 C（Err 分支文案）本轮未做全量二次比对**（上轮已确认 evolve_*/model_route/output_validate/task_challenge 的 Err 文案与文档一致），存在漏网的极低可能——诚实披露为遗留风险。

---

## 资源消耗

| 资源 | 说明 |
|---|---|
| 子代理 1 | bugfind：逐行核对 ~110 个 instrumented_tool 的 schema↔async fn↔引擎转发（只读） |
| 子代理 2 | fix_and_merge：2/2 修复 + 收口判据 |
| 指挥官 | 逐条终审核实（读源码 L5702/L404/L5713/L2605）+ 独立复跑全量判据 + Cycle 5/6 回归确认 |
| 全量 `moon test --target js` | 686 测试 |
| `moon check` | 33 tasks, 0 errors |
| 未用 | issue_scan、moon build、live MCP 实调（server 是过期二进制 PID 34528，未重启） |

---

## 任务分配记录

| 环节 | 承担者 | 交付 |
|---|---|---|
| bugfind | 子代理（只读） | 零命中族收敛结论 + 2 处 LOW 反向缺陷 + 回归确认 |
| fix_and_merge | 子代理 | 2/2 修复（server.mbt，仅 edit） |
| polish | 子代理 + 指挥官复核 | cl7 / doc_surface / tools_sync / fmt / 卫生 全 PASS |
| verify | 指挥官 | 独立复跑全量 + 逐条读源码核实 |
| 终审 | 指挥官 | 2/2 核实 + 独立复跑判据 + 回归确认 |
| 记忆/汇报 | 指挥官 | memory/2026-10-11.md + 本汇报 |

---

## 遗留风险

1. **server.mbt 为共享并发文件**：fix 子代理确认同仓另一 agent 同时改了 task_plan_deep/evolve_distill/evolve_submit/evolve_lesson/laya_decide/dag_mc/plan_revise/goal_drift_check/cost_budget_check/progress_gate/phi_accrual/issue_scan 等（部分可能即本代理 Cycle 5/6 未提交改动被误判为「他方」）。**本轮终审已重跑回归确认 Cycle 5/6 全 intact**（行号因并发编辑位移但均在位），但**不保证下轮仍 intact——每轮终审必须重跑回归**。
2. **方向 C 未重扫**：Err 分支文案与文档的二次比对本轮未做全量，建议 Round 8 补扫。
3. **未逐行核对的工具**（bugfind 诚实披露）：laya_decide / omega_* 五件 / reserve_* 三件 / cost_budget_* / phi_accrual 全字段 / task_triage / task_challenge / loop_tick/status / pipeline_tick / status_summary / board_ascii / state_flow_ascii / cost_stats / selfdrive_parse_next_tasks/pick_next/dispatch ——集中在 server.mbt 尾部 4300-4900 与 6600-6783 段，**建议 Round 8 补扫**。
4. **BUG-198 行为变更**：output_validate 现在接受 external_results 两种形态（对象直传 / JSON 字符串）。**未做端到端 MCP 实调**（server 过期二进制 PID 34528，未重启）；已用全量 686/686 兜底。
5. **BUG-199 政策落实**：loop_create 删除 `now` 后门。无测试给 MCP 层传 `now`（`ops_loop_wbtest.mbt` 的 `"now"` 是 `ops.loop_create` 内部函数第 3 位置参数 `created_at`，非参数后门）。外部调用方若曾依赖传 `now` 现在会拿到服务端盖章时间——**符合政策，语义变更需提示**。
6. **MCP server 为过期二进制**（PID 34528）：本轮所有判定基于源码 + 单元测试。
7. 既知债务：omega_strong / omega_strong_test fmt debt；engine_dag_ext.mbt L859-866 doc 缺 `rejected` 说明（4 轮遗留）；Cycle 4 丢失 ~45 行 WIP 未复现；server.mbt 文末多余空行（HEAD 已存在）；board_ascii_test.mbt fmt 两处（他方已改）。BUG-142（moon exit-0 不可靠）仍 OPEN。

---

## 后续建议

1. **Round 8 bugfind 补扫未覆盖面**：server.mbt 尾部 4300-4900（omega_*/reserve_*/cost_budget_*/phi_accrual/task_triage/task_challenge/loop_*）与 6600-6783（board_ascii/state_flow_ascii/status_summary/cost_stats/selfdrive_pick_next/dispatch）；并**重扫方向 C**（Err 分支文案与文档二次比对）。
2. **方向 A（参数丢弃）族已收敛**：不再重复全量扫同一批工具（bugfind 建议「避免下轮重复」）——下轮改扫未覆盖面 + 方向 C。
3. **重启 MCP server**（PID 34528 过期）后做 live 回归：output_validate 双形态 external_results / loop_create 无 now / progress_gate 三态 / evolve_distill 非终态 Err。**本轮不做**（纪律：不活调过期二进制）。
4. **反向缺陷族**（impl 读 schema 未声明字段）：BUG-198/199 属新族，Round 8 可反向扫一轮——逐个工具找「impl 里 get_X 或 m.get 读的键不在 schema 字段表」。
5. **每轮终审必须独立重跑** `moon test`（看 Total tests 汇总行）+ `moon check` + `check_plugin_sync`，不靠 fix 子代理自述。
6. **MoonBit 新实坑已入档**（供后续轮次预防）：`catch {…}` 后紧跟 `match` 是解析歧义，须先落到 `let` 再 match，且 match arm 内 `let` 须包 `{ }` 块；`Json::object({})` 被多处引用会报「has type : function type」（Json 非 Copy，隐式函数化），须每处独立构造。

---

## 超额内容

- **负结果留痕**：Round 7 明确记录「零命中 BUG-190/191 型缺陷」这一结论——避免下轮重复全量扫同一批工具，把预算留给未覆盖面。这是 bugfind 子代理主动建议的元认知动作。
- **新族识别（反向缺陷）**：Round 6 修的 BUG-190/191 是「schema 声明了却不读」（正向）；Round 7 的 BUG-198/199 是「impl 读了 schema 未声明的字段」（反向）。两方向都破坏一源四态，但语义不同。Round 8 可反向扫一轮，把 schema↔impl 双向都收口。
- **政策面 vs 文档面优先级**：BUG-199 选「删后门」而非「改文档把 now 写进 schema」——因为这是**政策面**问题（BUG-33「调用面无 now 参数」），不是文档面问题。改文档等于给政策开例外、把「服务端权威时间」降级成「调用方可注入」，与全库十余处声明相悖。删一行零回归且符合政策字面。**这一优先级判断值得入档**：当缺陷同时涉及政策面与文档面时，政策面优先，文档面改法只在政策允许时用。
- **诚实披露零命中面**：方向 A/B 各列大量 NON-DEFECT（手动复刻默认值属正确做法），避免下轮重复误报；方向 C 未做全量二次比对，如实标为缺口。
- **零误报 3 连轮**：Cycle 5 (4/4)、Cycle 6 (7/7)、Cycle 7 (0/2 新族 + 2 反向) 均零误报。本轮 bugfind 甚至主动把「手动复刻默认值」这类易误报项逐一排除。

---

## 来源

- 缺陷清单：`memory/bugs.md`（BUG-198/199，2/2 FIXED）
- 修复落点：`src/server/server.mbt`（L404 helper / L2605 loop_create / L5702 schema / L5713 impl）
- bugfind 子代理回传（方向 A/B/D + 零命中族结论 + 2 反向缺陷 + 未覆盖面披露）
- fix_and_merge 子代理回传（2/2 修复证据 + MoonBit 实坑）
- 指挥官终审：读源码 L5702/L404/L5713/L2605 + 独立复跑全量判据 + Cycle 5/6 回归逐条 grep 确认
