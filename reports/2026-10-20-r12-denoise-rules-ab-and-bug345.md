# R12 组合模式 · BUG-333 降噪预案实测 + 上报 BUG-345（Round 12）

- 日期：2026-10-20
- 模式：寻虫 + 打磨（bugfind + polish）
- 轮次：R12 / 256（目标 ACTIVE，未关闭）
- 结论：**降噪规则文件实测生效（severity 覆盖✓），但暴露 BUG-345——`issue_scan` 的 `by_severity` 聚合把 `info` 档并入 `low` 桶，使 BUG-333 预案「净化 by_severity 的 low/high」结构性不成立**。已用 fist-mbt 自身账本上报。
- 来源：R11 报告 `reports/2026-10-20-r11-churn-clean-sweep.md`（入库 `memory/bug333_denoise_rules.json` 后可当 `rules_file` 实证）

## 结果摘要

### 1. 并发状态复查
- 工作树脏 **205**（R11 206，基本持平）；`src/server` 仍 **37 脏** ⇒ 源码修复继续阻塞（禁写 `src/server/*`）

### 2. BUG-333 降噪预案实测（A/B 同参对比）
对同一目录 `src/ltl`、同一 release 二进制（v0.3.9）、同一 `max_findings=100`，仅差 `rules_file`：

| 维度 | 默认（无 rules_file） | 带 `memory/bug333_denoise_rules.json` |
|---|---|---|
| `moonbit-match-exhaustive` severity | **low** count=9 | **info** count=9（覆盖生效✓） |
| 该规则 why/hint | 原版（"运行时对未处理变体 panic"） | **降噪版**（"编译器已保证穷尽…降 severity 为 info"）✓ |
| 逐条 findings 的 severity | low | **info** ✓ |
| `by_severity` | {high:0, medium:0, **low:69**} | {high:0, medium:0, **low:69**} ❌ **一字不变** |
| 实际应得（逐条统计） | low=19, info=50 | low=10, info=59 |

**结论**：severity 覆盖 + why/hint 文案替换**都已生效**，但 `by_severity` 聚合**完全没反映覆盖**。

### 3. BUG-345（新发现 · 真 bug，非误报）
**摘要**：`issue_scan` 的 `by_severity` 聚合把 `info` 档并入 `low` 桶，BUG-333 降噪预案无法净化 `by_severity`。
**编号**：BUG-345（OPEN，`memory/bugs.md`，`reported_by=polish-lead`，severity=medium）

**根因（读源确认，`src/server/issue_scan.mbt`）**：
```moonbit
// L1969-1976 严重度聚合（单次遍历）
for h in dedup {
  if h.severity == "high" { high = high + 1 }
  else if h.severity == "medium" { medium = medium + 1 }
  else { low = low + 1 }   // ← info 落进这里
}
```
- `by_rule`（L1987）用规则表 `r.severity` ⇒ 覆盖后显示 `info`；
- `by_severity`（L1970）用命中 `h.severity`，但值域只有 `high`/`medium`/**其余→low** 三桶；
- ⇒ 把 severity 降到 `info` **不改变任何桶**，只改了标签。

**后果**：BUG-333 预案写明的目标「降 severity 为 info，净化 by_severity 的 low/high」**结构性不成立**。降噪落地后 `by_severity.low` 仍被子串近似噪音灌满，判读 low/high 的初衷失效。

**修复建议（待并发 WIP 清空后落地 `src/server/issue_scan.mbt`）**：
1. 聚合改成**四桶**：`high` / `medium` / `low` / `info`（`info` 单独计数，不再并入 low）；回执 `by_severity` 增 `"info"` 键。
2. 配套**白盒锁**：`src/server/issue_scan_wbtest.mbt` 加一条「外部规则把某内建规则 severity 降为 info ⇒ by_severity.info 增加、by_severity.low 相应减少」的断言（防未来回退）。
3. 顺带把 `by_severity` 与 `by_rule` 的严重度来源统一（都取同一 `h.severity` / 同源），避免"标签改了桶没改"这类错位再犯。

> 注意：以上均为修复点定位与方案，**未修改 `src/server/*`**（并发 WIP 保护）。

### 4. 附：本轮顺带复核的 issue_scan 命中（继续误报，未上报）
- `src/ltl/ltl.mbt:335` `let c = s[i]` / `:343` `c.to_int()`：`s[i]` 在 `for i in 0..<s.length()` 循环内、`c` 为单字符 `Char`，`to_int()` 取码点 —— 安全。
- `src/ltl/ltl.mbt:312` `states[i]`：调用方 `states_to_json(states)` 遍历 `states`，`i` 由 `states.length()` 上界 —— 安全。
- `src/ltl/ltl.mbt:359-373` `format_hex4`：`v % 16` / `pad = 4 - s.length()` 均在 `let mut` 累加路径上，无未定义下标 —— 安全。
- `src/core/core_role.mbt:95` `match (role, action)`：RBAC 全组合穷尽（编译期已保证）—— 安全。

## 资源消耗
- 调用：`issue_scan` ×2（A/B 同参对比）/ `report_bug` ×1
- 新增 commit：无（本轮未改任何源文件；BUG-345 入 `memory/bugs.md` 由 `report_bug` 自动追加）
- 未改 `src/server/*`，未 `git add -A`

## 任务分配记录
- 全自查自跑（无子代理）。
- BUG-345 修复点已定位到 `src/server/issue_scan.mbt` L1969-1976，待并发 WIP 清空后由本人或 owner 落地（含配套白盒锁）。

## 遗留风险
1. `src/server` 37 脏未清 ⇒ BUG-345 修复 + BUG-333 ①③（`--min-severity`）+ BUG-327 p2 + BUG-238 server 层全部阻塞。
2. publish P1 7 项仍红（全并发 WIP，R11 已列表）。
3. **BUG-333 降噪预案即使接线也无法净化 `by_severity`**（BUG-345）—— 这是本轮最重要的风险，若不修，降噪对"判读 low/high"无收益。

## 后续建议
1. 优先修 BUG-345（四桶聚合 + 白盒锁）—— 它是 BUG-333 预案价值能否兑现的前置条件。
2. BUG-333 ①③ 与 BUG-345 一起收口，`--min-severity` 与 `info` 桶口径统一。
3. 建议给 `issue_scan` 的 A/B 对比加一条常驻判据脚本（`scripts/`）：固定目录 + 固定 rules_file，断言 `by_severity.low` 在降噪后严格下降 —— 把这次手工发现的回归锁住。

## 超额内容
- 本轮把 R11 入库的 `memory/bug333_denoise_rules.json` 从"预案语料"升级为"**实测可生效的 rules_file**"，并用量化 A/B 证明其 severity 覆盖能力真实存在 —— 这是 BUG-333 落地前的一手证据。

## 来源
- 工具回执（本轮）：`issue_scan` ×2（默认 / rules_file=memory/bug333_denoise_rules.json，均 src/ltl）、`report_bug`（BUG-345）
- 源码复核：`src/server/issue_scan.mbt` L469-501（命中构造 `rule.severity`）、L1962-2024（聚合 `h.severity` 三桶 + `by_rule` 用 `r.severity`）、L1732-1784（外部规则 `severity` 解析）
- 前置：R11 报告、BUG-333 账本条目、`memory/bug333_denoise_rules.json`（commit 524a198）
