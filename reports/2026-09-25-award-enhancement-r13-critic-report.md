# 获奖提升 · R13 汇报：Critic 防漂移门禁（SAGE 论文落地）

> 日期：2026-09-25｜目标 pillar：调研增强（拿来主义）＋ 计划性增强（自进化防退化）
> 方式：fist-mbt 自驱式获奖概率提升链路；本轮新增 1 个 MCP 工具 `evolve_critic`（75→76）。

## 结果摘要
- 新增 `evolve_critic` MCP 工具：把 SAGE 论文"Critic 过滤防课程漂移"落成**入库前纯计算评审门禁**，供 agent 在把 principle/lesson/资产写进 DGM 档案库前先过一遍 Critic：
  - **重复/漂移拦截**：与档案库最相似资产 Jaccard 重合 **≥ 0.70（`critic_dup_sim`）** → 判「疑似课程漂移/重复」，直接建议拒收；
  - **稳健性门禁**：综合分 `0.5·score + 0.5·novelty(新颖度)` 低于阈值 `threshold`（默认 0.85）→ 判「稳健性不足」，暂缓入库；
  - 只评审**不写库**，杜绝自进化积累趋同低质信号、检索注入被噪声淹没。
- 落点（纯 MoonBit，无新表/依赖）：
  - [critic.mbt](../src/evolve/critic.mbt)：`critic_review` + `critic_most_similar` + `critic_dup_sim`；
  - [server.mbt](../src/server/server.mbt)：注册 `evolve_critic`（复用 `sync_db_lessons` 先纳入 DB [lesson] 再判漂移）。
- **复用设计（避免重复造轮子）**：复用同包私有的 `tokens`/`jaccard`、`Archive::novelty`、`scoring.score_accept`/`score_rank`，未重造词法/评分。
- 验证：`moon test --target js` **213/213**（+4）；E2E `scripts/evolve_critic_verify.py` **PASS**（tools/list=76 + 放行 + 拒收 + 收紧阈值拒收 + 仓库根无临时库）。

## 资源消耗
- 改动：新增 `src/evolve/critic.mbt`、`src/evolve/critic_test.mbt`、`scripts/evolve_critic_verify.py`；修改 `src/server/server.mbt`（工具注册 + map 描述）+ 若干 `.mbti`。
- 测试：新增 4 条单测（空库放行 / 高重合拒收 / 全新放行 / 低稳健性拒收）。
- 文档：工具数 75→76、测试 209→213 全量同步（README/AGENTS/ARCHITECTURE/USAGE/deliverable/agent-map/scripts-README/mcp_smoke/申报书）；AGENTS 自我记忆表 (5)→(6)；deliverable/申报书补 R13 行；research/ecosystem-borrow 把 SAGE 标为 ✅。

## 任务分配记录
- 直接实现（指挥官终审制）：SAGE 论文信号前序已蒸馏进 research/ecosystem-borrow.md；本轮把"Critic 防漂移"落地为既有自进化体系的补强门禁。因涉及跨模块（evolve + server）小改，采用直接实现 + 终审，未走 FIST 任务循环。

## 遗留风险
- 相似度用词集 Jaccard，对"措辞不同但语义相同"的漂移不一定判重（可后续接语义嵌入，但保持"纯计算、不依赖 LLM 自评"仍是本方案的刻意取舍）。
- 阈值 0.70 / 0.85 为经验值，未做全库调参。
- Challenger（生成更难任务，SAGE 另一半）仍未实现。

## 后续建议
- 下一可借力点（按调研强度）：
  1. **难度校准**：把 `decide_difficulty` 接进 `gradient` 标签，让拆解难度更真实；
  2. **Challenger 生更难任务**（SAGE 另一半）：对已归档任务生成进阶变体，形成"由易到难"的训练/推进序列；
  3. **Dynamic/Marketplace 能力路由**（远期）。

## 超额内容
- 顺带把 `fist://map` 里过时的 server 描述工具数从 70 修正到 76，保证"文档即实现/资源即实现"。

## 来源
- 调研：`memory/research/ecosystem-borrow.md`（SAGE 论文信号蒸馏）。
- 代码：`src/evolve/critic.mbt`、`src/server/server.mbt`、`src/evolve/critic_test.mbt`、`scripts/evolve_critic_verify.py`。