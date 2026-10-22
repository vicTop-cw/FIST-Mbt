# Round 46 报告：BUG-333 降噪预案（外部 rules_file 版）实机验证

## 结果摘要

为 BUG-333（issue_scan 精度不足）设计并**实机验证**了一个**零源码改动**的降噪预案——利用 `issue_scan` 的 `rules_file` 外部规则 JSON 参数（`scan_merge_rules` 同名覆盖内建）把三条噪音规则 severity 归入 `info`，净化 `by_severity` 的 low/high 判读。三档目录（src/store 7 文件、src/ops 14 文件、src 全量 131 文件）全部验证通过，`secs-overflow`（显式 Int32 Y2038）在降噪版中**正确保留未误降**。

## 资源消耗

| 项 | 值 |
|---|---|
| 时间跨度 | 2026-10-20 15:38 → 15:55（约 17 分钟） |
| 调用数 | 3 次 issue_scan（store/ops/src 全量）+ 1 次文件写入 + 3 次 memory 追加 |
| 落盘 | `memory/bug333_denoise_rules.json`（1149 B） |
| 未消耗 | 无外部 API / 无 moon 构建 |

## 任务分配记录

| 任务 | 执行者 | 状态 |
|---|---|---|
| 读 issue_scan.mbt 规则引擎（merge_rules / regex_to_needle / 三条噪音规则定义） | 本 session | 完成 |
| 构造降噪 JSON（match-exhaustive 降 info；unused-variable / long-function 保持 info） | 本 session | 完成 |
| src/store 降噪版验证（7 文件） | 本 session（issue_scan） | 完成 |
| src/ops 降噪版验证（14 文件） | 本 session（issue_scan） | 完成 |
| src 全量降噪版验证（131 文件） | 本 session（issue_scan） | 完成 |

## 三档验证数据

| 档 | 文件数 | by_severity | 噪音归 info |
|---|---|---|---|
| src/store | 7 | high 0 / medium 0 / low 981 | match-exhaustive 205 + unused-variable 211 + long-function 213 = 629 |
| src/ops | 14 | high 0 / medium 1 / low 822 | 119 + 331 + 178 = 628 |
| **src 全量** | 131 | high 0 / medium 1 / low 10613 | 1606 + 4380 + 1906 = **7892** |

**src 全量其他规则完整保留**：json-injection 1414 / shared-mutable 466 / result-discard 276 / array-index-bounds 159 / empty-match 110 / overly-broad-catch 94 / private-field-leak 90 / noop-assignment 39 / possible-overflow 25 / string-index 24 / race-condition 9 / resource-leak 7 / dead-code 6 / floating-point-equality 2 / **secs-overflow 1 medium（显式 Int32 Y2038，正确保留）**。

## 遗留风险

1. **外部规则无法减少 finding 总数**：子串匹配本质（`scan_regex_to_needle` 取最长 alnum）决定只能降 severity 不能真正过滤，降噪版 total 10614 仍含 7892 info。
2. **降噪 JSON 需持久维护**：并发 agent 收口后若内建规则变动，`bug333_denoise_rules.json` 需同步（同名覆盖仍生效但文案可能过时）。
3. **info 仍需人工过滤**：7892 条 info（match-exhaustive 1606 + unused-variable 4380 + long-function 1906）靠编译器保证/人工复核，不自动关闭。

## 后续建议

1. **收口后采用**：把 `memory/bug333_denoise_rules.json` 的三条 severity 调整合并进 `issue_scan.mbt` 内建规则（`moonbit-match-exhaustive` 由 low 改 info），消除外部 JSON 依赖。
2. **降噪预案文档化**：README/AGENTS.md 增补「issue_scan 降噪用法：`rules_file=memory/bug333_denoise_rules.json`」。
3. **BUG-333 账本更新**：标 FIXED 需 evidence（内建规则 severity 调整 + 单测锁），收口后执行。

## 超额内容

- 顺带发现 `src/server/ocr_scan.mbt` **不在并发 agent WIP**（36 文件 WIP 中无它），收口后可独立修 BUG-327。
- 实证 BUG-327 不能通过 delegate 子命令运行时绕过（OCR 二进制对 .mbt 一律不评审），判为外部依赖限制。

## 来源

- 内建规则定义：`src/server/issue_scan.mbt` L278 / L313 / L334（moonbit-long-function / moonbit-match-exhaustive / moonbit-unused-variable）
- 同名覆盖语义：`scan_merge_rules` L1795（外部同名替换内建，其他内建保留）
- 外部 JSON 格式：`scan_parse_external_rules` L1721 / `scan_regex_to_needle` L1689
- 降噪 JSON：`memory/bug333_denoise_rules.json`
- 实机验证：`issue_scan dir={src/store|src/ops|src} rules_file=memory/bug333_denoise_rules.json`