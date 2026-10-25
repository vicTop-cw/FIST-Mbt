# Stage 3 前置准备执行报告

> **文种**：执行记录 · **性质**：只读普查 + 落盘保全，**未做任何压缩/repack/reflog expire**
> **日期**：2026-10-25 · **执行**：commander-alpha
> **依据**：`reports/2026-10-25-stage3-prerequisites-checklist.md`（`c46d9511`）
> **所有数字均为本次现读，非引用历史报告**

---

## 0. 结论

| # | 步骤 | 结果 |
|---|---|---|
| ① | 只读普查 | ✅ 56 版本清单 + pack 分布 |
| ② | `--mirror` 备份 | ✅ **593 MB / 主仓外 / HEAD 一致 / 18,970 对象** |
| ③ | 62 tip bundle | 🔴 **失败** —— 全量 bundle 看着成功、`clone` 验证失败（详见 §3） |
| ④ | G1 逐版本判污染 | ✅ **28 污染（2259.5 MB）/ 28 真内容（9.3 MB）** |
| ⑤ | 28 真内容保全 | ✅ **28/28 + cmp 28/28 同 / 9.4 MB** |
| ⑥ | 删坏 bundle | ✅ 已删（clone rc=128 证明坏），`_archive` 594 MB → 31 MB |

**⇒ rollback insurance 唯一依赖 = `--mirror` 备份（已验证）。**
**⇒ 压缩策略应改为「只删 28 个污染版，保留 28 个真内容版」（收益 98.3%，不丢真内容）。**
**⇒ 压缩本身仍未执行（须 owner 裁决 + worktree 归零）。**

---

## 1. 只读普查

### 1.1 pack 分布

```
1.4G  pack-629e5c0ef82a70ea372bcb061e6a2b74d6a96a63.pack
589M  pack-c2775e2a1efe0dabdc24a10a5351bd434d58fbbc.pack
5.0M  pack-12ba1258dc782c2eaac3c2fc1953343995062249.pack
```

### 1.2 `memory/2026-10-22.md` 的唯一 blob

```bash
git rev-list --objects --all | grep "memory/2026-10-22.md$" | awk '{print $1}' | sort -u
→ 56 个唯一 blob
```

---

## 2. `--mirror` 备份（唯一 rollback insurance）

```
路径:   E:/IDEProjects/AI/git-mirror-backup-20261025.git   ← 主仓外，不在任何 worktree 子树内
命令:   git clone --mirror E:/IDEProjects/AI/FIST-Mbt <path>
大小:   593 MB
对象:   count=0 / in-pack=18970
```

**核验**：
```
备份 HEAD: 3182527259b764d2bfb3a9e8971e194c5d88dd76
主仓 HEAD: 3182527259b764d2bfb3a9e8971e194c5d88dd76
⇒ 一致 ✅
```

---

## 3. 🔴 bundle 失败全过程（判例-50 的实证）

### 3.1 第一版：62 个单 tip bundle —— 全败

```bash
for tip in <62 个 sha>; do git bundle create <tip>.bundle <tip>; done
→ FAIL 62/62: fatal: Refusing to create empty bundle.
```

**原因**：这些 tip 都已是某个 ref 的祖先。`git bundle create <file> <sha>` 只打包
「该 sha 可达、且不在声明排除面内」的对象 ⇒ 无新对象 ⇒ 空 bundle。

### 3.2 第二版：全量 bundle `--all` —— 表面成功

```bash
git bundle create _archive/branch-tip-bundles/all-history.bundle --all
→ 593.2 MB / 334 个 ref

git bundle verify <bundle>
→ "The bundle records a complete history."
→ rc=0  ✅
```

### 3.3 独立 clone 验证 —— **失败**

```bash
git clone _archive/branch-tip-bundles/all-history.bundle /tmp/v
→ error: Could not read c144bee836fb58e976e344f58881823f74d31049
→ fatal: Failed to traverse parents of commit 2b1670ccd9aa72d15b0381272eb49aae554b5ea7
→ fatal: remote did not send all necessary objects
→ rc=128
```

### 3.4 根因

```bash
git cat-file -p 2b1670cc
  tree   752dbcdfb8aa4247ed6a66083e18bf3b9d452f7e
  parent c144bee836fb58e976e344f58881823f74d31049     ← 父 commit 的 tree 没进 bundle
  author t <t@t> 1792731812 +0800                      ← **测试夹具产生的 commit**
  committer t <t@t> 1792731812 +0800

git cat-file -t c144bee8 → commit（当前仓库有，bundle 里没有）
```

**`t <t@t>` 是本仓测试夹具的固定 author**（`e2e_guard_mutation` / `check_merge_markers` /
`check_branch_ancestry` 等 selftest 在临时仓里造 commit 时用）。它被某个 ref 引用，
但其父链不完整。

### 3.5 判例-50 的结论

> **`git bundle verify` 只验「bundle 声明的 ref 的可达性」，不验「父链完整性」。**
> **⇒ `verify` 说 OK ≠ 真能用。必须做独立 `clone` 验证。**

**若没有做这次 clone 验证，593 MB 的 bundle 会是一个「看着能用」的假保险 ——
压缩后才发现无法恢复，那时备份已经不可再生。**

### 3.6 处置

按统帅裁决 **方案 A**：放弃 bundle，用已验证的 `--mirror` 作为唯一 rollback insurance。

```bash
# 删前最后确认（再做一次 clone）
git clone <bundle> /tmp/v   → rc=128  ✅ 确认坏
rm -rf _archive/branch-tip-bundles
```

**`_archive` 从 594 MB → 31 MB。**

---

## 4. G1 逐版本判污染（核心）

### 4.1 判据（统帅定）

```
唯一行占比 = 唯一行 / 总行数
  < 5%   → 🔴 污染
  ≥ 5%   → 🟡 疑似真内容（保全）
```

### 4.2 分类计数

| 类别 | 版本数 | 合计体积 | 占总体积 |
|---|---|---|---|
| 🔴 污染（< 5%） | **28** | **2259.5 MB** | **99.6%** |
| 🟡 疑似真内容（≥ 5%） | **28** | **9.3 MB** | **0.4%** |
| 合计 | **56** | **2268.8 MB** | 100% |

### 4.3 分布特征

**污染版（28 个）** —— 体积集中在极端少数：
```
639,905,457 B  (610.3 MB)  ← 最大
639,407,674 B  (609.8 MB)
 91,344,943 B  ( 87.1 MB)  ← 以下骤降
 91,344,925 B  ( 87.1 MB)
 91,344,767 B  ( 87.1 MB)
 ...（另 5 个 87.1 MB 同级 + 4 个 29.0 MB 级）
```

**真内容版（28 个）** —— 最大仅 867 KB，唯一行占比 10.07% ~ 95.65%：
```
867,642 B  5,006 行 / 504 唯一 / 10.07%
867,292 B  5,014 行 / 512 唯一 / 10.21%
865,973 B  4,999 行 / 499 唯一 /  9.98%
...
 31,626 B    253 行 / 242 唯一 / 95.65%  ← **最小、最像首版原始日志**
```

### 4.4 ⚠️ 这个结果推翻了我清单里的一处隐含假设

**我在 `2026-10-25-stage3-prerequisites-checklist.md` §1 写：**
> 「压缩的收益 98.8% 来自这一个文件的 56 个版本」
> 「这 56 个版本里绝大多数是污染」

**「绝大多数是污染」是错的 —— 实际是对半（28/28）。**
只是**污染版占体积 99.6%**，所以「收益来自污染」这个结论仍成立，但**版本数上不是「绝大多数」**。

**⇒ 若按「这个文件名整个删」的策略，会连带删掉 28 个真内容版本（9.3 MB）。**
这正是检查 6 写「不许因为叫这个文件名就整个删」的原因 —— **清单写对了，我的口头概括写错了**（判例-46：概括会吞掉例外）。

---

## 5. 28 个真内容版本的保全

```
路径:   _archive/memory-2026-10-22-real/<full-sha>.md
来源:   从 --mirror 备份 git cat-file blob <sha> 提取（**不从主仓取**，确保与备份一致）
数量:   28 / 28   ✅
核验:   cmp 28/28 同 ✅（对照主仓对象逐字节）
体积:   9.4 MB
```

**最小版本（首版候选）**：
```
5f37ac06148bb72e18702696f93111dce00646dc.md   31,626 B / 253 行 / 242 唯一 / 95.65%
```

---

## 6. 压缩策略建议（供 owner 裁决）

### 6.1 原策略的问题

「删 `memory/2026-10-22.md` 的全部历史」⇒ **连带删掉 28 个真内容版本（含首版候选）**。

### 6.2 建议策略

**只删 28 个污染版（2259.5 MB），保留 28 个真内容版（9.3 MB）。**

| | 原策略 | 建议策略 |
|---|---|---|
| 删除量 | 2268.8 MB | **2259.5 MB** |
| 收益 | 98.8% | **98.3%** |
| 真内容版本 | **全部丢失** | **全部保留（9.3 MB）** |
| 首版候选 | **丢失** | **保留** |

**⇒ 少省 9.3 MB（0.5%），但保住 28 个版本的真内容。这个取舍没有争议。**

### 6.3 执行方式（Stage 3 时用）

```bash
# 用 filter-repo 的 --strip-blobs-with-ids 只删污染 blob，不删整个路径
git filter-repo --strip-blobs-with-ids <28 个污染 blob sha 的清单文件>
```

**⚠️ 该方法需要 Stage 3 执行时验证：`--strip-blobs-with-ids` 是否会把引用这些 blob 的
历史提交**改写为删除该文件**（而非保留空 commit）。执行前必须在备份上试跑一次。**

---

## 7. 当前状态（未碰主仓 .git）

```
✅ 未压缩、未 repack、未 reflog expire、未 gc
✅ 未推任何远端（本轮只 commit 报告到本地 main + gitcode）

rollback insurance: E:/IDEProjects/AI/git-mirror-backup-20261025.git
  593 MB / HEAD 31825272... == 主仓 HEAD / 18,970 对象

_archive 现状:
   31M  total
  9.4M  memory-2026-10-22-real/       ← 28 个真内容版本
  6.5M  wt-salvage/                   ← 88 项 worktree 保全
   15M  dbs-20261021/
   其余 各 < 100 KB
```

---

## 8. 缺口与风险

| # | 缺口 | 说明 |
|---|---|---|
| G1 | **`--strip-blobs-with-ids` 未验证** | 建议策略依赖它。**执行前必须在备份上试跑**，确认它只删目标 blob 不改写其它历史 |
| G2 | **worktree 仍有 6 个** | Stage 3 执行前置未满足（检查 3） |
| G3 | **`origin/main` 落后 172** | 但统帅已裁定：这是 mirror 特性，不是要修的问题。**本报告据此不列为缺口** |
| G4 | **坏 bundle 的根因（测试夹具 commit 被 ref 引用）** | 该 commit `2b1670cc` 仍在历史里。**它本身不占体积，但会让任何 `--all` bundle 失败**。若将来仍需 bundle，必须先找到并排除引用它的 ref |
| G5 | **28 个真内容版本未逐个读内容** | 只按「唯一行占比」分类，**未人工确认它们确实是史料而非另一种污染**。建议压缩前抽查 3~5 个 |

---

**报告完成。未执行压缩。主仓 `.git` 一字节未动。**
