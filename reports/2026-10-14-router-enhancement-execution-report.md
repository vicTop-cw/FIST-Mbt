# 2026-10-14 FIST-Mbt 路由增强计划执行报告

> 目标：实现 `docs/2026-10-14-fist-mbt-router-enhancement-plan.md` 中**未实现**的计划项。
> 状态：**全部完成**（P1.1 自动切换备用模型 + P1.3 性价比选型 + P2 laya 判断路由）。

## 结果摘要

| 计划项 | 计划状态 | 当前状态 | 本次动作 |
|---|---|---|---|
| ① 自动切换备用模型 | ⚠️ 半实现 | ✅ **已实现** | **补齐重试循环 + 失败冷却**（commit 42478cd / 927c14b / 75757d5） |
| ② laya 判断路由 | ❌ 未实现 | ✅ **已实现** | **完整实现**（commit 1b5d36f） |
| ③ 性价比选型 | 计划声称已实现但代码无 | ✅ **已实现** | **补齐** `price_per_call`/`price_per_1k`/`rank` + `cost_performance()` 排序（commit 42478cd） |

## 资源消耗

- 代码改动：`src/router/model_router.mbt` / `src/router/router_config.mbt` / `src/router/router_state.mbt` / `src/router/model_router_wbtest.mbt` / `src/router/router_config_wbtest.mbt` / `src/server/model_router_ops.mbt` / `src/server/server.mbt`
- 新增文件：`docs/2026-10-14-fist-mbt-router-enhancement-plan.md`（更新）、`reports/2026-10-14-file-lock-mechanism.md`、`reports/2026-10-10-p2-guards-report.md`、`reports/2026-10-13-multilane-lock-mechanism-report.md`
- 测试新增：
  - P2 laya：`lp_1`~`lp_6` 六条白盒锁
  - P1.3 性价比：`cp_1` / `cp_2` 两条
  - P1.1 备用链：`fc_1` / `fc_2` / `fc_3` 三条
  - P1.1 冷却：`cd_1` / `cd_2` / `cd_3` 三条
  - 合计 14 条新白盒锁（全仓 1037 → 1051）
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
- `moon test --target js src/router`：**100/100**（新增 6 条 P2 + 2 条 P1.3 + 3 条 P1.1 + 3 条冷却）
- `moon test --target js src/server`：**253/253**
- `moon test --target js`（全仓）：**1051/1051**（含并发 agent 新增测试）
- `moon fmt --check`：PASS
- `check_tools_sync`：PASS

## 遗留风险

1. **P1.3 token 用量回填**：`ModelQuota` 的 `price_per_call`/`price_per_1k` 字段与 `cost_performance()` 已就绪，但 atomcode/aider 调用后的真实 token 用量回填**尚未接线**——`cost_estimate` 仍是占位语义。不影响选型（未知价格不参与比较），但回填后选型会更准。
2. **laya sidecar 依赖**：`mr_laya_tier_hint()` 只在 `use_laya=true` 时真调 sidecar（1s probe + 3s decide 预算）；sidecar 不可用时静默返回 ""（零回归）。sidecar 的 `laya` Python 包在目标机器不存在时 `--probe` 会 exit 3，路由仍正常。
3. **冷却只对路由 pick 生效**：`executor_run` 里显式传 `model` 时不代记账也不触发冷却（与既有"调用方指定 model 不代记账"语义一致）。

## 后续建议

1. 补齐 P1.3 的 token 用量回填（atomcode/aider 调用后回灌 `price_per_call` 实际值）。
2. 在 `use_laya=true` 且 laya 可用时做一次 A/B 观察，验证"复杂任务倾向更高档位"是否符合预期。
3. 给 `executor_run` 的重试与冷却加端到端冒烟（目前是路由单侧白盒 + 编译通过），验证 `FIST_MODEL_MAX_RETRIES` / `FIST_MODEL_COOLDOWN_SECS` 真实生效。

## 超额内容

- **文件锁机制速览**：`reports/2026-10-14-file-lock-mechanism.md`（顺带考察，非计划项）——总结 `reserve_scope` / `lock_acquire` 两层如何防多 agent 并发编辑冲突，裁决共用 `rsv_action` 单一真源。

## 来源

- 计划：`docs/2026-10-14-fist-mbt-router-enhancement-plan.md`
- 真源代码：`src/router/`（决策与状态 schema）+ `src/server/model_router_ops.mbt` + `src/server/server.mbt`
- 锁机制报告：`reports/2026-10-14-file-lock-mechanism.md`