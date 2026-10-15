# Round 32 报告 · caf_memory_status_text + RouterConfig 字段改动面教训

- 日期：2026-10-15
- Goal-2 轮次：R32（上一轮 R30-31）
- 提交：`1bbcf9d`（4 files, 132 insertions）
- 门禁：`moon fmt --check` ✅ / `moon info` 0 errors ✅ / `moon test --target js src/router` 162/162 ✅ / `moon test --target js` 全仓 **1161/1161** ✅

## 结果摘要

**落地产物**：`src/router/model_router_caf.mbt` 新增 `pub fn caf_memory_status_text(CafMemory) -> String`——把 CAF 记忆渲染成按模型聚合的可读文本：

```
CAF 记忆：3 条记录，2 个模型
free-a：1/2 成功 (50%)，均成本 0.1
free-b：1/1 成功 (100%)，均成本 0.2
```

空记忆渲染为 `"CAF 记忆：空（0 条记录）"`。这是 P2c §2.3 status 展示的**纯计算部分**，与 `pick_caf_dry_run` 同模式：接线前先把纯计算放好，server 层 `model_route` / `model_router_status` 调用它即可让 CAF 记忆状态可观测。

**配套白盒锁**：`caf_status_1~2`（落在 `model_router_caf_wbtest.mbt`）
- `caf_status_1_空记忆渲染为 0 条记录`
- `caf_status_2_按模型聚合成功率与均成本`

**文档**：`docs/2026-10-15-fist-mbt-caf-p2c-wiring-design.md` 追加 R32 进度块 + RouterConfig 字段改动面教训 + 全仓回归恢复确认。

## 资源消耗

- 3 个代码/接口文件 + 1 个文档文件（`model_router_caf.mbt` / `model_router_caf_wbtest.mbt` / `pkg.generated.mbti` / p2c wiring 设计文档）
- 全仓 `moon test --target js` 一次（后台）≈ 数分钟
- `moon info` 两次、`moon check` 两次（含一次误读）、`issue_scan` 一次

## 任务分配记录

- 全部由本人（lead agent）执行：代码、测试、门禁、文档、memory、报告

## 遗留风险

1. **§2.3 server 接线仍是唯一阻塞**：`RouterConfig` 加 `caf_default_preference` / `caf_min_evidences` 字段 + `model_router_ops.mbt` 里回写 / 透传 / status 三处，都等并发 agent 的 `model_router_ops.mbt` WIP 收口。
2. **RouterConfig 字段改动面已量化**：全仓 `window_seconds:` 构造点 24 处、仅 `use_caf_memory` 字段在 3 个 wbtest 里出现 36 次，构造形状不一，regex 只匹配到 20/36。已回退，列为独立子任务。
3. **P2d 冷启动偏好仍未启用**：`caf_default_preference` 默认空 = 零回归；Round 25 A/B 已表明 P2d 在成本敏感场景可能更差，需场景 A/B 后再开。

## 后续建议

1. **优先**：并发 agent 收口 `model_router_ops.mbt` 后，一次性做 §2.3 接线 + RouterConfig 字段。**给 wbtest 引入集中构造 helper**（`rt_cfg(...)` / `mrc_cfg(...)`），测试统一走 helper，将来再加字段只改一处——避免再次撞 36 处构造点。
2. **接线顺序**：先接 P2c 记忆路由（`use_caf_memory=true` 时按成功率软重排 + 回写 + status 展示），P2d 偏好作为后续增强（默认空 = 零回归）。
3. **回归约束已解除**：全仓 `moon test --target js` 已恢复 1161/1161，后续 commit gate 直接跑全仓即可，不必退到 router 子集。

## 超额内容

- **寻虫无果的取舍**：`issue_scan src/router` 598 findings 全 low/info（OCR 常见误报：JSON 拼接当注入、函数名当 long-function、catch-all 等），无真高危；剩余 2 条 OPEN bug（BUG-185/186）都是 `e2e_irm_line` 安装器域、非本 CAF 链。**不强行造 bug 修**——把 R32 的产出落在可回归的纯计算上，比硬修非本域 bug 更稳。
- **RouterConfig 字段尝试的回退**：试了 3 个文件（`model_router.mbt` / `model_router_caf.mbt` / `router_config.mbt`），`moon check` 报 21 errors（全是 wbtest 构造点缺字段），regex 批量补只命中 20/36，形状各异风险高 → `git checkout` 全部回退。**结论**：该改动不是"小改"，应作为独立子任务系统化做。

## 来源

- 计划原文：`docs/2026-10-14-fist-mbt-router-caf-learning-plan.md`
- 接线设计：`docs/2026-10-15-fist-mbt-caf-p2c-wiring-design.md`
- 实现：`src/router/model_router_caf.mbt` / `src/router/model_router_caf_wbtest.mbt`
- 前轮：R28-29（`reports/2026-10-15-round28-29-caf-bug206-dryrun-report.md`）、R30-31（`reports/2026-10-15-round30-31-caf-loop-and-p2d-unify-report.md`）