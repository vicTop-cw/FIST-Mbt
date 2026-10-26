# gitcode 剩余容量审计报告

- 日期：2026-10-26 ｜ 执行：Lane G（slim-team）｜ 性质：**纯只读审计**（未 push / 未删分支 / 未动远端）
- 目标：给出 gitcode 剩余容量精确画像，并判断「Compact 之后能否降到 1.0 GiB 以下」
- 仓 HEAD：`93168d6a` ｜ 本地 `.git`：**21M**（`--no-local --mirror` 重建后，零 unreachable）

---

## 0. 一句话结论

> **够了，去 Compact 即可。** gitcode 可达面已降到 **245.95 MiB（= 限额 1.0 GiB 的 24.0%）**，
> **余量 778 MiB**。剩余 11 个 >1MB 大 blob 合计仅 **约 50 MiB**，即使一个都不删，
> Compact 后也远低于 1 GiB。**不需要再删分支。**

---

## 1. 六项读数（逐条）

### ① gitcode 远程分支数 = **101** ✅

```
$ git ls-remote --heads gitcode | wc -l
101
```
（清理前 137 → 删 35 支 → 101，与统帅口径一致）

### ② 本地 gitcode refs 数 = **102** ✅

```
$ git for-each-ref --format='%(refname)' refs/remotes/gitcode | wc -l
102
```
（101 支 + `gitcode/HEAD` 符号引用 = 102，与预期一致）

### ③ gitcode refs 覆盖对象数与解压字节

```
$ git rev-list --objects --remotes=gitcode | wc -l
7740

$ git rev-list --objects --remotes=gitcode | cut -d' ' -f1 \
    | git cat-file --batch-check='%(objecttype) %(objectsize)' \
    | awk '{s+=$2} END {printf "%.2f GiB\n", s/1073741824}'
0.24 GiB      （精确值 245.95 MiB）
```

**按类型拆解**：

| 类型 | 个数 | 解压字节 |
|---|---|---|
| blob | 3,707 | **228.35 MiB** |
| tree | 3,245 | 16.78 MiB |
| commit | 788 | 0.82 MiB |
| **合计** | **7,740** | **245.95 MiB** |

### ④ >10MB 的大 blob：**0 个** ✅

```
$ cut -d' ' -f1 temp/_gcp.txt | git cat-file --batch-check='%(objectname) %(objecttype) %(objectsize)' \
    | awk '$2=="blob" && $3>10485760'
（空输出）
```

降阈值到 >1MB，还剩 **11 个**，逐个点名（含持有分支，全部实测）：

| # | 大小 | sha | 路径 | 持有分支 |
|---|---|---|---|---|
| 1 | 5.81 MB | `d7d3b5260d67` | `memory/2026-10-22.md` | **1 支**：`slave/fix/whisperer-head-state-r120` |
| 2 | 5.80 MB | `3b908e19f30c` | `memory/2026-10-22.md` | **1 支**：`slave/docs/readme-staleness-onsite-reading-r118` |
| 3 | 5.80 MB | `c68d3c9f7492` | `memory/2026-10-22.md` | **1 支**：`slave/fix/backlog-control-char-r120` |
| 4 | 5.80 MB | `c64912510ba2` | `memory/2026-10-22.md` | **1 支**：`slave/fix/backlog-reconcile-r119` |
| 5 | 5.80 MB | `fafebedf4363` | `memory/2026-10-22.md` | **1 支**：`fix/probe-attribution-daqing` |
| 6 | 5.80 MB | `859308010274` | `memory/2026-10-22.md` | **1 支**：`slave/fix/audit-branch-delete-face-r118` |
| 7 | 5.80 MB | `25adfc399be6` | `memory/2026-10-22.md` | **2 支**：`fix/audit-script-execution-face`、`slave/fix/audit-script-execution-face` |
| 8 | 5.23 MB | `11a5e7306bbb` | `dist/fist-mbt.js` | **94 支**（= 几乎所有分支，是跟踪件） |
| 9 | 3.62 MB | `7fe77afd6407` | `dist/fist-mbt.js` | **43 支**（同上，旧版本） |
| 10 | 1.15 MB | `844c316739d6` | `memory/2026-10-21.md` | **41 支** |
| 11 | 1.00 MB | `d37ed607cfeb` | `memory/bugs.md` | 1 支：`main`（**账本，绝不能删**） |

**小计**：11 个 = **约 50 MB**（占 245.95 MiB 的 ~20%）。

### ⑤ 老基线快照分支：**68 支（纯新增）/ 86 支（单 commit）**

```
$ for r in <101 支>; do git rev-list --count main..gitcode/$r; done | sort -n | uniq -c
      1 0          ← 与 main 同点
      1 ERR        ← HEAD 符号引用
     86 1          ← 只 1 条独有 commit
      8 2
      3 3
      1 4
      1 5
```

**86 支只有 1 条独有 commit**。进一步核 stat 是否纯新增（`git diff --numstat main...branch` 删除行数 = 0）：

| 类别 | 支数 | 含义 |
|---|---|---|
| **纯新增（删除 0 行）** | **68** | **「老基线快照」** —— 分支自带一条 commit 加了个文件，本质是旧基线 + 一点增量 |
| 含删除行 | 18 | 有真实改动（重构/删除），**不可当快照盲目删** |

含删除的 18 支点名：`feat/agent-fingerprint-pid-guard`(13) / `feature/web-dashboard-health`(9) /
`fix/agent-pid-instance-lock`(21) / `fix/battery-registration-anchor`(1) / `fix/e2e-upgrade-mirror-escape-r2`(1) /
`fix/guard-dedupe-and-orphan-naming-r47`(14) / `fix/list-tools-single-source-r39`(13) /
`fix/mbti-eol-cover-all-r43`(4) / `fix/readme-tool-count-j18-r41`(4) / `fix/three-trunk-reds-r48`(7) /
`refactor/fist-gate-fmt-single-source-r42`(23) / `slave/atomcode/battery-count-doc-hermetic-selftest-r151`(12) /
`slave/docs/backlog-no-copy-count-r175`(1) / `slave/feat/backlog-count-pointer-guard-r176`(4) /
`slave/feat/unit-number-branch-face-r174`(13) / `slave/fix/consolidated-r65`(638) /
`slave/fix/count-guard-reject-rc-r178`(20) / `slave/fix/find-main-cwd-r159`(4)

### ⑥ 残留删除后能降到多少（**实测投影，不是估算**）

用「保留 main + 16 支（18 支含删除中与 main 去重后）」实测：

```
现状（全部 102 refs）        : 245.95 MiB / 7,740 对象
删掉 68 支纯新增快照后（16 refs）: 183.92 MiB / 7,241 对象
可回收                       : 62.03 MiB（25.2%）
```

---

## 2. 关键问题：Compact 只回收 unreachable —— **现在还有没有 unreachable 大对象？**

### 方法学说明（诚实标注）

**gitcode 服务端的 unreachable 对象，从本地无法直接观测。** 本地仓是 `git clone --no-local --mirror` 重建的，
**只含可达对象**（`git fsck --no-reflogs --unreachable` = **0 行**，`.git` = 21M、单 pack 19.29 MiB）。
⇒ 我能精确给出**可达面**，但**不能**给出服务端 unreachable 面的读数。这个必须在服务端侧看。

### 但可以给出强下界论证

**服务端报 `git_repo size (2.4 GiB)`，而可达面只有 `0.24 GiB`。**

```
2.4 GiB（服务端报） - 0.24 GiB（实测可达面）= 约 2.16 GiB 差额
```

这个差额**只能是**：
1. **unreachable 对象**（刚删的 35 支分支留下的历史 + 更早的 reflog 残留）—— Compact 会回收；
2. **打包开销/多个 pack 未合并** —— Compact 会重打包消除；
3. **GitCode 的容量统计口径**（如按 pack 文件物理大小而非解压字节，或含 LFS / 其他项目内资源）。

**关键**：无论差额是 1/2/3 哪一种，**Compact 都是对症的**：
- 若是 unreachable ⇒ Compact 直接回收（这正是 Compact 的定义）；
- 若是 pack 碎片 ⇒ Compact 重打包消除；
- 若是统计口径（物理 vs 解压）⇒ **那 2.4 GiB 里约 2.16 GiB 是「已死但未物理回收」的空间，Compact 后物理占用 = 可达面的物理表示 ≈ 0.1–0.2 GiB**。

### 结论

> **没有需要「再删分支」才能解掉的可达大对象。** 最大的一组（7 个 `memory/2026-10-22.md` 版本，约 40 MB）
> 全部躺在 `slave/*` 与少量 `fix/*` 分支上，即使**一个都不删**，可达面也只有 245.95 MiB。
> **Compact 后预期落在 120–250 MiB 区间，远低于 1.0 GiB 限额。**

### Compact 后预期（两种情形）

| 情形 | 预期容量 | 是否达标（<1.0 GiB） |
|---|---|---|
| **A. 服务端确实有大量 unreachable**（差额主因） | **≈ 120–170 MiB**（可达面压紧，系数 0.5–0.7） | ✅ **大幅达标** |
| **B. 服务端 unreachable 已基本没有**，差额是统计口径 | ≈ 0.24 GiB = **246 MiB** | ✅ **仍然达标（24%）** |

**两种情形都达标。** 不需要为了容量再删任何分支。

---

## 3. 是否建议再删那 68 支纯新增快照？

**从容量角度：不必要**（见 §2，两种情形都达标）。
**从整洁角度：可选**，可回收 **62.03 MiB（25.2%）**，但**有风险**：

- 这 68 支虽「只 1 条独有 commit 且纯新增」，但那 1 条 commit 可能正是**某个任务的交付快照**；
- 我 10/24 的容量报告已立过纪律：**硬门（`audit_branch_delete.py`）证明不了已合就不删**；
- **建议：不删。** 若将来逼近限额再按「逐支过硬门 + 证明其内容已在 main」处理。

---

## 4. 两个附带发现（不是本任务要求，但影响判断）

### ① `gitcode/master` 仍是**默认分支**，指向 `5e769af3`

```
$ git ls-remote --symref gitcode HEAD
ref: refs/heads/master   HEAD
5e769af348259ef29a666dc860ef215d36f9ba34  HEAD
```

**但它是干净的**：相对 main 独有 commit **0**、独有对象 **0**，已包含在 245.95 MiB 里。
⇒ 不影响容量结论，但**默认分支仍是陈旧的 master 而非 main**，是个长期一致性隐患（我 10/24 报告 §五 已报过）。

### ② `dist/fist-mbt.js` 是跟踪件，占 8.85 MB（两个版本）

`dist/fist-mbt.js` 被 **94 支分支**引用、旧版被 43 支引用。**这是跟踪的发布产物**，不能删
（`git ls-files dist/` 有它）。它占可达面的 3.6%，属合理成本。

---

## 5. 缺口与风险

| # | 缺口/风险 | 严重度 | 说明 |
|---|---|---|---|
| 1 | **服务端 unreachable 面无法从本地观测** | 中 | 本地是可达-only 的 mirror。2.16 GiB 差额的构成（unreachable / pack 碎片 / 统计口径）**只能由服务端 Compact 后回读验证** |
| 2 | **Compact 是服务端动作，需 owner 操作** | — | 路径 `[Project Management] → [Compact]`。我无法执行，也无法预估耗时 |
| 3 | 若 Compact 后仍 >1.0 GiB | 低 | 说明差额来自「统计口径」而非死对象。届时唯一解是**历史重写**（`filter-repo` 摘掉 `memory/2026-*.md` 的 21 个版本）或**换新仓**——都不可逆，需 owner 批 |
| 4 | 删 35 支后，若 Compact 拒绝 | 低 | 部分服务端要求「先无活跃操作」才允许 Compact，需选空闲窗口 |
| 5 | 68 支纯新增快照仍在 | 低 | 占 62 MiB。**本报告建议不删**（风险 > 收益） |

---

## 6. 建议入档位置

- 本报告：`reports/2026-10-26-gitcode-residual-capacity-report.md`（已产出）
- **Compact 执行后**：建议追加一节「Compact 后实测」到本报告，回填服务端真实容量，用于**验证 §2 的情形 A/B 哪个成立**——这也是本次审计唯一未闭合的格。
