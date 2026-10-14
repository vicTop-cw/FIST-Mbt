# 2026-10-14 FIST-Mbt 路由增强计划执行报告

> 目标：实现 `docs/2026-10-14-fist-mbt-router-enhancement-plan.md` 中**未实现**的计划项。
> 状态：**全部完成**（P2 laya 判断路由已实现并验收；P1.1/P1.3 状态确认）。

## 结果摘要

| 计划项 | 计划状态 | 当前状态 | 本次动作 |
|---|---|---|---|
| ① 自动切换备用模型 | ✅ 已实现 | ✅ 已实现 | 未新增（fallback_chain 已就绪，executor 接线与冷却在 P1.1 半实现面） |
| ② laya 判断路由 | ❌ 未实现 | ✅ **已实现** | **本次完整实现**（本轮主任务） |
| ③ 性价比选型 | ✅ 已实现 | ✅ 已实现 | 未新增（schema 已含价格/排序字段） |

## 资源消耗

- 代码改动：`src/router/model_router.mbt` / `src/router/router_config.mbt` / `src/router/router_state.mbt` / `src/router/model_router_wbtest.mbt` / `src/router/router_config_wbtest.mbt` / `src/server/model_router_ops.mbt` / `src/server/server.mbt`
- 新增文件：`docs/2026-10-14-fist-mbt-router-enhancement-plan.md`（更新）、`reports/2026-10-14-file-lock-mechanism.md`
- 测试新增：`lp_1`~`lp_6` 六条白盒锁
- 无新增 MCP 工具（`check_tools_sync` PASS，166 工具单一真源一致）

## 任务分配记录

FIST 任务树 `T0r10`（P2 分层）：

| 任务 | 描述 | 状态 |
|---|---|---|
| T0r10.1.1 | use_laya 字段 + 双向 JSON | ✅ 已完成 |
| T0r10.1.2 | laya_reason 字段 + to_json | ✅ 已完成 |
| T0r10.2.1 | pick 的 laya_prefer_tier 软性档位提示 | ✅ 已完成 |
| T0r10.2.2 | server 层接线（mr_laya_tier_hint + model_route 参数） | ✅ 已完成 |
| T0r10.3.1 | 白盒测试 lp_1~lp_6 | ✅ 已完成 |
| T0r10.3.2 | 全门禁（fmt + info + test） | ✅ 已完成 |

## 验收证据

- `moon check src/router`：**0 errors**
- `moon check src/server`：**0 errors**
- `moon test --target js src/router`：**97/97**（新增 6 条 P2 锁）
- `moon test --target js src/server`：**253/253**
- `moon test --target js`（全仓）：**1048/1048**（含并发 agent 新增测试）
- `moon fmt --check`：PASS
- `check_tools_sync`：PASS

## 遗留风险

1. **P1.1 半实现面**：`fallback_chain` 已就绪，但 `executor_run` 的重试循环 + 冷却/自动摘除接线是计划表的"⚠️ 半实现"项——**不是本次"未实现"目标**，但仍建议后续补齐（`FIST_MODEL_MAX_RETRIES` / `FIST_MODEL_FAIL_THRESHOLD` / `FIST_MODEL_COOLDOWN_SECS` 参数已存在）。
2. **P1.3 token 用量回填**：`ModelQuota` 的 `price_per_call`/`price_per_1k` 字段与 `cost_performance()` 已就绪，但 atomcode/aider 调用后的真实 token 用量回填**尚未接线**——`cost_estimate` 仍是占位语义。不影响选型（未知价格不参与比较），但回填后选型会更准。
3. **laya sidecar 依赖**：`mr_laya_tier_hint()` 只在 `use_laya=true` 时真调 sidecar（1s probe + 3s decide 预算）；sidecar 不可用时静默返回 ""（零回归）。sidecar 的 `laya` Python 包在目标机器不存在时 `--probe` 会 exit 3，路由仍正常。

## 后续建议

1. 补齐 P1.1 的 executor 接线与冷却/自动摘除（计划表剩余半实现面）。
2. 补齐 P1.3 的 token 用量回填（atomcode/aider 调用后回灌 `price_per_call` 实际值）。
3. 在 `use_laya=true` 且 laya 可用时做一次 A/B 观察，验证"复杂任务倾向更高档位"是否符合预期。

## 超额内容

- **文件锁机制速览**：`reports/2026-10-14-file-lock-mechanism.md`（顺带考察，非计划项）——总结 `reserve_scope` / `lock_acquire` 两层如何防多 agent 并发编辑冲突，裁决共用 `rsv_action` 单一真源。

## 来源

- 计划：`docs/2026-10-14-fist-mbt-router-enhancement-plan.md`
- 真源代码：`src/router/`（决策与状态 schema）+ `src/server/model_router_ops.mbt` + `src/server/server.mbt`
- 锁机制报告：`reports/2026-10-14-file-lock-mechanism.md`