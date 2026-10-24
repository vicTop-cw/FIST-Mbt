# 判据覆盖面修复报告（判例-16 / 判例-17 落地）

> **任务**：task-22 · **模式**：fix_and_merge · **执行**：commander-alpha · **日期**：2026-10-24
> **判例来源**：统帅定案（判例-16「判据覆盖必须 ≥ 修复覆盖」/ 判例-17「判据要区分讨论与指令」）

---

## 一、结果摘要

三笔小步提交，各自独立可回滚：

| # | 提交 | 修的是什么 | 读数变化 |
|---|---|---|---|
| 1 | `1756ba04` | `check_entry_paths` 区分「讨论」与「指令」（判例-17） | 违例 **5 → 1**；自检 12 → **17 格** |
| 2 | `59a09fbc` | `check_esm_bundle_runnable` 覆盖面 1 → 全部 executable（判例-16） | 覆盖面 **1 → 4** 个 bundle；自检 15 → **26 格** |
| 3 | `33be91a0` | `check_mbti_eol` 覆盖面 3 份硬编码 → 跟踪面全量（判例-16 / R43） | 覆盖面 **3 → 24** 份 `.mbti`；自检 12 → **13 格** |

门禁：`moon check --target js` = **0 errors**（501 warnings 与基线同读数）。
提交纪律：每笔提交前 `git diff --cached --name-only` 确认暂存面**只有 1 个文件**。

---

## 二、逐笔证据

### 2.1 `1756ba04` — `check_entry_paths`（判例-17）

**病灶**：R1「退役入口引用」的豁免面只有 `.py` 的整行 `#` 注释（`PY_COMMENT_LINE`）。
但 `.py` 的非执行文本有两种：`#` 注释行 **与三引号 docstring 块**。docstring 作用与注释完全等同
（Python 不执行），却漏在豁免面外。

实测 5 处违例里 4 处是假阳：
```
ISSUE_ESM_CJS_BUNDLE_CRASH.md:86          用户面 · 真违例（保留）
check_esm_bundle_runnable.py:127 / :133   docstring 解释产物映射规律 · 假阳
patch_esm_main.py:39 / :40                docstring 解释「原实现只 patch 最大的」· 假阳
```

**修法**：新增 `stripped_docstring_lines()`（逐行切分三引号状态，返回 docstring 内行号集合）；
`mentions()` 对 `.py` 同时豁免 `#` 注释行与 docstring 行。**用户面（docs/、根 `*.md`）照旧全量判。**

**自证 +5 格**（成对，只加豁免不加后三格等于把判据改瞎）：
```
e2e-retired-in-comment-not-flagged              docstring 提到 → 不误报
e2e-retired-in-code-flagged                     活代码提到   → 必报
e2e-docstring-exempt-does-not-weaken-code-face  同文件里豁免不得放过活代码行
e2e-user-face-still-flagged                     .md 用户面    → 仍必报
e2e-docstring-line-splitter                     同行内开闭不污染后续行
```

**收益**：一次修判据，`patch_esm_main.py`（别人的在途工作）的两处 docstring **自动豁免**，
不需逐个文件改写措辞——这正是「修判据而非改注释」的价值。

### 2.2 `59a09fbc` — `check_esm_bundle_runnable`（判例-16）

**病灶**：`DEFAULT_BUNDLE` 只验 1 个 bundle，而 `patch_esm_main.py` 的修复面是**全部** executable。
实测 4 个 executable 包，4 个产物都含 `node:sqlite`：
```
cmd/cli/cli.js (5201.3 KB)  cmd/main/main.js (5013.9 KB)
cmd/commissar/commissar.js (434.6 KB)  smoke/smoke.js (322.7 KB)
```
⇒ 若 `commissar.js` / `smoke.js` 漏了垫片，本尺看不见；而电池里那格跑 `--selftest`，
连窄覆盖也照不到。**司令-β 从修复面独立撞到同一根因**（旧 patch 只挑最大的那个，`smoke.js`
漏网、加载即崩），两个方向指向同一条链。

**修法（方案 B：从 `moon.pkg` 反解，不硬编码）**：
```
executable_pkg_dirs(root)  扫仓库内**所有**含 moon.pkg 且声明 pkgtype(kind:"executable") 的目录
                           （不限 cmd/*：smoke/ 现在在根下第二层，将来要迁 tests/smoke/）
bundles_for_pkg(pkg_dir)   反解 <build>/<pkg_dir>/<basename>.js，退回 <build>/<pkg_dir>/main.js
resolve_bundles(...)       取第一个存在的；全不存在 ⇒ 未构建（记 diag，不算红）
```

**第一次实跑就抓到自己的错**：初版按 `basename(pkg_dir)` 拼路径，`cmd/cli` 被解析成
`build/cli/cli.js`（漏了 `cmd/` 这层）⇒ 4 个包 3 个「未构建」。**写死 `cmd/cli/cli.js` 的话
这个错永远看不见** —— 这正是「不硬编码」的价值。

**另一处修正**：扩面后发现旧判定（跑 `version` 看回执）对两个新入口**假红**：
- `cmd/commissar` **没有 version 子命令**（打印用法后 `exit(1)`）
- `cmd/main` 的 `version` 只往 stderr 写 ExperimentalWarning，stdout 空

它们没崩，只是不打版本号。改为 `node --input-type=module -e <ESM 探针>` 做
`import(pathToFileURL(p).href)`：
- Windows 盘符路径直接喂 ESM loader 会报 `Received protocol 'e:'`（实测踩过），必须转 `file://`；
- 探针**先打占位行再 import**，于是「import 期自行 exit」的入口（commissar）也能判对；
- `version` 回执降级为**诊断证据**（照打，不参与判定）。

**自证 +6 格**，其中后两格直接对表司令-β 的场景：
```
e2e-coverage-from-pkg-not-hardcoded         覆盖面来自反解且必含 cmd/cli
e2e-coverage-covers-all-built-executables   已构建 executable 数 == 逐件验的数量
e2e-every-executable-has-bundle-candidate   每个包都能反解出非空候选
e2e-bundle-candidates-under-build-dir       候选必须落在 _build/js/debug/build/ 下
e2e-unpatched-executable-detected           **修复面漏网**：静态档报 SHIM_MISSING
e2e-unpatched-classified-not-generic-crash  漏网 bundle 归类 ESM_CJS_REQUIRE，不混进 OTHER_CRASH
```

### 2.3 `33be91a0` — `check_mbti_eol`（判例-16 / R43）

**病灶**：`MBTI_FILES` 硬编码 3 份，而 `git ls-files '*.mbti'` 现读 **24 份**
⇒ 另外 **21 份**谁被 `core.autocrlf` 刷成 CRLF，本尺照样报绿。R43 报过，至今未修。

**修法**：新增 `tracked_mbti_files()`，`git ls-files -- '*.mbti'` 取跟踪面全量；
取不到 git ⇒ 退回 `MBTI_FILES_FALLBACK`（原 3 份关键产物），让无 git 环境仍覆盖核心。
**判定逻辑一字未改，只改覆盖面。**

**扩面立刻抓到真违例（这正是扩面的意义）**：
```
修前 → PASS（假绿）
修后 → FAIL：工作树 `.mbti` 有未提交改动
       |  M src/core/pkg.generated.mbti
```
那是别的 agent 并发改 `src/core/core_task.mbt` 后 `moon info` 的副产物，正好落在**原先看不见的
21 份**里。**该 dirty 属并发 WIP，非本笔引入；本笔只让尺看得见它。**

**自证 +1 格**（三条子断言）：
```
coverage-from-tracked-surface
  ① 覆盖面非空（空面会让后续检查静默全绿）
  ② 覆盖面 ⊇ 兜底清单（动态取数不得漏掉关键产物）
  ③ 覆盖面数 == git ls-files '*.mbti' 数（对表两个真源，不写死数字）
```

---

## 三、全仓普查（task-22 §③）

### 3.1 已知三例的现状

| 判据 | 窄在哪 | 本次处置 |
|---|---|---|
| `check_esm_bundle_runnable.py` | 只验 1 个 bundle | ✅ **已修**（`59a09fbc`） |
| `check_mbti_eol.py` | 只盯 3 份 `.mbti`，另 21 份谁脏都报绿（R43） | ✅ **已修**（`33be91a0`） |
| `check_selftest_call_face` J2 | 按**函数名**判 ⇒ 改名即绕过（判例-3） | ⛔ **未修**（见 §3.3） |

### 3.2 普查方法（可复现）

扫 `scripts/check_*.py`，匹配形如 `NAME = (` / `NAME = [` 后跟 1~6 条带扩展名的字符串字面量
——这是「手抄少量清单」的形状。命中 3 项：

| 判据 | 常量 | 项数 | 判定 |
|---|---|---|---|
| `check_desc_enum_sync.py` | `ENUM_REGISTRY` | 5 字段 × 2 条 | ✅ **不是缺口** —— L186 `for entry in ENUM_REGISTRY:` 完整遍历 |
| `check_mbti_eol.py` | `MBTI_FILES_FALLBACK` | 3 | ✅ 已修为兜底用，不再是主覆盖面 |
| `check_test_sync.py` | `MUST_CARRY` | 5 | ✅ **不是缺口** —— 它是「这 5 份文档必须携带测试数」的**要求面**，不是扫描面；扫描面是 L170 的 `git ls-files '*.md'` 全量 |

**结论：普查范围内无新增同类缺口。**

### 3.3 明确不修的一项及理由

**`check_selftest_call_face` J2「按函数名判 ⇒ 改名即绕过」**（判例-3 已记）：

- 它窄在**判定依据**（函数名），不是**覆盖面**（扫描哪些文件）。
- 判例-16 说的是「覆盖的面 ≥ 主张的面」；J2 的面是全的，问题是**识别方式可绕过**。
- 修它要动「怎么认出调用面」，属**判据语义变更**，不是覆盖面补丁。按 task-22 的边界
  「❌ 不加新判据（那是 advance 的活）」，**本笔不动，留给后续单**。
- 建议单独开单：把「按名字认」改为「按 AST/调用形状认」，并配成对自证格。

---

## 四、缺口与风险

| # | 项 | 说明 |
|---|---|---|
| R1 | **`src/core/pkg.generated.mbti` 当前 dirty** | 并发 agent 改 `core_task.mbt` 后 `moon info` 的副产物，**非本笔引入**。扩面后本尺会持续报 FAIL 直到有人提交或还原它 —— **这是正确行为**（§5.3 的警告文案已给出修法），但会让人误以为是新回归。建议统帅转告那位 agent |
| R2 | **反解路径靠「产物目录 == 包目录」的实测规律** | 本仓目前成立（`cmd/cli` → `build/cmd/cli/`、`smoke/` → `build/smoke/`）。若 MoonBit 将来改变产物布局，本尺会退化成「未构建」diag 而非静默漏检；届时改 `bundles_for_pkg()` 一处即可 |
| R3 | **`--selftest` 里的 `diag-real-bundle` 格** | 依赖真仓已构建产物；CI 未构建时该格不出现（不参与 fails）。**不影响判定**，但「真仓 4 个 bundle 都 PASS」这个读数只在本地/已构建环境可见 |
| R4 | **CI 是否装了 node** | ESM 探针档需要 node。无 node 时本尺**退回静态垫片核**（`bundle_checks`），仍能挡「忘跑 patch」，但验不到「真加载崩」。既有设计如此，本笔未改 |
| R5 | **`patch_esm_main.py` 仍是别人的 WIP** | 本笔全程未碰。它的 docstring 两处借 §2.1 的判据精度自动豁免 |
| R6 | 提交均**仅本地**（`1756ba04` / `59a09fbc` / `33be91a0`） | 按纪律未 push，等统帅决定推送通道 |

---

## 五、建议

1. **R1 立刻处理**：`src/core/pkg.generated.mbti` 的 dirty 会让 `check_mbti_eol` 持续红。
   要么那位 agent 把 `core_task.mbt` + `.mbti` 一起提交，要么 `git checkout -- src/core/pkg.generated.mbti` 还原。
2. **判例-16 可以推广成一条常驻自检**：任何尺只要有「覆盖面清单」，就该有「覆盖面 == 真源」的对表格
   （本次三笔各加了一格，形态相同：**对表两个真源，不写死数字**）。
3. **`check_selftest_call_face` J2** 另开单，按 §3.3 处理。
