# R6 · `check_test_sync` 同步任务 · 停手记录 + 机制缺口入账 · 2026-10-26

> **本单状态：按统帅裁决 A「等收口」，未改任何 `.md`。**
> 本报告交付的是：①机制缺口 `BUG-425` 入账 ②`(a)` 方案可行性的判定读数 ③徽章与实际值的差异。

---

## 一、结论

| 项 | 结果 |
|---|---|
| 实测总数 | **1505**（首跑）→ **1510**（`check_badge --fresh` 真跑时）；**工作树仍在变** |
| 是否按 1505 改 17 处 `.md` | **未改**（统帅裁决 A：等 12 个在途文件收口）|
| 机制缺口 | **已入账 BUG-425**（`check_test_sync` 并发期天然假红）|
| `(a)` 读 HEAD 数行方案 | ❌ **实测不精确**（`^test` 行 1506 vs 实测 1505，差 1）|
| 徽章 | **已过期**：README `1463/1463` vs 实测 **1510/1510**（未改，等收口）|

---

## 二、证据

### 2.1 停手依据：实测总数超阈值且不稳定

```
$ python scripts/moon_test_env.py --target js
汇总：Total tests 1505 / passed 1505 / failed 0
Total tests: 1505, passed: 1505, failed: 0.        rc=0
```

判绿以**汇总行**为准（不信 `exit 0`，BUG-142）。

| 基线 | 首跑 | 稍后（`--fresh` 真跑）|
|---|---|---|
| 1463（17 处 `.md` 写的）| 1505 | **1510** |
| 1468（Round 3 实测）| +37 | +42 |

**同一工作树、半小时内两次实测差 5** ⇒ 直接印证「工作树是移动靶」。

### 2.2 `+37` 的来源（不是判据漂移，是他人在途工作）

`git status --porcelain` 12 个文件在途（**只记录，未 stash / checkout / 改动**）：

| 文件 | 变化 |
|---|---|
| `src/store/multi_store.mbt` | **+427 行** |
| `src/server/ocr_scan.mbt` | **+261 行** |
| `src/server/ocr_scan_wbtest.mbt` | **+214 行** |
| `src/server/server.mbt` | +53 行 |
| `src/server/output_validate.mbt` | +4 行 |
| `?? src/store/store_migration_wbtest.mbt` | 新增，**10 个 test** |
| `?? src/engine/engine_scope_perm_role_wbtest.mbt` | 新增，**6 个 test** |
| `?? src/engine/engine_bug418_leader_probe_wbtest.mbt` | （无 `^test ` 行）|
| `memory/bugs.md` / 两个 `pkg.generated.mbti` | 账本 / 接口同步 |

### 2.3 ⭐ `(a)` 方案可行性判定（统帅点名要先给读数）

**结论：`^test` 行计数 ≠ `moon test` 实测总数 ⇒ `(a)` 不是精确面。**

| 面 | `^test` 行数 | `moon test` 实测 | 差 |
|---|---|---|---|
| 工作树（跟踪 + 未跟踪全量 `*.mbt`）| **1506** | **1505** | **−1** |
| `HEAD`（`git show HEAD:<f>` 逐文件累加）| **1479** | 未跑（HEAD 树未实测）| — |

复现命令：
```bash
# HEAD 面
for f in $(git ls-files '*.mbt'); do git show "HEAD:$f" 2>/dev/null | grep -cE '^test '; done | paste -sd+ | bc
# → 1479

# 工作树面（跟踪 + 未跟踪）
for f in $(git ls-files '*.mbt'; git ls-files --others --exclude-standard '*.mbt'); do grep -cE '^test ' "$f"; done | paste -sd+ | bc
# → 1506   （而 moon test 实测 = 1505）
```

**已排除的偏差来源**（逐个 grep 验证）：
- `skip` / `ignored` / `pending`：测试日志 grep **全空**
- 缩进内联 `test "` 行：`grep -E '^\s+test "'` = **0**
- `test_inline` / `@skip` / `ignore_test` 标记：全仓 grep **空**

⇒ 偏差来源未能定位到单一构造，但**结论不变**：`^test` 行数是**近似面**，不能冒充精确判据。

### 2.4 徽章 vs 实测（`check_badge --fresh`）

```
$ python scripts/check_badge.py --fresh temp/audit/lane_x_badge.log README.md
FRESH 真跑全仓：成功
    汇总：Total tests 1510 / passed 1510 / failed 0
  Total tests: 1510, passed: 1510, failed: 0.
BADGE-STALE: README 徽章 1463/1463 ≠ 实际测试数 1510/1510。
rc=1
```

**徽章落后 47 个测试。** 具体位置：

| 文件:行 | 当前值 | 应为（若现在改）|
|---|---|---|
| `README.md:8` | `tests-1463%2F1463-brightgreen` | `tests-1510%2F1510-…` |
| `README.md:122` | `# → Total tests: 1463, passed: 1463, failed: 0` | `1510` |

**未改**（裁决 A：等工作树收口。且 1505→1510 已证明此刻改必漂）。

### 2.5 `572`（native 面）零改动证明

`572` 出现位置全部是 **native 面**，与 JS 徽章无关：

| 文件:行 | 内容 |
|---|---|
| `README.md:28` | `moon test --target native -j 1` = **572/572** |
| `AGENTS.md:187` | 同上 |
| `ARCHITECTURE.md:81` | 同上（并注明「不拿 native 数当门槛」）|
| `README_EN.md:110` | **混行**：`**1463/1463** tests green on the JS backend … The native track measured **572/572** …` |

**本轮 `git diff` 为空 ⇒ 572 零改动**（未改任何文件，自然成立）。
**标记 `README_EN.md:110` 为高危混行**：同一行既有 JS 的 1463 又有 native 的 572，整行替换会改坏 572。收口后同步时**必须只改 JS 那半**。

---

## 三、分析

### 3.1 为什么「等收口」是对的（统帅补的第二条最硬）

按工作树数改文档 = 把**别人未提交的工作量**写进文档 ⇒ 文档**领先于** git 事实。
若那 12 个在途文件有任何一个被回滚（`multi_store.mbt` +427 行是大改，不是没可能），
17 处会**全部变成错的**，而且是「文档说 1505、实测 1468」这种**静默错**。

> **改错要被人看出来，改早没人看出来。**

### 3.2 BUG-425 的定性：判据在制造噪声，不是在检测漂移

`check_test_sync` 的**读数面**（工作树实测）与**原文面**（文档写的已提交态）**不同源**。
在并发开发期（本仓常态），它**每一次都会红**，除非人工传入脏树数。

**同族但更狠**：
- 判例-XX「打印 ≠ 生效」= 读数不准
- Lane F「工作树是移动靶」= 被测对象在变
- **本条的差别**：前两条是「读数不准」，本条是「**判据自己在制造噪声**」——
  它输出的红**不是缺陷信号**，而是一个**不可判状态**被强判成了红。

### 3.3 方案取舍：`(b)` 优先，`(c)` 只保留显式覆盖

| 档 | 判定 |
|---|---|
| **(a)** 读 HEAD 数 `^test` 行 | ❌ **实测不精确**（1506 vs 1505）⇒ 引入「近似面冒充精确面」的新缺陷 |
| **(b)** 脏则 advisory（退出码降 0 + 点名文件） | ✅ **推荐主体**。直接消灭假红；与 `check_fmt_gate` 的 DEGRADED(2) 同族（BUG-388 先例：**判据无法自证时拒绝判红也拒绝判绿**）|
| **(c)** 双模式 `--source=head\|worktree` | ⚠️ `head` 档要么贵（临时 worktree 真跑）要么不准（数行）⇒ 只保留 `--source=worktree` 作显式覆盖 |

**「工作树脏」= 一种「判据无法自证」，应复用 DEGRADED 口径而不是新造一个档。**

---

## 四、缺口与风险

1. **本单未完成**：17 处 `.md` 一处未改。需等 12 个在途文件收口后重启本单。
2. **实测总数仍在漂**：1505（22:00）→ 1510（22:20）。收口后必须**重测**，不得复用本报告的 1505/1510。
3. **`^test` 行数差 1 的根因未定位**：已排除 skip/内联/marker 三类。若要 `(a)` 方案，必须先查清这 1 个偏差（建议单开）。
4. **`README.md` 自检注释行（:122）也会过期**：`check_badge` 的 R50/R52 判据会一起抓它，收口后需与徽章同批改。
5. **`README_EN.md:110` 是混行高危点**：JS 数与 native 572 在同一行，整行替换必坏 572。已在 §2.5 标记。
6. **`check_test_sync` 未加「脏则降级」**：BUG-425 已入账，但**未修**（不在本单范围，且改动面在 `scripts/`，需单独派单）。

---

## 五、建议入档位置

| 内容 | 位置 |
|---|---|
| BUG-425（判据制造假红） | `memory/bugs.md` 已入账；建议同步进判例集（「判据的读数面与原文面必须同源」）|
| `(a)` 方案不精确的读数 | BUG-425 detail 已含 |
| `README_EN.md:110` 混行高危 | 收口后同步单的**必读提醒**（建议写进 `scripts/README.md` 的 check_badge 条目）|
| 徽章落后 47 | 收口后与 17 处 `.md` 同批修 |
