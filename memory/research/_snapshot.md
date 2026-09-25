# fist-mbt 概率门禁证据快照（第 28 次评估 · R109 增量后）

> 时间：2026-09-26 · 用途：喂给 4-AI 的统一唯一事实依据（AI1=self / AI2=LongCat / AI3=默认 / AI4=kimi-k3）
> 口径：全档达标 一等≥0.70 / 二等≥0.85 / 三等≥0.97，AND 聚合。

## 一、硬指标（可复现）
- **102 个 MCP 工具**（+3 resources +2 prompts，R104 新增 circuit_fail/succeed/status 熔断器三态、R109 新增 tx_contract 迁移契约检查），`moon test --target js -j 1` **301/301 全绿**（Windows + WSL(Linux) 双端实测一致；R107 新增 8 个 quickcheck 属性测试、R109 新增 6 个契约检查测试）。
- 工具链 moonc ≥0.10.14（评选会同要求版本），mooncakes **v0.2.4 已发布**（200 OK），一页申报书 PDF 已生成。
- CI 三轨道（js ubuntu / native ubuntu / js windows）实时徽章；守卫族 check_tools_sync(102)/check_test_sync(301)/check_badge/check_scripts_index/map_verify/cleanup --check 全 PASS。
- 依赖全公开：`moon update` 即可构建，无私有包/无硬编码盘符/任意机器结果可复现。

## 一b、p3 必然性证据（本次第 28 次评估前实测输出，非纸面）
- 一键自检链实测全过（本会话真实运行）：`moon test --target js -j 1` → **Total tests: 301, passed: 301, failed: 0**；`python scripts/mcp_smoke.py` → **PASS tools/list → 102 个工具 … MCP-SMOKE PASS**；`python scripts/award_demo.py` → **MCP-AWARD-DEMO PASS**（R68-R109 能力链一条命令全通，含 executor_auction/progress_gate/phi_accrual/saga_repair/plan_revise/goal_drift_check/health_check/circuit_breaker/tx_contract 实测输出——R104 段 fail×3→open→half_open→closed 全环、R109 段 待领取 execute 前置拒绝→认领后全通过，结尾 cleanup → CLEAN）。
- 守卫族实测全 PASS：check_tools_sync（102 对齐）/ check_test_sync（301 对齐）/ check_badge（README 徽章 301%2F301 == 实测）/ check_scripts_index / map_verify（fist://map 12 分组）/ cleanup --check（CLEAN：仓库根仅 fist-mbt.db）。
- 验收闭环真实走通：发布→认领→拆分→执行→提交→验收→归档 全生命周期 + Omega 强验证（语料 316 条）+ 看门狗跨进程 heal（heartbeat 11 条）+ 概率式判活 phi_gate。
- 双端可复现：JS 后端 Windows + WSL(Linux) 均 301/301（此前多轮双端实测一致）；mooncakes 发布成功即外部验证构建/打包/发布链路。
- **文档=实现实时校准**：申报书/README/AGENTS/deliverable/scoring_rubric/BACKLOG/USAGE/agent-map 工具 102、测试 301 全量对齐；第 27 次评估（R107 后）4 AI 全过（AI3/AI4 p1 微升 0.74）。
- **提交包完备性**：申报书（md+PDF）齐备、mooncakes v0.2.4 发布页在线（200 OK）、CI 三轨道（js ubuntu / native ubuntu / js windows）实时徽章、README 环境要求（Node≥24 / native sqlite）齐全——评审/评分者首读即定位，无"找不到/不一致"硬伤。

## 二、近八轮（R101-R109，均实测通过）
| 轮 | 能力 | 证据 |
|---|---|---|
| R101 | 门禁复评确认 R100（第 24 次评估全过 · `--prompt-file` 通道连续五轮零超时） | 4 AI 全过：AI2 0.72/0.86/0.97 · AI3 0.72/0.87/0.98 · AI4 0.72/0.87/0.98 |
| R102 | **四金信号健康巡检 `health_check`**（Google SRE Book 2016「Monitoring Distributed Systems」蒸馏）：project_health 从"一个等级"升级为"四个信号"——latency（完成周期 p50/p90 百分位，<3 条 insufficient，SRE 用百分位不用均值）/ traffic（活跃需求）/ errors（失败率 >0.3 attention）/ saturation（积压率——SRE 先行指标：系统先积压后坏，>0.5 attention 预警）；grade=最差信号，纯读不写库 | board_ascii_test +3；280→283/283 |
| R103 | 门禁复评确认 R102（第 25 次评估全过 · `--prompt-file` 通道连续六轮零超时 · AI3 大涨） | 4 AI 全过：AI3 0.75/0.90/0.98（三档大涨）· AI2 0.72/0.87/0.98 · AI4 0.71/0.86/0.97 |
| R104 | **熔断器三态 `circuit_fail`/`circuit_succeed`/`circuit_status`**（Nygard Release It! 2007 / Fowler / Azure / AWS 蒸馏）：Closed 窗口内失败计数达阈值 → Open（fail-fast 拒绝，allow_call=false 微秒返回不耗线程池，防级联失败）→ 恢复定时器到期 → Half-Open（放行探测请求）→ 探测成功 Closed / 失败回 Open；store 双后端 circuit_breakers 表（幂等 upsert + clear），engine 纯函数状态机 | engine_circuit_test +4；283→287/287 |
| R105 | 门禁复评确认 R104（第 26 次评估全过 · `--prompt-file` 通道连续七轮零超时） | 4 AI 全过：AI1 0.73/0.88/0.98 · AI2 0.73/0.87/0.97 · AI3 0.73/0.88/0.98 · AI4 0.72/0.87/0.97 |
| R106 | **English README**（P3 国际受众 · Lambda World 2026）：评审/评分者首读第一印象 + 国际受众双受益，纯文档零回归 | README_EN.md 新建（约 200 行英文）；守卫族全 PASS；287/287 不变 |
| R107 | **quickcheck 属性测试**（BACKLOG P2「集成 moonbitlang/core/quickcheck 替代硬编码断言」落地 · 拿来主义支柱实证）：core/decompose 两个此前无直接测试的包补上 8 条随机输入属性——default_slices 数量与前缀不变量 / difficulty_label 三档合法+整段单调 / difficulty_label_from 单调 / Task 迁移纪律四连（claim 空 assignee 拒绝、execute 仅两态、reopen 仅归档拒绝、split 叶子拒绝、submit/reject 对称）——固定 seed 可复现，OOM 域防护（大 Int 域放行） | decompose_quickcheck_test +3 + core_quickcheck_wbtest +5；287→295/295 |
| R108 | 门禁复评确认 R107（第 27 次评估全过 · `--prompt-file` 通道连续八轮零超时 · AI3/AI4 p1 微升 0.74） | 4 AI 全过：AI1 0.73/0.88/0.98 · AI2 0.73/0.88/0.98 · AI3 0.74/0.88/0.98 · AI4 0.74/0.88/0.98 |
| R109 | **迁移契约检查 `tx_contract`**（BACKLOG P2「Transactional transition：invariant 失败整笔拒绝、状态 A 回稳」落地 · Design by Contract 蒸馏：Meyer Eiffel 1986/1997 precondition/invariant/postcondition 三件套 + PMAT ch59 work-item 契约先例 + Gray & Reuter 事务原子性语境，101→102 工具）：对 (task, action) 只读预检——precondition（前置状态合法，复用 Task 迁移语义）/ invariant（领域不变量迁移后成立：IN-1 id 非空 / IN-2 K 值 depth≥1 / IN-3 split_n≥1 / IN-4 身份保持 / IN-5 assignee 纪律）/ postcondition（目标态=文档化目标态）；任一失败 → verdict=rejected 整笔拒绝、状态 A 回稳（不落库）；纯计算只读不写库 | engine_contract_test +6；295→301/301 |

## 三、机制设计家族（排程/预算/市场/可靠性全景）
PERT/CPM(dag_slack) → 概率完工(dag_mc) → STAR 依赖图成本路由(dag_cost_route) → SwarmHarness 信任轴(executor_route) → ZEBRA 预算阶段切分(cost_budget_split) → Agora 置信度拍卖(executor_auction) → PROGROUTER 进度门控(progress_gate) → Phi Accrual 可靠性闭环(phi_accrual + watchdog phi_gate) → Saga 全局补偿(saga_rollback) → 局部补偿控级联(saga_repair) → 反馈驱动计划修订(plan_revise) → 全局目标校验(goal_drift_check) → 四金信号健康巡检(health_check) → **熔断器(circuit_breaker：外部调用 fail-fast + 恢复探测，防级联失败)**——"更好的 AI 项目管理工具"从拆解→执行→反馈修订→目标校验→排程→预算→派单→看护→补偿→巡检→熔断全链路闭环，每个机制都有论文锚点（Nygard Release It! 2007 最经典韧性著作）且纯 MoonBit 可复现。

## 四、三支柱（@用户建议落地）
- **地图**：`fist://map`（机器可读工具分组）、board_ascii 实时看板、status_summary 项目脉冲、project_health 健康卡 + health_check 四金信号、docs/agent-map.md、USAGE 手册——agent 首读即定位，无需全项目乱找。
- **复用**：reserve_scope 作用域预订（Interlinked）、evolve_asset_register 外部资产注册、调研档 20260926.cost-market-routing.md / reliability-phi-accrual.md / saga-compensation.md / local-compensation.md / plan-revise.md / goal-drift-check.md / health-check.md / circuit-breaker.md / transactional-transition.md 全部信号落地；moonbitlang/core/math 复用（非自造）；goal_drift_check 复用 @evolve.tokens/jaccard、health_check 复用 @ops.iso_to_secs、circuit 复用 store 双后端模式（不新造词法/时间解析/持久化范式）；**R107 复用 moonbitlang/core/quickcheck 属性测试库**（随机输入验证不变量替代手写固定断言，test-only 导入不污染产物体积）；**R109 tx_contract 复用 Task 迁移方法语义 + 对标 PMAT ch59 work-item 契约先例**（不新造状态机/预检范式）——拿来主义支柱再实证。
- **整洁**：store_open scratch 临时区隔离、cleanup_artifacts --check CI 干净度门禁、check_scripts_index 工具脚本单一索引——临时脚本任务完即清、代码生成物统一清理。

## 五、自举采用证据（系统用自己打磨自己——读盘真实数据）
- 交付库 fist-mbt.db 实测：**753+ 任务 / 157+ 已完成 + 32 已归档 / 212+ 执行记录 / 316 语料(specs) / 5 自进化档案 / 心跳 11+**。
- 自驱闭环：selfdrive 审视轮 → parse_next → publish_next 持续自推；watchdog_tick（phi_gate 可选）无人值守。
- 演示链 award_demo 一条命令跑通 R68-R109 能力链（健康卡/dag_cost_route/executor_auction/progress_gate/phi_accrual/saga_repair/plan_revise/goal_drift_check/health_check/circuit_breaker/tx_contract），showcase.ps1 30-60s 视觉终端巡演（九态/DAG/自治派送）。

## 六、门禁历史（新档位 70/85/97 已连续多轮全过，最近第 27 次评估 R107 后）
第 16(R77)/17(R78)/18(R83)/19(R84-R90 四跑并述)/20(R92)/21(R94)/22(R96)/23(R98)/24(R100)/25(R102)/26(R104)/27(R107) 次评估均 PASS=是；R108 复评确认 R107（第 27 次评估全过 · AI3/AI4 p1 微升）；R109 tx_contract 硬创新后本轮第 28 次复评确认稳健。
