# Round 138 报告 · laya_decide 实测 + 并发深度验证

- 日期：2026-10-15
- 提交：无（纯验证轮）
- 角色：运维验证轮 + 深度验证轮

## 结果摘要

### 1. laya_decide 实测

用 `laya_decide` 对 shim 收尾任务做决策：

```
available = false（laya sidecar 崩溃，exit_code=-1）
decision:
  source       = fallback（内建规则式分支 laya_route）
  complex      = true
  feature_route = 深度验证（family 命中：深度验证 score=6/6）
  split_n      = 4（复杂度高 → +1）
  reasons:
    - 无 Laya 可用，采用规则式决策（词法子串打分，确定性可复现）
    - feature_route 命中族 - 深度验证
    - 任务复杂度高 → 建议拆分数 +1
decision_note = decision 由内建规则式分支 laya_route 补齐（Laya sidecar 只输出 answers，
                不产出 feature_route/split_n）；本工具保证 decision 恒在，
                调用方无需按 available 自行分支
```

**关键发现**：**决策恒在**的契约正确履行——Laya 不可用时自动回退到规则式分支，不阻断调用方。`feature_route=深度验证`（score 6/6）命中，`split_n=4`（复杂度高→+1）。

### 2. 采纳建议：并发深度验证

按 laya 建议做"深度验证"，新增 shim 并发测试：

```python
# 发送 20 并发请求（10 tools/list + 10 resources/list，交错 id 1000-1019）
for i, rid in enumerate(ids):
    send({"jsonrpc":"2.0","id":rid,"method": "tools/list" if i<10 else "resources/list","params":{}})
# 校验：全部响应 id 正确匹配
```

**结果**：

```
收到 20/20, 错误 0, 缺失 [], 错配 [], 重复 0
PASS: 并发 id 全部正确匹配
```

**结论**：shim 并发安全——20 请求并发时每个响应的 id 与请求 id 一一对应，无错配、无重复、无丢失。与 A4 超时机制协同（正常响应 disarm，不误触）。

## 资源消耗

| 项 | 值 |
|---|---|
| 工具调用 | laya_decide × 1、pwsh × 2 |
| 提交 | 无 |
| 触碰并发 WIP | 无 |

## 任务分配记录

- 本会话 Round 138 完成：laya_decide 实测 + 并发深度验证。

## 遗留风险

1. **内建 compat 的 protocolVersion 回写缺陷**——已归档为 DGM 资产 `asset-mcp-compat-...`。
2. **BUG-155 假绿持续**——HEAD 仍含 stale dist。
3. **BUG-161/163 内建修复未提交**。

## 后续建议

1. `laya_decide` 的 `available=false` 时不要 panic——decision 恒在，按它执行即可。
2. 并发测试应加入回归测试（`scripts/test_shim_handshake.py`）固化为第 29 检查。

## 超额内容

- 无（严格限于 laya_decide + 并发验证）。

## 来源

- `laya_decide` → available=false, feature_route=深度验证, split_n=4
- 并发测试：20 请求交错 id → 20/20 正确匹配
