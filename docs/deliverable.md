# FIST-Mbt 参赛交付说明（评审速览）

> 定位：**纯 MoonBit 实现的 MCP Server**——AI 指挥官式任务编排，同时是"更好的 AI 项目管理工具"。
> 一次自检即验证核心链路，其余为逐项证据索引。2026-09-25 状态。

## 一、10 秒自检（评审用这个）
```bash
# ① 构建 + 拉起 MCP server 并自检（需 Node ≥ 24）
moon build --target js cmd/main
python scripts/mcp_smoke.py
# 期望输出：PASS tools/list → 103 个工具 / PASS publish / PASS get → MCP-SMOKE PASS
```

## 二、硬指标（快照）
| 项 | 值 |
|---|---|
| MCP 工具 | **103**（+ 3 resources + 2 prompts） |
| 测试 | **`moon test --target js` 307/307**（Windows + WSL(Linux) 双端实测全绿） |
| 回归 | 0（既有语义不破坏，增强默认关闭零回归） |
| 依赖 | 全公开，`moon update` 即可构建，无私有包/登录/vendor |
| Env | Node ≥ 24；`moon info && moon fmt` 后测试（AGENTS.md / 环境要求） |

## 三、核心能力（评审点）
1. **任务编排闭环**：发布→认领→拆分(plan_deep 递归)→执行→提交→验收→归档；父任务自动上卷。
2. **AI 自驱式**：selfdrive_*（审视→自我派活）；自驱脚本见 `scripts/*_selfdrive.py`。
3. **Omega 强验证**：语料创建→审核→成果复验门禁，不达标记打回、超限升级人工（防死循环）。
4. **DGM 自进化**：档案库 + 多样采样 + 蒸馏 principle + **失败回流 lesson**（见探索性闭环脚本）。
5. **DAG 编排**：显式依赖 `dag_depend`、关键路径/并行度/ASCII 图/topo 排序。
6. **多租户**：命名空间物理隔离（`store_open`，`scratch` 临时区不污染根）。
7. **项目地图**：`fist://map` resource——agent 首读即有，避免全项目乱找（docs/agent-map.md）；`board_ascii` 实时任务看板，一眼看全貌。

## 四、自驱增强证据（git 4994aae → HEAD，47 轮）
| 轮 | 增强 | 验证脚本 |
|---|---|---|
| 1 项目地图 | `fist://map` + docs/agent-map + 调研纪要 | `map_verify.py` |
| 2 失败回流 | `evolve_lesson` | `lesson_verify.py` |
| 3 DAG 显式 | `dag_depend` + to_json 修复 | `dag_depend_verify.py` |
| 4 双端复现 | WSL 199/199 复核 | —（实机） |
| 5 临时隔离 | `store_open(scratch)` | `scratch_verify.py` |
| 6 回流闭环演示 | lesson 归档→dead_ends 可见 | `lesson_chain_selfdrive.py` |
| 7 Omega自动落lesson | auto-lesson + 进程内可见 | `omega_lesson_verify.py` |
| 8 看板 | `board_ascii` 实时任务看板 | `board_ascii_test.mbt` |
| 9 脉冲 | `status_summary` + fix `fist://overview`(version/9态) | 单测 + E2E |
| 10 作用域预订 | `reserve_scope/check/release`（Interlinked 拿来主义） | 双后端单测 + E2E |
| 11 预订整洁 | `clear()` 一并清空 reservations（防跨次残留） | 单测 |
| 12 难度梯度 | `task_plan_deep gradient=true`：拆解子任务带「难度梯度 序号/总数:易/中/难」+「更简单变体」提示（LADDER 信号） | `plan_gradient_verify.py` |
| 13 Critic防漂移 | `evolve_critic` 门禁（SAGE）：入库前纯计算评审拟议 principle/lesson，重合≥70% 判课程漂移拒收、综合分低暂缓 | `evolve_critic_verify.py` |
| 14 Challenger进阶 | `task_challenge`：对已完成/已归档任务发布更难变体新根任务（[challenge] 溯源 + 重要度升档，SAGE 四专家环补齐） | `task_challenge_verify.py` |
| 15 生成物清理 | `cleanup_artifacts.py`：除交付库 fist-mbt.db 外清理 *.db/-shm/-wal 与 temp/；--check 作 CI 干净度守卫 | 实跑 74+63 移除 + CLEAN |
| 16 自驱 DEMO | `award_demo.py`：一条命令串演 map→拆解(gradient)→验收→Challenger→Critic→预订→脉冲/看板 | `python scripts/award_demo.py` |
| 17 难度校准 | `task_plan_deep gradient+calibrate`：按切片给真实难度 0..5 覆盖位置档（LADDER 补真实难度） | `plan_gradient_verify.py`（含 calibrate） |
| 18 文档一致 | agent-map 分组对齐 77 工具、fist://map 文案 76→77（文档即实现扫尾） | 全仓 grep 计数审计 |
| 19 native 证据 | `moon check --target native` 0 错误；Windows native 竞态(0xc0000374)文档如实修正，权威门槛=JS 后端双端+Linux native | 实机验证 + cleanup CLEAN |
| 20 交付完整化 | deliverable 轮证据补齐/遗留如实化（native 竞态、已实现的失败回流不误列） | 文档核对 |
| 21 下一步推荐 | `task_triage`：可领取任务按 优先级→重要度→深度 排行 + suggestion（agent 无需全量扫描即可决定下一单） | `engine_triage_test.mbt` + award_demo ⑨ |
| 22 CI/计数收尾 | CI 三轨道复核（js/native-Linux/js-Win，native 只在 Linux 跑规避竞态）+ 补漏 4 处 77→78 工具计数 | ci.yml 核对 + 全仓 grep |
| 23 能力路由 | `task_triage want`：描述/id 命中能力关键词的可领取任务排头部，suggestion 标注能力匹配（Marketplace 雏形） | `engine_triage_test.mbt` + award_demo ⑨(want=编排) |
| 24 轮表对账 | deliverable 轮证据表 R1..R23 连续（修正错位/补缺/追新） | 文档核对 |
| 25 自检门禁 | README「一键完整自检(评审用)」+ 修正 Tools(61→78) 超陈旧计数，期望逐条实跑核对 | `moon test`+`mcp_smoke`+`award_demo` |
| 26 自驱取单 | `selfdrive_pick_next`：按 triage 能力推荐自动取走顶部并认领（待领取→已领取，无人值守按能力自推进） | `engine_triage_test.mbt` + award_demo ⑩ |
| 27 自驱闭环演示 | award_demo ⑪ 推荐→取单→执行→验收→再推荐整圈跑通 | `award_demo.py` |
| 28 脚本整洁 | 清临时残留(`_score_probe/_probe_result`) + rubric 正式化(`_ai_prompt→scoring_rubric`) + 陈旧计数修正（项目整洁支柱） | `git rm/mv` + `score_gate.py` py_compile |
| 29 挑战题防漂移门禁 | `task_challenge critic=true`：挑战变体发布前过 `critic_review`（与 evolve_critic 同一单一真源），当前策略漂移自动降档、全部漂移拒发（防"由易到难"退化成同质坍缩，SAGE Critic 过滤题目 + R-Few） | `engine_challenge_test.mbt`(+3) + `task_challenge_verify.py` |
| 30 能力路由 | `executor_register`/`executor_route`：执行者登记能力标签，按 { 能力覆盖率 desc → 负载 asc } 路由最佳执行者（Marketplace/Dynamic 范式，按专长+负载分配） | `registry_test.mbt`(+4) + `executor_route_verify.py` |
| 31 能力注册持久化 | `executor_*` 落 store executors 表（双后端）+ `executor_clear` 重置：能力注册跨进程可复现（进程A注册→进程B路由读到→clear 消失） | `executor_store_test.mbt`(+3) + `executor_route_verify.py`（跨进程三段） |
| 32 能力自动派单 | `selfdrive_dispatch`：triage 取顶部 → executor_route 按 want 找最佳执行者 → 直接认领给该执行者（待领取→已领取，把"推荐"落成动作） | `dispatch_verify.py` E2E |
| 33 派单免手传 | `selfdrive_dispatch` 不传 want 时从任务描述自动抽取已注册能力标签（need_auto） | `dispatch_verify.py`（免 want 用例） |
| 34 徽章守卫 | `check_badge.py` + ci.yml JS 轨 Badge guard：README 徽章 ≠ 实测测试数即 FAIL（杜绝计数手改漏同步） | `python scripts/check_badge.py`（正/负路径） |
| 35 LADDER 深化 | `gradient` 提示补"先易后逆推"自举闭环（先完成更简单变体再推广/逆推到本体） | `simpler_variant_hint` + decompose_test 断言 |
| 36 地图同步 | `fist://map` tool_groups 全量同步到 85 工具 10 分组（补 看板/脉冲/预订/推荐+M、Marketplace·能力路由、pick_next/critic/lesson/challenge），map_verify 加断言 | `map_verify.py` E2E |
| 37 gradient真实DAG | `task_plan_deep gradient_dag=true`：把 LADDER「更简单变体→先易后逆推」由提示文本升级为**真实 DAG 前驱链**——每层兄弟切片按由易到难连 depends_on，更难切片须等前驱完成后才可认领，经 `dag_ready/dag_ascii/topo_sort` 可见；仅显式开启，默认零回归、工具数不变 | `decompose_test.mbt`「gradient_dag 真实 DAG 前驱链」用例 |
| 38 执行计划视图 | `task_plan_deep` 返回新增 `exec_order`：拆解后即给出整棵子树的**按 DAG 拓扑序、附难度档/依赖/深度的扁平执行清单**，agent 拿到即可照单执行（纯读无副作用，不加工具）；与 gradient_dag 协同——依赖先于被依赖，"先易后逆推"可见可执行 | `decompose_test.mbt`「plan_exec_order DAG 序执行计划」用例 |
| 39 推荐带依赖 | `task_triage` 每条推荐任务新增输出 `depends_on`（复用 R39 DAG 边）：走 `dag_depend`/`gradient_dag` 建的依赖，"下一单"不光看难度/优先级，还能看到它就绪的前驱是谁（DAG→推荐纵向闭合，复用/拿来主义支柱） | `engine_triage_test.mbt`「task_triage 暴露 depends_on」用例 |
| 40 难度抽取单一化 | `task_triage` 的难度标签改复用 R40 的 `extract_difficulty` 单一抽取来源（去重 `triage_label_of` 的 `:易]` 后缀粗匹配，并支持 calibrate 真实难度 `难 d=5`→难 归一；空回退叶/分支兜底不变）——消除两处难度解析重复，落实支柱②复用/避重复 | `engine_triage_test.mbt`「task_triage 返回可领取排行并带难度标签」既有用例回归 |
| 41 脉冲难度分布 | `status_summary` 新增 `by_difficulty`（待领取任务按 易/中/难/无 分布）：`extract_difficulty` 升为 pub 跨包复用（server 包），项目脉冲一眼看"待办难度结构"（支柱①＋②） | `board_ascii_test.mbt`「status_summary … by_difficulty 不变量」用例 |
| 42 工具单一真源 | `scripts/check_tools_sync.py` + ci.yml 两轨：唯一真源=server.mbt 实际注册名，校验 AGENTS 表格工具名 ⊆ 真源、真源全部入 AGENTS、四文档工具总数==85（双向防幽灵/漏写）。守卫发现 AGENTS 只列 54/85 后补齐 29 个（新增 自驱闭环/运维杂项/ATGC-old 三组，生命周期14、自进化11、Omega补2），PASS | `python scripts/check_tools_sync.py`（PASS）+ `moon test` 233/233 |
| 43 测试数单一真源 | `scripts/check_test_sync.py` + ci.yml JS 轨：补 check_badge 盲区，跨 README/AGENTS/deliverable/scoring_rubric 校验测试总数==实测（N/N、N 全绿、独立 N 任一），正路径 PASS、负路径 FAIL=1 | `python scripts/check_test_sync.py --total 233`（PASS） |
| 44 地图补全 | `fist://map` tool_groups 补齐 R46 新工具家族（生命周期 publish_parallel/reopen_task、强验证 verify/verify_fix、新增「运维·日志/缺陷/成本/调度」「衍生·ATGC-old」分组、自驱补 selfdrive_dispatch）；map_verify 加断言锁住关键补漏——agent 首读地图即全概（支柱①） | `python scripts/map_verify.py`（PASS 12 分组）+ `moon test` 233/233 |
| 45 看门狗派发预览 | `watchdog_tick` 在显式 ns 无人值守场景新增 `detail.ready_dispatch_preview`：复用 engine.triage 给出"下一单可自动派发"的候选（纯读不认领，避免 ops 仓与 server 进程内 exec_reg 耦合；自治派单的前置信号） | `ops_watchdog_test.mbt`「watchdog R51 派发预览」用例（+1） |
| 46 看板难度标注 | `board_ascii` 每行任务附自身难度档（复用 pub `extract_difficulty` 单一来源）——实时看板一眼看任务难度结构（支柱①"一目了然"＋②"复用"） | `board_ascii_test.mbt`「board_ascii 每行标注难度档」用例（+1） |
| 47 引擎层自治派单 | 新增 `FistEngine::dispatch_next`（engine 层 store-backed 自治派单 primitive，R56）：读 store 持久化执行者能力注册 + executor 包 `route_pick` 按能力/负载路由 → 把 triage 顶部任务直接认领给最佳执行者（无注册回退 agent）。纯增量、零回归、不经 server 进程内 exec_reg——是看门狗自治派单的地基（未起 watchdog，仅 engine primitive + 单测） | `engine_dispatch_test.mbt`「dispatch_next」用例（+2） |
| 48 看门狗自治派单 | `watchdog_tick` 新增 `autodispatch`/`autodispatch_want`（R57，默认关闭零回归）：显式 ns 无人值守且无活跃任务时调 engine `dispatch_next` 把顶部待领取任务按能力/负载认领给最佳执行者，结果并入 `detail.autodispatch`——自治闭环闭环：派单 primitive + 看门狗驱动全打通（引擎层派单下沉、不经 server 进程内 exec_reg） | `ops_watchdog_test.mbt`「watchdog R57」用例（+2） |
| 49 派单能力自动抽取 | `dispatch_next` 在 `want` 为空时从顶部任务描述自动抽取所需能力标签（R58，store-backed 复用 R33「免手传」思路、不依赖 server exec_reg）：扫描述里出现的 store 持久化执行者能力标签取最长命中，返回 `want` 字段——「零参数自动派单」达成，watchdog `autodispatch_want` 可缺省 | `engine_dispatch_test.mbt`「want 自动抽取路由」用例（+1） |
| 50 父计划回注 | `plan_deep` 增 `reinject_context`（R63，ReCAP 借鉴，默认 false 零回归）：把「父计划摘要 + 剩余兄弟」回注进每条子任务描述，递归下钻整树继承——让拆出的原子片知道自己"为什么做、旁边还有谁"，防上下文漂移；engine + MCP task_plan_deep 双端贯通 | `decompose_test.mbt`「reinject_context 回注+默认关闭零回归」用例（+1） |
| 51 项目健康卡 | 新增 `project_health` 工具（R68）：单次调用聚合 in_flight/ready/done/blocked/reviewing/archived 六类计数 + 健康等级(empty/attention/stalled/healthy) + blocked_tasks，可接 ns 过滤——"agent 一眼看全项目健康"，正中支柱①"一目了然"与"更好的 AI 项目管理工具" | `board_ascii_test.mbt`「project_health 健康卡+等级判定」用例（+1） |
| 52 瓶颈与松弛分析 | 新增 `dag_slack` 工具（R71，PERT/CPM 硬核调度）：对每个任务算 earliest/latest/slack（0=关键路径，>0=可灵活并行安排），返回 { makespan, critical, slack_map, cycle }——"找出谁在关键路径上、谁有松弛可并行"，支撑排程优化。门禁复评 FAIL(AI3 p1 0.62) 后按"硬创新"要求落地，非演示叠加 | `dag_ext_test.mbt`「dag_slack 临界+松弛+环检测」用例（+1） |
| 53 排程视图·负载感知 | 新增 `dag_schedule` 工具（R74→R75）：基于 dag_slack 的松弛分析落成可执行排程——critical_batch(关键路径瓶颈,须串行盯紧) + flexible_batch(slack>0,按最早开始排序可并行,附 assignee，未认领项 add suggest=活跃负载最低的已注册执行者，R75 负载感知)——谁在瓶颈、谁可并行派单、建议派给谁，排程优化闭环 | `dag_ext_test.mbt`「dag_schedule 分批+assignee」「R75 负载感知 suggest」用例（+2） |
| 54 依赖图成本路由 | 新增 `dag_cost_route` 工具（R77，STAR 式蒸馏）：对 flexible 未认领任务按拓扑序贪心给建议执行者——执行成本(难度档 易/中/难→1/2/3，复用 extract_difficulty) + 切换成本(依赖执行者不同则 +1，STAR 上下文切换税) + 能力约束过滤(描述命中的已注册能力标签，复用 auto_want)，成本相等取负载最低。返回 { cost_route:[{task_id,assignee,est_cost,switch_cost,total}], total_est_cost, basis, note }——DAG 家族最后拼图：critical_path→slack→schedule→cost_route，排程优化闭环最终形态；纯读不 claim | `dag_ext_test.mbt`「dag_cost_route 能力约束+切换税+总成本」「同执行者免切换税+空注册表跳过」用例（+2） |
| 55 历史信任轴 | `executor_route` 增强（R80，SwarmHarness 蒸馏）：排序键升级为 { 能力覆盖 desc → 历史信任(名下已完成/名下总数，验收通过率，无历史 0.5 中性) desc → 负载 asc }，返回候选带 trust 字段 + basis——防"只认领不交付"，按专长+信任+负载分配；`route_pick_with_trust` 新签名，原 `route_pick` 保留零回归；engine 加 `executor_trust` 计算 | `registry_test.mbt`「route_pick_with_trust 信任轴排序」用例（+1） |
| 56 预算阶段切分 | 新增 `cost_budget_split` 工具（R81，ZEBRA 背包水填充蒸馏简化版）：给定总预算按任务 DAG 阶段(slack earliest 层级)切分——每阶段份额=阶段难度权重(难3/中2/易1)占总量比例×总预算(余数补最大权重阶段)，返回 { stages:[{level,tasks,difficulty_sum,share}], total_budget, makespan, note }——预算在依赖图上按阶段切分：瓶颈阶段占额可见，超支先预警 | `dag_ext_test.mbt`「budget_split_by_dag 阶段切分+空仓库」用例（+1） |
| 57 置信度校准拍卖 | 新增 `executor_auction` 工具（R87，Agora arXiv 2607.09600 蒸馏）：把分派从"排序推荐"升级为"按出价竞拍"——每个已注册执行者对所需能力 need 出价（显式 `bid` 或默认按能力覆盖率），经校准系数 1-\|出价-历史验收通过率\| 折扣防胜者诅咒（过度自信而兑现差的执行者被惩罚），再乘负载折扣 1/(1+负载) 得拍卖分；能力覆盖>0 方可竞拍，返回 bids 全表 + winner + basis + note。Marketplace 叙事续：能力登记→路由(专长+信任+负载)→**拍卖(校准出价)** | `registry_test.mbt`「auction_pick」用例（+3：能力门槛+默认出价 / 胜者诅咒防护 / 负载折扣+空 need） |
| 58 进度预算门控 | 新增 `progress_gate` 工具（R88，PROGROUTER arXiv 2608.25992 蒸馏）：对任务子树按已消耗预算(难度权重 易/中/难→1/2/3，自动估算或 `spent` 手动注入)与完成进度(已完成+已归档/子树任务数)做双路径剩余成本预测——线性=燃尽率×剩余工作量、保守=1.2×线性（PROGROUTER 双路径），元门控给决策 OK(预算充足继续)/CAUTION(线性可行但缓冲不足→降档缩范围)/ESCALATE(线性已超支→追加预算或暂停)。计划性增强：预算×进度在线体检，先预警后决策，纯计算零副作用 | `dag_ext_test.mbt`「progress_gate」用例（+4：OK 自动估算 / CAUTION / ESCALATE+双路径数字 / 未开工+全完成+空任务+非法预算） |
| 59 概率式故障检测 | 新增 `phi_accrual` 工具（R89，Hayashibara 2004 经典算法，Cassandra/HBase 生产采用）：按心跳间隔历史分布算怀疑度 φ=-log10(P(心跳晚于 elapsed 到达))，替代固定 timeout——窗口内间隔均值 μ+标准差 σ 建模（σ≈0 回退指数分布；\|z\|≥3 用尾部渐近展开保精度，core 无 sqrt 用牛顿法自实现），φ≥threshold(默认 8,原论文口径) 判 suspect 否则 healthy；无间隔历史 insufficient。升级看护语义：心跳节奏越快、越久没来才值得怀疑——可靠性工程新能力维度 | `engine_phi_test.mbt`「phi_accrual」用例（+3：σ=0 指数回退 / 正态建模 z=5 健康 z=6 怀疑 / 单调性+空历史） |
| 60 概率式看护闭环 | watchdog 端到端 φ 判活（R90，默认关闭零回归）：新增 heartbeat_history 表（SQLite，每任务保留最近 1000 条间隔）——`heartbeat` 工具每次上报自动算间隔落库（复用 @ops.iso_to_secs）；`watchdog_tick` 加 `phi_gate=true`（+`phi_threshold`，默认 8）：心跳超时判定改用概率怀疑度 φ（读持久化间隔历史 + elapsed），φ≥阈值才回滚——心跳节奏越快、越久没来才值得怀疑（实测静默 100s、间隔 5s：φ≈8.7 判死，而固定 timeout 600 不判）；`clear()` 一并清空间隔史。可靠性线程闭环：原语→持久化→运行时行为 | `ops_watchdog_test.mbt`「R90」用例（+2：间隔史写入/时间序读回/clear 清空 + phi_gate 早于固定 timeout 判活对照） |
| 61 Saga 补偿事务 | 新增 `saga_register`/`saga_rollback` 两工具（R92，Garcia-Molina & Salem 1987 SIGMOD 蒸馏，91→93 工具）：多步骤任务链每个前向步骤成功后登记「可补偿动作」（业务逆转描述，非 DB ROLLBACK）到 durable action log（saga_log 表，UNIQUE(ns,root,step) 幂等重登记）；失败时 `saga_rollback` 按 LIFO（严格倒序）返回待补偿序列，mark=true 默认消费防重复回滚、mark=false 仅预览——失败不再卡死/整树重来，按补偿序列优雅收尾；`clear()` 一并清空。失败收尾显式化（看护发现失败 → Saga 负责收尾） | `engine_saga_test.mbt`（+4：LIFO 倒序+mark 幂等 / 幂等重登记 / mark=false 预览 / clear 清空） |
| 62 Monte Carlo 完工预测 | 新增 `dag_mc` 工具（R94，Van Slyke 1963 首倡 MCS 求网络完工分布，93→94 工具）：PERT 确定性分析的概率式补充——按难度档采样三角分布时长（易(2,3,5)/中(3,5,8)/难(5,8,14)），xorshift32 确定性 PRNG + 牛顿法 sqrt（core 无 sqrt）整网模拟 samples 次，得完工分布(min/mean/p50/p90/max) + 按期概率 P(≤deadline) + 关键度排行（任务出现在最长路径的频率，含近关键路径，top 10）——克服 PERT 单关键路径/merge bias，回答"能不能按期、风险在哪、谁是最大风险"；seed 固定可复现 | `dag_mc_test.mbt`（+4：同 seed 可复现 / p_on_time 单调 / 关键度 A→B 链 / insufficient+samples 钳制） |
| 63 局部补偿控级联 | 新增 `saga_repair` 工具（R96，Plan Commitment 2023 / scope-aware repair 2026 蒸馏，94→95 工具）：给定失败步骤，计算最小补偿切片——失败步骤 + 其依赖下游（任务 depends_on 传递闭包中仍 pending 的步骤；无 task_id 时按注册序保守兜底 basis=order）——只补偿切片（LIFO）、切片外步骤保留承诺不补偿（keep，控级联不涟漪撤销），与 `saga_rollback` 全局 LIFO 整链收尾互补；mark=true 消费切片（幂等）、keep 保持 pending 供后续按需补偿——plan repair 保留承诺 > 整树重规划 | `engine_saga_test.mbt`「saga_repair」（+4：depends_on 闭包最小切片+旁路 keep / 注册序兜底 / mark=false 预览+失败步骤 Err / keep 与 rollback 两级共存） |
| 64 反馈驱动计划修订 | 新增 `plan_revise` 工具（R98，ReAct arXiv 2210.03629 / CoPAL arXiv 2310.07263 蒸馏，95→96 工具）：把「拆完即弃」升级为「执行中持续修订」——给定根任务及子任务执行反馈，计算计划三分 keep（已证有效承诺保留）/ rework（失败或其依赖链受牵连需返工，控级联不涟漪）/ ready（依赖全部有效且未执行，下一步可做）；feedback 缺省读真实状态（已完成/已归档=ok、已打回/已暂停=否），传 [{task_id, ok}] 显式覆盖；纯计算只读不写库（决策建议，执行权在 agent/指挥官）——ReAct 交错 + CoPAL 分级纠正（可恢复→局部修订） | `dag_ext_test.mbt`「plan_revise」（+4：status 基础 keep/rework 级联 / ready+feedback 覆盖 / feedback no 级联 / 根不存在 ok:false） |
| 65 全局目标校验 | 新增 `goal_drift_check` 工具（R100，goal drift arXiv 2505.02709 / Repetitiveness Rate arXiv 2603.12710 / IntentCUA 2602.17049 / HiMAP ICML2026 蒸馏，96→97 工具）：每子任务完成后校验是否偏离根目标（drift）或与兄弟重复（non-redundancy）——词法 Jaccard 纯计算（复用 @evolve.tokens/jaccard 单真源，零 LLM 自评，贴「评测是计算」原则）。drift=1-jaccard(根目标,子任务)>0.7 判 drift_suspect（附 re_anchor 提示：把根目标重新注入，防 context drift 渐失原始目标）；与任一兄弟 jaccard≥0.7 判 redundant_suspect（防重复子目标/重复造轮子，HiMAP uniqueness monitor）；subtask_id 缺省校验根下全部后代；纯计算只读不写库 | `dag_ext_test.mbt`「goal_drift_check」（+3：aligned/drift_suspect 附 re_anchor / redundant_suspect 兄弟重复+subtask_id 过滤 / 根不存在 ok:false） |
| 66 四金信号健康巡检 | 新增 `health_check` 工具（R102，Google SRE Book 2016「Monitoring Distributed Systems」蒸馏，97→98 工具）：project_health 从"一个等级"升级为"四个信号"——latency（最近已完成任务完成周期 created_at→updated_at 秒，p50/p90 百分位，<3 条 insufficient，SRE 用百分位不用均值）/ traffic（活跃需求 in_flight+ready）/ errors（失败率 已打回+已暂停/总数 >0.3 attention）/ saturation（积压率 待领取/总数——SRE 先行指标：系统先积压后坏，>0.5 attention 预警）；grade=最差信号（healthy/attention/idle）；纯计算只读不写库，ns 可选过滤 | `board_ascii_test.mbt`「health_check」（+3：空仓 idle+latency insufficient / 积压过半 saturation attention 先行预警 / healthy+latency p50/p90=120s） |
| 67 熔断器三态 | 新增 `circuit_fail`/`circuit_succeed`/`circuit_status` 三工具（R104，Nygard Release It! 2007 / Fowler / Azure / AWS 蒸馏，98→101 工具）：Closed（窗口内失败计数）→ 达阈值 → Open（fail-fast 拒绝，allow_call=false 微秒返回不耗线程池）→ 恢复定时器到期 → Half-Open（放行探测请求）→ 探测成功 Closed / 探测失败回 Open；store 双后端 circuit_breakers 表（幂等 upsert + clear 清空），engine 纯函数状态机（now_secs Int，规避 engine 无 ops 依赖） | `engine_circuit_test.mbt`「circuit」（+4：Closed 计数达阈值→Open fail-fast / Open 到期→Half-Open 放行探测→succeed→Closed / Half-Open 探测失败→回 Open / 窗口外复位+clear 清空） |
| 68 迁移契约检查 | 新增 `tx_contract` 工具（R109，Design by Contract 蒸馏：Meyer Eiffel 1986/1997 precondition/invariant/postcondition 三件套 + PMAT ch59 work-item 契约先例，101→102 工具）：对 (task, action) 只读预检——precondition（前置状态合法，复用 Task 迁移语义，Err 即前置失败）/ invariant（领域不变量在迁移后成立：IN-1 id 非空 / IN-2 K 值 depth≥1 / IN-3 split_n≥1 / IN-4 身份保持 id/project_dir/ns / IN-5 assignee 纪律，claim/reopen 除外）/ postcondition（目标态=文档化目标态）；任一失败 → verdict=rejected 整笔拒绝、状态 A 回稳（不落库），全部通过 → allowed；纯计算只读不写库（决策建议，执行权在调用方）——"Traditional ticket systems track what to do. DbC tracks what must remain true while you do it." | `engine_contract_test.mbt`「tx_contract」（+6：待领取 execute 前置拒绝回稳 / 已领取 execute 三件套全通过 / K 值非法 depth=0 任务 execute：前置过但 IN-2 不变量拒、整笔拒绝回稳 / claim 空 assignee 前置拒绝 / submit 对称（执行中 allowed、待验收前置拒绝）/ reopen on 已归档 前置拒绝） |
| 69 反馈收敛 | 新增 `eval_feedback` 工具（R111，Evaluator-Optimizer schema 蒸馏：Anthropic E/O 模式 + Self-Refine arXiv 2303.17651 + Reflexion arXiv 2303.11366 + zubi.ai 四段式，102→103 工具）：把自由文本反馈归一为 Defects/Evidence/Fix/Acceptance 四段式契约 + 确定性 verdict——无缺陷且 acceptance 非空 → pass（optimizer 可收敛）；否则 fail + flags（evidence_missing / fix_missing / section_missing:...）；纯计算只读不写库（决策建议，执行权在调用方；与 plan_revise 反馈修订互补：反馈从叙事升级为可计算契约，E/O 闭环 Defects→Fix→再 eval→pass 硬上限防死循环）——"agents reliably skew positive when grading their own work"（Anthropic 2026 harness：分离干活者与评判者是强杠杆） | `engine_eval_test.mbt`「eval_feedback」（+6：四段完整无缺陷 pass / 有缺陷+证据+修复 fail 结构化 / 缺陷缺证据 evidence_missing / 缺陷缺修复 fix_missing / 仅 Defects 段 section_missing 三缺 / 空文本全缺段） |

> 注：内存日志/汇报用字母轮号（含若干纯文档/CI 非功能行，不入上表）；本表仅计功能轮。

## 五、文档即实现
- 工具/资源/测试数均与实测一致（README/AGENTS/ARCHITECTURE/agent-map 已同步）。
- 过程日志 `memory/2026-09-25.md`；综合汇报 `reports/2026-09-25-award-enhancement-5rounds-report.md`。
- 调研：`memory/research/20260925.enrich-roadmap.md`（Repo Map / DALIA / TURA / AgentX / MoonBit 新特性）、`memory/research/ecosystem-borrow.md`（§五 二轮调研：SAGE/R-Few/SPICE/SEP-1686/RepoMap）、`memory/research/20260926.cost-market-routing.md`（成本感知调度/市场式路由：STAR 依赖图拍卖 / CASTER / ZEBRA / Agora / PROGROUTER / SwarmHarness——已落地 dag_cost_route R77 / executor_route 信任轴 R80 / cost_budget_split R81 / executor_auction 置信度拍卖 R87 / progress_gate 进度预算门控 R88，含落地设计草案）、`memory/research/20260926.reliability-phi-accrual.md`（可靠性工程新线程：Phi Accrual 概率式故障检测，落地 phi_accrual R89，Cassandra/HBase 生产采用）。
- 遗留如实：Windows native 竞态、`node:sqlite` 实验性警告、测试落盘 `temp/`（cleanup --check 兜底）见 §六。

## 六、遗留（诚实自曝）
- Windows native 测试偶发 `0xc0000374`（堆损坏/竞态，`-j 1` 可降但不保证消除；权威稳定门槛 = JS 后端双端 + Linux native，产品单进程不受影响，README「已知边界」）。
- `node:sqlite` 打实验性警告（功能正常）。
- 测试落盘目前在仓库 `temp/`（gitignore），由 `cleanup_artifacts.py --check` 作干净度门禁；`@fs.tmpdir` 在本工具链未暴露，"收敛到系统 tmp" 作为可选后续。
- Dynamic/Marketplace 能力路由（executor 抽象层朝"能力注册+按负载/专长分配"）为远期项。

*（内容由AI生成，仅供参考）*