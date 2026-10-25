# Stage 3（历史压缩）前置检查清单

> **文种**：前置检查清单 · **性质**：只读分析产出，**本文件不执行任何压缩/写操作**
> **日期**：2026-10-25 · **执行**：commander-alpha
> **用途**：filter-repo 不可逆。执行前必须逐条过本清单；**任一条不满足 ⇒ 不执行**。
> **权威读数**：本文所有数字均为 2026-10-25 10:2x 现读，非引用历史报告。

---

## 0. 一句话结论

**当前不满足执行条件。** 两条硬前置未达成：

| 前置 | 现状 | 结论 |
|---|---|---|
| **worktree 归零** | 还有 **5 个非主 worktree** | 🔴 **未满足** |
| **三端一致** | `origin/main` 落后 **171 个提交** | 🔴 **未满足** |

**⇒ Stage 3 执行前必须先清 worktree + 三端对齐。** 另有 8 条须逐条核验。

---

## 1. 压缩能省多少：现读数据（为第 6 条备料）

```
.git 总体积                     2.0 GB
打包体积 (size-pack)            1.91 GiB  / 168 packs
松散对象                        9.58 MiB  / 1007 objects
prune-packable                  654

memory/2026-10-22.md 在历史里：
  版本数                        56
  合计                         2268.8 MB
  最大单版                      610.3 MB

全部 >1MB blob：
  数量                          41
  合计                         2296.0 MB
```

**⇒ 结论：`memory/2026-10-22.md` 一个文件占了 `.git` 的绝大部分（2268.8 / 2296.0 ≈ 98.8%）。**
**压缩的收益 98.8% 来自这一个文件的 56 个版本。**

**⚠️ 这 56 个版本里绝大多数是污染**（去重后唯一行数 910 / 3,698,202 行 —— 见第 2 条判据）。
**但「哪些版本是污染」尚未逐个验证** —— 执行前必须做（见第 6 条）。

---

## 2. 十条检查项

### 检查 1：压缩前必须知道「哪些 blob 是唯一的」

**为什么**：压缩前若不知道哪些 blob 被引用，可能删掉仍在用的历史。

**怎么查**：
```bash
git rev-list --objects --all | sort -k2 | awk '{print $1}' | sort -u | wc -l   # 全部可达对象
git rev-list --objects --all -- memory/2026-10-22.md                            # 该文件的全部版本
```

**🚩 红线（判例-24）**：`git rev-list HEAD --not --all` 在 **sibling repo 场景下恒为 0**，
**不能当作「无独有提交」的证据**。必须用 `--not <main 全部 ref>` 显式列出排除面：
```bash
git -C <wt> rev-list HEAD --not $(git -C E:/IDEProjects/AI/FIST-Mbt rev-parse --all)
```

**回滚预案**：这一步只读，无副作用。

---

### 检查 2：大 blob 不一定是垃圾 —— 判据是「去重后唯一行数」

**为什么**：613 MB 看着像垃圾，但**大 ≠ 垃圾**。必须证明。

**怎么查（四条同时成立才算污染）**：
```bash
F=memory/2026-10-22.md
wc -l          "$F"    # ① 全文件行数
sort -u "$F" | wc -l   # ② 去重后唯一行数（污染 ⇒ 占比极低）
grep -oE '^## R[0-9]+' "$F" | sort -u | wc -l   # ③ 标题种类数
# ④ 字节/行 = 总字节 / 总行数（正常行长度 ⇒ 非二进制损坏）
```

**实测标定**（`bug-triage` 的 613 MB 版本）：
```
① 3,698,202 行
② 910 行唯一（0.0246%）    ← 关键判据
③ 38 种 R 标题
④ 174 B/行
⇒ 污染实锤（每 457 行一个 R70、每 18 行重复一次）
```

**🚩 红线（判例-53）**：**不能拿另一个 worktree 的同名文件读数当期望值。**
同名文件在不同 worktree 里是**分叉**的（判例-48）——昨天 `xd7gqcjf` 那份是 384 MB / R70=19,110，
`bug-triage` 那份是 613 MB / R70=8,085。**两份不同版本，基准不能互用。**

**回滚预案**：只读。

---

### 检查 3：压缩改写历史 ⇒ 所有 worktree / 分支 SHA 全变 ⇒ **必须 worktree 归零后做**

**为什么**：filter-repo 重写所有 commit 的 SHA。任何登记在案的 worktree 其 `HEAD` 指向的
commit 在压缩后**不再存在** ⇒ 该 worktree 变成悬空（`fatal: not a valid object name`）。

**怎么查**：
```bash
git worktree list | wc -l            # 必须 == 1（只有主工作树）
git for-each-ref --format='%(refname)' refs/heads | wc -l   # 本地分支：确认是否要保留
```

**现读**：
```
$ git worktree list | wc -l
6        ← 🔴 未满足（应为 1）

  主工作树
  Temp/frp-wt                        ← 别人的（fix/render-release-priority-master）
  Temp/mergeability-bn5486xy/wt      ← 审计组判
  Temp/mergeability-okca3qgu/wt      ← 审计组判
  Temp/mergeability-xd7gqcjf/wt      ← 审计组判
  light-wt/cmd-beta                  ← 3 个 R 态属别人在途（判例-57）
```

**🚩 红线**：**worktree > 1 ⇒ 不执行。** 尤其别人的 worktree（`frp-wt` / `cmd-beta`）
压缩后会让**别人正在做的工作全部失效**，且他们可能不知道发生了什么。

**回滚预案**：无 —— 这一步的损失是「别人的工作树失效」，无法回滚（只能重建 worktree，
但工作树里的未提交改动**永久丢失**）。

---

### 检查 4：`git filter-repo` 会让 `rev-list` / `git cherry` 全部失效（判例-1）⇒ 压缩后只剩 `diff` 可信

**为什么**：filter-repo 重写后，commit 的 patch-id 全变。`git cherry`（按 patch-id 比对）
会把「已合并」判成「未合并」；`rev-list` 的区间语义也会变（因为 SHA 变了）。

**怎么查**：压缩前**先把需要的判断结论落成文件**，不要留到压缩后现查：
```bash
git log --oneline --all > _archive/pre-filterrepo-all-commits.txt
git branch -a --format='%(refname) %(objectname)' > _archive/pre-filterrepo-refs.txt
git tag -l --format='%(refname) %(objectname)' >> _archive/pre-filterrepo-refs.txt
```

**🚩 红线**：**压缩后的任何结论都必须用 `diff` 重算，不得引用压缩前的 `rev-list`/`cherry` 结果。**

**回滚预案**：这份落盘快照本身就是压缩后的「历史对照表」。

---

### 检查 5：压缩不可逆 ⇒ 必须先 `git clone --mirror` 一份完整备份

**为什么**：filter-repo 是**破坏性重写**，没有内置 undo。

**怎么查/做**：
```bash
# 备份到仓库外（不要放在仓库内，否则会被算进打包面）
git clone --mirror E:/IDEProjects/AI/FIST-Mbt E:/IDEProjects/AI/FIST-Mbt-backup-pre-stage3.git

# 核验备份完整
git -C E:/IDEProjects/AI/FIST-Mbt-backup-pre-stage3.git rev-parse HEAD      # == 主仓 HEAD
git -C E:/IDEProjects/AI/FIST-Mbt-backup-pre-stage3.git count-objects -vH   # 对象数一致
```

**🚩 红线**：**备份必须与主仓 HEAD 一致且对象数一致**。备份不完整就等于没有备份。
**备份必须放在 `.git` 之外、且不在任何 worktree 子树内。**

**回滚预案**：`rm -rf 主仓 && git clone 备份 主仓`。**这是唯一的回滚路径**，
所以备份核验是十条里最不能省的一条。

---

### 检查 6：`memory/2026-10-22.md` 的 56 个版本 —— 必须逐个判「污染还是唯一内容」

**为什么**：省 98.8% 空间全靠这个文件，但**「大」不等于「全是垃圾」**。
56 个版本里可能有一个是**真正的首版**（有价值），其余是 append 污染。

**怎么查**：
```bash
# 列出全部版本的 (sha, size)
git rev-list --objects --all -- memory/2026-10-22.md | while read sha path; do
  printf "%10s  %s\n" "$(git cat-file -s "$sha")" "$sha"
done | sort -rn

# 逐个跑检查 2 的四条判据（尤其是「去重后唯一行数」）
for sha in <上面列出的 sha>; do
  git cat-file -p "$sha" > /tmp/v.md
  echo "$sha  行=$(wc -l < /tmp/v.md)  唯一=$(sort -u /tmp/v.md | wc -l)"
done
```

**判据**：唯一行占比 < 1% ⇒ 判污染。
**若某版本唯一行数正常**（如 > 万级唯一行）⇒ **可能是真内容，必须保留或单独保全**。

**🚩 红线**：**不许「因为文件名叫 memory/2026-10-22.md 就整个删掉」** ——
必须逐版本出「唯一行占比」读数，污染版才删。

**回滚预案**：备份（检查 5）里有全部 56 个版本。

---

### 检查 7：压缩前三端必须一致

**为什么**：压缩后本地 SHA 全变，推送时需要 `--force`。**若远端还有别的提交没拉下来，
一 force 就把别人的提交冲掉。**

**怎么查**：
```bash
git rev-parse HEAD
git ls-remote --heads gitcode main | cut -f1
git ls-remote --heads origin main  | cut -f1
git ls-remote --heads gitcode master | cut -f1
git ls-remote --heads origin master  | cut -f1
```

**现读（2026-10-25 10:2x）**：
```
local main      : 6030494b628be419fb167f7eae60e3066c39ea79
gitcode/main    : 6030494b628be419fb167f7eae60e3066c39ea79   ✅ 一致
origin/main     : 9e6b196f566284209d2c4594407bb32f9c155b1c   🔴 **落后 171 个提交**
gitcode/master  : 5e769af348259ef29a666dc860ef215d36f9ba34
origin/master   : 80d97a203a3e625b40e09ee9333a50b72dce2188
```

**🚩 红线**：**任意一端不一致 ⇒ 不执行。**（当前 `origin/main` 落后 171 ⇒ **不满足**）

**回滚预案**：先推齐三端（快进 push，不需 force），再重新过本条。

---

### 检查 8：压缩后必须验证「行为面没变」

**为什么**：filter-repo 只改历史，不该改工作树。但**必须证明**，不能假设。

**怎么查（压缩后立即跑）**：
```bash
moon check --target js                 # 必须 0 errors
python scripts/moon_test_env.py        # 必须 Total tests: 1457, passed: 1457, failed: 0
python scripts/run_guards.py --list    # 必须「缺执行面 0」，格数与压缩前一致
python scripts/check_doc_surface.py    # 必须 PASS（工具数 170 不变）
```

**基线（压缩前必须先记录）**：
```
格数 / 尺数 / 测试数 / 工具数  ← 四项必须在压缩前落一份读数，压缩后逐项对比
```

**🚩 红线**：**任何一项数字变了 ⇒ 立即从备份恢复并报 owner。**
**尤其注意**：`moon test` 的 rc 不可靠（BUG-142），**必须解析 `Total tests:` 汇总行**。

**回滚预案**：从检查 5 的备份 clone 回来。

---

### 检查 9：压缩必须 owner 裁决（不可逆）—— 方案 + 预案给 owner，不自己执行

**为什么**：本仓 AGENTS「金条四」：不可逆操作只给方案，执行权留在 owner。

**怎么查/怎么做**：
1. 本文（前置检查清单）作为**方案的一部分**
2. 附**预估收益**（检查 1/6 的数据：预计省约 2.2 GB 中的 98.8%）
3. 附**预估风险**（检查 3/7/8 的三条红线）
4. 附**回滚预案**（检查 5 的备份路径与核验命令）
5. **owner 明确批准后才执行**

**🚩 红线**：**本清单的任何执行动作都不得由写清单的人自己发起。**

**回滚预案**：不执行 = 无损。

---

### 检查 10：保留 rollback insurance —— 62 支已删分支的 tip

**为什么**：2026-10-24 的清理删了 62 支本地分支。
虽然它们的 commit 对象**大多仍可达**（被 main 或其它 ref 引用），但
**filter-repo 会重写全部 commit ⇒ 那些 tip 的 SHA 全部作废**。

**怎么查**：
```bash
# 62 支的 tip 记录在：
#   reports/2026-10-24-branch-cleanup-execution.md  §3（65 行逐支表，含 tip sha）
# 压缩前核验：这些 tip 是否仍可达
python scripts/check_commit_reachable.py  # 若无此脚本，用下面这条手工核：
for sha in <62 个 tip>; do git cat-file -e "$sha" 2>/dev/null && echo "OK $sha" || echo "GONE $sha"; done
```

**🚩 红线**：**压缩前必须把 62 个 tip 的「内容」而不只是「SHA」保全下来。**
做法：`git format-patch` 或 `git bundle create` 落 `_archive/`：
```bash
git bundle create _archive/pre-stage3-deleted-branch-tips.bundle <62 个 tip sha>
```
**bundle 是自包含的** —— 压缩后即使 SHA 变了，bundle 里仍是压缩前的历史。

**回滚预案**：`git clone _archive/pre-stage3-deleted-branch-tips.bundle` 可取回全部 62 个 tip。

---

## 3. 执行顺序（前 5 步全是只读/落盘，第 6 步才动 .git）

```
第 1 步：跑检查 1 / 2 / 4 / 6 的只读普查 → 落 _archive/pre-stage3-census.txt
第 2 步：跑检查 5 的 --mirror 备份 → 核验 HEAD + 对象数一致
第 3 步：跑检查 10 的 bundle 保全 → 核验 62 个 tip 可取
第 4 步：跑检查 3 的 worktree 归零 + 检查 7 的三端对齐
第 5 步：记录检查 8 的基线四项读数
第 6 步：owner 批准 → 执行 filter-repo → 跑检查 8 验证
第 7 步：三端 force push（需 owner 二次确认）→ 再跑一遍检查 8
```

**任何一步不满足 ⇒ 停在该步，报 owner。**

---

## 4. 当前状态汇总（2026-10-25 10:2x 现读）

| 检查项 | 状态 | 读数 |
|---|---|---|
| 1 唯一 blob 普查 | ⚪ 未做 | — |
| 2 大 blob 污染判据 | 🟡 部分（1 个样本已证：613 MB 版本唯一行占比 0.0246%） | 56 个版本待逐个 |
| **3 worktree 归零** | 🔴 **未满足** | **6 个（应为 1）** |
| 4 落盘快照 | ⚪ 未做 | — |
| 5 --mirror 备份 | ⚪ 未做 | — |
| **6 56 版本逐个判** | ⚪ 未做 | 已列版本数 56 / 合计 2268.8 MB |
| **7 三端一致** | 🔴 **未满足** | **origin/main 落后 171** |
| 8 基线四项 | ⚪ 未做 | — |
| 9 owner 裁决 | ⚪ 未做 | — |
| 10 62 tip bundle | ⚪ 未做 | — |

**⇒ 10 条里 2 条明确不满足、8 条未开始。Stage 3 当前不可执行。**

---

## 5. 缺口与风险

| # | 缺口 | 说明 |
|---|---|---|
| G1 | **56 个版本的污染判定未做** | 只知道 1 个样本（613 MB）是污染。**其余 55 个版本必须逐个跑「唯一行占比」** —— 可能有真正有价值的首版 |
| G2 | **`origin/main` 落后 171** | 需先快进推齐。**注意**：这不是我能单方面做的（涉及推远端） |
| G3 | **压缩收益的 98.8% 来自一个文件** | ⇒ 若 owner 不接受删 `memory/2026-10-22.md` 的全部历史，**压缩收益会从 2.2 GB 降到几十 MB**（其余 >1MB blob 合计仅 27 MB）。**这个取舍必须 owner 知情** |
| G4 | **别人的 worktree（`frp-wt` / `cmd-beta`）** | 压缩会让他们失效。需先协调他们收工 |
| G5 | **`git bundle` 的 62 tip 保全** | 我尚未做。这是压缩前唯一能把「已删分支历史」带过压缩的手段 |

---

**清单完成。未执行任何压缩动作，未碰 `.git`，未做任何写操作。**
