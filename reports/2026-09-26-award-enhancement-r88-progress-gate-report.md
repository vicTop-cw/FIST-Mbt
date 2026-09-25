# R88 汇报：进度预算路由门控 progress_gate（PROGROUTER arXiv 2608.25992 蒸馏落地）

> 日期 2026-09-26 · FIST 指挥官终审通过 · 结果摘要 / 资源消耗 / 分配记录 / 遗留 / 建议 / 超额 / 来源 全齐

## 一、结果摘要
- **目标**：接续 R87 的"调研蒸馏转落地"节奏，兑现调研档 20260926.cost-market-routing.md 最后一块可落地信号「PROGROUTER 在线进度引导路由」——预算×进度双路径预测 + 元门控决策，正中 @用户"计划性增强"建议。
- **达成**：新增 `progress_gate` 工具（89→**90**）：engine 纯计算——`subtree_ids`（复用 children_of BFS）收集子树；progress=已完成+已归档/子树任务数；spent=子树非待领取任务难度权重 易/中/难→1/2/3（复用 extract_difficulty 单一来源），`spent_override>0` 可手动注入；双路径预测 线性=燃尽率×剩余工作量、保守=1.2×线性；元门控 OK(继续)/CAUTION(降档缩范围)/ESCALATE(追加预算或暂停)。server 复用 jnum 零新依赖。
- **验收**：`dag_ext_test.mbt` **+4**（OK 自动估算 / CAUTION / ESCALATE+双路径数字 / 未开工+全完成+空任务+非法预算）；全量 **252→256/256**（+4）；mcp_smoke 90 工具；award_demo ⑧ 段加 R88 演示行（实测 verdict=ESCALATE：progress=0.1/spent=8 超支检出）**PASS**；守卫族 tools/test/badge/index/map 全 PASS；cleanup CLEAN。

## 二、资源消耗
- 全量 `moon test --target js -j 1`（256/256）+ mcp_smoke（build 后 90 工具）+ award_demo（R88 段）+ 守卫族 + cleanup。
- 变更：engine_dag_ext.mbt(+progress_gate/subtree_ids ~110 行) / dag_ext_test.mbt(+4) / server.mbt(工具注册+map 组更新) / README/AGENTS(运维·成本组 10→11)/deliverable(R58)/USAGE(§6.8)/agent-map/scoring_rubric/mcp_smoke expected 90/BACKLOG 锚点/申报书(§6 补 49 行)/memory 调研档（PROGROUTER ✅）/award_demo(R88 行)。

## 三、任务分配记录
- R88 属轻量单函数硬能力 + 4 测试 + 文档同步，指挥官亲自做，未开子任务。

## 四、遗留风险
- 燃尽率线性外推为简化模型（假设单位进度成本恒定），非 PROGROUTER 原版多视角进度评分器 + 双路径神经预测；已如实标注"蒸馏简化版"，复杂进度曲线可后续加深。
- spent 缺省为难度权重代理（非真实 token/成本）；真实成本注入走 `spent` 手动参数（与 cost_stats 口径衔接为后续项）。

## 五、后续建议
- 调研档 20260926 五信号（STAR/CASTER/ZEBRA/Agora/PROGROUTER/SwarmHarness）已全部落地完毕——机制设计家族叙事完整（PERT/CPM→STAR 成本路由→SwarmHarness 信任轴→ZEBRA 预算切分→Agora 置信度拍卖→PROGROUTER 进度门控）。下一候选：新调研线程（如 Phi Accrual 概率式故障检测，BACKLOG P3，升级 watchdog 固定 timeout）或英文 README（P3，国际受众）、门禁 cron 化（需定时场景）。

## 六、超额内容
- 无超额；改动严格限定进度预算门控工具家族。

## 七、来源
- `src/engine/engine_dag_ext.mbt` `progress_gate`/`subtree_ids`（R88）
- `src/engine/dag_ext_test.mbt` R88 四用例
- `src/server/server.mbt` progress_gate 注册
- `memory/research/20260926.cost-market-routing.md` §一/§二（PROGROUTER arXiv 2608.25992 候选→✅ 已落地）
- `scripts/award_demo.py` ⑧ 段 R88 行
