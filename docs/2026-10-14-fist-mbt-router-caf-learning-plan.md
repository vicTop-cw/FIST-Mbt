---
AIGC:
    Label: "1"
    ContentProducer: 001191440300708461136T1XGW3
    ProduceID: 9f2a11add43fbf12a546606fb2b962ab_d728abf0c7c311f1944f525400248c00
    ReservedCode1: oiUJIxhr4hdJbjPw2b5HJ951Ss9ByNMPmyIDIgEiiijz6JvjUX4qR5aCutVfDatZFW62/le50sNPYbE1k2Q385euAGOFM7VqQyi5uHM2XyPMcO2OMRpTTHX4eox6x4sndbax0i0uJ4V0R6+m9emAmhi9SJGlcR5HwHabjd/xgyaKr85B+NJf9azDc/o=
    ContentPropagator: 001191440300708461136T1XGW3
    PropagateID: 9f2a11add43fbf12a546606fb2b962ab_d728abf0c7c311f1944f525400248c00
    ReservedCode2: oiUJIxhr4hdJbjPw2b5HJ951Ss9ByNMPmyIDIgEiiijz6JvjUX4qR5aCutVfDatZFW62/le50sNPYbE1k2Q385euAGOFM7VqQyi5uHM2XyPMcO2OMRpTTHX4eox6x4sndbax0i0uJ4V0R6+m9emAmhi9SJGlcR5HwHabjd/xgyaKr85B+NJf9azDc/o=
---



# 2026-10-14 FIST-Mbt 路由学习计划：ACRouter C-A-F 轻量移植（执行反馈记忆）

> 状态：**P1 + P2a + P2b 完成，P2c §2.1 配置项 + §2.2 pick_caf 软性重排钩子 + 验收标准 3 dry_run 纯计算 + P2d 冷启动偏好统一 已完成**（2026-10-15 Round 8-10 更新：加 `CAF_EDIT_MAX_LEN=256` 长度守卫 + 属性测试 131 全绿 + 性能基准验证 + 接线设计文档落盘；**Round 27 更新**：`ModelRouter::pick_caf` 软性重排钩子在 `src/router/model_router_caf.mbt` 实施并提交 `4b3b168`，4 条回归锁 152/152 全绿；调试中发现 `iso_to_secs` 对 Y2038 后日期溢出返回 -1 的 BUG-218 同类陷阱，测试冷却截止须在 Y2038 内；唯一遗留项 P2c §2.3 回写+status wiring 因 `src/server/model_router_ops.mbt` 被并发 agent WIP 阻塞，设计文档见 `docs/2026-10-15-fist-mbt-caf-p2c-wiring-design.md`；**Round 28-31 更新**：BUG-206（Y2038 冷却失效）修复 `ed40ada`、验收标准 3 dry_run 纯计算 `54f172c`、caf_loop_1 回写通路真源 `132fcca`、P2c+P2d 统一（`caf_reorder_combined` + `caf_default_preference`/`caf_min_evidences` 透传）`2a669ef`，router 160/160 全绿；server 层 §2.3 接线仍等 `model_router_ops.mbt` 释放；**Round 32 更新**：status 展示纯计算部分 `caf_memory_status_text` 落地 `1bbcf9d`（2 条 caf_status 锁，router 162/162，全仓 1161/1161 回归恢复）；尝试给 `RouterConfig` 加 `caf_default_preference`/`caf_min_evidences` 时发现构造点侵入面过大已回退；**Round 33 更新**：`RouterConfig` 两字段**已落地** `c54fe68`（struct + default `[]`/10 + from_json/to_json + clone_pools + router_state merge 全透传，regex 一次性 20/20 补齐全仓 20 处构造点，`cfg_ofm_2` 键集合锁 7→9，新增 `caf_cfg_1`/`caf_cfg_2` 两锁，router 164/164 全绿）——**更正 Round 32 的 36 处为误判**（真实 `use_caf_memory:` 构造点 24 处，其中 20 处 wbtest 需补，regex 全命中）；§2.3 接线的 router 侧前提现已齐备，仅剩 `model_router_ops.mbt`（并发 agent WIP）待释放后收口）
> **P2d 追加（Round 22-23）**：冷启动启发式 `caf_soft_reorder_with_preference` 已在 `src/router/router_caf_ext.mbt` 实施（7 测试 145/145，全仓 1124 零回归），接线待 P2c 释放后统一接入。设计见 `docs/2026-10-15-fist-mbt-caf-p2d-cold-start-design.md`
> 真源：`src/router/`（决策与状态 schema）+ `src/server/model_router_ops.mbt`（记账与进程生命周期）+ `src/executor/`（成功/失败信号）
> 依据：基于 v0.3.8→v0.4.x 增量源码核查 + ACRouter（Agent-as-a-Router，arXiv:2606.22902）C-A-F 学习路由思想

## 背景与动机

当前 model-router 的路由是**调用前确定性决策**：按 5h 滚动窗口 + 95% 阈值预判，free 耗尽切 paid，双空显式失败；fallback_chain 按性价比排序在失败后顺延；冷却/自动摘除（`FIST_MODEL_FAIL_THRESHOLD` / `FIST_MODEL_COOLDOWN_SECS`）处理 unhealthy 模型；`cost_performance()` + `sort_by_cost_performance()` 做同档位性价比选型。路由为纯函数确定性逻辑，完全不使用 LLM。

**缺口**：以上决策全部发生在**调用之前**，执行之后的成败与成本经验没有被沉淀复用——同一特征（同语言、同难度、同动作类型）的任务每次都是从零决策，不记得历史上哪个模型对这类任务成功率更高、更省成本。

**ACRouter 思想（arXiv:2606.22902，Agent-as-a-Router）**：路由器不只做一次性选路，而是围绕 **C-A-F** 三要素形成学习闭环——**Context**（任务上下文特征）→ **Action**（选择模型/动作）→ **Feedback**（执行成败与成本回灌），让路由策略随反馈持续改进：相似任务优先选历史成功率高的模型。

**移植边界（明确不做什么）**：
- 只移植**思想**（C-A-F 闭环 + 经验记忆），不搬 ACRouter 的 Python 代码
- **不引入 0.8B 模型权重**：ACRouter 原文用轻量模型做路由预测，本计划完全不做模型化，只用进程内统计记忆 + 轻量近似检索
- 不改变现有确定性路由的硬约束语义，经验记忆只做**软性提示**

**目标**：让路由从"调用前确定性决策"升级为"执行后经验沉淀"，相似任务优先选历史成功率高的模型，且默认关闭时零回归。

## 总体设计：轻量 C-A-F 闭环

```
 Context(任务特征) ──▶ Action(pick 选型) ──▶ executor 执行
      ▲                                        │
      │                                        ▼
 相似检索(kNN 近似) ◀── 反馈记忆表 ◀── Feedback(成败+成本回写)
 (Top-K 成功率统计)       (FIFO ≤10000 条)
```

三个模块：

### (a) 反馈记忆层（Feedback Memory）

- 每次 executor 跑完，将一条经验记录写入**进程内记忆表**：`（任务特征、所选模型、成败、成本）`
- 记录上限 **10000 条 FIFO**（超出淘汰最旧），防止无界增长；进程重启即清空，不做持久化（轻量第一）
- 与现有 `model_router_status` 记账**衔接**：复用 executor 已生成的成功/失败信号与配额记账，**不新增埋点面**，只在记账落库处加一条旁路写入记忆表

### (b) 相似检索（Similarity Retrieval）

- 基于任务特征做**轻量 kNN 近似检索**：特征维度=语言 / 难度 / 包范围 / 动作类型
- **无需向量库**：用特征哈希（如 64-bit 分桶）+ 编辑距离近似计算相似度
- 取 Top-K 历史记录统计该特征邻域的成功率（成功数/总数）与平均成本，作为决策依据

### (c) 决策融合（Decision Fusion）

- 检索结果作为**软性提示**注入现有 `pick` 决策：在配额硬约束内，若某模型在相似历史中成功率显著占优，则提升其排序优先级
- **不破配额硬约束**：候选集与配额判定仍走确定性逻辑，经验只在候选集内做排序微调
- 复用已实现的 `laya_prefer_tier` 钩子思路（软性微调而非推翻，超时/无数据回退纯函数决策）
- **默认关闭**：`router.use_caf_memory=false`，关闭时行为与 v0.3.8 完全一致（零回归基线）

**原则：确定性逻辑为主、经验记忆为辅。**

## 涉及模块

| 模块 | 改动 | 说明 |
|---|---|---|
| `src/router/` | 记忆表 schema + 相似检索 + 决策融合 | 新增 `CafRecord`（特征哈希/模型/成败/成本/ts）、`CafMemory`（FIFO 环形表）、`knn_search()`、pick 内软性排序钩子 |
| `src/server/model_router_ops.mbt` | 执行结果回写记账 | 在 executor 成功/失败信号处旁路写入记忆表，衔接现有配额记账 |
| `model_router_status` | 展示新增记忆统计 | 记忆表条数、Top 成功率模型、最近 K 条样本摘要 |
| 配置项 | `router.use_caf_memory` | 默认 `false`；开启需显式配置 |

## 验收标准

1. **离线回放可复现**：用历史执行记录离线回放构建记忆表，能复现"按成功率排序的模型优先级"（与人工标注一致）
2. **开启后不增成本且成功率不降**：A/B 对比（开/关）在相同任务集上，成本 ≤ 基线且成功率 ≥ 基线；若有偏差须记录偏差待修（不掩盖）
3. **dry_run 可预览**：`dry_run=true` 时返回建议模型 + 历史依据（Top-K 样本的成功率/平均成本），便于审计与人工校验
4. **零回归基线**：`router.use_caf_memory=false` 时行为与 v0.3.8 完全一致（纯函数确定性路由，无记忆读写）

## 排期与优先级

| 阶段 | 内容 | 优先级 | 依赖 | 状态 |
|---|---|---|---|---|
| P1 | 反馈记账与记忆表（复用现有 executor 成功/失败信号 + 配额记账旁路） | P1 | 无（仅接线+schema） | ✅ 已实现（2026-10-15，含 BUG-188/173/174 修复） |
| P2 | 相似检索与决策融合（kNN 近似检索 + pick 软性排序 + status 展示 + 配置项） | P2 | P1（记忆表就绪） | 🔄 进行中（P2a 相似检索 + P2b 决策融合核心已实现，P2c 接线待办） |

- 两阶段**独立可合入**：P1 合入即开始沉淀经验（暂不影响决策），P2 合入才开启学习路由；均不触碰确定性路由基线
- 与既有增强计划（自动切换/laya 判断/性价比选型）并行，不冲突；决策融合钩子与 laya 钩子共用同一"软性微调"通道

## 当前代码基线状态（HEAD）

**已有（复用面）**：
- `PickDecision` 含 `fallback_chain: Array[String]` 备用链；`compute_fallback_chain()` 按同 tier→另一 tier、性价比排序
- `ModelQuota` 含 `price_per_call` / `price_per_1k` / `rank` + `cost_performance()` / `sort_by_cost_performance()`
- executor 已产出成功/失败信号（重试、冷却、自动摘除）；`filter_unhealthy_models` + `is_model_unhealthy` 黑名单过滤
- `should_retry_on_invalid_json` + `append_retry_prompt` 二次重试

**待办（本计划新增面）**：
- `CafRecord` / `CafMemory` schema 与 FIFO 环形表（`src/router/`）
- executor 记账处旁路回写（`src/server/model_router_ops.mbt`）
- 特征哈希 + 编辑距离 kNN 检索
- pick 内软性排序钩子（复用 laya_prefer_tier 通道，超时/无数据回退）
- `model_router_status` 记忆统计展示
- `router.use_caf_memory` 配置项（默认 false）
*（内容由AI生成，仅供参考）*
*（内容由AI生成，仅供参考）*
