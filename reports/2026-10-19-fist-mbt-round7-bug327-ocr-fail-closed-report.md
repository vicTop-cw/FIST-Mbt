# Round 7 · BUG-327 part 1 · ocr_scan 顶层 `ok` 对假绿 fail-closed

- **时间**：2026-10-19 10:31（Asia/Shanghai）
- **模式**：打磨/寻虫/修复（Round 7 / 256）
- **HEAD**：181c7e3（Round 6）
- **结论**：BUG-327 part 1 修复落地并全量验证；part 2 因并发 agent WIP 留待下轮，账本诚实保持 OPEN。

---

## 1. 结果摘要

| 判据 | 结果 |
|---|---|
| `moon test --target js` | **Total tests: 1334, passed: 1334, failed: 0**（rc 0） |
| 测试增量 | 1333 → **1334**（+1 = 新增对抗锁 `BUG-327_ocr_effective_ok_fail_closed_on_fake_green`） |
| `check_test_sync.py temp/mt7.log` | **PASS**（实测 1334，扫描 121 份文档，16 声明全部等于实测；must-carry 5 齐全；25 豁免有效；rc 0） |
| `moon fmt --check`（我改动的 2 文件） | **rc 0**（"no work to do"） |
| `memory/bugs.md` | **未改** → 无 `gen_plugins.py` 再生需求，cl7 不受影响 |
| BUG-327 | **OPEN**（part 1 完成，part 2 待下轮） |

---

## 2. BUG-327 part 1：ocr_scan 顶层 `ok` fail-closed

### 2.1 改动（`src/server/ocr_scan.mbt`，13+/1-）

新增纯函数（置于 `ocr_scan_impl` 之前）：

```moonbit
pub fn ocr_effective_ok(okk : Bool, reviewed : Bool) -> Bool { okk && reviewed }
```

在 `ocr_scan_impl` 的 `Ok(j)` 分支：

```moonbit
// 改前：("ok", Json::boolean(okk))
// 改后：
let ok_eff = ocr_effective_ok(okk, reviewed)
("ok", Json::boolean(ok_eff))
```

`reviewed` 由 `ocr_fake_green_check(stdout)` 在 `subcmd == "scan" || "files"` 时给出（真审到内容才 true），否则 `(true, "")`。

**语义变化**：顶层 `ok` 从「进程退出码 0 = 成功」变为「退出码 0 **且** 确有 reviewable 内容」。这正是 BUG-327 账本（L5488）给出的「建议修复方向」第一条——`reviewable_count=0` 的 `.mbt` 全拦场景下 `ok=false` + `fake_notice` 明确提示，杜绝只看 `ok` 的门禁把假绿读成「已 review」。

### 2.2 对抗锁（`src/server/ocr_scan_wbtest.mbt`，11+）

```moonbit
test "BUG-327_ocr_effective_ok_fail_closed_on_fake_green" {
  assert_false(ocr_effective_ok(true, false))  // 假绿 → fail-closed
  assert_true(ocr_effective_ok(true, true))    // 真审到 → ok
  assert_false(ocr_effective_ok(false, true))  // 进程失败 → 仍失败
  assert_false(ocr_effective_ok(false, false))
}
```

四断言覆盖真值表全 4 组合，锁死「假绿必须 fail-closed」这条不变量；若被改回 `ok = okk`（BUG-327 前的假绿行为），第一断言必红。

**踩坑**：首版误写 `assert_false(x, "msg")`（双参），MoonBit 的 `assert_false`/`assert_true` 只收单参 → 编译错、`moon test` rc=1；改为单参后通过。`moon fmt` 重排后触发一次 `FS_STALE_VERSION`，重读后重试成功。

---

## 3. docs 同步：8 文件 32 处 1333→1334

| 文件 | 替换处数 |
|---|---|
| README_EN.md | 12（徽章 / 命令注释 / 套件规模 / 守卫描述等） |
| README.md | 7 |
| AGENTS.md | 4 |
| ARCHITECTURE.md | 2 |
| README.mbt.md | 2 |
| docs/deliverable.md | 2 |
| scripts/scoring_rubric.md | 2 |
| docs/agent-map.md | 1 |

脚本 `temp/sync1334.py` 精确替换，**跳过** `memory/`（历史记录）、`reports/`（历史记录）、`dist/fist-mbt.js`（内部常量）。替换后抽查 `README_EN.md` diff 确认 12 处全为合法测试数声明（徽章 URL / `Total tests:` 注释 / `1334-test JS suite` / `check_test_sync (1334 aligned)` / native 门槛引用），无误伤。

`check_test_sync` 首跑红（文档 1333 ≠ 实测 1334）→ 同步 → 复跑 **PASS**，判据正确工作。

---

## 4. 为什么 BUG-327 保持 OPEN（诚实标注）

账本 L5488 给的是**二选一**建议方向，part 1 已实现第一条（fail-loud `ok=false`）。但 L5477 摘要同时点名「bugfind 的 `require_ocr` 门是伪能力/可静默满足」——`server.mbt:2859-2879` 的 `require_ocr` 预检目前**仍只探 OCR 二进制可达性**（`ocr_probe_binary`），不含「`.mbt` 是否真的可审」这一维：

- part 1 修的是**工具层**：真调 `ocr_scan` 的调用方现在会看到 `ok=false`。
- part 2 修的是**门禁层**：`require_ocr` 预检仍会在 `.mbt` 全拦时静默放行 bugfind。

**为何本轮不做 part 2**：`src/server/server.mbt` 已被并发 agent 修改（`git status` 显示 `M`，8 行，非我改动；其 `src/omega/*` 亦有 207 行 WIP）。共享文件改动与并发 agent 冲突风险高，且我无法确认该 `M` 是否为对方未完成的编辑。故 part 2 留待并发收口后下一轮独立处理。

`memory/bugs.md` 本轮**未改** → 未触发「加 bug 账必带 `gen_plugins.py` 再生」的连锁，cl7 不受影响。

---

## 5. 并发 agent 隔离

| 文件 | 状态 | 归属 | 本轮处理 |
|---|---|---|---|
| `src/server/ocr_scan.mbt` | `M` 13+/1- | **我** | ✅ 纳入提交 |
| `src/server/ocr_scan_wbtest.mbt` | `M` 11+ | **我** | ✅ 纳入提交 |
| `src/server/server.mbt` | `M` 8 | 并发 agent | ⛔ 未触碰 |
| `src/omega/omega_tool.mbt` | `M` 207+ | 并发 agent | ⛔ 未触碰 |
| `src/omega/moon.pkg` | `M` | 并发 agent | ⛔ 未触碰 |
| `src/evidence/*` + 3 scripts | untracked | 并发 agent | ⛔ 未触碰（等用户裁决） |

全仓 `moon fmt --check` 的 rc=-1 源于并发 agent 的 `src/omega/omega_tool.mbt`（`git --no-index` diff 失败），pre-existing，非本轮引入；只对我改动文件单独跑 fmt --check = **rc 0**，满足 commit 门禁实际覆盖面。

---

## 6. 资源消耗

- 代码改动：2 文件 24 行（13+/1- + 11+）
- 文档同步：8 文件 32 处
- 记忆：`memory/2026-10-19.md` 追加 Round 7 段
- 临时脚本：`temp/sync1334.py`（同步后删除）、`temp/mt7.log`（测试日志，check_test_sync 已消费）

---

## 7. 遗留风险

1. **BUG-327 part 2**（`require_ocr` 门只探二进制可达性）**未修**，账本 OPEN，等并发收口后下一轮。
2. **P1 发布载荷面仍红**（rc=1）：并发 agent `src/evidence/` 5 文件 + `scripts/_gen.py`/`fix_esm_require.py`/`pol_keeper_run.py` 未跟踪又未 ignore ⇒ `moon publish` 会公开。凭据形状 0 命中（纯 P1 源码公开，非 P2 秘密泄漏）。等用户裁决。
3. **全仓 fmt --check** 被并发 agent `src/omega/omega_tool.mbt` WIP 挡住（pre-existing，rc=-1）；并发收口后需重排一次恢复 fmt 门强度。
4. **3 项用户裁决未动**：① `15fe403` 撤回 `git reset --soft HEAD~1`？② BUG-268 summary 与 15fe403 标号错配（substring FP 修复是否应独立 bug 号）？③ `src/evidence/` 入库还是进 `.gitignore`？

---

## 8. 后续建议

- 并发 agent 收口 `server.mbt`/`omega_tool.mbt` 后：补 BUG-327 part 2（`require_ocr` 增加 `.mbt` 可审性 fail-closed 判据），可把 BUG-327 关进 FIXED。
- 处理 P1 发布载荷面（等用户裁决方向）。
- 守卫窄面遗留（`substring(start=n-n%k,end=n)` / `start=p,end=p+2` 仍误报，本仓零实例）：可在下一轮做 TP 锁或收窄规则。

---

## 9. 来源

- 代码：`src/server/ocr_scan.mbt`、`src/server/ocr_scan_wbtest.mbt`
- 记忆：`memory/2026-10-19.md`（Round 7 段）
- 账本：`memory/bugs.md` L5476-5490（BUG-327，本轮未改）
- 测试日志：`temp/mt7.log`
- 同步脚本：`temp/sync1334.py`