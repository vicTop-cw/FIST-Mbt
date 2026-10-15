# Goal-2 Round 34 报告：CAF 边界加固 5 锁

- **日期**：2026-10-15
- **提交**：`6059b5f`（2 文件 +124）
- **状态**：主线 §2.3 server 接线仍被并发 agent 占用，本轮转 CAF 纯计算域边界加固 + 寻虫验证

## 结果摘要

### 背景

`model_router_ops.mbt` 本轮确认**真被并发 agent 改动**（`git diff --numstat` = 4/9，`src/server/` 共 27 文件 WIP），§2.3 接线（CAF 记忆回写 / config 字段透传 / status 展示）无法推进。按目标「持续寻虫-修复-验证-推进」，转向**不碰并发域的边界加固**。

### 寻虫结果（无 bug，正向验证）

- `issue_scan src/router`：**634 findings 全 low/info**，0 high、0 medium。R33 新加的 `from_json`/`to_json` 代码无高危。
- **`caf_soft_reorder_with_preference`** 鲁棒性审查：偏好含候选外模型 → `idx=-1` 跳过不越界；偏好重复项 → 第二次 `idx=-1`；空候选集 → for 不执行。**无索引越界**。
- **`caf_memory_status_text`** 审查：`cnt>0` 守卫 + 整数除法，无除零/NaN；且聚合逻辑保证 `cnt>=1`（新模型 `+1`），`cnt=0` 分支不可达（防御性）。

结论：两项核心函数边界稳健，**不需要改实现**，改为加锁防回归。

### 新增 5 条边界锁

| 锁 | 钉死的契约 | 区分度 |
|---|---|---|
| `caf_pref_8_空候选集安全` | 空候选集 + 非空偏好 + 空记忆 → `[]` 不 panic | 会 panic 即红 |
| `caf_pref_9_min_evidences零语义` | `min_evidences=0` + stats 非空 → 退化成功率排序（钉「0 = any evidence counts」） | 断言 `[m_mid,…]`，错误路径 `[m_free,…]` |
| `caf_pref_10_全零stats走偏好` | `total` 全 0 + `min_evidences=10` → `evidence_total=0` 走偏好 | 断言 `[m_mid, m_free]`，错误路径 `[m_free, m_mid]` |
| `caf_status_3_单模型多条记录` | 整数除法 `200/3=66%` 截断不 panic | 断言精确文本 |
| `caf_status_4_全失败记录不产出NaN` | 全失败记录不产出 `NaN`/`Inf` | 含 NaN/Inf 即红 |

## 资源消耗

`moon fmt` / `moon info`（0 errors 564 warnings）/ `moon test --target js src/router` ×3 / 全仓回归 ×1 / `issue_scan` ×1

## 任务分配记录

本人在 router 域独立推进，未触碰并发 agent 工作面（`src/server/`、`src/router/router_caf.mbt`）。

## 遗留风险

- **§2.3 server 接线仍未做**：`model_router_ops.mbt` 三件事（`executor_run` 后 `caf_memory.push` / config 两字段透传 `pick_caf` / status 展示 `caf_memory_status_text`）。router 侧前提已齐备（R33 落地），只等并发 agent 释放。
- **CAF 纯计算域加固空间已小**：`router_caf_ext_wbtest.mbt` 已有 7 条 pref 锁，本轮只补到 3 条真正缺失的边界。后续若无新代码，继续加锁边际收益递减。

## 后续建议

1. **R35 首选**：并发 agent 释放 `model_router_ops.mbt` 后立即做 §2.3 接线（验收 = `executor_run` 走 CAF 路由 + status 看到记忆聚合 + dry_run 预览返回建议模型与依据）。
2. **R35 备选**：`caf_stats` 按 `feature_hash` 分组的语义审查（ACRouter 应特征感知路由，现聚合按 model 分组跨上下文）——但该实现属并发 agent 域。
3. **持续寻虫**：每轮跑 `issue_scan` + `boundary_probe`，确认无新增高危。

## 超额内容

- 纠正对并发域状态的判断方法：用 `git diff --numstat`（而非 `git status --short`）区分「真改动」与「CRLF 噪音」，避免误判占用/空闲（R32 曾因此白等一轮）。

## 来源

- 代码：`src/router/router_caf_ext.mbt`（只读审查）、`src/router/model_router_caf.mbt`（只读审查）
- 测试：`src/router/router_caf_ext_wbtest.mbt`、`src/router/model_router_caf_wbtest.mbt`
- 设计：`docs/2026-10-15-fist-mbt-caf-p2d-cold-start-design.md`、`docs/2026-10-15-fist-mbt-caf-acceptance-status.md`
- 记忆：`memory/2026-10-15.md`（Round 34 条目）
