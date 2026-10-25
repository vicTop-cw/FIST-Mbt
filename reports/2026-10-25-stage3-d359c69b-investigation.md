# `d359c69b` 调查报告

> **文种**：调查报告 · **性质**：只读，**未合并、未改动任何分支**
> **日期**：2026-10-25 · **执行**：commander-alpha
> **起因**：Stage 3 前置准备发现 `d359c69b` 是「止住失控日志」的修复，但不在 main 上

---

## 0. 结论（一句话）

**`d359c69b` 是一个未合并分支上的单提交，作者 `t <t@t>`（测试夹具作者），
它**新增了一把有价值的闸**（`check_memory_log_size.py`），但**同时把 20+ 份 `memory/*.md` 流水账提交进了跟踪面**——
这正是本仓 `.gitignore:157` 后来要挡掉的东西。**

**⇒ 值不值得合：`check_memory_log_size.py` 值得单独摘，整支合入不建议。**

---

## 1. 在哪个分支

```bash
$ git branch -a --contains d359c69b
  fix/memory-log-runaway          ← 唯一一支，本地分支

$ git for-each-ref --contains d359c69b --format='%(refname)'
  refs/heads/fix/memory-log-runaway
```

**⇒ 无任何远程分支包含它。只在本地一支上。**

**该支的完整提交链 = 1 个提交**：
```bash
$ git log --oneline main..fix/memory-log-runaway
d359c69b fix(memory): 止住失控日志 —— `memory/2026-10-22.md` 613 MB → 0.23 MB，并给 `memory/*.md` 上体积/重复度闸
```

---

## 2. 与 main 的 diff（38 个文件 / +10,874 / −22）

### 2.1 构成分析（按性质分类）

| 类别 | 文件数 | 说明 |
|---|---|---|
| **`memory/*.md` 流水账（新增）** | **20+** | `2026-09-24` ~ `2026-10-22` 等，共约 8,000+ insertions —— **这是「污染」不是「修复」** |
| **`scripts/check_memory_log_size.py`（新增）** | 1 | **154 行，有价值的新判据** |
| `scripts/run_guards.py` | 1 | +2 行（登记该新判据） |
| `scripts/README.md` | 1 | +3/−1（索引条目） |
| `docs/2026-10-20-slave-tasks.md` | 1 | +8/−8（锚点） |
| `plugins/*/SKILL.md`（4 宿主） | 8 | 各 +2~6/−2~6（生成投影） |
| **`memory/2026-10-22.md`（新增）** | 1 | **245,988 B / 1,062 行** |

### 2.2 ⚠️ 提交说明与实际改动不符

**提交说明**：
> `memory/2026-10-22.md` **613 MB → 0.23 MB**

**实际**：
```
d359c69b^  (父 0b8e3cd2) 里 memory/2026-10-22.md → 无此文件
d359c69b   里 memory/2026-10-22.md → 245,988 B (240 KB / 1,062 行)
```

**⇒ 这不是「把 613 MB 改成 0.23 MB」，而是「从无到有新增了一个 240 KB 的版本」。**
613 MB 那份**在别的 commit 上**（就是本报告之前查到的 28 个污染 blob）。

**⇒ 提交说明描述的是「事故的现状」，不完全是「本提交做了什么」。**

---

## 3. 是否依赖 main 没有的其他提交

```
父提交 = 0b8e3cd2
```

**核验**：
```bash
git merge-base --is-ancestor 0b8e3cd2 main
```

**结果**：父提交是 main 的祖先（`0b8e3cd2` 在 main 历史中）。

**⇒ `d359c69b` 是「单个提交直接挂在 main 的某个祖先上」，不依赖其它未合并提交。**
**⇒ 技术上可以干净 cherry-pick（如果只摘它）。**

---

## 4. 值不值得合？

### 4.1 值得的部分：`scripts/check_memory_log_size.py`

**154 行，判据设计扎实**（自述摘要）：

```
判据（两条，独立可读）
  · 体积：任一 memory/*.md > MAX_MB（默认 2 MB）⇒ 红
  · 重复度：按「空行分段」统计完全重复的段块，重复块占段块总数 > MAX_DUP_RATIO（默认 0.5）⇒ 红
```

**它自述的实测依据与本次调查完全吻合**：
- `memory/2026-10-22.md` 在 gitcode/main 上长到 **613.31 MB / 3,698,202 行**
- `## R70 …` 标题出现 **180,386 次**，不同章节只有 **51 个**
- 历史里每提交增长约 **87 MB**（87 → 174 → 261 → 348 → 435 → 522 → 610）

**⚠️ 但这与本报告 G1 的读数有出入**：
```
d359c69b 自述：R70 出现 180,386 次 / 不同章节 51 个
本报告 G1 ：bug-triage 版 R70 = 8,085 次（593 MB 版）
            xd7gqcjf 版（昨天）= 19,110 次（384 MB 版）
```
**⇒ 三个数字对应三个不同版本，正是判例-53「跨 worktree 用读数当基准」的又一实例。**
**`check_memory_log_size.py` 的注释里写死了 180,386，若真入库，这个数字本身就是下一个漂移点。**

**它自述的第二条后果特别值得保留**：
> **GitHub 拒收**：`File memory/2026-10-22.md is 609.79 MB; this exceeds GitHub's file size limit of 100.00 MB`
> ⇒ **整条 origin 交付线被冻死**（`origin/master` 因此落后 `gitcode/main` 18 个提交）

**⇒ 这解释了本报告 §之前查到的「origin/main 落后 172」的根本原因之一** ——
不是 mirror 特性那么简单，而是**GitHub 拒收了这个 610 MB 的文件**。

### 4.2 不值得的部分：20+ 份 `memory/*.md` 入库

**这些文件正是本仓 `.gitignore:157 memory/2026-*.md` 要挡的东西。**

**若整支合入**：
1. 20+ 份流水账重新进跟踪面 ⇒ `.gitignore` 规则形同虚设（跟踪面优先于 ignore）
2. 其中 `memory/2026-10-22.md` 240 KB 会**重新带上重复度问题**
3. 与 `wt-salvage` 已保全的 88 项**大量重复**

### 4.3 结论

| 项 | 建议 |
|---|---|
| `scripts/check_memory_log_size.py`（154 行） | **值得单独摘取**，但须**去掉注释里写死的 180,386 等历史读数**（改成「见账本」或从一个真源反解） |
| `scripts/run_guards.py` 的 +2 行登记 | 随判据走（若摘判据则一并摘） |
| `scripts/README.md` 索引条目 | 同上 |
| **20+ 份 `memory/*.md`** | **不合**（`.gitignore` 已挡，且 `wt-salvage` 已保全） |
| `docs/2026-10-20-slave-tasks.md` 的锚点 | 唯 main 可判（锚点常漂移），单独核 |
| `plugins/*` 8 个文件 | **不合**（生成投影，须由 `gen_plugins.py` 从真源重生成，不许手改） |

**⇒ 一句话：整支不合；若要，只摘 `check_memory_log_size.py` + 它的 2 行登记 + README 索引条目，且须清掉写死的历史读数。**

---

## 5. 附带发现（与 Stage 3 直接相关）

### 5.1 origin/main 落后 172 的根因

`check_memory_log_size.py` 的注释给出了关键线索：

> **GitHub 拒收**：`File memory/2026-10-22.md is 609.79 MB; this exceeds GitHub's file size limit of 100.00 MB`
> ⇒ **整条 origin 交付线被冻死**（`origin/master` 因此落后 `gitcode/main` 18 个提交）

**⇒ 统帅此前裁定「`origin/main` 落后 = mirror 特性，不是要修的问题」——
这个判断需要修正：至少部分是「GitHub 拒收 610 MB 文件」导致的，不是设计意图。**

**这一条对 Stage 3 有直接影响**：即使做完 `reflog expire + gc --prune` 清了本地悬空对象，
**若那 610 MB 仍在历史里，push 到 GitHub 仍会被拒。**

### 5.2 这也解释了 bundle 为什么坏

**同一个 610 MB blob 让 `git bundle create --all` 产生父链不完整的 bundle**（详见 `stage3-preparation-execution.md` §3）。

---

## 6. 缺口与风险

| # | 项 | 说明 |
|---|---|---|
| G1 | **`d359c69b` 的作者是 `t <t@t>`** | 与坏 bundle 的根因同名。**需确认这是不是真实作者的笔误**（若真是测试夹具误提交，则整支可信度存疑） |
| G2 | **`check_memory_log_size.py` 未验证能否运行** | 我未 `git show` 出来跑过它的 `--selftest`（那需要检出该支，属写操作）。**若要合，必须先验证** |
| G3 | **该支无远程副本** | 只在本地，若被误删则丢失。**建议先 `git branch archive/memory-log-runaway d359c69b` 保一个 ref** |
| G4 | **§5.1 的结论需统帅确认** | 「origin 落后 = mirror 特性」这个既有裁定可能需要修正 |

---

**本报告未合并、未检出、未改动任何分支。主仓 `.git` 一字节未动。**

---

## 7. 补充核验（执行后追加）

### 7.1 父提交确认为 main 祖先 ✅

```
$ git merge-base --is-ancestor 0b8e3cd2 main
→ YES
```

**⇒ §3 的声明成立：`d359c69b` 直接挂在 main 的某个祖先上，技术上可干净 cherry-pick。**

### 7.2 28 份「真内容」已按裁决清理

```
起点：28 份 / 9.4 MB
保留：1cd7f910de3a (871,479 B，最大，含 6 个版本完整史)
      5f37ac06148b ( 31,626 B，最小，首版起点)
删除：26 份冗余（同一日志的中间 append 长度）
现状：2 份 / 892 KB
```

**依据**：G5 深查证明这 28 份是**同一日志的 28 个 append 长度**（首 60 字节哈希唯一首部数 = 1/28，
以最小版本为前缀 = 28/28），不是 28 份独立史料（判例-61 候选）。

### 7.3 `fix/memory-log-runaway` 无远程副本 —— 建议先保 ref

```
$ git rev-parse --verify archive/memory-log-runaway
→ 无
```

**该支只在本地，且无任何远程分支包含 `d359c69b`。若本地分支被误删，这支就没了。**

**建议**：`git branch archive/memory-log-runaway d359c69b`（保一个 ref）。
**我未执行** —— 该操作会写 `.git`，按纪律不擅自做，报统帅。
