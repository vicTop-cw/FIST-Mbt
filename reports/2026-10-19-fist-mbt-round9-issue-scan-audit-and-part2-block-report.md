# Round 9 · 寻虫审计 + CI 覆盖核验 + BUG-327 part 2 阻塞定位

- **时间**：2026-10-19 11:10（Asia/Shanghai）
- **模式**：寻虫 / 验证 / 清整（Round 9 / 256）
- **HEAD**：334b0de（Round 8）
- **结论**：dogfood `issue_scan` 全仓寻虫（9923 命中，high/medium = 0，稀有命中逐条验证为噪声）；核验 `check_badge` 确在 CI 覆盖（Round 8 修复是必要的）；精确定位 BUG-327 part 2 的阻塞为「提交 server.mbt 会连带并发 agent 未提交的 omega evidence 特性」，而非笼统的「文件脏」。

---

## 1. 并发 agent 收口状态

| 项 | 状态 |
|---|---|
| 新提交 | `2761c39 fix(cli): native 目标 argv 偏移 + sqlite 链接` |
| 未提交文件数 | 17 → **14** |
| `src/omega/*` | **已干净**（`moon.pkg` / `omega_tool.mbt` / `omega_tool_test.mbt`） |
| `src/server/server.mbt` | **仍 M**（diff 在 `omega_verify_fix` 区 5444-5473） |
| `src/server/issue_scan_wbtest.mbt` | 内容 == HEAD（diff --stat 不列，仅 EOL/stat 差异） |

---

## 2. BUG-327 part 2 阻塞定位（本轮新证据）

### 2.1 关键事实

并发 agent 的 `server.mbt` 未提交 diff（6+/2-）**完全在 `omega_verify_fix` 区（5444-5473）**，把 `@omega.batch_verify_fix` 换成 `@omega.verify_fix_with_evidence`（接 omega evidence 三轮真实修复引擎，`failed_results` 仅兼容展示）。

**require_ocr 区（2859-2879 / 2977-2993）未被并发 agent 触碰**。

### 2.2 精确结论

- **编辑安全**：在 2859 / 2977 加 `.mbt` 可审性 fail-closed **无冲突风险**（并发 agent 不碰该区）。
- **提交不安全**：`git add src/server/server.mbt` 会把并发 agent 未提交的 omega evidence 特性一并带进我的 commit——我不拥有那段改动、不确定其 wbtest 覆盖 ⇒ **不能替并发 agent 提交**。

这是「编辑安全 ≠ 提交安全」的边界，比笼统的「server.mbt 脏」更精确，也说明 part 2 的解锁条件是 **并发 agent 先提交 server.mbt**（不是等它收口全仓）。

### 2.3 建议解锁路径

1. 并发 agent 提交 `server.mbt`（含 omega evidence 特性）后，`src/server/server.mbt` 转干净。
2. 我即可编辑 2859 / 2977 加：`ocr_probe_binary` 返回 Some 后，追加 `ocr_reviewability_check(project_dir)`（MoonBit-only 项目 → `available:false` + `reviewable:false` + note），使 `available:true` 不再等于「OCR 会真跑」。

---

## 3. CI 覆盖核验（Round 8 盲区的定性）

### 3.1 确认

`.github/workflows/ci.yml` 显式包含：

```
run: python3 scripts/check_badge.py /tmp/moon_test.log README.md
```

同文件含 8 处守卫引用（`check_publish_payload` / `check_tools_sync` / `check_test_sync` / `check_badge` / `check_plugin_sync` / `check_doc_surface` / `check_scripts_index` 等）。

### 3.2 定性

- **徽章陈旧若未修，下次 push 就 CI 红** ⇒ Round 8 的 `1108→1334` 修复是**必要的**，非装饰。
- **盲区纯属本地漏跑 check_badge**（我 Round 5/6/7 只跑 check_test_sync）。CI 没漏。
- 根目录 `ci.yml` 不存在；真源在 `.github/workflows/ci.yml`（我 Round 8 先在根目录找，找不到是路径错）。

---

## 4. 寻虫审计（dogfood `issue_scan`）

### 4.1 总览

`issue_scan dir=src` → 129 文件 / **9923 命中 / high=0 / medium=0 / low=9923**（truncated=true）。

分布（全部低/信息级）：

| 规则 | 计数 | 定性 |
|---|---|---|
| moonbit-unused-variable | 4258（info） | 子串近似 let 声明点，编译期已查 |
| moonbit-match-exhaustive | 1513（low） | Option/match 穷尽性编译期保证，子串提示性 |
| moonbit-json-injection | 1409（low） | 拼接构造的提示，大量误报 |
| moonbit-long-function | 1446（info） | 子串近似 fn 定义行 |
| moonbit-shared-mutable | 465（low） | 派生不回写，提示性 |
| moonbit-array-index-bounds | 159（low） | 数组下标无守卫，多为有前置 length 校验 |
| 其它 | ~600 | result-discard 275 / private-field-leak 90 / empty-match 109 / overly-broad-catch 87 / race-condition 9 / resource-leak 7 / dead-code 6 / float-eq 2 |

### 4.2 稀有真信号逐条验证

| 命中 | 验证结果 |
|---|---|
| **浮点 `==`**（critic.mbt:69 `score == 0.5`；lesson.mbt:39 `score == 0.0`） | **哨兵 idiom 非精度 bug**：`0.5` 表示「未计分」→ 走 novelty；`0.0` 表示「未传默认值」。这是合法用途（与字面哨兵比，非精度敏感计算）。 |
| **abort 死代码**（claimguard_wbtest:1036/1259、cost_tool_test:18/31/50、dag_ext_test:716） | 全在**测试文件**；「下一行」是 match 续行（`,` / `_ => abort(...)`），非真不可达。issue_scan 默认 `include_tests=false` 却不排除 `_test.mbt`——此为本轮可改进点（见 §4.4）。 |
| **result-discard 275**（`.ignore()`） | MoonBit `ignore(expr)` 是 fire-and-forget 的**意图 idiom**，非吞错（编译期 Result 非丢弃不报错，但意图明确）。 |
| **resource-leak 7** | 未在 src 找到 `File::open` 实例（无打开未关闭的裸资源）。 |
| **race-condition 9** | 跨 async 共享可变态的提示，await 使用点，未发现确定性交错缺陷。 |

### 4.3 结论

**issue_scan 是启发式分诊工具**：9923 命中里 high/medium = 0，产品代码无启发式高危命中（真高危须 OCR LLM review / 人工复核）。稀有命中逐条验证后**无一为真实缺陷**——这本身是正面的健康信号，而非「一堆 bug 未修」。

### 4.4 本轮可改进点（未做，留建议）

issue_scan 默认 `include_tests=false` 却不排除 `_test.mbt` / `_wbtest.mbt` 文件本身——abort 死代码命中全落在测试文件里就是证据。建议下轮在扫描层把 `_test.mbt` / `_wbtest.mbt` 文件整体跳过（与 `include_tests` 参数语义对齐）。`src/server/issue_scan.mbt` 目前干净可编辑；但 `issue_scan_wbtest.mbt` 是并发 agent 文件（内容 == HEAD，仅 EOL），动规则前需确认其锁期望。

> **⚠️ 更正（Round 10，2026-10-19 11:13）**：本节为**误判**，正式撤回。`issue_scan.mbt:1639-1640` `scan_collect` 已在 `include_tests=false` 时跳过 `_test.mbt`/`_wbtest.mbt`；`issue_scan dir=src/claimguard`（默认）返回 `scanned_files:1`、命中全为 `claimguard.mbt`，测试文件被正确排除。abort 候选来自我自己的 PowerShell grep，非扫描器输出。**issue_scan 本身无此问题。** 详见 `reports/2026-10-19-fist-mbt-round10-correction-and-array-index-audit-report.md`。

---

## 5. 守卫窄面复核（为何不做）

`scan_guard_substring_end_var`（issue_scan.mbt:697）已含 BUG-164 双形态：
- **B**：`if <end_var> > start` / `>= start`（start ≥ 1 时）
- **C**：`start == 0 && <end_var> <= target.length()`

遗留 FP（`substring(start=n-n%k, end=n)` / `start=p, end=p+2`）**在本仓零实例** ⇒ 为 0 实例加算术端识别规则属推测性增码，会让守卫更复杂而无实际收益。**不做**，符合「不为不存在的问题加复杂度」。

---

## 6. 资源消耗

- 门禁/扫描：`issue_scan`（129 文件 / 9923 命中）、CI 覆盖 grep、并发 diff 审阅
- 稀有命中逐条验证：浮点 `==` 2 处、abort 死代码 6 处、resource-leak grep
- 记忆：`memory/2026-10-19.md` 追加 Round 9 段
- 报告：`reports/2026-10-19-fist-mbt-round9-issue-scan-audit-and-part2-block-report.md`

---

## 7. 遗留风险

1. **BUG-327 part 1 未上线**：源码已修（5dcdaaa），但 `dist/fist-mbt.js` 未重建（停在 2026-10-18），运行中 server 顶层 `ok` 对 `.mbt` 假绿仍 `true`。需从干净 HEAD 重建（不能等并发 WIP 收口后再建——应建在并发 agent 提交稳定点）。
2. **BUG-327 part 2 阻塞**：需并发 agent 先提交 `server.mbt`（解锁条件已精确定位）。
3. **P1 发布载荷面**仍红：并发 agent `src/evidence/` 5 文件 + 3 脚本未跟踪又未 ignore，`moon publish` 会公开。凭据形状 0 命中。等用户裁决。
4. **全仓 `moon fmt --check`** 仍 rc=-1（并发 agent WIP），并发收口后需重排。
5. **issue_scan 未排除 `_test.mbt`**（§4.4），下轮可改。

---

## 8. 后续建议

1. **并发 agent 提交 `server.mbt` 后** → 立即做 BUG-327 part 2（§2.3 路径）→ 从干净 HEAD 重建 dist（part 1 上线）→ 关 BUG-327 FIXED。
2. **下轮**：`issue_scan` 扫描层排除 `_test.mbt` / `_wbtest.mbt` 文件本身（与 `include_tests` 对齐）。
3. **待用户裁决**：① `15fe403` 撤回；② BUG-268 标号错配；③ `src/evidence/` untracked（牵连 P1）。

---

## 9. 来源

- 工具回执：`issue_scan`（dir=src，129 文件 / 9923 命中 / 0 high / 0 medium）
- 代码：`src/server/server.mbt`（只读 diff 5444-5473）、`src/server/issue_scan.mbt`（只读 690-744）
- CI：`.github/workflows/ci.yml`（grep `check_badge` 等 8 处守卫）
- 稀有命中逐条验证：`critic.mbt` / `lesson.mbt` / `claimguard_wbtest.mbt` / `cost_tool_test.mbt` / `dag_ext_test.mbt`