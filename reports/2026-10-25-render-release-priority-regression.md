# `fix/render-release-priority-master` 基线倒退核查报告

> **指令**：统帅裁决「先核删了什么 → 若 main 还有则不删 → 若 main 也删了则那是误删需恢复」
> **核查人**：司令-γ · 2026-10-25
> **结论**：**这是真基线倒退，且倒退的是「判例-9 的整套修复」——建议 DROP（不删、不合）**

---

## 1. 它删了什么

```
$ git diff --name-status main...origin/fix/render-release-priority-master
D  .github/workflows/sync-from-gitcode.simulate.sh     ← 删了 16 格真跑模拟跑手
M  .github/workflows/sync-from-gitcode.yml             ← 把判例-9 的修复整条退回
M  scripts/render_dsh_patch.py                         ← 它自己的改动
```

**main 上这两个文件都在**（`git cat-file -e main:...` 命中）⇒ **删它们就是倒退**。

---

## 2. 关键证据：分支把「判例-9 修复」整条退回去了

**main 版**（我昨天落盘，`40e7f024`）：
```
OK=0; FAIL=0; FAILED_LIST=""
for b in $BRANCHES; do
  if git push --force gh "$b:$b" 2>/dev/null; then OK=$((OK+1)); else FAIL=$((FAIL+1)); …
done
echo "::notice::branch sync: OK=$OK FAIL=$FAIL"
echo "::warning::failed branches: $FAILED_LIST"
```

**分支版**（48 行，退回旧写法）：
```
命中计数：
  for b in              → 1
  OK=0                  → 0        ← 计数没了
  ::notice::branch sync → 0        ← 聚合读数没了
  || echo               → 2        ← 静默吞回来了
  || true               → 4        ← && 静默吞
```

**⇒ 这不是「小删改」，是把「102 支静默失败」那个坑重新挖开。**

---

## 3. 我的守卫判它红（6 条违例）

`scripts/check_sync_workflow_reports_failures.py` 对分支版 workflow：

```
读数：run 块 1 / push 行 3 / 聚合 echo 0
VIOLATION [S1] 静默吞失败（rc 归零）      ×3
VIOLATION [S2] 缺聚合读数的 echo
VIOLATION [S3] 缺 ::warning::failed branches: 形态的失败点名行
VIOLATION [S4] 缺「枚举面为空」守卫
```

**⇒ 这是我昨天立的判据当场抓住的。判例-9 的守卫锁住了倒退。**

---

## 4. 它自己的改动是什么

`scripts/render_dsh_patch.py` 的 2 个文件改动 —— 这部分是它**真正的增量**，
但被「倒退两个 sync 文件」包在一起。

**若要保留它自己的增量，只能单摘 `render_dsh_patch.py`，绝不可整支合。**
（判例-1：基线倒退只取分支独有那一小段，不整支 cherry-pick。）

---

## 5. 建议处置

| 方案 | 评价 |
|---|---|
| **A. DROP（不删、不合）** | ⚠️ 但它当前的顶树会让「若有人误合」重新引入判例-9 的坑 |
| **B. 蒸馏 `render_dsh_patch.py` 增量 → 删分支** | ✅ **我建议这个**：保住它的真增量，同时消除误合风险 |
| **C. 直接删，不蒸馏** | 会丢 `render_dsh_patch.py` 的改动（需先确认该改动在 main 有没有等价物） |

**我建议 B**，但删分支前需确认：β 正在删的 `Temp/frp-wt` worktree **是否引用这支**
（统帅已提醒：「β 正在删 `frp-wt` worktree，引用的正是这个分支。顺序：你核完 → 我通知 β 再删」）。

**⇒ 本报告只核，不动分支。等统帅通知 β 后再删。**

---

## 6. 来源

- 分支：`origin/fix/render-release-priority-master`
- 判据：`git diff --name-status main...<br>` + `git cat-file -e` + `check_sync_workflow_reports_failures.py` 实测
- 判例：1（基线倒退）· 9（静默失败）+ 我的 S1–S5 守卫 · 41（远端读数）· 54（判存在不判输出）
