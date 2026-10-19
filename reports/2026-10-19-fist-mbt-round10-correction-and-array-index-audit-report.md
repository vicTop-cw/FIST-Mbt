# Round 10 · 更正 Round 9 §4.4 误判 + 数组下标审计收口

- **时间**：2026-10-19 11:13（Asia/Shanghai）
- **模式**：验证 / 清整（Round 10 / 256）
- **HEAD**：1e7c5b4（Round 9）
- **结论**：实证证伪 Round 9 §4.4 的"可改进点"（issue_scan 本就正确排除测试文件），并完成 claimguard 数组下标审计——6 处命中全为有界循环安全，扫描器按设计工作。诚实更正已落档。

---

## 1. 更正 Round 9 §4.4（诚实优先）

### 1.1 误判原文

Round 9 §4.4 声称：

> issue_scan 默认 `include_tests=false` 却不排除 `_test.mbt`/`_wbtest.mbt` 文件本身——abort 死代码命中全落测试文件即证据。建议下轮在扫描层把 `_test.mbt`/`_wbtest.mbt` 文件整体跳过。

### 1.2 证伪证据

**代码**：`src/server/issue_scan.mbt:1639-1640` `scan_collect`：

```mbt
} else if p.has_suffix(".mbt") {
  if include_tests || not(scan_is_test_file(p)) {
    out.push(p)
  }
}
```

`scan_is_test_file`（1609-1611）：`p.has_suffix("_test.mbt") || p.has_suffix("_wbtest.mbt")`。⇒ `include_tests=false`（默认）时**已跳过**测试文件。

**实证**：`issue_scan dir=src/claimguard`（默认 include_tests=false）→ `scanned_files:1`，全部命中为 `src/claimguard/claimguard.mbt`，`claimguard_wbtest.mbt` **被正确跳过**。

### 1.3 根因

Round 9 的 abort 候选（`claimguard_wbtest.mbt`/`cost_tool_test.mbt`/`dag_ext_test.mbt`）来自我自己的 PowerShell `Select-String` 全局 grep，**不是 `issue_scan` 的输出**。我把两个不同来源的结果混为一谈，得出"扫描器不排除测试文件"的错误结论。

### 1.4 更正

**`issue_scan` 本身无此问题，Round 9 §4.4 撤回。** 该建议不成立，不需要"下轮改"。

---

## 2. 数组下标审计收口（array-index-bounds）

`claimguard.mbt` 6 处 `array-index-bounds` 命中逐条验证：

| 行 | 代码 | 上下文 | 判定 |
|---|---|---|---|
| 445 | `let a = states[i]` | `for i=0; i<states.length(); i=i+1` | 有界安全 |
| 665 | `let e = es[i]` | 同上（es 长度上界） | 有界安全 |
| 690 | `let e = es[i]` | 同上 | 有界安全 |
| 1001 | `negotiate_plan(remaining[i],…)` | `for i=0; i<remaining.length(); i=i+1` | 有界安全 |
| 1015 | `remaining[i] < remaining[best]` | 同循环；`best` 来自循环内合法下标 | 有界安全 |
| 1055 | `rem2.push(remaining[i])` | `for i=0; i<remaining.length(); i=i+1` | 有界安全 |

**结论**：6 处全为 **C 风格有界循环**，无一越界。

### 2.1 为什么扫描器照报

`scan_guard_for_bounded`（issue_scan.mbt:907）只识别：
- 形态：`for <v> in 0..<N`（MoonBit range 迭代）
- 条件：N 为**数字字面量**；目标 `vn` 为 **String 字面量**（用于 string-index / substring 上下文）

它**不识别** C 风格 `for i = 0; i < arr.length(); i = i + 1` 的**数组**循环（界是 `arr.length()` 而非字面量，目标是数组变量而非字符串）。

### 2.2 这是不是 bug？

**不是**。`array-index-bounds` 是 severity=low 的启发式分诊提示，hint 原文是「用 `get(i)` Option 语义或先 `length()` 校验」——它的任务是**把待人工核对的点位交出来**，不是断言越界。`for i=0; i<arr.length()` 是标准安全写法，扫描器无法静态确定、提示核对，属**按设计工作**。

### 2.3 为何不修（本轮）

1. **低危分诊提示**，非布尔门（不像 `check_badge` 会红/绿），误报成本是"人工扫一眼"，不产生错误结论。
2. 修它要动 `issue_scan.mbt` 规则评估 + 新增 C-for 守卫，而 `issue_scan_wbtest.mbt` 是并发 agent 文件（内容==HEAD，锁期望未知），风险大于收益。
3. 全仓 159 处 `array-index-bounds` 应同此解释（绝大多数为有界循环提示）。

留作可选优化，**不擅动**。

---

## 3. 并发 agent 状态

| 项 | 状态 |
|---|---|
| HEAD | 1e7c5b4（Round 9），并发 agent 未提交新 commit |
| `src/server/server.mbt` | **仍 M**（omega evidence 特性未提交） |
| 未提交总数 | **14**（未变） |
| `src/omega/*` | 干净 |

**BUG-327 part 2 仍阻塞**：`server.mbt` 未收口。

---

## 4. 资源消耗

- 代码核对：`issue_scan.mbt:1603-1647`（scan_collect / scan_is_test_file）、`issue_scan.mbt:905-964`（scan_guard_for_bounded）、`claimguard.mbt:438-451 / 995-1056`
- 实证：`issue_scan dir=src/claimguard`（scanned_files:1，仅 claimguard.mbt）
- 记忆：`memory/2026-10-19.md` 追加 Round 10 更正段
- 报告：`reports/2026-10-19-fist-mbt-round10-correction-and-array-index-audit-report.md`

---

## 5. 遗留风险

1. **BUG-327 part 1 未上线**（dist 未重建）；**part 2 阻塞**（server.mbt 未收口）。解锁条件不变。
2. **P1 发布载荷面**仍红（`src/evidence/` 等未跟踪又未 ignore），等用户裁决。
3. **全仓 `moon fmt --check`** 仍 rc=-1（并发 agent WIP）。
4. 本轮未改任何 `.mbt` → 无需 fmt / 测试门禁（增量零回归）。

---

## 6. 后续建议

1. 并发 agent 提交 `server.mbt` 后 → 立即做 BUG-327 part 2 → 从干净 HEAD 重建 dist → 关 BUG-327 FIXED。
2. array-index-bounds 的 C-for 识别：若后续要做，须先确认 `issue_scan_wbtest.mbt` 锁期望（可先在**新** wbtest 文件加锁，不碰并发文件）。

---

## 7. 来源

- 代码：`src/server/issue_scan.mbt`（只读 1603-1647、905-964）、`src/claimguard/claimguard.mbt`（只读 438-451、995-1056）
- 实证：`issue_scan dir=src/claimguard`（scanned_files=1 / 仅 claimguard.mbt / 163 命中 low）
- 前序：Round 9 报告 §4.4（本次撤回）