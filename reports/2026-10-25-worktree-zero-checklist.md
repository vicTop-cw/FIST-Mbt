# Worktree 归零 checklist（Stage 3 前置）

> **服务对象**：`reports/2026-10-25-stage3-reflog-expire-checklist.md` §2 前置条件②
> **性质**：操作前检查清单，**本文档不含已执行动作**
> **起草**：commander-delta · 2026-10-25 · **执行者：β**（统帅派单）
> **判据来源**：判例-51（A 态 ≠ 可恢复）、判例-59（口径自证）

---

## 〇、目标

**`git worktree list | wc -l` 从 `6` → `1`（只剩主仓）。**

为什么 Stage 3 要求这个：`reflog expire --expire=now --all` 会清掉所有 HEAD 移动历史，
**若此时有 worktree 正在用它自己的 HEAD 做操作，可能造成引用不一致**。
归零是最保守的姿势。

---

## 一、现读基线（2026-10-25 实测，执行时必须重新现读）

```
$ git worktree list --porcelain

worktree E:/IDEProjects/AI/FIST-Mbt
HEAD 03e2f8c8aba362372fb46a65dd1efb3a05f15692
branch refs/heads/main                      ← 主仓，保留

worktree C:/Users/victo/AppData/Local/Temp/frp-wt
HEAD 04429a100c0a43401467afb804c7b6bfe8c78b96
branch refs/heads/fix/render-release-priority-master    ← 有独立分支

worktree C:/Users/victo/AppData/Local/Temp/mergeability-bn5486xy/wt
HEAD b5c8a36637348671ad224751672d1e636c9a21a7
detached                                     ← detached

worktree C:/Users/victo/AppData/Local/Temp/mergeability-okca3qgu/wt
HEAD 95e3808a067a22ff63edf330c927e82f46127a99
detached

worktree C:/Users/victo/AppData/Local/Temp/mergeability-xd7gqcjf/wt
HEAD b5c8a36637348671ad224751672d1e636c9a21a7
detached

worktree E:/IDEProjects/AI/light-wt/cmd-beta
HEAD d0fe7da5bc37f7e859d94c1fc672571be7f8a6c0
branch refs/heads/lightwt/cmd-beta            ← 有独立分支
```

### 逐项实测读数（2026-10-25）

| # | worktree | 类型 | 大小 | 脏条目 | **独有提交** | 判定 |
|---|---|---|---|---|---|---|
| 0 | 主仓 | main | — | — | — | **保留** |
| 1 | `Temp/frp-wt` | branch `fix/render-release-priority-master` | 62M | 1 | **0** | 待处置 |
| 2 | `Temp/mergeability-bn5486xy/wt` | detached | 17M | **104** | **0** | 待处置 |
| 3 | `Temp/mergeability-okca3qgu/wt` | detached | 18M | **100** | **0** | 待处置 |
| 4 | `Temp/mergeability-xd7gqcjf/wt` | detached | 17M | **58** | **0** | 待处置 |
| 5 | `light-wt/cmd-beta` | branch `lightwt/cmd-beta` | 110M | 3 | **0** | 待处置 |

**合计非主仓：5 个 / 224M / 独有提交全为 0。**

---

## 二、⚠️ 脏条目 ≠ 有独有内容（判例-51 + 判例-59 口径自证）

### 2.1 mergeability-* 的 104 条脏状态是什么

```
$ git -C <wt> status --porcelain | cut -c1-2 | sort | uniq -c
      1  D
     23 A
     79 AA      ← both added（冲突未解决）
      1 AD
```

**`AA` = both added = 合并冲突未解决的现场。**

### 2.2 但这是**试跑残留**，不是真实未提交工作

| 证据 | 读数 |
|---|---|
| 无 `MERGE_HEAD` | 三个 worktree 全部 **无 MERGE_HEAD** ⇒ 没有「合并进行中」 |
| 创建时间 | `Oct 23 23:38~23:39` —— **两天前的临时件** |
| 独有提交 | 全部 **0** |
| 来源 | `scripts/check_slave_mergeability.py` 在临时 worktree 里试跑 cherry-pick，留下冲突现场 |

⇒ **这是「别人的一次性探针留下的残骸」，不是任何人的在途工作。**

### 2.3 🔴 但 `git worktree remove` 仍会拒绝

```
fatal: '<wt>' contains modified or untracked files, use --force to delete it
```

**判例-51/59 强制要求：`--force` 前必须证明 blob 可恢复。**

---

## 三、逐项归零方案

### 3.1 三个 `mergeability-*`（detached，共 52M）

**唯一需要证明的一点**：那 104/100/58 条脏状态里有没有**独有内容**。

```bash
# 对每个 wt 执行（只读）
WT="C:/Users/victo/AppData/Local/Temp/mergeability-bn5486xy/wt"

# ① 独有提交必须为 0
git -C "$WT" log --oneline HEAD --not --all | wc -l          # 期望 0 ✅（已验）

# ② 每个 AA/A 文件的 blob 是否在历史里可寻址（判例-59：不看 status，看 git log）
git -C "$WT" status --porcelain | awk '{print $2}' | while read f; do
  h=$(git -C "$WT" log --all --format=%H -- "$f" 2>/dev/null | head -1)
  [ -n "$h" ] && echo "OK   $f" || echo "★无历史 $f"
done
```

**★无历史 的文件必须逐个看内容**（可能是试跑时新生成的）。判定为「无意义」后才可 `--force`。

**命令**：
```bash
git worktree remove --force "$WT"
```

**⚠️ 必须先完成 §3.1 的 ②，不能直接 `--force`。**

### 3.2 `Temp/frp-wt`（branch `fix/render-release-priority-master`，62M）

**这个有独立分支，比 detached 复杂**：

```bash
WT="C:/Users/victo/AppData/Local/Temp/frp-wt"
BR="fix/render-release-priority-master"

# ① 分支是否已并入 main（内容面判，判例-14：不用祖先关系）
git diff --diff-filter=A --name-only main "$BR" | wc -l     # 新增文件数

# ② 独有提交
git -C "$WT" log --oneline HEAD --not --all | wc -l          # 已验 0

# ③ 那条 1 个脏条目是什么
git -C "$WT" status --porcelain
```

**处置**：
- 若分支已并入 main ⇒ `git worktree remove --force "$WT"` + `git branch -D "$BR"`
- 若分支未并入 ⇒ **先报统帅**（可能是需要保留的通道分支）

**⚠️ 删分支属不可逆**，本文档只列判据，**执行权在 β/统帅**。

### 3.3 `light-wt/cmd-beta`（branch `lightwt/cmd-beta`，110M）

**这是司令沙箱**（light-wt 命名空间）。

```bash
WT="E:/IDEProjects/AI/light-wt/cmd-beta"
BR="lightwt/cmd-beta"

# ① 独有提交
git -C "$WT" log --oneline HEAD --not --all | wc -l          # 已验 0

# ② 3 个脏条目
git -C "$WT" status --porcelain

# ③ 分支内容是否已在 main
git diff --diff-filter=A --name-only main "$BR" | wc -l
```

**⚠️ 特别注意**：`cmd-beta` 是别的 agent 的沙箱。
**若该 agent 仍 active，删除会打断它的工作** —— 执行前必须确认统帅/该 agent 已放行。

---

## 四、执行顺序

```
第 0 步  现读基线：git worktree list --porcelain（不信本文档的快照 —— 判例-10c）
第 1 步  §3.1 三个 mergeability-*：逐个跑「无历史文件」检查 → --force
第 2 步  §3.2 Temp/frp-wt：判分支是否已并入 → 报统帅 → 处置
第 3 步  §3.3 light-wt/cmd-beta：确认 agent 放行 → 处置
第 4 步  git worktree prune -n            # 查死登记
第 5 步  验收
```

---

## 五、验收判据

| 判据 | 命令 | 期望 |
|---|---|---|
| worktree 数 | `git worktree list \| wc -l` | **1** |
| 无 detached | `git worktree list \| grep -c detached` | **0** |
| 无死登记 | `git worktree prune -n` | **无输出** |
| 主仓完好 | `git status --porcelain \| wc -l` | 与归零前一致 |
| 主仓 HEAD | `git rev-parse --short HEAD` | 与归零前一致 |
| `.git/worktrees` 清空 | `ls .git/worktrees 2>/dev/null \| wc -l` | **0** |

---

## 六、回滚

**worktree remove 是低风险操作**（分支保留、提交保留），回滚方式：

```bash
# 若误删了需要的 worktree
git worktree add <原路径> <原分支或原HEAD sha>
```

**⚠️ 唯一不可逆的是 `git branch -D`** ——
本文档 §3.2/§3.3 若涉及删分支，**必须统帅单独签字**。

---

## 七、边界（本文档不涉及）

| 不涉及 | 理由 |
|---|---|
| 删除任何 git 分支 | 属不可逆，需单独签字 |
| `git worktree prune`（真执行） | 只列 `-n` 预览 |
| 动主仓工作树 | 只判 5 个非主 worktree |
| `.git` 任何写操作 | Stage 3 方案 B 才动，且需 owner 签字 |

---

## 八、给 β 的一句话

**5 个 worktree 独有提交全为 0，但 3 个 mergeability-* 有 79 个 `AA` 冲突残留 ——
那不是「未提交工作」，是 `check_slave_mergeability.py` 试跑留下的现场（无 MERGE_HEAD、两天前）。

**但 `--force` 之前仍须跑 §3.1 的 ②「无历史文件」检查** ——
判例-59：`git status` 的 `A`/`AA` 标记 ≠ blob 不在对象库，要看 `git log --all -- <path>`。**
