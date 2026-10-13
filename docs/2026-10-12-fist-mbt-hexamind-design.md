---
AIGC:
    Label: "1"
    ContentProducer: 001191440300708461136T1XGW3
    ProduceID: 9f2a11add43fbf12a546606fb2b962ab_881167dfc60c11f197b3525400248c00
    ReservedCode1: T4TPrcMMIGc5h9YOErVTQbTBeTrnmV70IPDQWbtZxe+nMxqIHug9PRyvBvFf/FCzHUbipm/+plgqVa1jg3++dce1M1fn+ZEENmeJHx+zSjWDaTpkyVIULFwX3tnv7fOuL9UKQ3aNx+8LIY5yTC3of6cSO8TFfy84t4KBOg+0/Y4zQD9ht3To+UQSx28=
    ContentPropagator: 001191440300708461136T1XGW3
    PropagateID: 9f2a11add43fbf12a546606fb2b962ab_881167dfc60c11f197b3525400248c00
    ReservedCode2: T4TPrcMMIGc5h9YOErVTQbTBeTrnmV70IPDQWbtZxe+nMxqIHug9PRyvBvFf/FCzHUbipm/+plgqVa1jg3++dce1M1fn+ZEENmeJHx+zSjWDaTpkyVIULFwX3tnv7fOuL9UKQ3aNx+8LIY5yTC3of6cSO8TFfy84t4KBOg+0/Y4zQD9ht3To+UQSx28=
---

# fist-mbt HexaMind 六元自驱决策设计

- 日期：2026-10-12
- 状态：设计稿 v0.1
- 定位：在 fist-mbt 现有模型路由之上，新增一层"多视角自驱编排"能力

---

## 1. 背景与动机

用户希望把"六顶思维帽"与"多模型"延伸做组合：同一个任务，并发发给不同思维帽 Agent（不同模型、不同思维模式），对比结果差异、合并差异、集中优化。典型场景：红帽（直觉）说方案好、绿帽（创造）也说好，但理由不同、甚至结论冲突——把这种分歧显性化，作为下一轮优化的输入。

本设计将传统 de Bono 六顶思维帽升级为**自驱决策体系**，并命名为 **HexaMind（六元决策）**。

## 2. 与传统六顶思维帽的本质差异

| 维度 | 传统六顶思维帽 | HexaMind 六元自驱决策 |
|---|---|---|
| 主体 | 一个人依次换帽子 | 六个独立 Agent 并行工作 |
| 驱动 | 主持人引导、人工切换 | 星核（蓝帽）自驱派发，config 驱动策略 |
| 执行方式 | 串行、同一思维主体 | 并行、每顶帽独立模型/上下文/参数 |
| 分歧处理 | 靠讨论弥合，不可追踪 | 分歧显性化为结构化清单，驱动下一轮 |
| 收敛机制 | 主持人拍板 | 分歧回灌 + 迭代收敛判定（轮次/差异阈值） |
| 模型利用 | 无 | 帽子 × 模型组合，风格差异放大视角差异 |
| 产出形式 | 讨论纪要 | 每帽结构化报告 + 分歧清单 + 裁决报告，全程可审计 |
| 可追溯性 | 弱 | 强：每帽产出、分歧演化、收敛过程全部存档 |

一句话概括：传统六顶帽是"思考方法"，HexaMind 是"决策引擎"——**帽子即 Agent，分歧即燃料，收敛即产出**。

## 3. 六元角色定义

每顶帽子 = 一个可配置的 Hat 对象：`{id, role_prompt, model_id, temperature, max_tokens, output_schema}`。

| 代号 | 中文名 | 对应传统帽 | 职能 | 模型策略 | 采样参数 | 输出契约 |
|---|---|---|---|---|---|---|
| stargazer | 观星者 | 白帽 | 事实观测、中立数据采集、现状陈述 | 知识/检索强模型（可配工具） | temp 低 (0.2) | `{facts[], sources[]}` |
| pulse | 脉冲 | 红帽 | 直觉反应、第一信号、情绪预感，不要求证明 | 快速便宜模型（OFM 免费池） | temp 高 (1.0)，短输出 | `{gut_signal, intensity, keywords[]}` |
| wallbreaker | 破壁者 | 黑帽 | 击穿漏洞、风险边界、"为什么不行" | 强推理模型（付费池） | temp 低 (0.3)，严格格式 | `{risks[], fatal_flaws[], severity}` |
| golddigger | 掘金者 | 黄帽 | 挖掘价值、优点、可行性、收益 | 平衡模型 | temp 中 (0.6) | `{values[], feasibility, worth}` |
| nova | 新星 | 绿帽 | 替代方案、突破可能、不设限发散 | 创造性模型 | temp 高 (1.1) | `{alternatives[], novel_ideas[], leap}` |
| nucleus | 星核 | 蓝帽 | 派发策略、分歧提取、收敛裁决、最终报告 | 最强总结/规划模型 | temp 低 (0.2) | `{verdict, divergence[], consensus, report}` |

命名含义：延续 fist-mbt 已有的 star_gate（星门）星际命名体系；每个名字体现自驱身份——观星者观测、脉冲发射信号、破壁者击穿、掘金者挖掘、新星爆发、星核统御。

## 4. 自驱决策闭环

```
用户任务
  │
  ▼
[星核 nucleus] 解析任务 → 按 config 策略决定派发哪几顶帽（按需选帽 2-6 顶）
  │
  ▼
[并行派发] stargazer / pulse / wallbreaker / golddigger / nova 同时执行
  │
  ▼
[收集] 每帽产出结构化报告（结论 + 论据 + 置信度）
  │
  ▼
[分歧提取] 程序化对比：结论冲突检测 + 论据路径差异 + 置信度对比
  │               → 输出「分歧清单 divergence[]」
  │
  ▼
[分歧回灌] 分歧清单作为新输入，回灌给相关帽子（或触发辩论模式）
  │
  ▼
[收敛判定] 差异阈值 / 轮次上限 / 星核裁决
  │
  ▼
[产出] 最终裁决报告 + 各帽原始报告 + 分歧演化记录（可追溯存档）
```

### 4.1 分歧提取（第一版规则化，后续可接 LLM）

- **结论冲突检测**：各帽 verdict 做语义相似度对比（第一版可用关键词/标签匹配，后续接 embedding）
- **论据路径差异**：同结论但 reasons[] 重叠度低 → "殊途同归"，记录为潜在分歧点
- **置信度对比**：同结论不同置信度 → 标记待回灌

### 4.2 收敛判定

- 差异阈值：分歧清单为空或全部标记"已回应" → 收敛
- 轮次上限：默认 2 轮（可配置），防成本爆炸
- 星核裁决：达到上限仍分歧 → 星核输出"分歧未收敛 + 各自立场 + 建议决策"

### 4.3 辩论模式（分歧最大时触发）

wallbreaker vs golddigger、pulse vs nova 两两对冲：各自回应对方论点，多轮迭代，由星核主持。

## 5. 架构设计（贴合 fist-mbt 现状）

### 5.1 模块划分

```
src/hat/
├── hat_config.mbt      # Hat 定义、config_json 解析、帽子模板
├── hat_router.mbt      # 帽子调度：选帽策略、参数覆写、并行发起
├── hat_run.mbt         # 单轮执行：派发 → 收集 → 结构化产出
├── hat_merge.mbt       # 分歧提取、差异计算、合并报告
├── hat_debate.mbt      # 辩论迭代、回合管理
└── hat_report.mbt      # 最终报告生成、存档结构
```

### 5.2 复用现有能力（零重复实现）

- 模型调用：继续走 `free_pool` / `paid_pool` + `executor_run` 接线口
- Star 门、5h 滚动窗口、lane 计数、model_auth_status 全部沿用
- 每顶帽只是"角色 Prompt + 模型偏好 + 采样参数"的配置组合，不新增模型层

### 5.3 MCP 工具暴露

| 工具 | 说明 |
|---|---|
| `hat_run` | 跑一组帽子（指定帽子集合/任务），返回各帽结构化产出 |
| `hat_merge` | 对已有产出做分歧提取 + 合并报告 |
| `hat_debate` | 对指定帽子启动辩论迭代 |

### 5.4 config 示例（config_json）

```json
{
  "hats": {
    "stargazer":  { "model": "paid:deepseek-r1", "temperature": 0.2, "enabled": true },
    "pulse":      { "model": "ofm:fast-free",     "temperature": 1.0, "enabled": true },
    "wallbreaker":{"model": "paid:qwen-max",      "temperature": 0.3, "enabled": true },
    "golddigger": { "model": "paid:deepseek-v3",  "temperature": 0.6, "enabled": true },
    "nova":       { "model": "ofm:creative",      "temperature": 1.1, "enabled": true },
    "nucleus":    { "model": "paid:deepseek-r1",  "temperature": 0.2, "enabled": true }
  },
  "hat_policy": {
    "max_rounds": 2,
    "converge_threshold": 0.3,
    "auto_select_hats": true,
    "debate_enabled": true
  }
}
```

## 6. 组合模式

1. **并行采集**（核心）：同一任务并发派发 N 帽，多视角素材一次收齐
2. **帽内投票**：同一顶帽绑多模型（如 wallbreaker 同时 3 个模型挑刺），同视角下筛离群
3. **辩论对冲**：黑 vs 黄、红 vs 绿两两对打，多轮回应，收敛分歧

## 7. MVP 落地路径

| 阶段 | 内容 | 验收 |
|---|---|---|
| P0 单轮并行 | 静态 6 帽定义 + hat_run 并行执行 + 星核总结 | 同一任务跑通 6 帽并行，产出多视角报告 |
| P1 分歧显性化 | hat_merge：结论冲突检测 + 分歧清单 | "红绿都叫好但理由不同"变成结构化 divergence[] |
| P2 迭代闭环 | 分歧回灌 + 收敛判定 + 辩论模式 | 完整跑通"并行 → 分歧 → 回灌 → 裁决"闭环 |

## 8. 成本与取舍

- 成本放大是必然的（N 帽 × M 模型）→ 按需选帽：简单任务 2 顶（stargazer + wallbreaker），决策类 4-6 顶
- OFM 免费池养探索型帽子（pulse / nova，高 temperature 可重试），付费池留给裁决（nucleus）和批判（wallbreaker）
- 轮次上限默认 2，防止迭代成本失控

## 9. 与 OFM / 现有 router 融合

- OFM 继续作为外部 HTTP 渠道（127.0.0.1:18899），hat 层不感知渠道细节
- hat_config 里 `model: "ofm:xxx"` 前缀经现有 lane 机制路由到 OFM
- 全部决策逻辑在 hat 层，router 层零改动，符合 improvement-plan-20261010.md 的"fist-mbt=路由器、OFM=渠道"定位

---

## 附：与传统六顶帽的对照速查

| 传统帽 | HexaMind 代号 | 一句话 |
|---|---|---|
| 白帽 | stargazer 观星者 | 只陈述事实，不表态 |
| 红帽 | pulse 脉冲 | 直觉第一信号，不解释 |
| 黑帽 | wallbreaker 破壁者 | 专职击穿，风险优先 |
| 黄帽 | golddigger 掘金者 | 专职挖掘，价值优先 |
| 绿帽 | nova 新星 | 专职爆炸性创意 |
| 蓝帽 | nucleus 星核 | 全场唯一指挥者 |
*（内容由AI生成，仅供参考）*
