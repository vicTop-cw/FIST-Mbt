# 兄弟目录清理 · 执行记录 · 2026-10-25

**来源**：核查报告 `bfb84ddc`（`reports/2026-10-25-sibling-directory-cleanup.md`）
**统帅批准**：分批执行（第一批 5 项 / `_lz_night_scratch` / 三个 slave clone）

---

## 一、结果摘要

| 指标 | 读前 | 读后 |
|---|---|---|
| 顶层目录数 | **34** | **26** |
| 释放体积 | — | **≈ 11.0 GB** |
| 删除目录 | — | **9 个** |
| 保全文件 | — | **14 个 / 328 KB** |
| 主仓 `.git` | HEAD `828eac43` | HEAD `828eac43`（**未变**）|
| 主仓 `git status` | 82（stat-dirty 噪音）| 82（**未变**）|

---

## 二、删除清单（9 项，逐项带删前核验）

### 第一批 5 项（统帅批准）

| # | 目录 | 大小 | 删前核验 | 结果 |
|---|---|---|---|---|
| 1 | `_fist_atgc_v2_ctl` | 1.23 MB / 29 files | DIR 非链接 · no-git · busy2h=0 · locked=0 | ✅ 已删 |
| 2 | `_fist_atgc_v2_exp` | 1.10 MB / 22 files | 同上 | ✅ 已删 |
| 3 | `_fist_iso` | 0.40 MB / 13 files | 同上 **+ 先保全**（见 §3）| ✅ 已删 |
| 4 | `backup` | 1.42 MB / 15 files | 同上 | ✅ 已删 |
| 5 | `AI` | 0 files（纯空目录）| 同上 | ✅ 已删 |

> 第一批合计 **≈ 4.15 MB**（比预估 2.6 MB 多 —— `_fist_iso` 里有库与审计日志）。

### 第二批 `_lz_night_scratch`（11 GB）

| 项 | 读数 |
|---|---|
| 删前大小 | **11 G**（`du -sh`）|
| 文件数 | **31,238** |
| 结果 | ✅ 已删 |

### 第三批 三个 slave clone（统帅批准删除）

| # | 目录 | HEAD | 结果 |
|---|---|---|---|
| 6 | `FIST-Mbt-slave-guard01` | `f07dbf24` | ✅ 已删 |
| 7 | `FIST-Mbt-slave-wt02` | `12e4356f` | ✅ 已删 |
| 8 | `FIST-Mbt-slave-wt03` | `81eac734` | ✅ 已删 |

> 三个都是 `github:vicTop-cw/FIST-Mbt.git` 的**独立 clone**（各有真 `.git` 目录，
> **不是** 主仓 worktree）⇒ 删目录**不触碰主仓 `.git`**。删前删后主仓 HEAD 均为 `828eac43`，已验证。

---

## 三、排雷记录（这是本单最关键的部分）

### 🔴 地雷 1：`_lz_night_scratch/Tnr` 是**符号链接** → `/e/IDEProjects/AI/Tnr`（**真实项目**）

`rm -rf _lz_night_scratch` 在部分平台会**跟随链接删除目标** ⇒ 会删掉整个 Tnr 项目。

**处置**：先 `rm Tnr` **解链**，再删目录。
**解链后核验**：Tnr 项目存在、`git status` **3 个未提交文件仍在** ✅

### 🔴 地雷 2：`_lz_night_scratch/lzcfix/target` 是**符号链接** → `lang-zone/target`（656 MB 构建产物）

同上先 `rm lzcfix/target` 解链。
**解链后核验**：`lang-zone/target` **656 MB 仍在**、`lang-zone` **420 个未提交文件仍在** ✅

### 排雷扫描（删前两轮，全清）

| 扫描 | 读数 |
|---|---|
| `find . -type l`（解链后）| **0** |
| PowerShell 递归 `Attributes -match 'ReparsePoint'` | **0** |
| `LinkType -eq 'HardLink'` | **0** |
| 抽样文件数 | 31,238（全量）|

### ⚠️ 一次**自曝的误判**（判例-50 家族）

删 slave clone 前的锁检测脚本报「**12 个 blocked**」，看着像有进程占用。
追查发现是**误判**：那 12 个全是 `.git/objects/*` 的**只读** object 文件 ——
`[IO.File]::Open(...,'Open','Read','None')` 可正常打开；
控制组普通源文件用 `'ReadWrite'` 也能正常打开 ⇒ **零真实锁、零进程占用**。

**教训**：检测脚本自己的读数也得先验一遍再当结论 —— 本仓已有判例-50 管「变异未命中锁」，
本单补一条同族：**「检测工具的读数也要自证」**。首轮那个 `locked=12` 如果直接当结论，
就会得出「有进程占用、不能删」的错误处置。

另：`Win32_Process` 全量扫（`CommandLine` + `ExecutablePath`）确认**0 个进程**引用三个 slave 目录。

---

## 四、保全清单（14 个文件 / 328 KB）

处置原则：**有用的史料先归档，再删原件**（owner 四原则之一）。

### 4.1 `_archive/sibling-salvage/2026-10-25/_fist_iso/`（224 KB）

| 文件 | 核验 |
|---|---|
| `fist-mbt.db`（167,936 B）| `cmp` **字节全同** |
| `gt_audit/`（2 份 txt，262 行）| `diff -r` **逐字节全同** |

**为什么救**：`fist-mbt.db` 含 `tasks=6 / specs=3 / call_log=38` —— 是当轮**真实调用记录**，
不是「纯实验副本」。`gt_audit/` 是 Actus 审计输出。统帅裁定**保留**。

### 4.2 `_archive/wt-salvage/2026-10-25/`（104 KB，含 `MANIFEST.md`）

| 来源 | 保全内容 | 行数 | 核验 |
|---|---|---|---|
| wt02 | `src/server/wt_tools.mbt` | **505** | `cmp` 字节全同 |
| wt02 | `src/server/wt_tools_wbtest.mbt` | **198** | `cmp` 字节全同 |
| wt02 | `server.mbt.diff` | 103 | `git diff HEAD` 导出 |
| wt02 | `pkg.generated.mbti.diff` | 188 | 同上 |
| wt02 | `upgrade_core.mbt.diff` | 34 | 同上 |
| wt03 | `docs/design-wt-sparse-scripts.md` | **72** | `cmp` 字节全同 |
| guard01 | `scripts/check_model_auth_no_key.py`（整份）| **392** | `cmp` 字节全同 |
| guard01 | `guard01-uncommitted.diff` | 91 | 完整未提交面 |

**wt02 的 703 行为什么必须救**：main 里 `wt_create` / `wt_status` / `wt_destroy` / `wt_tools`
`git grep` **0 命中** ⇒ 那是全仓**唯一**的 worktree 生命周期工具实现（判例-51）。
**wt03 的 72 行**：main 跟踪面 `design-wt-sparse` **0 命中** ⇒ 设计稿只存在于该 clone（判例-24 同型）。

`MANIFEST.md` 另附 **§0 还原口径**：三个 clone 的分支名 + HEAD + `git clone -b` / `git checkout` 复原命令
⇒ **删了也重建得回来**。

---

## 五、guard01 38 行的分类（统帅裁决：单独派单）

### 内容（读 diff 原文）
**GUARD-01 的两个新扫描面**：
```python
WORKFLOWS_DIR = ".github/workflows"          # ① CI workflow 面（凭据 env 注入点）
EXAMPLE_GLOBS = ("*.mcp.example.json", ...)  # ② 根目录 example 模板面
```

### 三项核验

| 核验 | 读数 | 结论 |
|---|---|---|
| ① main 有无这两个面 | `grep WORKFLOWS_DIR\|github/workflows\|EXAMPLE_GLOBS\|mcp.example` → **0 命中** | main **没有** |
| ② 功能增量 vs 旧实现残留 | guard01 独有函数 **0** / main 独有函数 **0** ⇒ **函数集完全相同** | 不是另起炉灶 |
| ③ guard01 是否落后 main | diff 中 main-only 行 = **1**（仅 docstring 一句日志文案）| 除该句外 **guard01 ⊇ main** |

### 分类结论

> **「应合 · 但不可直接拿那份文件」**

- **应合**：CI workflow 面 + example 面是 `check_model_auth_no_key` 的**真空白**
  （凭据被贴进 `.github/workflows/*.yml` 目前**无人报警**），与本仓判例-16 方向一致。
- **不可整文件覆盖**：会让 main 那 1 行日志文案回退 —— 正是判例-53「不能拿旧基线当顶树」。
- **不可 `git apply`**：diff 基于旧 blob `e1fc7e9a`，main 现为另一 blob，直接 apply 会冲突/覆盖。

**正确做法**：摘常量 + `collect_files` 里两个 glob 块 + docstring 两行，**手工嫁接 main 现版**。
**属独立工作量**（改判据 + 补自检格 + 电池锚点同批），已由统帅**单独派单**，不在本单范围。

---

## 六、刻意不动清单（红线）

| 项 | 理由 |
|---|---|
| `Pentad`（22.9 GB）/ `Tnr` / `vq` / `lang-zone` / `vools` / `兹` / `rx-mbt` / `sigma-lang` / `mcpconftest` / `Actus` / `fist-evidence` / `NPU-Tnr-test` | **别的项目本体**（各独立 origin / 独立发布面）|
| `Tnr` / `Tnr_p0` / `Tnr_merge_check` 三份同 origin 检出 | 判例-51/53：**同 origin ≠ 同内容**；未逐份核独有提交 ⇒ **全保留**（统帅裁定不核、三份全留）|
| `lang-pulgins`(180 MB) / `Nodea` / `Nodea-ATGC` | **无 `.git`** ⇒ 删即不可恢复，无「已在 origin」证据 ⇒ **不动** |
| `_archive/`（22.8 GB）| 内含 `Ceres`/`ClipRelay`/`CustEditor`/`Cypy` 等**别的项目**史料；**不整删**，只增不删本单两个 salvage 子目录 |
| `DownLoads`（19.7 GB）| 用户下载区，**非本仓产物** ⇒ 不动 |
| `light-wt/`（101 MB）| 司令沙箱（其他 agent 在用）⇒ 不动 |
| `name-squats` / `temp` / `competition` / `_fist_meta_prompts` | 对外占名 / 可能是他人测试沙箱 / 待 owner 决策 ⇒ 本轮不动 |
| `git-mirror-backup-20261025.git` | **统帅建的 rollback insurance**（593 MB / 18,970 对象 / HEAD==主仓 HEAD）⇒ **不动** |

---

## 七、当前 26 个顶层目录

```
他项目本体 17：Pentad Tnr Tnr_p0 Tnr_merge_check vq lang-zone vools 兹 rx-mbt
               sigma-lang mcpconftest Actus fist-evidence NPU-Tnr-test
               lang-pulgins Nodea Nodea-ATGC
本仓相关 5： FIST-Mbt(主仓) _archive light-wt temp _fist_meta_prompts
其它 4：     DownLoads competition name-squats git-mirror-backup-20261025.git
```

（另：`_fist_atgc_v2_正文.md` 为单文件，非目录，未计入。）

---

## 八、遗留风险

1. **`rx-mbt` 的 origin URL 仍内嵌明文 OAuth token** —— 本单未处置（统帅派给 δ 单独处理）。
   **报告与所有记录均不回显 token 本体。**
2. **`_archive/` 22.8 GB 未分级** —— 内含多个他项目史料，须逐项目确认已在各自 origin 后再处置。
3. **`DownLoads` / `name-squats` / `temp` / `competition` / `_fist_meta_prompts`** 待 owner 决策。
4. **guard01 的 GUARD-01 两扫描面**已单独派单；摘之前，`check_model_auth_no_key`
   对 `.github/workflows/*.yml` 与根目录 `*.mcp.example.json` 仍**无覆盖**（真实缺口，未修）。
5. **`_lz_night_scratch` 内 `lang-zone/`(2.9 G) 与 `lzcfix/` 是无 `.git` 的临时副本**，
   已随目录删除；若其中曾有未同步到 `lang-zone` 主仓的改动，**无法恢复**（删前未发现此类内容，
   但此判断基于规模抽查而非逐文件比对 —— 如实记录该边界）。
