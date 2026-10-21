---
AIGC:
    Label: "1"
    ContentProducer: 001191440300708461136T1XGW3
    ProduceID: 9f2a11add43fbf12a546606fb2b962ab_90dcb9dfc77f11f1944f525400248c00
    ReservedCode1: sEGxwspJ3SSOHfaxFp2pK5uzA1e41nFyJic2ljrS3xNXz/Qo4chJXSZ3dAMixtoVnTRP4YRu844y/GtYSzuTvkRfdg/W9pCadW5a1e2UljDp0CIxweUyFhAyarF8kZYTTBiYnTbQK/e8M1nb7hD+3dzqAy7uOX6yOxjkRSnGBGyScs88JKbcS5KgV3I=
    ContentPropagator: 001191440300708461136T1XGW3
    PropagateID: 9f2a11add43fbf12a546606fb2b962ab_90dcb9dfc77f11f1944f525400248c00
    ReservedCode2: sEGxwspJ3SSOHfaxFp2pK5uzA1e41nFyJic2ljrS3xNXz/Qo4chJXSZ3dAMixtoVnTRP4YRu844y/GtYSzuTvkRfdg/W9pCadW5a1e2UljDp0CIxweUyFhAyarF8kZYTTBiYnTbQK/e8M1nb7hD+3dzqAy7uOX6yOxjkRSnGBGyScs88JKbcS5KgV3I=
---

# 2026-10-14 FIST-Mbt 路由增强计划：备用切换 / laya 判断 / 性价比选型

> 状态：**P1 两项已实现（P1.1 自动切换备用模型 + P1.3 性价比选型），P2 已实现（laya 判断路由），2026-10-14 更新**
> 真源：`src/router/`（决策与状态 schema）+ `src/executor/` + `src/server/model_router_ops.mbt`
> 依据：基于 v0.3.8→v0.4.x 增量源码核查

## 背景

当前 model-router 的路由是**调用前确定性决策**：按 5h 滚动窗口 + 95% 阈值预判，free 耗尽切 paid，双空显式失败；429 只归因（RATE_LIMIT）无重试循环；unhealthy 模型仅能靠环境变量 `FIST_OFM_UNHEALTHY_MODELS` 手动指定；路由为纯函数确定性逻辑，完全不使用 LLM。

### 2026-10-14 更新：三个增强方向状态变迁

| 增强项 | 原状态 | 当前状态 | 说明 |
|---|---|---|---|
| ③ 性价比选型 | 计划 | ✅ **已实现** | `ModelQuota` 已有 `price_per_call`/`price_per_1k`/`rank` 字段 + `cost_performance()` + `sort_by_cost_performance()` + `compute_fallback_chain()`按性价比排序；旧状态文件回落兼容 |
| ① 自动切换备用模型 | 计划 | ✅ **已实现** | `fallback_chain` 已加进 `PickDecision`、`compute_fallback_chain()` 已实现并按性价比排序；`executor_run_impl` 已接入重试循环（`FIST_MODEL_MAX_RETRIES` 默认 1）+ 冷却/自动摘除（`FIST_MODEL_FAIL_THRESHOLD` 默认 3，`FIST_MODEL_COOLDOWN_SECS` 默认 60），响应带 `retry_count`/`fallback_chain`/`retried_models` |
| ② laya 判断路由 | 计划 | ✅ **已实现** | `RouterConfig.use_laya` 开关（默认 false）+ `RouteDecision.laya_reason` 标注 + `pick(laya_prefer_tier~)` 软性档位提示 + `mr_laya_tier_hint()` async 探测 + server 层接线；零回归（1048/1048） |

## 增强项 1：失败后自动切换备用模型

**目标**：路由从"调用前一次性决策"升级为"调用后失败可重试切换"，覆盖 429 / 5xx / 连接超时等运行时失败。

设计要点：
- 决策返回增加 `fallback_chain`：按配额可用性与失败类型给出有序备用模型列表
- `executor_run` 增加重试语义：外部执行器非零退出 / 超时 / 429 时，按 fallback_chain 顺延下一候选，重试上限可配置（默认 1 次）
- 429 处理升级：从"仅归因 RATE_LIMIT"升级为"触发冷却 + 切换备用池"，冷却窗口可配置
- unhealthy 模型处理升级：从"仅环境变量手动指定"升级为"自动摘除（连续失败 N 次进入冷却） + 可配置的自动恢复"
- 账本一致性：重试消耗的配额必须逐次记账，避免同一任务重复扣费；切换后旧模型的 used 不回滚

涉及模块：`src/router/`（fallback 决策）、`src/executor/`（重试编排）、`src/server/model_router_ops.mbt`（记账与进程生命周期）

验收标准：
- 模拟 429 场景，任务自动切换备用模型并完成，账本记录两次调用
- 连续失败自动摘除，达到冷却窗口后自动恢复
- `fallback_chain` 在 `dry_run=true` 时可预览

## 增强项 2：laya 判断路由（LLM 辅助决策）

**目标**：在确定性路由之上引入 laya 做**增强判断**，覆盖确定性逻辑无法表达的软性因素（任务复杂度、上下文长度、供应商实时健康度等）。

设计要点：
- 保持**确定性逻辑为主、laya 为辅**：纯函数先出候选集，laya 仅在候选集内做软性排序/微调，不推翻配额硬约束
- laya 参与点候选：任务拆解档位（split_n）之外，增加"模型档位建议"（简单/中等/复杂任务映射到不同 tier）
- 默认仍关闭（对齐现状），开启需显式配置 `router.use_laya=true`
- laya 判断超时兜底：LLM 无响应或超时时回退纯函数决策，不阻塞调用
- 可观测性：laya 参与过的决策在返回中标注 `reason=laya:<档位>`，便于审计与 A/B 对比

涉及模块：`src/router/`（候选集 + laya 钩子）、laya 接口层（超时与降级）

验收标准：
- 关闭时行为与 v0.3.8 完全一致（回归基线）
- 开启后复杂任务倾向更高档位，但配额耗尽时仍受硬约束
- laya 超时 3s 内回退，不产生额外失败路径

## 增强项 3：性价比选型

**目标**：ModelQuota 引入价格/成本/排序维度，路由支持"同档位内按性价比选最优"。

设计要点：
- ModelQuota 扩展字段：`price_per_call`、`price_per_1k`（可选）、`rank`（质量排序，数值越大越强）
- 新增选型规则：同 tier 内优先满足配额约束，再按 `rank / price` 性价比降序选择；价格未知（沿用 `cost_estimate` 占位语义）时不参与比较，保持原顺序
- `cost_estimate` 从占位升级为真实估算：atomcode/aider 调用后按 token 用量回填，作为下次选型的输入
- 兼容性：旧状态文件无价格字段时逐项回落，不 panic（沿用 BUG-53 教训）

涉及模块：`src/router/`（schema 扩展 + 选型排序）、`src/server/model_router_ops.mbt`（token 用量回填）

验收标准：
- 同档位两个模型（贵快 vs 便宜慢）按性价比选出便宜者，配额约束不被突破
- 旧 schema 状态文件读入无 panic，warnings 明示价格字段缺失
- 回填的 token 用量参与后续选型，`model_router_status` 可见

## 排期与归属

| 增强项 | 优先级 | 状态 | 影响面 |
|---|---|---|---|
| 3 性价比选型 | P1 | ✅ 已实现（2026-10-14，commit 42478cd） | src/router schema + server ops |
| 1 自动切换备用模型 | P1 | ✅ 已实现（2026-10-14，commit 42478cd + 927c14b + 75757d5） | src/router + src/server ops |
| 2 laya 判断路由 | P2 | ✅ 已实现（2026-10-14，commit 1b5d36f） | src/router + src/server ops + laya 接口 |

三项均不影响 v0.3.8/v0.4.x 确定性路由基线，可独立合入。

## 当前代码基线状态（HEAD）

- `ModelQuota` 已含 `price_per_call` / `price_per_1k` / `rank` 字段 + `cost_performance()` 性价比评分
- `sort_by_cost_performance()` 同 tier 内按性价比降序排列
- `compute_fallback_chain()` 按同 tier→另一 tier、性价比排序
- `PickDecision` 含 `fallback_chain: Array[String]` 备用链
- `RouterConfig` 含 `use_laya: Bool`（默认 false）开关
- `RouteDecision` 含 `laya_reason: String`（默认 ""，laya 参与时 `laya:<tier>`）
- `RouterConfig::from_json` 支持 `free_pool` / `paid_pool` / `ofm_endpoint` / `use_laya`
- `should_retry_on_invalid_json` + `append_retry_prompt` 用于 OFM 回体不可解析时的二次重试
- `filter_unhealthy_models` + `is_model_unhealthy` 精确匹配黑名单过滤
- `ModelQuota` 已含 `cooldown_until`（ISO，""=无冷却）+ `mark_failure()` / `in_cooldown()` 方法
- `ModelRouter::mark_failure()` 遍历两池标记失败冷却（跨包可调用）
- `pool_pick` 跳过冷却中的模型（新增 `now~` 参数）
- `router_state` 全链透传 `cooldown_until`（from_json / merge_usage / reset_windows / to_state）
- server `mr_record_failure()`：读 env `FIST_MODEL_COOLDOWN_SECS`（默认 300 秒）后标记冷却
- `executor_run` CLI 通道重试循环：`fallback_chain` 逐个尝试、`retried` 数组回执、
  每个失败分支都记配额（进程真起来那记）并标记冷却
*（内容由AI生成，仅供参考）*
