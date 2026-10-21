# R16 报告：降噪规则 v2 + BUG-347（外部 rules_file 的 `::` 限定剥离）

- **轮次**：R16（组合模式·打磨/寻虫/修复/验证/清整 第 16 轮）
- **日期**：2026-10-20
- **作用域**：`issue_scan` 的 `rules_file` 路径 · `memory/bug333_denoise_rules_v2.json` · `src/ltl` · `src/store`
- **产物**：`memory/bug333_denoise_rules_v2.json`（v2 降噪清单，机器可消费）、`memory/bug347_external_pattern_probe.json`（三探针实证）、BUG-347 账本条目、本报告

---

## 结果摘要

本轮以 A/B 实验验证 v2 降噪规则清单时，意外挖出**一个此前未被识别的更严重缺陷 BUG-347**，并同时**推翻了 R12 的一条误判**（"`pattern` 字段惰性"）。

### 1. 三探针交叉实证（核心产出）

对 `issue_scan` 的外部 `rules_file` 路径做控制变量实验（目标目录 `src/ltl`，该目录**不含任何 `Json::string(` 调用**）：

| 探针 `rules_file` 的 json-injection `pattern` | 含 `::` | `src/ltl` json-injection 命中 | 结论 |
|---|---|---|---|
| 基线（不带 rules_file） | — | 0（不在 by_rule） | 内建表按**字面量** `Json::string(` 匹配 |
| `Json::string(` | 有 | **11** | 命中 `*.to_string()` / `formula_to_string(` / `verdict_to_string(` |
| `Foo::string(`（无关命名空间） | 有 | **11（逐字相同）** | `Json::` 与 `Foo::` 无差别 ⇒ **命名空间限定被丢弃** |
| `NOPEstring(`（无 `::`，仅含 `string(`） | 无 | **0** | 触发条件是"含 `::`"，不是"含 `string(`" |
| `###NOMATCH-MARKER###`（无 `::`） | 无 | 0（`src/store` 上把 json-injection 从 45 打到 0） | 外部 `pattern` 字段**确实生效** |

11 条命中的真实行：`src/ltl/ltl.mbt` L37 `Atom("__true__".to_string())`、L62、L284 `pub fn formula_to_string(...)`、L287/288/289/290/292 `formula_to_string(`、L298 `verdict_to_string(`、L347 `out.push(c.to_string())`、L367 `s = hex_chars[d].to_string() + s`。**无一行含 `Json::string(` 或 `Foo::string(`。**

### 2. 根因（BUG-347）

`issue_scan` 对外部 `rules_file` 的 `pattern` 与内建规则表使用**两套语义不同的匹配器**：

- **内建表**：按字面量 `"Json::string("` 匹配（基线 `src/store`=45 命中，`src/ltl`=0）。
- **外部 `rules_file`**：先按 `::` `split` 取**尾段**，再做子串匹配 ⇒ `"Json::string("` 被静默降级为 `"string("`，命中全库每个 `*.to_string()` / `formula_to_string(` / `verdict_to_string(` 调用，假阳性**爆炸式扩散**（`src/ltl` 从 0 → 11；`src/store` 从 45 → 53）。

### 3. 对既有结论的修正

- **修正 R12 的"`pattern` 字段惰性"**：控制组 `###NOMATCH-MARKER###` 在 `src/store` 上把 json-injection 从 45 打到 0，证明外部 `pattern` **真的生效**。R12 当时的判定样本不足以区分"生效"与"恰好无命中"，属误判。
- **深化 BUG-346**：BUG-346 的内建路径判断仍成立（内建表确实按字面量匹配安全构造器 `Json::string(`，基线 45/45 假阳）。但同一条规则在**外部 `rules_file` 路径**上有更严重变体（BUG-347），两者叠加使该规则的 FP 面远大于最初估计。

### 4. v2 降噪清单的同步修正

`memory/bug333_denoise_rules_v2.json` 的 json-injection 条目已按 BUG-347 修正：
- `pattern` 从 `"Json::string("` **显式改为 `"string("`**，如实编码 BUG-347 生效后的真实行为（作为 `rules_file` 传入时实际匹配 `*string(`）。
- `why` / `description` 补齐 BUG-346 + BUG-347 双缺陷溯源与三探针证据。
- 注明本文件其余三条（match-exhaustive / unused-variable / long-function）的 `pattern` **不含 `::`**，不受 BUG-347 影响。
- severity 保持 `info`，修 BUG-346/347 前先止损，`by_rule`/per-hit 不再污染 `low` 桶。

> 注意：**`by_severity.low` 仍未净化**——`src/store` 全量 `{high:0, medium:0, low:989}`、`src/ltl` `{low:80}`。原因即 BUG-345（`by_severity` 聚合缺 `info` 档、`else→low` 兜底），需改 `src/server/issue_scan.mbt`，本轮因 `src/server` 有并发 WIP（37 个未提交改动，R14/R15/R16 三连一致）未动。

---

## 资源消耗

| 项 | 量 |
|---|---|
| `issue_scan` 调用 | 6 次（基线 ltl/store、v2 ltl/store、控制 NOMATCH ltl/store、控制 NOPE ltl、终极 Foo ltl） |
| 探针文件读写 | 3 次写 + 1 次删除 + 1 次归档 |
| `report_bug` | 1 次（BUG-347） |
| 源文件编辑 | 0（`src/server` 保持只读） |

---

## 任务分配记录

| 动作 | 执行者 | 说明 |
|---|---|---|
| 三探针实验设计+执行 | 本人 | 控制变量法锁定 `::` 剥离机制 |
| BUG-347 上报 | 本人 | severity=high，证据含三探针结果 |
| v2 清单 BUG-347 修正 | 本人 | pattern 显式化为 `string(` |
| BUG-345 / BUG-346 / BUG-347 落地修复 | **待派** | 全部需改 `src/server/issue_scan.mbt`，被并发 WIP 阻塞 |

---

## 遗留风险

1. **BUG-345 / 346 / 347 均未真正修复**（需改 `src/server/issue_scan.mbt`，37 个并发未提交改动连续三轮不变，仍不可触碰）。
2. **`issue_scan` 的 `rules_file` 全模式存在语义不一致**：外部 pattern 走 `::` 剥离 + 子串匹配，内建走字面量匹配。任何含 `::` 的外部规则都会触发 BUG-347，不止 json-injection——这是**系统性风险**，建议修复时统一两套匹配器。
3. **`by_severity.low` 桶混入 `info`**：R11/R13/R15/R16 四轮读数均被 BUG-345 污染，`low` 计数不能当"中低危真实数量"解读。

---

## 后续建议

1. **优先修 BUG-347**（外部 pattern 与内建共用匹配器），它直接影响 `rules_file` 这一公共能力对所有外部使用者的正确性，比 BUG-345/346 优先级更高。
2. 修 BUG-345（`severity_bucket` + `by_severity` 补 `info` 档 + wbtest 锁）后重跑本轮 A/B，预期 `src/store` 的 `by_severity` 出现 `info` 桶、`low` 显著下降。
3. 并发 WIP 收口后一次性落地 BUG-327/333/345/346/347 五条 OPEN 修复（本人名下 4 条 + 本轮新增 1 条）。
4. 探针文件 `memory/bug347_external_pattern_probe.json` 建议保留为常驻回归语料，BUG-347 修复后应断言 `Foo::string(` 与 `Json::string(` 命中集**逐字相同**且**不含** `to_string(` 调用。

---

## 超额内容

- 未新增任何 `src/server` 改动（严守并发 WIP 边界）。
- 无新任务发布（当前无本人活跃命名空间；并发命名空间 `tnr-polish`/`light-isolation`/`ns-skill-worktree`/`zi-migration`/`_proj_lang-zone` 未触碰）。
- 新增 BUG-347 入账（`memory/bugs.md` 现 347 条）。

---

## 来源

- 本报告：`reports/2026-10-20-r16-denoise-rules-v2-and-bug347.md`
- v2 降噪清单：`memory/bug333_denoise_rules_v2.json`
- 三探针实证：`memory/bug347_external_pattern_probe.json`
- 前序：R14 `reports/2026-10-20-r14-bug345-fix-blueprint.md`（BUG-345 蓝图）、R15 `reports/2026-10-20-r15-store-scan-bug346-rule-inversion.md`（BUG-346 首次发现）
- 账本：`memory/bugs.md` BUG-345 / BUG-346 / BUG-347