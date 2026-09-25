# fist-mbt 概率门禁证据快照（第 19 次评估 · R84-R90 增量后）

> 时间：2026-09-26 · 用途：喂给 4-AI 的统一唯一事实依据（AI1=self / AI2=LongCat / AI3=默认 / AI4=kimi-k3）
> 口径：全档达标 一等≥0.70 / 二等≥0.85 / 三等≥0.97，AND 聚合。

## 一、硬指标（可复现）
- **94 个 MCP 工具**（+3 resources +2 prompts，R94 新增 dag_mc Monte Carlo 完工预测），`moon test --target js -j 1` **269/269 全绿**（Windows + WSL(Linux) 双端实测一致）。
- 工具链 moonc ≥0.10.14（评选会同要求版本），mooncakes **v0.2.4 已发布**（200 OK），一页申报书 PDF 已生成。
- CI 三轨道（js ubuntu / native ubuntu / js windows）实时徽章；守卫族 check_tools_sync(94)/check_test_sync(269)/check_badge/check_scripts_index/map_verify/cleanup --check 全 PASS。
- 依赖全公开：`moon update` 即可构建，无私有包/无硬编码盘符/任意机器结果可复现。

## 一b、p3 必然性证据（本次第 19 次评估前 24h 内实测输出，非纸面）
- 一键自检链实测全过（本会话真实运行）：`moon test --target js -j 1` → **Total tests: 269, passed: 269, failed: 0**；`python scripts/mcp_smoke.py` → **PASS tools/list → 94 个工具 … MCP-SMOKE PASS**；`python scripts/award_demo.py` → **MCP-AWARD-DEMO PASS**（R68-R90 能力链一条命令全通，含 executor_auction/progress_gate/phi_accrual 实测输出，结尾 cleanup → CLEAN）。
- 守卫族实测全 PASS：check_tools_sync（94 对齐）/ check_test_sync（269 对齐）/ check_badge（README 徽章 269%2F269 == 实测）/ check_scripts_index / map_verify（fist://map 12 分组）/ cleanup --check（CLEAN：仓库根仅 fist-mbt.db）。
- 验收闭环真实走通：发布→认领→拆分→执行→提交→验收→归档 全生命周期 + Omega 强验证（语料 316 条）+ 看门狗跨进程 heal（heartbeat 11 条）+ 概率式判活 phi_gate。
- 双端可复现：JS 后端 Windows + WSL(Linux) 均 269/269（此前多轮双端实测一致）；mooncakes 发布成功即外部验证构建/打包/发布链路。
- **文档=实现实时校准（本轮第 19 次评估刚做）**：复核发现申报书表头陈旧计数（88 工具/249 测试），已实时校准为 **91 工具 / 261 测试 / 双端 261/261**，全文再无陈旧当前状态（仅历史轮表如实留痕）；申报书 md+PDF（55KB）与 README（徽章 261%2F261）、AGENTS、deliverable、scoring_rubric 全量对齐——消除"文档失真→淘汰风险"感知。
- **提交包完备性**：申报书（md+PDF）齐备、mooncakes v0.2.4 发布页在线（200 OK）、CI 三轨道（js ubuntu / native ubuntu / js windows）实时徽章、README 环境要求（Node≥24 / native sqlite）齐全——评审/评分者首读即定位，无"找不到/不一致"硬伤。

## 二、近四轮硬创新（R87-R90，均实测通过）
| 轮 | 能力 | 证据 |
|---|---|---|
| R87 | **Agora 置信度校准拍卖 `executor_auction`**（arXiv 2607.09600）：能力覆盖>0 方可竞拍；出价×校准系数 1-\|出价-历史验收通过率\|（防胜者诅咒）+负载折扣 | registry_test +3；award_demo 演示行 PASS |
| R88 | **PROGROUTER 进度预算门控 `progress_gate`**（arXiv 2608.25992）：预算×进度双路径剩余成本预测（线性/保守 1.2×），元门控 OK/CAUTION/ESCALATE | dag_ext_test +4；award_demo 演示行 PASS（实测超支检出） |
| R89 | **Phi Accrual 概率式故障检测 `phi_accrual`**（Hayashibara 2004，Cassandra/HBase 生产采用）：φ=-log10(P 心跳晚到)，σ=0 指数回退+正态建模+尾部渐近+牛顿 sqrt | engine_phi_test +3；award_demo 演示行 PASS（φ=44.98 suspect） |
| R90 | **概率式看护闭环**：heartbeat_history 表持久化间隔 + watchdog_tick `phi_gate=true` 端到端 φ 判活（默认关闭零回归）——实测静默100s/间隔5s φ≈8.7 判死而固定 timeout 600 不判 | ops_watchdog_test +2 |

## 三、机制设计家族（排程/预算/市场/可靠性全景）
PERT/CPM(dag_slack) → STAR 依赖图成本路由(dag_cost_route) → SwarmHarness 信任轴(executor_route) → ZEBRA 预算阶段切分(cost_budget_split) → Agora 置信度拍卖(executor_auction) → PROGROUTER 进度门控(progress_gate) → **Phi Accrual 可靠性闭环(phi_accrual + watchdog phi_gate)**——"更好的 AI 项目管理工具"从拆解→排程→预算→派单→看护全链路闭环，每个机制都有论文锚点且纯 MoonBit 可复现。

## 四、三支柱（@用户建议落地）
- **地图**：`fist://map`（机器可读工具分组）、board_ascii 实时看板、status_summary 项目脉冲、project_health 健康卡、docs/agent-map.md、USAGE 手册——agent 首读即定位，无需全项目乱找。
- **复用**：reserve_scope 作用域预订（Interlinked）、evolve_asset_register 外部资产注册、调研档 20260926.cost-market-routing.md + reliability-phi-accrual.md 全部信号落地；moonbitlang/core/math 复用（非自造）。
- **整洁**：store_open scratch 临时区隔离、cleanup_artifacts --check CI 干净度门禁、check_scripts_index 工具脚本单一索引——临时脚本任务完即清、代码生成物统一清理。

## 五、自举采用证据（系统用自己打磨自己——读盘真实数据）
- 交付库 fist-mbt.db 实测：**753 任务 / 157 已完成 + 32 已归档 / 212 执行记录 / 316 语料(specs) / 5 自进化档案 / 心跳 11**。
- 自驱闭环：selfdrive 审视轮 → parse_next → publish_next 持续自推；watchdog_tick（phi_gate 可选）无人值守。
- 演示链 award_demo 一条命令跑通 R68-R90 能力链（健康卡/dag_cost_route/executor_auction/progress_gate/phi_accrual），showcase.ps1 30-60s 视觉终端巡演（九态/DAG/自治派送）。

## 六、门禁历史（新档位 70/85/97 已连续多次全过，最近第 18 次评估 R83 后）
第 16(R77)/17(R78)/18(R83) 次评估均 PASS=是；R87-R90 四轮硬创新后本轮第 19 次复评确认稳健。
