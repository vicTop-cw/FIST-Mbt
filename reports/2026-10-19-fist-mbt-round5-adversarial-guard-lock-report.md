# Round 5 · 对抗守卫锁 · 报告

> 组合模式 [打磨·寻虫·修复·验证·清整·推进] · 全程使用 fist-mbt 自驱能力 · 2026-10-19

## 结果摘要

**守卫族「非 catch-all」性质被永久锁定**：新增 `src/server/issue_scan_adversarial_wbtest.mbt` 5 条对抗锁（4 真阳性 + 1 正控），
`moon test --target js` 从 1328 → **1333 / 1333 / 0**，权威门全绿；`check_test_sync` 同步转 PASS。

## 证据（独立复跑，非自述）

| 判据 | 结果 |
|---|---|
| `moon fmt --check` | rc 0 |
| `moon test --target js` | **Total tests: 1333, passed: 1333, failed: 0**（rc 0） |
| `scripts/check_test_sync.py temp/mt2.log` | **PASS**（实测 1333，扫描 121 份文档，16 声明全部等于实测；must-carry 5 齐全；豁免 25 条有效；rc 0） |

## 交付物

### 1. 5 条对抗守卫锁（`src/server/issue_scan_adversarial_wbtest.mbt`，84 行）

把 lint_14 那「单点真阳性负锁」扩展为 5 条成对锁，锁死守卫的**边界语义**而非仅锁一条样本：

| 锁 | 守卫形状 | 期望 | 断言 |
|---|---|---|---|
| A `adv_guard_mod_runtime_k_not_exempted` | `% runtime_k`（非常量 K） | 仍命中 | `assert_false(guarded)` |
| B `adv_guard_mod_negative_shift_not_exempted` | `(n - x) % k` | 仍命中 | `assert_false(guarded)` |
| C `adv_guard_find_plus_offset_not_exempted` | `find(...)+offset` 作 start | 仍命中 | `assert_false(guarded)` |
| E `adv_guard_wrong_var_length_not_exempted` | 多行守卫但比较的是**错变量** `u` | 仍命中 | `assert_false(guarded)` |
| 正控 `adv_guard_positive_control_still_exempts` | 同形状、变量正确（`end > 3`）/ 错误（`other > 3`） | 前者豁免、后者不 | 前者 `true`、后者 `false` |

**意义**：守卫的豁免条件是「具体白名单模式 + 精确变量匹配」，不是「附近有 `if <x> < end` 就当安全」。
若守卫被改成 catch-all，A/B/C/E 必有一发转 true → 测试红，立即被 CI 抓住。

### 2. 8 份文档测试数 1328 → 1333 同步

`check_test_sync` 首跑红（16 处声明 1328 ≠ 实测 1333）→ 精准替换（跳过 `dist/fist-mbt.js` 内部常量、`BACKLOG.md` 的 commit 哈希 `9f13284`）→ 判据转绿。

### 3. OCR 双轨对 MoonBit 惰性确认 → BUG-327 + 修复单

- `ocr_scan` 对 `.mbt` 恒 `unsupported_ext`（`opencodereview.exe` 硬编码扩展白名单不含 `.mbt`，无 CLI/config 逃逸口）。
- BUG-327 已上报（OPEN），修复单 T0r588 已发布到 ns `bugs`。
- 已确认 BUG-327 非 BUG-165 重复：BUG-165 已通过 `ocr_reviewed=false` + `notice` 暴露假绿；BUG-327 的残余价值 =
  `require_ocr` 门只探二进制可达性（不验 MoonBit 可审性）+ 顶层 `ok` 在假绿时仍为 true。修复单已带此区分。

## 资源消耗

- 子进程：`moon fmt` / `moon fmt --check` / `moon test --target js` ×2 / `check_test_sync` ×2。
- 无外部 API、无 OCR 二进制调用（已判定不可用即不再起进程）。

## 任务分配记录

- 全程 Lead 自跑（轻任务面：单文件新增 + 机械文档同步），未派子代理——本轮改动面窄、验证链路单一。
- 复用 fist-mbt 自身能力做判据：`issue_scan`（扫描守卫族）、`ocr_scan`（OCR 可行性）、`check_test_sync`（文档同步）、`report_bug` + `publish_task`（BUG-327 闭环）。

## 遗留风险

1. **守卫「窄而不漏」的另一面**：安全写法 `substring(start = n - n % k, end = n)`（正控）与 `start = p, end = p + 2` 仍被守卫规则放过——
   本仓**零实例**，故未作 TP 锁；若未来有人写这种代码，会误报（守卫窄、规则宽）。已在测试文件头注释注明。
2. **15fe403 撤回 / BUG-268 标号错配 / `src/evidence/` untracked**：三项均**等用户裁决**，未动。
3. **`require_ocr` 门形同虚设**（探二进制而非验 MoonBit 可审性）——BUG-327 修复单 T0r588 在 `bugs` ns，待认领。

## 后续建议

1. 修复单 T0r588（OCR MoonBit 可行性 + `require_ocr` 门语义）可由自驱流水线认领，或由用户裁决是否纳入下一轮。
2. 若要让守卫覆盖「安全写法」免误报，建议新增 `scan_guard_end_var_exact`（要求守卫比较变量 == end 变量），并配正/负控锁。
3. 三项等裁决事项尽快收口，避免 `src/evidence/` 长期 untracked 触发 `check_publish_payload` 红面。

## 超额内容

- 无计划外功能；仅把「验证」升级为「永久测试锁」，属打磨收尾的自然延伸。

## 来源

- 守卫族实现：`src/server/issue_scan.mbt`（`scan_guard_*` 族 + 既有 `issue_scan_wbtest.mbt` 正/负控锁）
- 对抗样本：`temp/adversarial/guard_adversarial.mbt`（本轮探测用，已清理）
- 新增锁：`src/server/issue_scan_adversarial_wbtest.mbt`
- OCR 惰性证据：`src/server/ocr_scan.mbt`（`ocr_fake_green_check` L321、扩展名白名单）
- 账本：`memory/bugs.md` BUG-327
- 修复单：ns `bugs` T0r588