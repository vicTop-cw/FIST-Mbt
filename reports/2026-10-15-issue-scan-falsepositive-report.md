# Round 119 Report · issue_scan 超时缺陷发现 + diff.mbt 假阳性证伪

**日期**：2026-10-15
**HEAD**：`09b25a5`
**目标**：实现未实现的计划；善用发布版 FIST-Mbt 能力

## 结果摘要

本轮做了一件事**有价值**的事：用 FIST-Mbt 的 `issue_scan` 工具扫自己的代码，发现并证伪了工具的一批假阳性 findings，同时上报了工具本身的可用性缺陷。

1. **上报 BUG-162**（OPEN，medium）：`issue_scan` 对 `src/` 全目录（226 个 .mbt）扫描必超时——根 `.mcp.json` 全局 `timeout_ms: 30000`，30s 客户端预算内扫不完。`issue_scan(src/diff)` 单文件秒回，证明是 scope 大、不是工具坏。
2. **证伪 diff.mbt 的 5 条 array-index-bounds findings**：加 7 个 DP 边界测试，全部通过（15/15），证明 issue_scan 报的 `dp[i-1][j-1]` 越界是**子串近似规则的假阳性**——`diff_lines` 的 DP 从 i=1,j=1 起，`dp[0][*]` 是哨兵行，L79 有 `i==0` 短路。
3. **基线提升到 1058/1058**（原 1051 + 新 7）。

## 资源消耗

- `issue_scan` × 3（全 src 超时 ×2 + 单文件正常 ×1）
- `moon test src/diff`（15/15）
- `moon test --target js` 全量（1058/1058）
- `moon fmt` / `moon fmt --check`（干净）
- 提交 1 个：`09b25a5`

## 任务分配记录

| 阶段 | 执行 | 产物 | 状态 |
|---|---|---|---|
| 探测 issue_scan 全 src | 我 | 两次超时 → 确认可用性缺陷 | ✅ |
| 探测 issue_scan 单文件 | 我 | `src/diff` 44 findings（全 low/info） | ✅ |
| 人工核实 diff.mbt 下标 | 我 | DP 从 1 起 + 哨兵行 + 短路 ⇒ 无越界 | ✅ |
| 上报 BUG-162 | 我 | OPEN（含根因 + 两条修复方向） | ✅ |
| 加 7 个边界测试 | 我 | 15/15 通过，证伪假阳性 | ✅ |
| fmt + 全量测试 + 提交 | 我 | 1058/1058，commit `09b25a5` | ✅ |

## 遗留风险

1. **BUG-162**：issue_scan 全 src 超时仍是 OPEN。修复方向两条（调大 timeout_ms / issue_scan 分批扫描），后者需改 `src/server/issue_scan.mbt`（并发 WIP），前者是全局配置影响面大 → 待 owner 裁决。
2. **BUG-156 低噪**：`src/diff` 是干净代码却报 44 条 finding（全 low/info）。这轮再次证明 ocr-local 外部规则的高假阳性率，支持「收窄 pattern」的论据。但收窄是独立决策。
3. **check_scripts_index / check_plugin_sync**：仍等并发 agent 提交。
4. **BUG-155**：仍待用户裁决（不可逆）。

## 后续建议

1. **owner 裁决 BUG-162**：建议先把 `.mcp.json` 的 `timeout_ms` 调大到 120000（issue_scan 是唯一需要长预算的工具），或给 issue_scan 加 `dir` 分批能力。
2. **issue_scan 规则降噪**：`moonbit-array-index-bounds` / `moonbit-shared-mutable` / `moonbit-long-function` / `moonbit-unused-variable` / `moonbit-match-exhaustive` 都是子串近似，低噪率高。可作为 BUG-156 收窄 pattern 的具体证据清单。
3. **边界测试法**：把 issue_scan 报的每处下标/索引都变成显式压测，绿即假阳性、红即真 bug。比逐个读源码快。

## 超额内容

- 确认 `issue_scan` 工具本身可用（非代码 bug），是 scope 性能问题。
- 顺带把 `text_diff` 工具的 diff_lines 边界覆盖从 8 测试提到 15 测试，覆盖 DP 首格/首行/长输入/尾部换行/无公共子序列/空 render。

## 来源

- `src/diff/diff.mbt` L43-92（diff_lines 实现）
- `src/diff/diff_test.mbt`（新增 7 个边界测试）
- `scripts/check_test_sync.py` L106-116（正则根因，本轮未改）
- `.mcp.json`（`timeout_ms: 30000` 全局）
- `memory/bugs.md`（BUG-162 上报）
- `memory/2026-10-15.md`（Round 119 记录）
- `moon test --target js` = 1058/1058