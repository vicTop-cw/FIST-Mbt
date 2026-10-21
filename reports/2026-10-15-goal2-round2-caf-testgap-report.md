# Goal-2 Round 2 报告 · BUG-173/174 状态确认 + C-A-F 测试覆盖缺口分析

- 日期：2026-10-15
- 目标：使用 fist-mbt 全程开发，持续【寻虫-修复-验证-推进】循环轮转
- 提交：无（纯验证轮）

## 结果摘要

### 1. BUG-173/174 状态

- BUG-173（medium, OPEN, T0r612 待领取）—— 仍未修
- BUG-174（low, OPEN, T0r613 待领取）—— 仍未修

### 2. issue_scan 规则扫描 src/router/

| 维度 | 值 |
|---|---|
| 扫描文件 | 19 |
| 总 findings | 965（truncated） |
| high | 5（index-out-of-bounds） |
| medium | 8（unwrapped-unwrap） |
| low | 952 |

**说明**：965 条多为低/信息级（string-index 59、array-index-bounds 45、match-exhaustive 100、unused-variable 499 等），需人工复核。本报告只对 C-A-F 相关文件做重点分析。

### 3. C-A-F 测试覆盖缺口（手工审 router_caf_wbtest.mbt + router_caf_bug188_wbtest.mbt）

| # | 缺口 | 触发条件 | 对应 Bug |
|---|---|---|---|
| 1 | 未测相等率 tie（rate 相同 + avg_cost 相同） | BUG-173 触发条件 | BUG-173 |
| 2 | 未测长字符串溢出 | BUG-174 触发条件（>14 字符） | BUG-174 |
| 3 | 未测环形回绕后 all() 顺序 | 满缓冲 push 后遍历 | — |
| 4 | 未测 max_size=1 单元素缓冲 | 环形退化边界 | — |
| 5 | 未测满缓冲覆盖（count==max_size 时 push） | FIFO 淘汰正确性 | — |

### 4. 处置边界

- 只读 src/router/，未修改源码。
- BUG-173/174 已通过 report_bug(publish_task=true) 上报，修复单入 ns=bugs。

## 资源消耗

| 项 | 值 |
|---|---|
| 工具调用 | pwsh × 1、bug_list × 1、read × 2、issue_scan × 1 |
| 提交 | 无 |
| 触碰并发 WIP | 无 |

## 任务分配记录

- 本会话 Goal-2 Round 2 完成：BUG-173/174 状态确认 + issue_scan + 测试覆盖缺口分析。

## 遗留风险

1. BUG-173/174 待并发 agent 修复。
2. C-A-F 测试覆盖 5 个缺口待补（尤其 BUG-173/174 的回归测试）。
3. 内建 compat 的 protocolVersion 回写缺陷——已归档为 DGM 资产。

## 后续建议

1. Round 3 建议：若 BUG-173/174 仍未修，继续【寻虫】扩面到 `src/server/model_router_ops.mbt`（接线面）。
2. 若并发 agent 修复 BUG-173/174，用 bug_fix 标 FIXED（需 evidence）。
3. 持续【寻虫-修复-验证-推进】循环，目标 256 轮。

## 超额内容

- 无（严格限于状态确认 + 覆盖缺口分析）。

## 来源

- `bug_list()` → BUG-173/174 OPEN
- `issue_scan(dir=src/router)` → 19 files / 965 findings
- `read(router_caf_wbtest.mbt)` → 11 tests + BUG-188 回归 2 tests
- `read(router_caf_bug188_wbtest.mbt)` → 2 tests
