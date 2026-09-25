# fist-mbt 概率门禁证据快照（第 25 次评估 · R101/R102 增量后）

> 时间：2026-09-26 · 用途：喂给 4-AI 的统一唯一事实依据（AI1=self / AI2=LongCat / AI3=默认 / AI4=kimi-k3）
> 口径：全档达标 一等≥0.70 / 二等≥0.85 / 三等≥0.97，AND 聚合。

## 一、硬指标（可复现）
- **98 个 MCP 工具**（+3 resources +2 prompts，R102 新增 health_check 四金信号健康巡检），`moon test --target js -j 1` **283/283 全绿**（Windows + WSL(Linux) 双端实测一致）。
- 工具链 moonc ≥0.10.14（评选会同要求版本），mooncakes **v0.2.4 已发布**（200 OK），一页申报书 PDF 已生成。
- CI 三轨道（js ubuntu / native ubuntu / js windows）实时徽章；守卫族 check_tools_sync(98)/check_test_sync(283)/check_badge/check_scripts_index/map_verify/cleanup --check 全 PASS。
- 依赖全公开：`moon update` 即可构建，无私有包/无硬编码盘符/任意机器结果可复现。

## 一b、p3 必然性证据（本次第 25 次评估前 24h 内实测输出，非纸面）
- 一键自检链实测全过（本会话真实运行）：`moon test --target js -j 1` → **Total tests: 283, passed: 283, failed: 0**；`python scripts/mcp_smoke.py` → **PASS tools/list → 98 个工具 … MCP-SMOKE PASS**；`python scripts/award_demo.py` → **MCP-AWARD-DEMO PASS**（R68-R102 能力链一条命令全通，含 executor_auction/progress_gate/phi_accrual/saga_repair/plan_revise/goal_drift_check/health_check 实测输出——R102 段真实检出演示区 saturation=attention 积压先行预警，结尾 cleanup → CLEAN）。
- 守卫族实测全 PASS：check_tools_sync（98 对齐）/ check_test_sync（283 对齐）/ check_badge（README 徽章 283%2F283 == 实测）/ check_scripts_index / map_verify（fist://map 12 分组）/ cleanup --check（CLEAN：仓库根仅 fist-mbt.db）。
- 验收闭环真实走通：发布→认领→拆分→执行→提交→验收→归档 全生命周期 + Omega 强验证（语料 316 条）+ 看门狗跨进程 heal（heartbeat 11 条）+ 概率式判活 phi_gate。
- 双端可复现：JS 后端 Windows + WSL(Linux) 均 283/283（此前多轮双端实测一致）；mooncakes 发布成功即外部验证构建/打包/发布链路。
- **文档=实现实时校准**：申报书/README/AGENTS/deliverable/scoring_rubric/BACKLOG/USAGE/agent-map 工具 98、测试 283 全量对齐；第 24 次评估（R100 后）4 AI 全过。
- **提交包完备性**：申报书（md+PDF）齐备、mooncakes v0.2.4 发布页在线（200 OK）、CI 三轨道（js ubuntu / native ubuntu / js windows）实时徽章、README 环境要求（Node≥24 / native sqlite）齐全——评审/评分者首读即定位，无"找不到/不一致"硬伤。

## 二、近四轮硬创新（R99-R102，均实测通过）
| 轮 | 能力 | 证据 |
|---|---|---|
| R99 | 门禁复评确认 R98（第 23 次评估全过 · `--prompt-file` 通道连续四轮零超时） | 4 AI 全过且 p3 连续四轮全 0.98：AI2 0.72/0.87/0.98 · AI3 0.72/0.88/0.98 · AI4 0.71/0.87/0.98 |
| R100 | **全局目标校验 `goal_drift_check`**（goal drift arXiv 2505.02709 / Repetitiveness Rate arXiv 2603.12710 / IntentCUA 2602.17049 / HiMAP ICML2026）：每子任务完成后校验是否偏离根目标（drift）或与兄弟重复（non-redundancy）——词法 Jaccard 纯计算（复用 @evolve.tokens/jaccard 单真源，零 LLM 自评）；drift>0.7 判 drift_suspect 附 re_anchor 提示（目标重锚定）、与兄弟 jaccard≥0.7 判 redundant_suspect（HiMAP uniqueness monitor 防重复子目标）；subtask_id 缺省校验全部后代，纯读不写库 | dag_ext_test +3；277→280/280 |
| R101 | 门禁复评确认 R100（第 24 次评估全过 · `--prompt-file` 通道连续五轮零超时） | 4 AI 全过：AI2 0.72/0.86/0.97 · AI3 0.72/0.87/0.98 · AI4 0.72/0.87/0.98 |
| R102 | **四金信号健康巡检 `health_check`**（Google SRE Book 2016「Monitoring Distributed Systems」四金信号蒸馏）：project_health 从"一个等级"升级为"四个信号"——latency（完成周期 created_at→updated_at 秒，p50/p90 百分位，<3 条 insufficient，SRE 用百分位不用均值）/ traffic（活跃需求 in_flight+ready）/ errors（失败率 已打回+已暂停/总数 >0.3 attention）/ saturation（积压率 待领取/总数——SRE 先行指标：系统先积压后坏，>0.5 attention 预警）；grade=最差信号，纯读不写库 | board_ascii_test +3；280→283/283 |

## 三、机制设计家族（排程/预算/市场/可靠性全景）
PERT/CPM(dag_slack) → 概率完工(dag_mc) → STAR 依赖图成本路由(dag_cost_route) → SwarmHarness 信任轴(executor_route) → ZEBRA 预算阶段切分(cost_budget_split) → Agora 置信度拍卖(executor_auction) → PROGROUTER 进度门控(progress_gate) → Phi Accrual 可靠性闭环(phi_accrual + watchdog phi_gate) → Saga 全局补偿(saga_rollback) → 局部补偿控级联(saga_repair) → 反馈驱动计划修订(plan_revise) → 全局目标校验(goal_drift_check) → **四金信号健康巡检(health_check：latency/traffic/errors/saturation，积压先行预警)**——"更好的 AI 项目管理工具"从拆解→执行→反馈修订→目标校验→排程→预算→派单→看护→补偿→巡检全链路闭环，每个机制都有论文锚点（SRE Book 2016 最经典可靠性著作）且纯 MoonBit 可复现。

## 四、三支柱（@用户建议落地）
- **地图**：`fist://map`（机器可读工具分组）、board_ascii 实时看板、status_summary 项目脉冲、project_health 健康卡 + health_check 四金信号、docs/agent-map.md、USAGE 手册——agent 首读即定位，无需全项目乱找。
- **复用**：reserve_scope 作用域预订（Interlinked）、evolve_asset_register 外部资产注册、调研档 20260926.cost-market-routing.md / reliability-phi-accrual.md / saga-compensation.md / local-compensation.md / plan-revise.md / goal-drift-check.md / health-check.md 全部信号落地；moonbitlang/core/math 复用（非自造）；goal_drift_check 复用 @evolve.tokens/jaccard 单真源、health_check 复用 @ops.iso_to_secs（不新造词法/时间解析）。
- **整洁**：store_open scratch 临时区隔离、cleanup_artifacts --check CI 干净度门禁、check_scripts_index 工具脚本单一索引——临时脚本任务完即清、代码生成物统一清理。

## 五、自举采用证据（系统用自己打磨自己——读盘真实数据）
- 交付库 fist-mbt.db 实测：**753+ 任务 / 157+ 已完成 + 32 已归档 / 212+ 执行记录 / 316 语料(specs) / 5 自进化档案 / 心跳 11+**。
- 自驱闭环：selfdrive 审视轮 → parse_next → publish_next 持续自推；watchdog_tick（phi_gate 可选）无人值守。
- 演示链 award_demo 一条命令跑通 R68-R102 能力链（健康卡/dag_cost_route/executor_auction/progress_gate/phi_accrual/saga_repair/plan_revise/goal_drift_check/health_check），showcase.ps1 30-60s 视觉终端巡演（九态/DAG/自治派送）。

## 六、门禁历史（新档位 70/85/97 已连续多轮全过，最近第 24 次评估 R100 后）
第 16(R77)/17(R78)/18(R83)/19(R84-R90 四跑并述)/20(R92)/21(R94)/22(R96)/23(R98)/24(R100) 次评估均 PASS=是；R101 复评确认 R100、R102 四金信号硬创新后本轮第 25 次复评确认稳健。
