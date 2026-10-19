# Round 11 · 权威门禁绿 + 徽章仍正确 + 寻虫盲区根因定位

- **时间**：2026-10-19 11:23（Asia/Shanghai）
- **模式**：验证 / 清整（Round 11 / 256）
- **HEAD**：ea0779e（Round 10）
- **结论**：权威门禁 `moon test --target js` = **1337/1337 绿**（工作树含并发 WIP，零回归）；徽章 1334 **仍正确**（334b0de..HEAD 未动测试文件）；定位「多轮寻虫找不到真 bug」的结构性根因是 BUG-327（.mbt OCR 不可用 = 本仓唯一语义 bug 检测能力缺失）。

---

## 1. 权威门禁绿（零回归确认）

```
Total tests: 1337, passed: 1337, failed: 0
```

- 1334 → 1337（+3 来自并发 agent **未提交**的 omega evidence 测试）。
- 判绿以 `Total tests: N, passed: N, failed: 0` 汇总行为准（BUG-142：`moon test` 退出码不可靠）。
- 含义：① 我的 Round 5~10 改动零回归；② 并发 agent 未提交特性可编译且全绿。

## 2. 徽章仍正确（无需改动）

- `git diff --name-only 334b0de..HEAD`（我 Round 8 修复徽章至今）**未动任何 `_test.mbt`/`_wbtest.mbt`**。
- ⇒ 已提交测试数仍 = **1334** = 徽章 1334。**正确。**
- 工作树 1337 的 +3 是并发 agent 未提交测试；其提交时需把徽章升到 1337（其责，我不代改）。

## 3. 并发 agent 状态

| 项 | 状态 |
|---|---|
| HEAD | ea0779e，并发 agent 未提交新 commit |
| 最近 commit | `2761c39` 只动 `cmd/cli/main.mbt`（36+、2 files、无测试） |
| `src/server/server.mbt` | **仍 M** |
| 未提交总数 | **14**（未变） |
| `moon test --target js` | 1337/1337 绿 |

**BUG-327 part 2 仍阻塞**：`server.mbt` 未收口。

## 4. 寻虫盲区根因定位（本轮新洞察）

### 4.1 事实

- `issue_scan` 的规则用**字面子串 pattern**：`moonbit-array-index-bounds` 为 `pattern: ["[i]", "[idx]", "[index]", "[k]"]`（issue_scan.mbt:217）。它匹配"行里含 `[i]`"，是粗粒度提示器。
- 语义层（真正的 bug 判定）在 `ocr_scan`（OCR LLM review）。而 **BUG-327**：OCR 对 `.mbt` 文件 `unsupported_ext` 全排除，`require_ocr` 门因此对 MoonBit 项目失效。

### 4.2 推论

**本仓唯一的语义 bug 检测能力（`.mbt` OCR）是坏的。** 这正是我 Round 5~11 多轮 `issue_scan` 寻虫「找不到真 bug」的**结构性根因**——不是「项目无 bug」，而是**语义检测通道不存在**，只剩粗粒度模式提示。

### 4.3 优先级

修复 BUG-327（dist 上线 part 1 + server.mbt 接 part 2）**才是恢复真实寻虫闭环的头号动作**，优先级高于任何零散噪声优化（array-index / 守卫窄面等）。这也是为什么 Round 9/10 的审计结论都指向"扫描器按设计工作"——它确实只是提示器。

## 5. 为何本轮不重建 dist

- `moon build --target js cmd/cli` 从**当前工作树**构建 → 会把并发 agent 未提交的 omega 代码一起打进 `dist/fist-mbt.js`（不合法，我不能发布他人的未提交工作）。
- 从干净 HEAD worktree 构建 → 需重下 `.mooncakes`（分钟级）+ 重打 `patches/sqlite-bug133/reapply.sh`（依赖侧补丁，BUG-133），风险高、验证受限（重启 server 会断自己的工具面）。
- ⇒ **风险>收益**，留到并发 agent 收口后、`server.mbt` 干净时一并做（part 1 + part 2 一起上）。

## 6. array-index-bounds 定论

`pattern` 是字面子串（`[i]` 等），**扫描器按设计是提示器**，非 bug 判定、无可修。Round 10 的"有界循环安全"结论成立，本轮补上根因（pattern 机制）。

## 7. 资源消耗

- 门禁：`moon test --target js` 全量（1337/1337）
- 核对：`git diff --name-only 334b0de..HEAD`、`git show 2761c39 --stat`、`issue_scan.mbt:215-220`
- 记忆：`memory/2026-10-19.md` 追加 Round 11 段
- 报告：`reports/2026-10-19-fist-mbt-round11-gate-green-and-scan-blindspot-report.md`

## 8. 遗留风险

1. **BUG-327 part 1 未上线 + part 2 阻塞**——本仓寻虫闭环头号阻塞，需并发 agent 先提交 `server.mbt`。
2. **并发 agent 未提交测试 +3**：其提交时徽章须升 1337（其责）。
3. **P1 发布载荷面**仍红（`src/evidence/` 等），等用户裁决。
4. **全仓 `moon fmt --check`** 仍 rc=-1（并发 WIP）。
5. 本轮未改任何 `.mbt` → 无需 fmt / 额外门禁（零回归已由 1337/1337 佐证）。

## 9. 后续建议

1. **并发 agent 提交 `server.mbt` 后** → 从干净 worktree 重建 dist（part 1 上线）→ 接 part 2 → 关 BUG-327 FIXED。这是恢复寻虫闭环的关键路径。
2. 在此之前，寻虫只能靠 `issue_scan` 粗粒度提示 + 人工/OCR 复核，无法自动语义检测。

## 10. 来源

- 门禁：`moon test --target js`（Total tests: 1337, passed: 1337, failed: 0）
- 代码：`issue_scan.mbt:215-220`（array-index-bounds pattern 字面子串）、`scan_collect` 1639-1640
- Git：`git diff --name-only 334b0de..HEAD`（空=未动测试）、`git show 2761c39 --stat`