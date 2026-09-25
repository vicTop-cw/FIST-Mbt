# R87 汇报：置信度校准拍卖 executor_auction（Agora arXiv 2607.09600 蒸馏落地）

> 日期 2026-09-26 · FIST 指挥官终审通过 · 结果摘要 / 资源消耗 / 分配记录 / 遗留 / 建议 / 超额 / 来源 全齐

## 一、结果摘要
- **目标**：接续 R80/R81 的"调研蒸馏转落地"节奏，兑现 R83 留痕候选「Agora 置信度拍卖」——把执行者分派从"排序推荐"升级为"按出价竞拍"，防"胜者诅咒"。
- **达成**：新增 `executor_auction` 工具（88→**89**）：`ExecutorRegistry::auction_pick` 纯计算——能力覆盖>0 方可竞拍；出价=显式 `bid` 或默认按能力覆盖率；校准=1-|出价-历史验收通过率|（过度自信而兑现差的执行者被惩罚）；拍卖分=出价×校准×负载折扣 1/(1+负载)；返回 bids 全表（逐行带 overconfident 标记）+ winner + basis + note。server 复用 executor_loads/executor_trust/sync_db_executors 零新依赖，`json_bid_map` 解析可选出价表。
- **验收**：`registry_test.mbt` **+3**（能力门槛+默认出价 / 胜者诅咒防护：过度自信 0.9·0.3 败给言行一致 0.6·0.6 / 负载折扣+空 need 无竞拍者）；全量 **249→252/252**（+3）；mcp_smoke 89 工具；award_demo ⑧ 段加 R87 行（竞拍 1 家 winner=exec_demo calibration≈0.943）**PASS**；守卫族 tools/test/badge/index/map 全 PASS；cleanup CLEAN。

## 二、资源消耗
- 全量 `moon test --target js -j 1`（252/252）+ mcp_smoke（build 后 89 工具）+ award_demo（R87 段）+ 守卫族 + cleanup。
- 变更：executor/registry.mbt(+auction_pick ~94 行) / registry_test.mbt(+3) / server.mbt(工具注册+json_bid_map+map 组更新) / README/AGENTS/deliverable/ARCHITECTURE/USAGE(补 §6.14)/agent-map/scoring_rubric/mcp_smoke expected 89/BACKLOG 锚点/申报书(§6 补 48 行)/memory 调研档（Agora ✅）/award_demo(R87 行)；顺带全量 `moon fmt` 的 `var`→`let mut` 弃用现代化（工具链新版）。

## 三、任务分配记录
- R87 属轻量单函数硬能力 + 3 测试 + 文档同步，指挥官亲自做，未开子任务。

## 四、遗留风险
- 校准系数为线性简化（1-|出价-兑现率|），非 Agora 原文的完整校准拍卖协议（如 IC/DSIC 保证）；已如实标注"蒸馏"口径。
- `bid` 为调用方一次性传入，未持久化执行者"常驻出价"——如需长期市场叙事可后续把 bid 并入 executor_register（schema 演进）。

## 五、后续建议
- 概率兜底连续多轮 PASS（R83 起第 18 次评估后未再复评）；候选：PROGROUTER 进度预算路由（调研档最后一块可落地信号，接 cost_budget_split + selfdrive_dispatch）、门禁 cron 化（需定时场景）、或英文 README（BACKLOG P3，国际受众）。

## 六、超额内容
- 顺带修复 `fist://map` server 计数陈旧点（87→89）与 USAGE 工具手册计数（87→89）——属"文档即实现"收尾，无功能超额。

## 七、来源
- `src/executor/registry.mbt` `auction_pick`（R87）
- `src/executor/registry_test.mbt` R87 三用例
- `src/server/server.mbt` executor_auction 注册 + json_bid_map
- `memory/research/20260926.cost-market-routing.md` §一/§二（Agora arXiv 2607.09600 候选→✅ 已落地）
- `scripts/award_demo.py` ⑧ 段 R87 行
