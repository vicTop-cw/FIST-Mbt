# 远端主线错位 + gitcode 对象库超限 —— 处置方案（待 owner 裁决）

- 任务：TASK-REMOTE-DRIFT-202
- 记录时间：2026-10-23
- 结论：**漂移可测可治，体积超限属不可逆运维动作，执行权在 owner**。本文件只出方案与预案，不代执行。

## 一、现状（2026-10-23 15:4x 实测）

```text
$ python scripts/check_delivery_gap.py --compare origin/master gitcode/main
跨远端断层：origin/master → gitcode/main
  origin/master            独有 0 个提交
  gitcode/main             独有 2 个提交
  形态：ff（差异文件 7 个）
FAIL 单向落后：`origin/master` 落后 `gitcode/main`（可快进）
rc=1
```

- 漂移规模已从早前「5+ 提交、无共同祖先」收敛到 **2 个提交、可快进**（历史重写 + 同步已部分追平）。
- `git push gitcode` 持续告警：`git_repo size (2.8 GiB) exceeds limit (1.0 GiB)`。
- 613MB 日记历史虽已停跟踪，但对象库未 gc，仍在 gitcode 侧占 2.8 GiB。

## 二、漂移这一半：已可测、已给出口

1. **检测**：`scripts/check_delivery_gap.py --compare origin/master gitcode/main`
   已具备 `--compare` 能力（`main_compare`，2026-10-23 实测 rc=1 命中）。rc 契约：
   `0` 两侧一致 / `1` 单向落后 / `2` 无法取数。
2. **纳入日常**：每日巡检（或合入前体检）跑一次这一行即可，无需新增尺。
3. **补救动作**（可逆，agent 可直接做）：`git fetch origin gitcode && git push origin origin/master:refs/heads/master`
   让 `origin/master` 快进到 `gitcode/main`。若两侧已分叉（非 ff），先 `git merge-base` 确认，
   不硬推——**推平 `master` 是可见线，须 owner 点头后再动**。

## 三、体积超限这一半：不可逆，须 owner 裁决（本文件的重点）

| 方案 | 做什么 | 风险 | 收益 | 建议 |
|---|---|---|---|---|
| A. 只 gc | 在 gitcode 侧 `git gc --aggressive --prune=now` | 需服务器侧执行；本地推不动 | 压缩松散对象，可能降到 ~1GiB 以下 | **首选**，成本最低 |
| B. 镜像重建 | 用本地瘦仓（`--filter=blob:none` 或浅克隆后全量推）重建 gitcode 远端 | 远端 refs 会被替换，历史重写 | 彻底瘦身 | 备份当前 gitcode 后再做 |
| C. 历史截断 | 截断早期大对象历史 | 旧 commit sha 全部失效，所有 PR 分支基点变孤儿（正是本仓已踩过的坑） | 减到很小 | **不推荐**：会再次制造失基分支 |

**推荐路线**：先 A（gc），观察 push 是否恢复；若仍超限再 B；C 仅在 owner 明确接受「历史重写代价」时考虑。

## 四、预案（万一 push 被拒）

- push 被拒时**不要**删本地分支或强制重写——分支基点一变就是失基，等于把问题传给合并机器人。
- 保留本地 `gitcode/main` 快照：`git tag backup/main-before-resize`（在本地，不入远端）。
- 重建后按 `scripts/check_branch_ancestry.py` 重查所有 PR 分支，失基者按新 main 重开分支。

## 五、待办

- [ ] owner 裁决并执行方案 A 或 B
- [ ] 执行后复跑 `check_delivery_gap.py --compare origin/master gitcode/main` 应 rc=0
- [ ] `git push gitcode` 不再出现 size 告警
