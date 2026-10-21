# 独立 L4 审计：issue_scan 规则层缺陷（BUG-345/346/347/348）第三来源确认

- **报告人**：agent-skill-docs（并行审计视角）
- **日期**：2026-10-21 09:30（+08）
- **对象**：`src/server/issue_scan.mbt` 的规则层（`by_severity` 聚合、`moonbit-json-injection`、外部 `rules_file` pattern 匹配器、`moonbit-unused-variable`/`moonbit-match-exhaustive` 精度）
- **范围**：**只读 + issue_scan 工具探针**，未改 `src/`（并发 WIP 归属）
- **结论摘要**：并发 agent（polish-lead / r16-issue_scan-ab）对 BUG-345/347/348 的三份诊断**全部成立**，我用**独立探针**（不同 JSON、不同目录、真读源码逐行）复现，命中数与它报告的**逐字一致**。六顶帽辩论 rate=0.333 未收敛的原因是**自证自**（自述 vs 自述），不是诊断有误——第三方独立证据已补齐。

## 结果摘要

| BUG | 声称 | 我的独立验证 | 判定 |
|---|---|---|---|
| BUG-345 | by_severity 聚合把 `info` 并入 `low` 桶 | 带 `bug333_denoise_rules_v2.json` 跑 `src/ltl`：by_rule 已显示 match-exhaustive=`info`(9)、unused-variable=`info`(27)、long-function=`info`(23)、json-injection=`info`(11)；但 **by_severity 仍 {high:0, medium:0, low:80}，与默认完全一致** | ✅ 确证 |
| BUG-347 | 外部 rules_file pattern 按 `::` 切分取尾段，命名空间限定被静默丢弃 | 三探针（我自写 JSON，非它的 `_ctl_pattern_probe.json`）在 `src/ltl`（无任何 `Json::string(` 调用）：`Foo::string(`→json-injection **11 条**；`Json::string(`→**11 条**；`NOPEstring(`（无 `::`）→**0 条**。与它报告的 11 条逐字一致 | ✅ 确证 |
| BUG-348 | `unused-variable` 报已使用的 let；`match-exhaustive` 报已含 catch-all 的 match | issue_scan(src/engine) = 1693 命中，**high=0 medium=0**；真读 `src/engine/cost_tool.mbt`（77 行）逐行：L29 `exceeded`→L43/46 使用、L31 `remaining`→L34/44/52 使用、L32 `action`→L45 使用、L68/72 match 均含 `_ => 0.0` | ✅ 确证 |

**证据强度**：全部达到 L4（L3 是并发 agent 的自述，我在同一工具上独立复现并真读源码，非转发其结论）。

## 详细证据

### BUG-345：by_severity 聚合信息丢失（确证）

- `src/engine` A/B：默认跑 by_severity={high:0, medium:0, low:1693}（全量 1693 条都落 low，因为 unused-variable=708、json-injection=340、match-exhaustive=252、long-function=215 全是 low/info）。
- `src/ltl` A/B：默认 by_severity={high:0, medium:0, low:80}；带 v2 降噪 by_severity={high:0, medium:0, low:80} **一字不变**，尽管 by_rule 里四条已显式降为 `info`。
- 根因：聚合块把 `info` 走 `else` 分支并入 `low`。**降噪只改了标签（by_rule / 逐条 findings），by_severity 的 low 计数不响应**，BUG-333 降噪预案「净化 by_severity 的 low/high」结构上不成立。

### BUG-347：外部 rules_file pattern 的 `::` 剥离（确证，最严重）

三探针（我自写 JSON，pattern 用字符串字段，schema 见 `memory/bug333_denoise_rules.json`）：

| pattern | json-injection 命中 | 说明 |
|---|---|---|
| `Json::string(` | 11 条（`src/ltl/ltl.mbt`，均为 `to_string()`/`formula_to_string(`/`verdict_to_string(` 行） | 目标 pattern |
| `Foo::string(`（无关命名空间） | **11 条，行号逐字相同** | 与 `Json::` 无差别 ⇒ `::` 前限定被丢弃 |
| `NOPEstring(`（无 `::`，仅含 `string(`） | **0 条** | 触发条件是「含 `::`」而非「含 `string(`」 |

**这是 issue_scan 对外部规则的契约破坏**：任何 `Namespace::method(` 喂进来都被静默降级为 `method(`，命中全库每个 `*.to_string()` 调用，假阳性爆炸式扩散。比内建表（BUG-346，至少字面量匹配安全构造器）更严重。

### BUG-348：扫描器精度缺陷（确证）

`src/engine` 1693 条命中里 `high=0 medium=0`。抽样 `cost_tool.mbt`（77 行）12 条 low/info 命中，真读源码：

| 行 | 命中规则 | 源码 | 实际是否使用 |
|---|---|---|---|
| L29 | unused-variable | `let exceeded = current >= limit` | **L43 `Json::boolean(exceeded)` + L46 `if exceeded`** ✅ 使用 |
| L31 | unused-variable | `let remaining = limit - current` | **L34/L44/L52 `remaining < limit*0.2` + `Json::number(remaining)`** ✅ 使用 |
| L32 | unused-variable | `let action = if exceeded {...}` | **L45 `Json::string(action)`** ✅ 使用 |
| L68 | match-exhaustive | `let limit = match args.value("limit") {` | **`_ => 0.0` catch-all** ✅ 已穷尽 |
| L72 | match-exhaustive | `let current = match args.value("current") {` | **`_ => 0.0` catch-all** ✅ 已穷尽 |
| L23/24/45/47/53/55 | json-injection | 全为 `Json::string(...)` | 安全构造器（BUG-346 FP） |
| L64 | long-function | `budget_check_json` 仅 13 行 | 报「超长函数」不合理 |

**结论**：cost_tool.mbt 上 12 条 low/info 命中 = **0 真 bug**。`unused-variable` 只按 `let <ident> =` 行首启发式匹配、不做实际使用性检查；`match-exhaustive` 不排除已含 catch-all 的 match——**两条规则在真实代码上近似全 FP**，淹没真告警（如 `moonbit-result-discard` 17 条、`moonbit-array-index-bounds` 19 条这些可能真有问题）。

## 资源消耗

- issue_scan 调用：6 次（3 探针 + A/B + src/engine + src/ltl）
- 源码读取：1 次（cost_tool.mbt 77 行全文）
- 临时探针：`temp/probe-{foo,nope,json}.json`（已删除）
- memory 追加：3 条（BUG-347 / BUG-348 独立验证 + 本轮总账）

## 任务分配记录

- 全部由 agent-skill-docs 独立完成（无子代理、无他人转述）。
- 并发 agent（host-sensenova-r1 / polish-lead / r16-issue_scan-ab）停在 R23 六顶帽辩论未收敛（rate=0.333，白 abstain/黑 reject/黄 pass），指挥官裁决「不自动推进，等 src/server 清空 + owner 授权」。

## 遗留风险

1. **BUG-345/346/347/348 全部 OPEN**，修复归属 `src/server/issue_scan.mbt`，受并发 WIP 阻塞。**这是扫描器自身的缺陷**，直接影响 `issue_scan` 作为「寻虫」工具的可用性——当前 low/info 桶被 FP 淹没，真告警（result-discard / array-index-bounds）难以辨识。
2. **v2 降噪文件（`bug333_denoise_rules_v2.json`）已显式把 json-injection 的 pattern 写成 `string(`**，这是**如实编码 BUG-347 的缺陷行为**（因为外部路径确实匹配 `string(`）——但这是「让降噪文件迁就 bug」，不是修 bug。修掉 BUG-347 后该 pattern 应改回 `Json::string(`。
3. **六顶帽辩论未收敛 ≠ 诊断有误**：独立第三方证据（本报告）已补齐，修复决策现在有外部依据支撑，不需继续辩论。
4. 我的三份独立验证全部落在并发 agent 已报告的 BUG 上，未发现新的规则层缺陷（未在 scope 里做全量新扫描）。

## 后续建议

1. **优先修 BUG-347**（外部 pattern `::` 剥离）——严重性最高（契约破坏），且修复独立（外部 pattern 匹配器与内建表对齐），不与 BUG-345/346/348 耦合。
2. **BUG-345**（by_severity 四桶）：聚合块加 `info` 分支即可，独立可并行。
3. **BUG-346/348**（内建表 FP + unused-variable/match-exhaustive 精度）：需要 actual-usage 检查 + catch-all 排除，工作量较大，建议与 BUG-333 降噪预案合并设计（降噪的语义正确版本）。
4. 修复后统一验证：`issue_scan(src/engine)` 的 low 桶应从 1693 大幅下降，`result-discard`/`array-index-bounds` 这类真规则占比上升。

## 来源

- 缺陷账本：`memory/bugs.md` BUG-345（L5740）、BUG-346（L5756）、BUG-347（L5777）、BUG-348（L5794）
- 源码：`src/engine/cost_tool.mbt`（77 行，全文复核）
- 降噪预案：`memory/bug333_denoise_rules.json`、`memory/bug333_denoise_rules_v2.json`
- 扫描日志：本会话 issue_scan 6 次调用（`call_log` 可查）
- 记忆：`memory/2026-10-20.md`（09:28–09:30 三条独立验证追加）