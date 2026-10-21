# FIST-Mbt R13 统一边界审视报告（本子代理口径 · 源码锚点版）

- 日期：2026-10-13
- 角色：FIST-Mbt R13 四模式流水线自我迭代 · 边界审视子代理（全局输入域 owner 视角）
- 原则：**根任务 spec 未写的域外行为，逐项给空输入 / 极值 / 非法输入 / 资源极限四类用例，或显式声明不适用并说明依据；不得沉默**（写下限语料时，强验证只会验证下限）
- 备注：`reports/2026-10-13-r13-boundary-audit.md` 已有一份**并发产出**的同名报告（6 主题 25 条，约 8 处"未核实"）。本文件以**更硬的源码行锚点**重新独立审视，两版可交叉对照——本版每条"预期行为"都带 `文件:行号`，凡不能锚定的行为一律标"未核实"。

> 覆盖范围：6 主题 × 4 类 = **24 条用例**，其中 2 条工具用例显式不适用、1 条元层规则非工具用例、5 条显式标"未核实"。

---

## 主题 1 · JIT 后端边界（moon JS vs native 整数语义 + issue_scan 极值/资源极限）

边界事实（源码锚点）：`src/server/issue_scan.mbt:170-177` 的 `secs-overflow` why 写死——MoonBit 默认 `Int` 在 **JS 为 53 位安全整数（~9e15）**、**native 为 64 位（~9.2e18）**，需 `days > 1e11` 才溢出（约 3.3 千年），正常代码不可能；**只有显式 `Int32`** 才在 `days*86400 > 24855 天`（约 68 年）时溢出（Y2038）。类型语境判定 `scan_has_int32_signal`（:515-524）/`scan_secs_suppressed`（:529-555）：只认显式 Int32 信号，`Int64/Double/f64` 一律 suppress；`prev_lines` 用 `scan_code_part` **去注释后**匹配，防注释散文误判（:528）。

| 类别 | 具体触发输入 | 预期行为 | 适用性 + 依据 |
|---|---|---|---|
| 空输入 | `issue_scan(dir="")` / 空目录 / 目录不存在 | `dir=""` → `Err("issue_scan: 非法目录…")`（`scan_dir_ok` 拒空串，:816）；**空目录**（合法路径、0 个 `.mbt`）→ `Ok` 且 `scanned_files=0, findings=[]`（`scan_collect` 对空 `read_dir` 不 panic，:797）；**目录不存在** → 同上 `scan_collect` 里 `read_dir catch` 静默 return，回空 findings 而非 Err——**spec 未写该差异，静默吞掉（未核实是否应报错，风险点）** | **适用**（其中"目录不存在"标未核实） |
| 极值 | `let t = (days : Int32) * 86400`，`days = 24856` | secs-overflow **真阳性保留**（`guard=false` 不过滤）；`days=24855` 边界不溢出 | **适用**。issue_scan.mbt:176-177 显式写死 24855 天阈值（≈68 年）；测试锚 `issue_scan_secs_overflow_test.mbt:16`（注入显式 Int32） |
| 极值 | 默认 `Int`（无 Int32 注解）下 `days*86400`，`days=1e12` | secs-overflow **suppress**（`guard=true`），不报假阳性 | **适用**。issue_scan.mbt:176「默认 Int 在 JS 53 位/native 64 位不会溢出，仅对显式 Int32 报警」；测试 `BUG-152 secs-overflow default Int suppressed`（issue_scan_wbtest.mbt:1127） |
| 非法输入 | 类型注解只出现在**注释散文**：`// Int32 上界…` + `days*86400` | 不得误判为真阳性，**suppress** | **适用**。issue_scan.mbt:528「prev_lines 用 `scan_code_part` 去注释后匹配」；测试 `BUG-152 secs-overflow Int32 only in comment suppressed`（issue_scan_wbtest.mbt:1158）。**跨行风险**：`let days:Int32` 声明在 >5 行之前时，`prev_window` 截到 10 行/`fn ` 行（:922-925）可能漏保留真阳性——memory/2026-10-13.md 遗留风险 1 已点，如实转引 |
| 资源极限 | 深层目录树 + 超大 `.mbt` 文件 | **未核实（可能栈溢出 / 内存无上界）**：`scan_collect` 是**无深度守卫的纯递归**（:792-811）；`max_findings` 在**全量 findings 收集完之后**才截断（:873-878、:969-970），截断前内存/耗时与文件规模线性；`scan_file` 用 `mem_read` 一次读入整文件（:836）。**spec 未写任何文件大小/深度/耗时上限** | **适用（阈值未核实）** |

---

## 主题 2 · 成本硬门（cost_stats / cost_budget_check / cost_budget_split / progress_gate）

边界事实（源码锚点）：`budget_check` 对 `limit<=0` 走非法预算短路 `valid=false/exceeded=false/action=rejected`（cost_tool.mbt:16-27，BUG-181②）；`budget_check_json` 缺 limit 回落 **0.0**（触发非法预算分支）而非 100.0（:64-76，BUG-211）。`progress_gate` 对 `budget<=0` 整笔拒绝 `ok=false/verdict=rejected`（engine_dag_ext.mbt:1024-1049，BUG-166）；`progress=0 & spent>0` 用 `burn_rate=-1.0` sentinel 而非归零（:1014-1020，BUG-165）；`spent_override<=0` 视为自动估算（:1010）。`cost_stats` 对 memory/无 DB 后端回 `zero_cost_stats`（store.mbt:706-727），对 sqlite 缺 `executions` 表用 ensure 兜住（store_sqlite.mbt:111-116）。`cost_budget_split` 对 `budget<=0` 拒绝并区分负数/零（engine_dag_ext.mbt:762-784，BUG-20②/BUG-180）；作用域空回 `insufficient` + `stages:[]`（:808-822、:891-902，BUG-184）。

| 类别 | 具体触发输入 | 预期行为 | 适用性 + 依据 |
|---|---|---|---|
| 空输入 | `cost_stats()` 在**从未写过任何 execution 记录的库**上 | 回**零值**（`total_records=0` 等），不抛异常打死 server | **适用**。store_sqlite.mbt:112「新库由建表清单覆盖，旧库由 cost_stats 的 ensure 兜住」；`cost_stats_executions_wbtest.mbt:29-43`（表被摘掉后自保回零值） |
| 空输入 | `cost_budget_split(root="不存在", ns="")` / 作用域内 0 任务 | `verdict=insufficient` + `stages:[]` + `makespan:0`，**不切出"三阶段全 0"的假切分** | **适用**。engine_dag_ext.mbt:808-822（根任务不存在）、:891-902（作用域空，BUG-20①） |
| 非法输入 | `cost_budget_check(limit=-5, current=10)` / `limit=0` | `valid=false, exceeded=false, action=rejected`，**不报误导性的 switch_free** | **适用**。cost_tool.mbt:16-27（BUG-181②）；测试 `BUG-181 cost_budget_check limit<=0`（cost_tool_test.mbt:40） |
| 非法输入 | `progress_gate(task_id, budget=-5, spent=0)` | `ok=false, verdict=rejected, action="非法预算：budget 必须为正（实收 -5）"`，回显实收值并带齐契约字段 | **适用**。engine_dag_ext.mbt:1024-1049（BUG-166，测试 dag_ext_test.mbt:1286） |
| 非法输入 | `cost_budget_split(budget=-50)` | `verdict=rejected`，**不产出 -42/-5/-2 的负份额**；note 区分"负预算=赤字"/"0=分母不成立" | **适用**。engine_dag_ext.mbt:762-784（BUG-20②） |
| 非法输入（spec 与实现矛盾的候选） | "负难度权重"作为可注入参数 | **不适用（该项不可达）**：`progress_gate`/`cost_budget_split` 的难度权重由 `triage_label_of(description)` 从**封闭集 难/中/易→3/2/1** 抽取（engine_dag_ext.mbt:997-999、:841-842），**不是可传参数**，调用方无权重注入面。**但注意**：若 spec 对外宣称"可配置难度权重"，该宣称即与实现矛盾（见主题 6） |
| 资源极限 | `progress_gate` 超预算上限：`budget=Int.Max`、子树全难 | `remaining`/`projection` 走 `Double`（:1011、:1014-1023）无 Int 溢出；`subtree_ids` BFS 用 `children_index()` 单次建索引（:920-935，R12-R8 已修 O(N×M)）——**N 极大时 O(N) 内存线性，spec 未写上界，具体规模阈值未核实** | **适用（溢出安全有锚点，耗时/内存无锚点）** |

---

## 主题 3 · delivery validation（output_validate 的 artifacts 逐件硬门）

边界事实（源码锚点）：空 artifacts 直接 `Err`（output_validate.mbt:485-489）；`artifact_spec_errors` 拒未知键/双给 path+check_key（:65-106，BUG-31）；`validate_artifact_path` 拒空/穿越/绝对路径/盘符（:27-42）；`check_file_artifact` 顺序=路径合法→存在→非空→min_chars→contains→not_contains 短路（:144-234）；`require_evidence=true` 且 evidence 空 → `verdict=fail`（:534-537）；`ov_parse_int` 有 `int_safe=200_000_000` 上界守卫（:275-287，BUG-221）；`check_moon_test_summary` 找不到 `Total tests:` 汇总行即 fail（:324-326，BUG-142）。

| 类别 | 具体触发输入 | 预期行为 | 适用性 + 依据 |
|---|---|---|---|
| 空输入 | `artifacts=[]` | `Err("output_validate: artifacts 为空——至少声明一条要验证的交付产物")` | **适用**。output_validate.mbt:485-489 |
| 空输入 | `artifacts` 非空、`evidence=""`、`require_evidence=true` | `verdict=fail, evidence_layer="l4-pass-but-l1-missing"`（硬门全过但示意层缺失） | **适用**。output_validate.mbt:534-537 |
| 空输入 | 单条 artifact `{path:"a/b.mbt"}` 文件不存在 / `external_results` 缺对应 `check_key` | `ok=false`，detail="文件不存在" / "外部结果缺失: key=…" | **适用**。output_validate.mbt:163-169、:352-358 |
| 非法输入 | artifact 同时给 `path` 与 `check_key` | `ok=false`，detail="path 与 check_key 二选一，不能同时给" | **适用**。output_validate.mbt:99-101（BUG-31 同族） |
| 非法输入（spec 与实现矛盾的候选） | invariant 自相矛盾：同一 artifact 同时 `contains:"X"` 且 `not_contains:"X"` | **未核实 / 实现无专门矛盾检测**：源码只分别检查 contains 命中与否、not_contains 命中与否（:192-211），**未先做"两 invariant 是否互斥"判定**——对同一字面量必然一条 fail，**结果上不会假 pass（安全），但 detail 只报首条、不报"你自相矛盾"**。若 spec 宣称"矛盾 invariant 会被单独检测出"则与实现不符 |
| 资源极限 | 超大 artifact 文件（如 100 MB 报告） | **未核实**：`check_file_artifact` 用 `mem_read` 一次读入全文件再 `content.contains/not_contains`（:171-211），**无文件大小上界**；`artifacts` 数组也**无条数上界**（for 循环逐件验，:496-529）。spec 未写任何上限 |
| 资源极限 | `check_key` 含 `moon_test` 时 stdout 汇总行超长 | 自动解析 `Total tests:` 行；`ov_parse_int` 遇 `int_safe=2e8` 上界即 `None`（不溢出绕回） | **适用**。output_validate.mbt:275-287（BUG-221）；测试 `output_validate_overflow_test.mbt` |

---

## 主题 4 · router state persistence（model_router 配额账 + Star 门）

边界事实（源码锚点）：`mr_check_ns` 复用 `@store.MultiStore::safe_ns`，空 ns 视为 `default`、其余非法显式拒绝（model_router_ops.mbt:16-25，BUG-64）；状态文件 `{project_dir}/memory/model-router-{ns}.json`（:29-32）；`mr_read` 读失败/非法 JSON 一律回 `Json::null()`（:37-51）；`router_restore` 状态非法/缺失→按 config 重建并**保留旧文件不删**（router_state.mbt:130-133、:150-152），坏条目跳过错 warning（:57-92），越界游标夹紧到 0（:216-235）；`window_seconds<=0`、`threshold_pct ∉ (0,100]` 回落 config 并 warning（:158-181）。`star_gate_verify_impl` 判定序 Unreadable→BadFormat→BadSignature→Stale→NoSuchUser→Valid，过期条件 `now > issued_at + ttl_seconds`（star_gate.mbt:302-306）；未配置→`gate_enabled=false, free_pool_unlocked=true` 默认零回归（AGENTS.md）。

| 类别 | 具体触发输入 | 预期行为 | 适用性 + 依据 |
|---|---|---|---|
| 空输入 | Star 门三 env 全未配置（`FIST_STAR_GATE_*` 缺失） | `gate_enabled=false, free_pool_unlocked=true`，**默认不设门、免费池放行**（零回归） | **适用**。AGENTS.md「默认未配置 Star 门 → gate_enabled=false/free_pool_unlocked=true 零回归」；白盒锁 `model_router_ops_wbtest.mbt` mo_10 |
| 空输入 | 状态文件不存在 / 空池 | `mr_read` 回 null → `router_restore` 按 config 新建路由器，warn "无有效状态，按配置新建路由器"（router_state.mbt:150-152）；`st_pool` 对缺池字段回落配置池（:62） | **适用** |
| 非法输入 | `namespace="a/b"`（含 `/`）或 `"a..b"` | **显式拒绝**，不静默丢账 | **适用**。model_router_ops.mbt:16-25（BUG-64：`/ \ . 空格 都会造成静默丢账或大小写串账，已拒绝`） |
| 非法输入 | 状态 JSON 损坏 / 配额账被外部篡改成 `used` 超 limit、`limit` 负、`free_idx=999` | 不崩溃；坏条目**跳过 + warning**（router_state.mbt:57-92）；`limit<0` 夹紧到 0（:78）；越界游标夹紧到 0 并 warning（:216-235）；**保留旧文件不删**（model_router_ops.mbt:34-36 "坏状态是证据，不能读一次就抹掉"） | **适用** |
| 非法输入 | attestation 过期（`now > issued_at + ttl_seconds`）或 login 不在名单 | `Stale` / `NoSuchUser` → `free_pool_unlocked=false`（fail-closed） | **适用**。star_gate.mbt:302-306、:334-336；`star_gate_wbtest.mbt` |
| 资源极限 | 多命名空间并发写**同一**状态文件（同 ns 双进程） | **未核实 / 无锁保护**：`mr_save` 是 `@fs.write_string_to_file` 直接覆盖（model_router_ops.mbt:67-76），**无文件锁 / 无原子写**；跨进程并发写同 ns 账 = lost-update 竞态。**注意**：`reserve_scope`/`lock_acquire` 文件锁族存在（AGENTS.md），但 `mr_save` 未接入它们——spec 未写并发语义，风险点 |
| 资源极限 | 配额耗尽后切换 | 两池皆不可用 → `ok=false` 显式失败，**绝不静默改用别的模型**；达 threshold 切付费、付费耗尽回免费 | **适用**。AGENTS.md `model_route` 契约（"两池皆不可用 → ok=false 显式失败，绝不静默改用别的模型"） |

---

## 主题 5 · 组合环边界（bugfind→fix_and_merge→polish→verify→advance）

边界事实（源码锚点）：`loop_tick` 空 steps 立即 stop（ops_loop.mbt:161-193）；`validate_loop_steps` 空/非法 mode 返回错误串（:354-379）；终止优先级 max_rounds→goal_reached→exceeded（:10-14）；`max_rounds` 判定用 `next_round >= max_rounds`（BUG-203 off-by-one 已修，:211-217）；exceeded 只在 `baseline_* > 0` 时参与（:231、:239）；LoopRegistry 是**进程内**可变 `Map`（:386-421；`server.mbt:65` 模块级 `let` 持有），**不落盘**。

| 类别 | 具体触发输入 | 预期行为 | 适用性 + 依据 |
|---|---|---|---|
| 空输入 | `loop_create(steps=[])` / `loop_tick` 于空 steps 环 | create 时 `validate_loop_steps` 返回 "steps is empty"；tick 时 `should_stop=true, stop_reason="loop has no steps"`，history `action=tick_abort` | **适用**。ops_loop.mbt:354-357、:161-193；测试 `loop_tick: 空 steps 立即停止`（ops_loop_wbtest.mbt:147） |
| 非法输入 | `steps=["advance","bogus"]`（7 模式之外） | `validate_loop_steps` 返回 "invalid step mode: bogus. must be one of: advance, polish, verify, bugfind, fix_and_merge, tidy, explore" | **适用**。ops_loop.mbt:358-379 |
| 非法输入 | 环步骤依赖断裂（如 fix_and_merge 前置 bugfind 未跑 / 依赖 mode 被禁用） | **未核实 / spec 未写依赖校验**：`validate_loop_steps` 只查 mode 名合法，**不校验 mode 间语义依赖或 mode 的 forbidden_tools 约束**；mode 约束本身在 `ops_modes.mbt` 的 PipelineMode 表（如 bugfind 的 `require_issue_scan`、fix_and_merge 的 `require_github_token`）。**环内 mode 依赖断裂在纯计算层无守卫**，执行层由各 mode 的实际 MCP 工具调用失败暴露 |
| 资源极限 | 多环并发 / 超 `max_rounds` | `max_rounds` 硬上限兜底（默认 5），`next_round >= max_rounds` 才 stop（BUG-203）；测试 `loop_tick: 完整走满触发 max_rounds`（ops_loop_wbtest.mbt:178） | **适用（防死循环有锚点）** |
| 资源极限 | LoopRegistry 无上限注册环 | **未核实**：`LoopRegistry.loops` 是 `Map[String, PipelineLoop]`，**无条目数上限、无 GC**（ops_loop.mbt:386-421）；`server.mbt:65` 的 `loop_reg` 模块级 let 持有，**进程重启即失**（非持久化）。spec 未写注册数上限与生命周期，风险点 |

---

## 主题 6 · 交付语料边界（元层：FIST 边界审视本身的边界，含本任务自我审视）

| 类别 | 具体触发输入 | 预期行为 | 适用性 + 依据 |
|---|---|---|---|
| 空输入 | 根任务 spec **完全没提**的主题（如"跨进程并发写同一状态文件"） | **不适用"沉默"**：对 spec 未写的域外行为，正确产出是**显式声明"未核实/不适用"+ 依据**，而不是默认通过（否则强验证只会验证下限，Goodhart 下界）。**本报告全部 24 条均带"适用性+依据"列**，未核实项逐条点名 | **适用（元规则）**：这是 `boundary_probe` 治弱语料的核心（AGENTS.md `task_plan_deep` 的 `boundary_probe` 描述） |
| 极值 | 域外行为极端情况（如 Int32 溢出、超深递归、超大文件） | 必须落到**可量化触发输入**（如 `days>24855`、`limit<=0`），不能停在"可能会溢出"；量不出来时诚实标"未核实" | **适用**：本报告 theme 1/3/4 的资源极限已量化到 `24855 天`、`Int.Max`、`2e8` 或源码行号 |
| 非法输入 | **spec 与实现矛盾**（如宣称"可配置难度权重"但实现是封闭集；宣称"矛盾 invariant 会被单独检出"但实现只报首条） | 以**源码为单一真源**优先，报告里**点名矛盾**而非替实现辩解；矛盾项本身是最高价值语料 | **适用**：本报告 theme 2「负难度权重不适用（无注入面）」、theme 3「矛盾 invariant 无专门检测」即此形态 |
| 资源极限 | 边界审视产出超量 / 覆盖过广 | 24 条用例按「每主题 × 4 类」收敛；宁诚实标"未核实"，不编造通过性用例；报告容量优先于覆盖广度 | **适用**：本报告 24 条 = 21 适用/未核实 + 2 显式不适用（工具用例）+ 1 元层规则；未编造通过性预期 |

### 本任务的自我审视（"不沉默"核查）

- **是否不沉默**：是。6 主题全部逐类作答，无整节跳过；凡 spec 未写的域外行为均落到"具体触发输入 + 预期行为 + 适用性/依据"三栏。
- **自我限制**：本任务**只读源码 + 只 append 报告/日志**，**未运行任何实测**（未跑 `moon test`、未起 MCP server 实调 `issue_scan`/`output_validate`/`model_route`）——凡标"未核实"的资源极限/并发条目，均为**静态审视结论而非实测读数**，须由后续执行者/验证者实测确认（证据梯 L4）。
- **自我盲点**：theme 1/3/4 的"超大文件/无锁并发"三条我倾向判为资源极限风险，但**未实测**是否真崩/真丢账——诚实标注为待验证。
- **并发冲突事实**：`reports/2026-10-13-r13-boundary-audit.md` 已有一份并发产出报告，本报告按"历史文件只追加不覆盖"改用独立文件名；两版结论在"8 处未核实缺口"上**高度重叠**（output_validate 矛盾 invariant、model_router 损坏 JSON、跨 ns 并发锁、loop_tick 空环/超 max_rounds），**交叉印证**使这些缺口更可信。

---

## 汇总：适用性与未核实清单

- **总计 24 条用例**（6 主题 × 4 类）。
- **显式不适用（2 条工具用例）**：theme 2「负难度权重不适用（实现无权重注入面）」；theme 6「spec 未提主题=不沉默元规则」（元层规则，非工具用例）。
- **未核实（5 条）**：theme 1「不存在的目录被静默吞成空 findings」；theme 1「深层递归/超大文件扫描阈值」；theme 3「超大 artifact/巨量 artifacts 的内存/耗时阈值」；theme 4「跨进程并发写同 ns 状态文件的竞态（无锁）」；theme 5「环内 mode 依赖断裂无校验」+「LoopRegistry 无上限注册/非持久化」。
- **最高价值语料（矛盾型）**：theme 3「矛盾 invariant 无专门检测」、theme 2「可配置难度权重与实现的封闭集不符」——这两条若被强验证者质疑 spec 宣称，即产出真实打回依据。

## 来源

- 真源只读：`src/server/issue_scan.mbt`、`src/engine/cost_tool.mbt`、`src/engine/engine_dag_ext.mbt`、`src/store/store.mbt`、`src/store/store_sqlite.mbt`、`src/server/output_validate.mbt`、`src/router/router_state.mbt`、`src/router/star_gate.mbt`、`src/server/model_router_ops.mbt`、`src/ops/ops_loop.mbt`、`src/server/server.mbt`
- 上下文：`AGENTS.md`、`AI-DEVELOPMENT-STANDARD.md`、`memory/2026-10-13.md`、`reports/2026-10-13-r13-boundary-audit.md`（并发版，交叉对照）
