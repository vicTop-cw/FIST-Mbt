# BUG-347 修复蓝图：统一 `issue_scan` 外部 `rules_file` 与内建的 pattern 匹配器

- **缺陷**：BUG-347（OPEN，high，R16 上报）
- **作用域**：`src/server/issue_scan.mbt`（改 `rules_file` 外部规则的 pattern 匹配路径）
- **状态**：drop-in 就绪，待 `src/server` 并发 WIP 清空即落
- **关联**：BUG-346（内建表按字面量匹配安全构造器）、BUG-345（`by_severity` 聚合缺 `info` 档）
- **本蓝图为独立修复**，不依赖 R14 的 BUG-345 蓝图，可单独落地

---

## 1. 根因（三探针实证，R16）

`issue_scan` 对内建规则表与外部 `rules_file` 使用**两套语义不同的匹配器**：

| 匹配路径 | 语义 | 基线实测 |
|---|---|---|
| 内建规则表 | 按**字面量**匹配 `pattern` | `src/store` json-injection=45（全为 `Json::string(`） |
| 外部 `rules_file` | 先按 `::` `split` 取**尾段**，再做**子串**匹配 | `src/ltl` json-injection=11（全为 `*.to_string(`） |

外部路径把 `"Json::string("` 静默降级为 `"string("`，`Json::` 命名空间限定被丢弃。

### 三探针交叉证据（目标 `src/ltl`，该目录无任何 `Json::string(` 调用）

| 探针 pattern | 含 `::` | json-injection 命中 |
|---|---|---|
| 基线（不带 rules_file） | — | 0 |
| `Json::string(` | 有 | **11** |
| `Foo::string(`（无关命名空间） | 有 | **11，逐字相同** |
| `NOPEstring(`（无 `::`，仅含 `string(`） | 无 | **0** |
| `###NOMATCH-MARKER###`（无 `::`） | 无 | 0 |

⇒ 触发条件是**"含 `::`"**，不是"含 `string(`"；`::` 前的命名空间限定被完全忽略。

---

## 2. 波及面（整表枚举，34 处 pattern）

对 `src/server/issue_scan.mbt` 全部规则 `pattern:` 字面量枚举，**含 `::` 的仅 2 条**：

| 规则 id | 内建 pattern | BUG-347 剥离后实际匹配 |
|---|---|---|
| `moonbit-json-injection`（L259） | `["Json::string("]` | `string(` ⇒ 命中全库每个 `*.to_string()` / `formula_to_string(` / `verdict_to_string(` |
| `moonbit-resource-leak`（L287） | `["::open("]` | `open(` ⇒ 命中任意 `open(` 调用 |

其余 32 条 pattern 不含 `::`，不受 BUG-347 影响（含 `match-exhaustive`/`unused-variable`/`long-function`/`shared-mutable` 等降噪族）。

**结论**：BUG-347 波及面 = 2/34 条规则，但这两条恰好都是**高危类**（JSON 注入、资源泄漏），且剥离后 FP 面爆炸式扩散，故定级 high。

---

## 3. 修复设计（drop-in）

**目标**：外部 `rules_file` 的 `pattern` 与内建规则表走**同一匹配器**，语义统一为字面量匹配。

### 方案 A（推荐，最小改）

在外部规则合并处，**不要**对 pattern 做 `::` 剥离；外部 pattern 按内建同款字面量匹配。即：

```text
外部规则 pattern 归一：
  pattern_text = r.pattern                // 不再 split("::").last()
  匹配判定   = line.contains(pattern_text)  // 与内建表同路径
```

需要确认内建表当前是否也走 `contains` 字面量（基线 `src/store`=45 全为字面量 `Json::string(` 命中，佐证内建确为字面量 `contains`）。

### 方案 B（防御加固，可选叠加）

即使统一为字面量，`Json::string(` 本身仍是**安全构造器**（BUG-346），修 A 后该规则仍 100% FP。建议同步：

- 把 `moonbit-json-injection` 的 pattern 改为**真实注入形状**，例如 `"] + "` / `" + \"` / 裸 `+ x +` 拼接进入 `Json::string(`，或匹配 `Json::object(` 内直接拼用户输入；
- 或按 BUG-333 方向，加入 `--min-severity` 与默认降噪锁，把该规则在默认态降为 info（当前 v2 清单已在 `rules_file` 面止损）。

### 方案 C（回归锚点）

修完必须新增/更新 wbtest 锁，把三探针行为**钉住**（否则回归不可见）：

```text
// src/server/issue_scan_wbtest.mbt（新增）
test "BUG-347: 外部 rules_file pattern 的 :: 限定不得被剥离" {
  // 同一目标语料，分别用 pattern "Json::string(" 与无关命名空间 "Foo::string("
  // 断言两命中集逐字相同
  assert_eq(scan_with(rule("Json::string(")), scan_with(rule("Foo::string(")))
  // 断言命中集不含裸 *.to_string() 调用
  let hits = scan_with(rule("Json::string("))
  assert_true(not_any(hits, "to_string("))
}
```

> 若采用方案 A 修复，则该锁在修复前是**红**（当前 `Foo::string(` 与 `Json::string(` 命中集相同且含 `to_string(`），修复后变绿——正是 TDD 的 RED→GREEN 形态。

---

## 4. 验收判据（A/B 守恒，R14 同款思路）

修复后应满足（对 `src/ltl` 复跑）：

| 判据 | 修复前 | 修复后 |
|---|---|---|
| 基线 json-injection 命中 | 0 | 0（不变） |
| rules_file `Json::string(` 命中 | 11（全为 `to_string(` 误报） | **0**（ltl 无 `Json::string(`） |
| rules_file `Foo::string(` 命中 | 11 | **0** |
| rules_file `NOPEstring(` 命中 | 0 | 0（不变） |
| rules_file `###NOMATCH###` 命中 | 0 | 0（不变） |

任一不满足 ⇒ 修复未落地，不得标 FIXED。

---

## 5. 落地路径

1. 等 `src/server` 并发 WIP（当前 37 个未提交改动 + 新增未跟踪 `src/server/bug335_ns_route_wbtest.mbt`，并发方仍在推进 BUG-335）清空。
2. 落方案 A + 方案 C 锁 → `moon fmt` → `moon test --target js` 全绿（重点 `Total tests: N, passed: N, failed: 0`）。
3. 复跑 §4 判据 5 行全过 → `bug_fix([BUG-347, BUG-346], evidence=...)` 销账。
4. BUG-345、BUG-333 ①③、BUG-327 可并行在 src/server 清空后同批落地。

---

## 来源

- 本蓝图：`reports/2026-10-20-r17-bug347-fix-blueprint.md`
- 实证探针：`memory/bug347_external_pattern_probe.json`
- 实证源：R16 报告 `reports/2026-10-20-r16-denoise-rules-v2-and-bug347.md`
- 待修规则位置：`src/server/issue_scan.mbt` L259（json-injection）、L287（resource-leak）