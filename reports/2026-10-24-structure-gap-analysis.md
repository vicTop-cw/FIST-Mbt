# 结构矫正清单（Structure Gap Analysis）

> **文种**：差距分析清单 · **性质**：只读分析，**本文件不执行任何移动/删除**
> **日期**：2026-10-24 · **审计组主官**：audit-preservation · **任务**：task-10
> **基线**：`main = 460026ba`（含 task-9 保全证明书）
> **尺**：`AI-DEVELOPMENT-STANDARD.md` §2「目标项目必备文档集」（R116 规范性正文真源）
> **取证器**：`temp/audit/structure_measure.py`（纯只读）

---

## 0. 一页摘要

### 结论：**§2 的七项骨架全部齐备。不合规的只是「骨架之外」的 12 个纯本地产物目录。**

| 类别 | 数量 | 处置 |
|---|---|---|
| §2 七项骨架 | **7/7 齐备** | 无需动作 |
| 纯本地产物目录（0 跟踪 + 已 gitignore） | **12** | ✅ 可直接清 |
| 未跟踪且**未**忽略 | **6** | ⚠️ 须先加 ignore 或归档 |
| 有跟踪文件的非标准目录 | **3**（`fist-mbt/` `omega/` `smoke/`） | 须给迁移路径 |
| 异常项 | **1**（`E` + U+FD3A 目录） | 存量事故，建议处置 |
| 完全合规的标准目录 | 其余 | 无需动作 |

### 需 owner 裁决（3 条）

1. **`E` + U+FD3A 目录**（MoonBit nightly 工具链误装，~295MB）——R19 报告已报过，至今未处置
2. **`fist-mbt/plans/`**（5 份治理提案）——是迁入 `docs/` 还是留在原地（引用了它的 docs 有 6 处）
3. **`smoke/`**（MoonBit 可执行包，M1 验收辅助）——迁 `scripts/blackbox/` 会破坏 `moon build`，是否接受

---

## 1. 尺：§2 原文（逐字引用）

> **`AI-DEVELOPMENT-STANDARD.md:29-43`**
>
> ### 2. 目标项目必备文档集（开发文档规范）
>
> 新建/接管一个目标项目时，以下骨架必须齐（缺项=开工前先补，不允许"代码先行文档后补"）：
>
> | 文档 | 必填内容 | 更新时机 | 门禁 |
> |---|---|---|---|
> | `README.md` | 是什么/为什么/快速上手/能力全景（逐个可查的名字 + 分组计数）/环境要求/已知边界 | 每次对外能力变化 | J2/J3/J4（当前自述版本 == `moon.mod`） |
> | `AGENTS.md` | 角色边界、分流决策树、任务包格式、终审与记忆纪律、工具表（逐名） | 编排纪律或工具面变化时 | J2 |
> | `CHANGELOG.md` | 每版一条，含 **验证证据**（测试数/门禁 verdict）与**遗留风险** | 每次发版或收口 | J4 豁免（历史陈述） |
> | `docs/<feature>-skill.md` | 何时用 / 怎么调（**真实参数名**）/ 各形态关系 / 已知边界 | 每个新工具 | J8（模板与文档的调用示例参数必须等于注册参数集） |
> | `memory/bugs.md` | `## BUG-N [时间]` 账本 + `### FIXED/NOT-FIXED` 状态段 | 发现即入账（`report_bug`） | 账本脚本 `bug_list` 可读 |
> | `memory/YYYY-MM-DD.md` + `reports/YYYY-MM-DD-<任务>-report.md` | 结论/证据/分析/缺口与风险/建议入档位置 | 每轮终审通过后 | 金条五：缺汇报=轮次未收口 |
> | `templates/pipeline_mode_*.md` | 每模式：角色/核心动作/禁止事项/交付物/FIST 调用顺序（真实参数）/红线/汇报格式 | 模式或工具契约变化时 | J8 + `mode_templates` 存在性 |
>
> > **历史豁免边界**：`CHANGELOG.md`、`memory/`、`reports/` 按日期记录当时事实，**不做追改**；对齐只作用于"当前承诺"型表面（README/AGENTS/skill/工具描述/模板）。批量替换历史日志＝把证据改成假话，属违例。

> **⚠️ 重要：§2 只规定「必备文档集」，没有规定「目录白名单」。**
> 因此「根目录有 `logs/`」**不能被判为违反 §2**——§2 里没有一条说不能有 `logs/`。
> 我把这类处置的依据换成 **§0 术语 + owner 原话「临时文件，临时产物删除，工具保留」**，
> 并在下表逐条标明依据来源。**不凭感觉说「标准结构应该如此」。**

---

## 2. §2 七项骨架实测（7/7 齐备）

**复现命令**：`python temp/audit/structure_measure.py`

| §2 要求 | 实测 | 状态 |
|---|---|---|
| `README.md` | 在 main：`README.md` + `README.mbt.md` + `README_EN.md` | ✅ |
| `AGENTS.md` | 在 main | ✅ |
| `CHANGELOG.md` | 在 main | ✅ |
| `docs/<feature>-skill.md` | **17 篇** `docs/*-skill.md` | ✅ |
| `memory/bugs.md` | 在 main | ✅ |
| `memory/YYYY-MM-DD.md` | **19 个**（注：`.gitignore` 既有裁决部分不入库，见 §6.2） | ✅ |
| `reports/YYYY-MM-DD-<任务>-report.md` | **524 个** `*-report.md` | ✅ |
| `templates/pipeline_mode_*.md` | **7 个**（= 7 模式上限，moon 侧 `mode_templates` 应一致） | ✅ |

> **§2 本身没有缺口。**本清单后续全部是「骨架之外的残余物」问题。

---

## 3. 根目录逐项清单（57 个目录）

**取证口径**：`跟踪数` = `git ls-files | cut -d/ -f1 | uniq -c`；`git忽略?` = `git check-ignore -q <dir>/`。

### 3.1 ✅ 可直接清理（12 个：0 跟踪 + 已 gitignore）—— 依据：owner「临时文件，临时产物删除」

| # | 目录 | 跟踪 | 已忽略 | 判定依据（实测） |
|---|---|---|---|---|
| 1 | `__pycache__` | 0 | ✅ | Python 字节码缓存 |
| 2 | `_build` | 0 | ✅ | moon 构建产物 |
| 3 | `_proj_lang-zone` | 0 | ✅ | 非本仓项目（兄弟目录 `lang-zone` 的投影） |
| 4 | `_proj_vools` | 0 | ✅ | 非本仓项目（兄弟目录 `vools` 的投影） |
| 5 | `_release` | 0 | ✅ | 发布产物 |
| 6 | `_scratch` | 0 | ✅ | 临时草稿 |
| 7 | `backup` | 0 | ✅ | 备份（*与 `backups/` 不同，后者未被忽略，见 3.2*） |
| 8 | `logs` | 0 | ✅ | 运行日志 |
| 9 | `target` | 0 | ✅ | Rust 式构建目录残留 |
| 10 | `temp` | 0 | ✅ | 运行临时区（**内含已登记 worktree，删前须 `worktree remove`**） |
| 11 | `vendor` | 0 | ✅ | 第三方源码 vendoring |
| 12 | `.mooncakes` | 0 | ✅ | moon 依赖缓存（`moon update` 会重生成） |

> **`temp/` 特别提示**：`git ls-files temp/` = 0，但它内含 **3 个已登记 worktree**（`temp/auth-measure/wt` 532 dirty、`temp/r66` 干净、`temp/wt-skill` 378 dirty）。
> **必须先 `git worktree remove` 那 3 个，再清 `temp/`**，否则 `git worktree list` 留下 prunable 悬空项。

### 3.2 ⚠️ 未跟踪且**未**忽略（6 个）—— 须先加 ignore 或归档

| # | 目录 | 内容 | 风险 | 建议 |
|---|---|---|---|---|
| 1 | `.agents` | 6 个跟踪文件 + 大量未跟踪产物 | 跟踪面已有（worktree 根） | 已部分忽略；补 `.agents/_*` 规则（瘦身组 task-4 已做） |
| 2 | `_archive` | 1 项 `dbs-20261021`（15MB） | 未忽略 ⇒ **会被 `check_publish_payload` 扫到** | 加 `/_archive/` 到 `.gitignore` |
| 3 | `_scratch-rounds` | 2 项（`fist-mbt.db` + `temp/`） | 未忽略 ⇒ 同上 | 加 `/_scratch-rounds/` |
| 4 | `backups` | 1 项 `db-before-dist-rebuild-20261016`（11MB） | 未忽略 ⇒ 同上 | 加 `/backups/` 或归档后删 |
| 5 | `origin` | **0 项（空目录）** | 空目录，git 不跟踪 | 可删 |
| 6 | `.tmp-p1` / `.tmp-warn-verify` | 各 0 项（空目录） | 空目录 | 可删 |

> **⚠️ 影响面（`check_publish_payload.py`，BUG-127）**：该判据扫的是「**工作树 − .gitignore**」而不是 git 跟踪面。
> ⇒ 上面 `_archive/`(15MB) / `backups/`(11MB) / `_scratch-rounds/` 三个未忽略目录，
> **当前正被这条判据当作"将随 `moon publish` 打包的文件"扫描**。
> 若其中有凭据形状内容，会判 **P2 事故级**。**建议优先加 ignore。**

### 3.3 有跟踪文件的非标准目录（3 个）—— 必须给迁移路径

#### 3.3.1 `fist-mbt/`（5 文件，36KB）—— 治理提案文档

```
fist-mbt/plans/2026-10-22-fist-dir-layout-governance-proposal.md
fist-mbt/plans/2026-10-22-rx-mbt-lightweight-proposal.md
fist-mbt/plans/README.md
fist-mbt/plans/decisions/2026-10-22-001-dir-layout-governance.md
fist-mbt/plans/decisions/2026-10-22-002-rx-mbt-lightweight.md
```

**性质**：这是**目录治理提案 + ADR（决策记录）**，是纯文档。

| 项 | 内容 |
|---|---|
| **§2 对应位置** | §2 没有「plans」项。最接近的是 `docs/` （§2 只要求 `docs/<feature>-skill.md`，但 `docs/` 已被用作文档总目录，现 109 个跟踪文件） |
| **建议动作** | 迁入 `docs/plans/` 与 `docs/decisions/`（保持 `decisions/` 的 ADR 命名不变） |
| **影响面（必读）** | ① `git grep -l "fist-mbt/"` 在 `docs/evolve.md`、`docs/features/F008-evolve.md`、`docs/improvement-plan-20261010.md`、`scripts/README.md`、`scripts/blackbox/e2e_guard_mutation.py` **等 ≥5 处有引用** —— **迁了这些引用会断，必须同批改**<br>② 若 `scripts/blackbox/e2e_guard_mutation.py` 里是硬编码路径，迁了之后该 e2e **会红**<br>③ **不触发** `check_scripts_index.py`（不扫 `docs/`）<br>④ **不触发** `check_entry_paths.py`（非 `cmd/*` 入口） |
| **风险** | 🟡 中（引用面 ≥5 处，须同批改） |
| **需 owner 裁决** | ✅ 是——治理提案本身可能正在讨论目录结构，迁走前应先确认提案是否已成决议 |

#### 3.3.2 `omega/`（2 文件，6KB）—— **空 MoonBit 包（无源文件）**

```
omega/moon.pkg            （supported_targets = "js+native" + native link flag）
omega/pkg.generated.mbti  （生成的接口）
```

**关键实测**：**该目录下没有任何 `.mbt` 源文件**（`ls omega/` 只有 `moon.pkg` 与 `pkg.generated.mbti`）。
真正的 omega 实现在 **`src/omega/`**（10 个文件：`check.mbt` / `gate.mbt` / `scoring.mbt` / `spec.mbt` / `omega_tool.mbt` + 测试）。
`@omega.xxx` 的引用全部指向 `src/omega/`。

| 项 | 内容 |
|---|---|
| **性质** | **构建残留/误建的空包**。`moon info` 会重生成 `.mbti` |
| **建议动作** | **删除**（无源文件 ⇒ 删了不损失任何实现） |
| **影响面（必读）** | ① **`moon build`/`moon check` 可能因「有 moon.pkg 无源文件」报错或忽略** —— 处置前先 `moon check --target js` 留基线<br>② 若 `moon.mod` 的包扫描把空包计入，删它反而**减少**一个包 ⇒ 包计数类判据（若有）会变<br>③ **不触发** `check_entry_paths.py`（非 executable 包）<br>④ `check_mbti_sync.py` 扫 `pkg.generated.mbti` —— 删目录后该脚本若按目录遍历会少一个扫描点 |
| **风险** | 🟢 低（空包），但**必须先跑一次 `moon check` 留证** |
| **需 owner 裁决** | 建议梭：先 `moon check` 记录，再删，再 `moon check` 对比 |

#### 3.3.3 `smoke/`（3 文件，6KB）—— MoonBit **可执行包**

```
smoke/main.mbt      （M1 验收辅助，直接驱动 SqliteStore + Store trait 做跨连接持久化验证）
smoke/moon.pkg      （pkgtype(kind: "executable") + import "vicTop-cw/fist-mbt"）
smoke/pkg.generated.mbti
```

**自述**（`smoke/main.mbt` 首行）：「FIST-Mbt sqlite smoke walker（M1 验收辅助，**非交付代码**）」。

| 项 | 内容 |
|---|---|
| **性质** | 可执行包，**不是**脚本 |
| **§2 对应位置** | §2 无对应项。同类脚本的真源位置是 `scripts/blackbox/`（黑盒 e2e） |
| **建议动作** | **二选一，需 owner 裁决**：<br>(a) 迁 `scripts/blackbox/` —— **但它是 `pkgtype(executable)` 的 MoonBit 包，`scripts/` 下不能被 moon 构建**，必须先改成 `cmd/smoke/` 才是 MoonBit 合法位置<br>(b) 就地保留（6KB，无害） |
| **影响面（必读）** | ① **`check_entry_paths.py`（BUG-93/101）从 `cmd/*/moon.pkg` 的 `pkgtype(kind:"executable")` 反解入口清单** ⇒ 迁到 `cmd/smoke/` 会**让该判据把它当成一个新入口**，进而检查它的产物路径是否指退役入口 ⇒ **可能新红**<br>② 迁 `scripts/` 会**破坏 `moon build`**（moon 只扫模块内包，`scripts/` 不是包目录）<br>③ `scripts/run_guards.py` 有引用<br>④ `docs/polish-plan.md` 有引用 |
| **风险** | 🔴 **高**（迁错位置直接断构建或造新红） |
| **需 owner 裁决** | ✅ 是——**建议①先不动**②若要动，只考虑 `cmd/smoke/` 且同批更新 `check_entry_paths` 期望 |

### 3.4 🔴 异常项：`E` + U+FD3A 目录

**实测命名（这是重点）**：

```
$ python -c "print([hex(ord(c)) for c in name])"
['0x45', '0xf03a']
```

目录名是 `E` + **U+FD3A**（`FULLWIDTH COLON` 家族里的一个变体），**不是**：
- `E:`（ASCII 冒号 0x3A）—— Windows 不允许做文件名
- `E：`（全角冒号 U+FF1A）—— 早期报告 `reports/2026-10-19-fist-mbt-round19-cleanup-scan-bug333-report.md:11` 记的是这个

**内容**：

```
E⟹/temp/moon-nightly/
    bin/{moon, moonc, moon-cram, moon-ide, moon-lsp, moon-wasm-opt, internal/tcc}
    include/{moonbit.h, moonbit_runtime.h, moonbit_simd.h, backtrace.h, moonbit-fundamental.h}
    lib/{runtime/, prelude_proof/, why3/, libbacktrace.a, libmoonbitrun.o, core.tar.gz}
    share/why3/{drivers, extraction_drivers, lang, stdlib, vim}
    CREDITS.md
```

⇒ **一整套 MoonBit nightly 工具链**（~295MB / 236 文件的 R19 读数）。

| 项 | 内容 |
|---|---|
| **成因** | 路径拼接事故：某个脚本把 Windows 绝对路径 `E:/temp/moon-nightly` 当**相对路径**传给工具，`:` 在文件系统层被规整成 U+FD3A ⇒ 在仓库根下**物理创建**了 `E⟹/temp/moon-nightly/` |
| **是否被引用** | `git grep -l "moon-nightly" main` ⇒ 只命中**历史报告**，无任何活代码引用 |
| **是否影响构建** | **否**。真实 moon 来自 PATH（`scripts/moon_env_probe.py` 自动发现 `~/.moon-shim/shim.exe`），与此目录无关 |
| **git 状态** | 命中 `.gitignore:29` 的 `temp/` 规则 ⇒ 已忽略、未跟踪 |
| **建议动作** | **删除整个 `E⟹` 目录（连同其中的 `temp`）**。如需 nightly 对齐，`moon` 分钟级可重装 |
| **影响面** | ① 触发 `.gitignore` 的 `temp/` 规则 ⇒ 删了不影响任何跟踪面<br>② **不触发**任何判据（未跟踪）<br>③ 删后 `ls -d */` 少一项，`check_repo_shape.py` 若对根目录做白名单会变绿（更干净） |
| **风险** | 🟢 低——但**这是不可逆动作**，且 **R19（2026-10-19）已报、至今未处置** ⇒ 本清单**只出方案，交 owner 裁决** |
| **需 owner 裁决** | ✅ 是（不可逆 + 存量遗留） |

> **命名陷阱提醒（给后续写处理脚本的人）**：
> `Remove-Item "E："`（U+FF1A）**删不到**这个目录。必须按 U+FD3A 匹配，或用：
> ```powershell
> Get-ChildItem -Directory | Where-Object { $_.Name -match '^E[\uF03A\uFF1A:]' } | Remove-Item -Recurse
> ```
> **处置前先用 `Get-ChildItem -Directory | Where-Object Name -like 'E*' | Format-List Name, FullName` 确认目标。**

### 3.5 ✅ 完全合规的标准目录（其余 36 个）

`src`(327) / `scripts`(154) / `docs`(109) / `plugins`(76) / `memory`(38) / `cmd`(16) / `templates`(11) /
`atgc-old`(11) / `packaging`(6) / `atgc`(6) / `web`(4) / `patches`(3) / `assets`(2) / `dist`(2) /
`.github`(8) / `.githooks`(3) / `.agents`(6) / `.dsh`(5) / `.codeartsdoer`(2) +
宿主/工具目录 `.atomcode` / `.trae` / `.office-claw` / `.pytest_cache` / `.mooncakes` / `.fist` / `.Fist-Mbt` / `.verify-wt`

> **`.Fist-Mbt/`（22MB）与 `.fist/`（135KB）**：未跟踪、未忽略 ⇒ **同 §3.2 风险**，
> 被 `check_publish_payload` 当作打包对象扫描。建议加 ignore。`.Fist-Mbt/` 是运行时数据目录（`data/*.db` + `db/`）。

---

## 4. 处置优先级（按风险降序）

| 优先 | 动作 | 理由 |
|---|---|---|
| **P0** | 给 `_archive/` `backups/` `_scratch-rounds/` `.Fist-Mbt/` `.fist/` 加 `.gitignore` 规则 | **`check_publish_payload` 正把它们当打包面扫**，有凭据就是 P2 |
| **P1** | 清 12 个纯本地产物 + 3 个空目录（`origin` `.tmp-p1` `.tmp-warn-verify`） | 0 跟踪、已忽略，零风险 |
| **P2** | 删 `omega/`（空包） | **无任何 `.mbt` 源文件**（真实现在 `src/omega/`）⇒ 删除零损失，但须先跑 `moon check` 留基线 |
| **P2** | `E` + U+FD3A 目录 | ~295MB 存量，R19 已报未处置；**不可逆，需 owner 点头** |
| **P3** | `fist-mbt/plans/` → `docs/plans/` + `docs/decisions/` | 引用面 ≥5 处，须同批改 |
| **P3** | `smoke/` | 🔴 高风险迁移，建议先不动 |

---

## 5. 逐条「迁了之后哪些判据会红」总表

| 判据 | 扫什么 | 本清单里哪项会触它 | 后果 |
|---|---|---|---|
| `check_scripts_index.py` | `scripts/` **直接子文件**必须在 `scripts/README.md` 登记 | **无**（本清单不新增/移动 scripts 直接子文件） | — |
| `check_entry_paths.py` | 从 `cmd/*/moon.pkg` 的 `pkgtype(executable)` 反解入口 | **`smoke/` 若迁到 `cmd/smoke/`** | 🟡 该判据把它当新入口并检查产物路径，**可能新红** |
| `check_publish_payload.py` | 「**工作树 − .gitignore**」，点号文件不进包 | **`_archive/` `backups/` `_scratch-rounds/` `.Fist-Mbt/` `.fist/`**（未忽略） | 🔴 **当前已在扫**，有凭据即 P2 |
| `check_doc_surface.py` J11 | CI 门步骤 ↔ 账本三向对表 | **无**（本清单不动 workflow 与账本） | — |
| `check_mbti_sync.py` | `pkg.generated.mbti` | **`omega/` 删除**、**`smoke/` 迁移** | 🟡 扫描点减少，若按目录遍历须同步 |
| `check_repo_shape.py` | 仓库形状（`core.bare` 等） | `E⟹` 删除 | 🟢 更干净，不红 |
| `moon build` / `moon check` | 包扫描 | **`omega/`（空包）**、**`smoke/`（可执行包）** | 🟡 `omega/` 先留基线；`smoke/` 迁错位置直接断构建 |

---

## 6. 缺口与风险

### 6.1 §2 只规定「必备」，不规定「禁止」

本清单**没有**任何一项是「违反 §2」。真正的判据来源是 **owner 原话「临时文件，临时产物删除，工具保留」**
+ `AI-DEVELOPMENT-STANDARD.md` §0 术语。**若 owner 想要真正的"目录白名单"标准，§2 需要扩写**——这是标准侧缺口，不是仓库侧。

### 6.2 `memory/YYYY-MM-DD.md` 的 §2 与 `.gitignore` 冲突（既有裁决）

§2 列了 `memory/YYYY-MM-DD.md` 为必备，但 `.gitignore:154-157` 既有裁决是「memory 日日志不入库」
（理由见 `reports/2026-10-24-merge-precedents.md`：614MB 级膨胀 + 每次合并必撞冲突；结构化核心记忆
`bugs.md`/`product.md`/`target.md` 单独入库）。
**这是标准与既有裁决的已知张力，不是本次结构问题的可解项**，记录备查、建议 owner 在 §2 里加一句豁免注。

### 6.3 未覆盖

- `reports/` 584 个文件 / `docs/` 109 个：未按 §2「更新时机」做时效性审计（属另一命题）
- 12 个纯本地产物目录的**内容**：只看了跟踪状态，未逐项读（15MB + 11MB 的 dB 备份是否有独有价值需专项）
- 宿主工具目录（`.atomcode` `.trae` `.office-claw` `.codeartsdoer`）：按 owner「工具保留」不动，未审计

### 6.4 与 task-9 的接口

`temp/` `_archive/` `backups/` 若清理，**必须先移除其中的已登记 worktree**（`temp/auth-measure/wt`、`temp/r66`、`temp/wt-skill`）。
详见 `reports/2026-10-24-asset-preservation-proof.md` §3.4。

---

## 7. 复现命令

```bash
# 结构度量（§2 七项 + 根目录逐个跟踪状态 + 异常项探测）
python temp/audit/structure_measure.py

# 根目录清单
ls -1d */ | sed 's:/$::'
git ls-files | cut -d/ -f1 | sort | uniq -c | sort -rn

# 每个目录是否被忽略
for d in */; do git check-ignore -q "$d" && echo "IGNORED  $d" || echo "NOT-IGN $d"; done

# E⟹ 目录的真名（U+FD3A）
python -c "import os;print([(x,[hex(ord(c)) for c in x]) for x in os.listdir('.') if x.startswith('E')])"

# omega 是否空包
ls omega/ ; ls src/omega/

# smoke 是否可执行包
cat smoke/moon.pkg
```

---

## 8. 来源

| 角色 | 贡献 |
|---|---|
| owner | 四原则：「按 fist-mbt 治理目标项目的结构出」「不是相关项目移除或迁出」「临时文件产物删除，工具保留」「只保留主仓一个文件夹」 |
| 统帅 | §2 当尺的定位、12 个未跟踪目录初查、4 条需核查判据（`check_scripts_index` / `check_entry_paths` / `check_publish_payload` / `check_doc_surface` J11） |
| `AI-DEVELOPMENT-STANDARD.md` | §2 原文（逐字引用）、§0 术语、§7 已知边界 |
| `reports/2026-10-19-fist-mbt-round19-cleanup-scan-bug333-report.md` | `E⟹` 目录的首次发现（R19） |
| 审计组 | 57 目录逐个跟踪状态实测、`omega/` 空包定性、`smoke/` 可执行包定性、U+FD3A 命名核对、逐条影响面推演 |
