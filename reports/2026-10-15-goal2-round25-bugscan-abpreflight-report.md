# Goal-2 Round 25 报告 · 寻虫 + P2d A/B 预演（场景依赖发现）

- 日期：2026-10-15
- 目标：使用 fist-mbt 全程开发，持续【寻虫-修复-验证-推进】循环轮转
- 交付：issue_scan 寻虫 + P2d A/B 预演脚本 + 场景依赖洞察

## 结果摘要

### 1. 寻虫环节（issue_scan src/router）

```
scanned_files: 10, total_findings: 571
by_severity: high 0, medium 0, low 571
```

全部 low 严重度，多为噪声（noop-assignment 是误报，`{reason: self.x}` 是结构体字面量不是赋值；array-index-bounds 多为已守卫的 `pool[i]`）。**未上报新 bug**。

### 2. P2d A/B 预演（关键发现）

`scripts/caf_p2d_coldstart_ab.py` 模拟 100 次路由决策，比较 3 个策略：

| 策略 | 成功 | 总成本 | 每成功成本 | 成功率 |
|---|---|---|---|---|
| Strategy 0 (baseline: 总是选第一个 m_free) | 50 | 100 | 2.000 | 50.0% |
| Strategy 1 (P2d 默认偏好 m_mid) | 74 | 200 | 2.703 | 74.0% |
| Strategy 2 (P2d 学到偏好 m_premium) | 91 | 300 | 3.297 | 91.0% |

**两个场景**：

- **场景 1（成本敏感）**：baseline 最优（每成功成本 2.000）。P2d 反而不优（2.703）。
- **场景 2（成功率敏感）**：P2d 最优（成功率 91.0% vs baseline 50.0%）。P2d 优于 baseline **+41 个百分点**。

### 3. 洞察：冷启动偏好是场景依赖的

**不能盲目设默认偏好为"选成功率最高的"**——那会让成本敏感场景变差。

| 场景 | 最优策略 | 建议偏好 |
|---|---|---|
| 成本敏感（预算紧） | baseline（选最便宜） | `[]` 或成本最低 |
| 成功率敏感（关键任务） | P2d（选成功率最高） | 成功率最高的模型 |

**建议**：P2d 接线到配置时，`caf_default_preference` 应由业务目标决定，不能硬编码。

### 4. P2d 设计文档更新

加入 A/B 预演结论，提示默认偏好按业务目标配置。

## 资源消耗

| 项 | 值 |
|---|---|
| 新增文件 | 1（scripts/caf_p2d_coldstart_ab.py） |
| 修改文件 | 1（docs/2026-10-15-fist-mbt-caf-p2d-cold-start-design.md） |
| FIST MCP 工具调用 | 2（issue_scan + assistant_status） |
| 未修改 src/ 真源 | ✅ |

## 遗留风险

1. P2c wiring 仍被并发 agent WIP 阻塞（model_router_ops.mbt 25 文件）。
2. P2d 尚未接线到 pick 流程。
3. 默认偏好的业务配置语义未定——需与用户/owner 对齐。

## 后续建议

1. Round 26：若 model_router_ops.mbt 释放 → 实施 P2c wiring + P2d 接线。
2. Round 26：考虑在 P2d 设计里加 `objective` 参数（cost/success），让默认偏好自适应。
3. Round 26：持续监控并发 agent 是否继续提交。

## 超额内容

- 无。

## 来源

- `scripts/caf_p2d_coldstart_ab.py`（新增，A/B 预演）
- `mcp__fist-mbt__issue_scan` → 571 findings 全 low
- `docs/2026-10-15-fist-mbt-caf-p2d-cold-start-design.md`（更新，加入场景依赖结论）
- `git log --oneline -5` → 并发 agent 未提交（1e5061e 后 3 轮无新提交）
