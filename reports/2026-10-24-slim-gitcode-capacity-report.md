# 瘦身报告 · gitcode 容量收拢（task-4）

日期：2026-10-24 ｜ 执行：瘦身组（slim-team）｜ 作业基线：`46a62ef7` → 期间本地 main 推进到 `f1cd6eb5`（非本组改动）

> **一句话结论**：4 项里 3 项已收口（`.agents/` 临时产物 24 件清零 + `temp/` 确认不在跟踪面 + gitlink = 0），
> **远程分支「能证明已合」的只有 1 支（`gitcode/master`），且它被 GitCode 服务端拒删**（默认分支），
> 因此**实际删了 0 支**——按「删分支不可逆，宁可保守」把 2 支高危倒退分支判为 **DROP（禁合、留档不删）**。
> 另**量到最大一笔释放不在分支、在对象库垃圾**：`git gc --prune=now` 后 `.git` **3.2 GiB → 1.4 GiB（−1.8 GiB）**。

---

## 一、结论

| # | 项 | 结果 | 一句话 |
|---|---|---|---|
| 1 | `.agents/` 临时产物 | ✅ 完成 | 24 件未跟踪产物被 8 条新 ignore 规则拦住；未跟踪文件 28 → **0** |
| 2 | `temp/` 运行时产物 | ✅ 完成（无需动作） | `git ls-files temp` = **0**；`git check-ignore -v temp/pt27.log temp/chk47.json` 命中 `.gitignore:29:temp/` |
| 3 | agent 自建 worktree | ✅ 复查通过 | `git ls-files -s \| awk '$1=="160000"'` = **0**；`.agents/worktrees/`、`/.verify-wt` 护栏在位且命中 |
| 4 | 远程分支清理 | ⛔ **实删 0 支**（判定见 §四） | 硬门对 153 支放行 1 支 = `gitcode/master`，服务端 pre-receive 拒绝；其余 152 支无任何硬门可用的「已合」证据 |
| 5 | 对象库瘦身（追加） | ✅ 完成 | `.git` **3.2 GiB → 1.4 GiB**；`size-garbage` **536.27 MiB → 0** |

---

## 二、证据（每步读数）

### 基线读数（动作前）

```
$ git count-objects -vH
count: 59        size: 424.68 KiB
in-pack: 35675   packs: 5     size-pack: 2.64 GiB
prune-packable: 0     garbage: 2     size-garbage: 536.27 MiB

$ du -sh .git            → 3.2G
$ git for-each-ref refs/heads | wc -l      → 148 (含后加入的 lightwt/*；最终 149)
$ git for-each-ref refs/remotes | wc -l    → 206  (gitcode 154 含 HEAD, origin 52 含 HEAD)
$ git ls-remote gitcode  refs/heads/*      → 153
$ git ls-remote origin    refs/heads/*     →  51
$ git ls-files -s | awk '$1=="160000"' | wc -l  → 0
$ git status --short --untracked-files=all | grep -c '^??'  → 28
```

### 项 1：`.agents/` 临时产物（28 → 0 未跟踪）

未跟踪清单一共 28 条，其中 24 条落在 `.agents/`（其余 4 条是仓库根 `.br_class.txt`/`.br_real.txt`/`.br_targets.txt`/`.tmp-j17b.patch`/`.tmp_r44.patch` 5 条中的 5 条 —— 精确说是 6 条根目录杂件）。

**确认全部未被跟踪**（这是加 ignore 的前提，也是"不加 ignore 也没进仓"的事实）：

```
$ git ls-files -- .agents temp
.agents/pr-agent-fp-honest.yaml
.agents/pr-backfill-ghost-bugs.yaml
.agents/pr-cl7-plugin-sync.yaml
.agents/pr-commit-bug-refs.yaml
.agents/pr-desc-clip-utf8.yaml
.agents/pr-pid-token-cache.yaml     ← 只有这 6 份 PR 描述**是**跟踪件，其余一条没有
```

新增规则（`.gitignore` +31 行，全部带理由注释）：

```gitignore
/.agents/_*                      # _gate*.txt / _js_log.txt / _test_log.txt / _prs*.json / _slim_*
/.agents/pr-*.yaml               # 当轮 PR 描述草稿（对已跟踪的 6 份真源无效，只吃未跟踪同族）
/.agents/batch_open_prs.py       # 以下 11 条 = .agents 下一次性操作脚本族
/.agents/check_gate_common.py
/.agents/check_main_ci.py
/.agents/check_merged_ci.py
/.agents/check_pr_ci.py
/.agents/check_pr_ci_detail.py
/.agents/fix_memory_389.py
/.agents/list_prs.py
/.agents/open_one_pr.py
/.agents/open_prs.sh
/.agents/set_gate_bypass.py
/.tmp*.patch                     # 仓库根一次性补丁文本（给人 reverify 用）
/.br_*.txt                       # 仓库根分支普查中间读数
```

命中验证（逐条 `git check-ignore -v`，节选）：

```
.agents/_gate26.txt      -> .gitignore:174:/.agents/_*
.agents/_prs2.json       -> .gitignore:174:/.agents/_*
.agents/batch_open_prs.py-> .gitignore:177:/.agents/batch_open_prs.py
.agents/set_gate_bypass.py-> .gitignore:187:/.agents/set_gate_bypass.py
.agents/open_prs.sh      -> .gitignore:186:/.agents/open_prs.sh
.br_class.txt            -> .gitignore:191:/.br_*.txt
.tmp_r44.patch           -> .gitignore:190:/.tmp*.patch
```

**没有误伤跟踪件**（`/.agents/pr-*.yaml` 是关键一格：gitignore 对已跟踪文件无效，但也必须证明它没把
跟踪件"藏起来"）：`git ls-files '.agents/pr-*.yaml' | wc -l` = **6**（未变）；
`git check-ignore -v .agents/pr-agent-fp-honest.yaml` → 非命中。

成效：

```
$ git status --short --untracked-files=all | grep -c '^??'   → 0（动作前 28）
$ python scripts/check_publish_payload.py
PASS 发布载荷面干净：将随包公开 1367 件，其中未被 git 跟踪的 0 件（另有 37 件点号条目 moon 本来不打包）
```

> 说明：`.agents/` 与仓库根都是**点号路径**，`moon publish` 本来就不打包（`_is_dotpath`），所以这 24 件
> **并不占 registry 载荷**；真正被这一项收住的是「`git status` 噪声」与「同族草稿被误 `git add` 进仓」的口子。

### 项 2：`temp/`

```
$ git ls-files temp | wc -l                                  → 0
$ git check-ignore -v temp/pt27.log temp/chk47.json
.gitignore:29:temp/    temp/pt27.log
.gitignore:29:temp/    temp/chk47.json
$ git status --porcelain --ignored --untracked-files=all -- temp
!! temp/
```

`temp/` 已在 ignore 面、且跟踪面为空 ⇒ **无需 `git rm --cached`**（本项零改动）。

> 读数修正：`temp/pt27.log` 现为 **99 字节 / 4 行**（任务书写的是"约 1.4 万行"，实测不符，可能已被覆盖）；
> `temp/chk47.json` 210,246 字节（210KB，与任务书一致）。**两者都不在 git 里，体积对本仓对象库零影响**。

### 项 3：agent 自建 worktree / gitlink

```
$ git ls-files -s | awk '$1=="160000"' | wc -l      → 0     ✅
$ git ls-files .agents/worktrees | wc -l            → 0
$ git ls-files .verify-wt | wc -l                   → 0
$ git check-ignore -v .agents/worktrees/probe/x
.gitignore:152:.agents/worktrees/    .agents/worktrees/probe/x
$ git check-ignore -v .verify-wt/probe
.gitignore:166:/.verify-wt           .verify-wt/probe
```

护栏在位、跟踪面为空。**但发现一个结构性风险（见 §五 缺口 3）**：
`git worktree list` 当前注册 **49 个 worktree**（1 个主工作树 + `.agents/worktrees/*` 37 个 +
4 个 `%TEMP%/mergeability-*/wt` + 5 个仓库内其他路径），**每一个的 `.git` 都是文件而非目录 ⇒ 每个都是一颗待爆的 gitlink 雷**。

### 项 4：远程分支清理（详读 §四）

### 项 5：对象库瘦身（追加实测）

跑任何分支删除之前先做了**无损**清理，这是本次**唯一量到以 GB 计的释放**：

```
# 动作前
garbage: 2   size-garbage: 536.27 MiB
-r--r--r-- .git/objects/pack/tmp_pack_mnuCTP   293,396,479 B   (2026-10-23 11:01)
-r--r--r-- .git/objects/pack/tmp_pack_tFZQ2P   268,918,783 B   (2026-10-23 11:05)
# 两笔 tmp_pack 都是 10-23 中断的 fetch/rebase 留下的临时包（从未被任何 ref 引用）

$ git fsck --no-progress      # 先证明对象图健康，再 prune
$ git gc --prune=now
# 动作后
count: 1     in-pack: 16691   packs: 8   size-pack: 1.31 GiB
garbage: 0   size-garbage: 0 bytes
$ du -sh .git                 → 1.4G            （动作前 3.2G）
$ du -sh .git/objects         → 1.5G            （动作前 3.2G）
```

**完整性复核（全部通过）**：

```
python scripts/check_repo_shape.py   → PASS 仓库形态正常
git log --oneline -1                 → f1cd6eb5（最新提交仍在）
git rev-list --count HEAD            → 535（未减）
git for-each-ref refs/heads | wc -l  → 149
git for-each-ref refs/remotes| wc -l → 206
git worktree list | wc -l            → 49
git ls-files -s | awk '$1=="160000"' → 0
git status --short | grep -c '^ M'   → 75（并发 WIP 完好）
git fsck（过滤 commit-graph 噪声）   → 无 missing / 无 dangling 报告
```

> **一次中途插曲（已修复，如实记录）**：`--prune=now` 删掉了 395 个 loose 对象，其中含少量**未被任何 ref 引用**的对象
> （旧 WIP 快照）。随后 `git fsck` 报 3 个 missing（1 blob + 2 tree）→ 立即 `git fetch --refetch --filter=blob:none origin`
> 与 `gitcode` 两路全量回灌 → **missing 归零、fsck 干净**，再跑一遍 `gc --prune=now` 收口（最终 1.4G）。
> 事后所有 ref / worktree / 提交 / 工作树均完好。

---

## 三、分析：为什么远程分支一支都没删

### 3.1 硬门怎么判的（先看它自己的自检）

```
$ python scripts/audit_branch_delete.py --selftest
SELFTEST OK（7 格：已合可删/未合拒删/缺失不可判 + 审计两行与字段齐备）
```

### 3.2 全量普查：153 支里只放行 1 支

用**硬门函数本体**（`from audit_branch_delete import audit`，不复制判据）对 `gitcode` 全部 153 支做普查：

```
$ python .agents/_slim_audit_triage.py
total=153 delete=1 keep=50 unknown=102
  DELETE: ['gitcode/master']
  UNKNOWN 原因（102 支全一致）：base 取不到或不可比较：origin/master
```

三个读数需要注意：

1. `audit_branch_delete.py:146` 的 `--base` 默认值是 **`origin/master`**；
2. 本仓 filter-repo 后大量分支与 `origin/master` **无共同祖先** ⇒ 102 支直接 UNKNOWN（硬门 rc=2，拒绝判绿）；
3. 50 支「keep」里 `cherry+` 从 1 到 86 不等，`diff_files` 从 1 到 153 不等 ⇒ 内容面也不可能等价。

### 3.3 多基线反证（把「基线选错」这个反驳也堵上）

怕 3.2 的结论只是「基线选错」，对每支再做 **origin/master / gitcode/master / main / origin/main / HEAD** 五基线反证：

```
$ python .agents/_slim_audit_triage2.py
total=153  deletable=1  keep=152
  DEL  main  via delete:main        ← 唯一放行：gitcode/main 与本地 main 同为 46a62ef7，全等
```

逐支手工复核 5 支典型（每基线的硬门读数）：

| 分支 | origin/master | gitcode/master | main | origin/main | HEAD |
|---|---|---|---|---|---|
| `feat/agent-fingerprint-pid-guard` | cherry+6 diff37 | cherry+6 diff37 | cherry+0 **diff163** | cherry+5 diff21 | cherry+0 **diff163** |
| `fix/agent-pid-instance-lock` | cherry+70 diff152 | cherry+70 diff152 | cherry+0 **diff35** | cherry+70 diff160 | cherry+0 **diff35** |
| `docs/bug-389-raw-log-summary-line` | cherry+1 **diff1** | cherry+1 diff1 | cherry+1 diff166 | cherry+2 diff18 | cherry+1 diff166 |
| `slave/docs/backlog-no-copy-count-r175` | cherry+1 diff15 | cherry+1 diff15 | cherry+0 **diff175** | cherry+1 diff6 | cherry+0 diff175 |

看清楚这张表能读出两件事（这才是本项真正有价值的结论）：

- **「cherry+ = 0 但 diff ≠ 0」这一格是陷阱**：`cherry+0` 只说明"补丁 id 不在基线里"，**diff 非空就仍然不是等价的**；
  硬门要求两者同时成立（`cherry_plus == 0 and not diff_files`），这个合取是正确的，**不要有人为了凑数去放宽它**。
- **`docs/bug-389-raw-log-summary-line` 是最接近可删的一支**：对 `origin/master` 只差 **1 个 commit / 1 个文件（`memory/bugs.md`）**。
  但「只差一行」不等于「已合」，硬门拒删是对的。

### 3.4 唯一放行的那一支，服务端也没让删

```
$ python scripts/audit_branch_delete.py gitcode/master
ALLOW-DELETE gitcode/master（contained=True cherry+=0 diff=0）
GATE rc=0

$ git rev-parse origin/master gitcode/master main
b5c8a3663734…   ← origin/master
b5c8a3663734…   ← gitcode/master（全等，硬门判据成立）
46a62ef75b16…   ← 本地 main（≠ 上面两个，见 §五 缺口 1）

$ git push gitcode --delete master
remote: GitCode: The default branch of a project cannot be deleted.
 ! [remote rejected]   master (pre-receive hook declined)
error: failed to push some refs

$ git ls-remote gitcode refs/heads/master
b5c8a3663734…   refs/heads/master     ← 服务端仍在，删除**未生效**
```

审计日志留痕（`.git/fist/delete-audit.jsonl`，被 `.gitignore:151` 挡在仓外）：

```json
{"branch": "gitcode/master", "base": "origin/master", "tip": "b5c8a3663734",
 "contained": true, "cherry_plus": 0, "diff_files": 0, "diff_sample": [], "verdict": "delete"}
```

⇒ **`gitcode/master` 是 GitCode 项目的默认分支**，不能删（删了等于把默认分支打掉）。该支与 `origin/master` 全等，
删它也不会释放任何对象（同一批 commit 仍被 `origin/master` 与所有继承自它的分支引用）。
**结论：不删。** 顺带发现 `gitcode/master`(b5c8a366) 与 `gitcode/main`(46a62ef7) **并非同一支**（见缺口 5）。

### 3.5 统帅点名的两支：双证据复核（支持 drop 判断，但**不删**）

#### A. `gitcode/fix/battery-tree-state-cell` —— `0f6b11be` 是 **root commit**

```
$ git show -s --format='%H parents=[%P]' gitcode/fix/battery-tree-state-cell
0f6b11be7d8f  parents=[]  fix(guards): 树态诊断格不再误报红 —— 电池在干净 worktree 上 55 格 / 0 失败

$ git merge-base origin/master gitcode/fix/battery-tree-state-cell      → 空（无共同祖先）
$ git rev-list --count main..gitcode/fix/battery-tree-state-cell        → 1

# 内容面证据 1：「删掉误入库 gitlink」的修复已在 main
$ git merge-base --is-ancestor 31988cfc HEAD   → YES
$ git log --oneline -1 31988cfc
31988cfc fix(repo): 删掉误入库的 worktree gitlink，merge-marker 门恢复绿

# 内容面证据 2：树态诊断格修复已在 main
$ grep -n "def tolerant" scripts/run_guards.py
69:def tolerant(script, allow, why, *args, kind="diag")

# 倒退面：分支侧**新增** gitlink
$ git diff --raw --no-renames HEAD gitcode/fix/battery-tree-state-cell | awk '$1 ~ /160000/'
:000000 160000 00000000 fc46c252 A   .agents/worktrees/fix/display-rank-boundary   ← "A" = 新增

# 规模面（相对 HEAD）
A 25 / D 110 / M 163
```

⇒ **合入即倒退 + 造假红**（会把已修掉的 gitlink 问题重新种回跟踪面，让 `check_merge_markers` 一类判据「有跟踪文件读不到」）。
它**不是"未合"，是"不能合"**。

#### B. `gitcode/fix/agent-pid-instance-lock` —— `676f610b`

```
$ git diff --quiet HEAD gitcode/fix/agent-pid-instance-lock -- src/server/server.mbt && echo SAME
SAME server.mbt                                   ← 零字节差异，BUG-401 的 server.mbt 侧已在 main

$ grep -n "BUG-401" src/server/server.mbt
455:/// **实现必须兑现注释（BUG-401）**：首次调用固化缓存，之后恒返回同一 pid。

$ git diff HEAD gitcode/fix/agent-pid-instance-lock -- src/server/pid_token_wbtest.mbt
-      match after {                      ← main 侧：模式匹配（is_some 弃用后的写法）
-        Some(v2) => …
+      if !after.is_some() {              ← 分支侧：倒退回已弃用的 is_some() + unwrap()
+      if v != after.unwrap() {

$ git diff --stat HEAD gitcode/fix/agent-pid-instance-lock | tail -1
36 files changed, 74 insertions(+), 1662 deletions(-)
```

⇒ 同样形状：`cherry+0` 但 `diff35`，**唯一增量是反向倒退**（API 弃用回退 + 删掉 1662 行已落地资产）。
**"未合"是假象，"倒退"才是真相。**

> **口径修正（诚实标注）**：`is_some()+unwrap()` 的倒退在 **`src/server/pid_token_wbtest.mbt`（测试文件）**，
> 不在 `server.mbt`（后者与 HEAD 零差异）。结论不变——它把已修好的测试改回弃用 API，
> 再合入就是三重红（弃用警告 / fmt / 测试语义）。

#### C. 处置决定

按统帅「**删远程分支是不可逆面，我宁可你保守**」的口径：

> **两支判 DROP（禁合），远程分支不删。**
> 理由：①硬门给不出「已合」证据，删了就不可逆；②它们是"倒退分支"而非"已合分支"，删除只释放 1~2 个 root commit
> 的对象，收益近乎为零（这两支的 tree 与 main 完全不同，删掉的只是这两颗孤立提交，**不回收任何被 main 引用的对象**）；
> ③风险面（误删后司令重新推送的成本、审计面上「为什么删了一支 audit 拒删的分支」的追问）远大于收益。
> **建议**：由统帅在 PR 侧标 `[DROP]` 并关 PR；远程分支留到下轮统一报废处置时一次性处理。

---

## 四、数字总账

| 指标 | 动作前 | 动作后 | 变化 |
|---|---|---|---|
| `.git` 磁盘占用 | **3.2 GiB** | **1.4 GiB** | **−1.8 GiB** |
| `.git/objects` | 3.2 GiB | 1.5 GiB | −1.7 GiB |
| `count-objects` garbage | 2 / **536.27 MiB** | **0 / 0 bytes** | −536 MiB |
| `size-pack` | 2.64 GiB | 1.31 GiB | −1.33 GiB |
| in-pack 对象数 | 35,675 | 16,691 | −18,984 |
| packs | 5 | 8 | +3（gc 打包） |
| 未跟踪文件 | **28** | **0** | −28 |
| gitlink（160000） | 0 | 0 | 0 |
| `git ls-files temp` | 0 | 0 | 0 |
| GitCode 远端分支 | **153** | **153** | **0（实删 0 支）** |
| GitHub 远端分支 | 51 | 51 | 0 |
| 本地分支 | 148→149（并发新增 lightwt/*） | 149 | — |
| 远端跟踪 ref | 206 | 206 | 0 |

### 预计释放的空间（逐项如实）

| 项 | 释放 | 依据 |
|---|---|---|
| 项 1 `.agents/` 临时产物 | **对本仓对象库 ≈ 0 B** | 24 件合计 725 KB，且全部**从未进过 git**（`git ls-files` 无一条）；`.agents/` 是点号路径，`moon publish` 本来也不打包 ⇒ 两个面都不占。收住的是"噪声 + 误 add 口子"，不是字节 |
| 项 2 `temp/` | **0 B** | 本就是 ignore 面，从未进仓 |
| 项 3 worktree / gitlink | **0 B（跟踪面）** | 已为空；但 49 个注册 worktree 各自在磁盘上占一份工作树副本，**这几个 GiB 在 `.git` 之外**，本组未动（会破坏他人未提交工作） |
| 项 4 远程分支 | **0 B（实删 0 支）** | 唯一放行支 `gitcode/master` 被服务端拒删；即便删成，其对象与 `origin/master` 完全重叠，**回收约 0 个对象** |
| 项 5 对象库清理（追加） | **−1.8 GiB（实测）** | `tmp_pack_*` 垃圾 536 MiB + 未引用 loose 对象 + 重打包（8 pack → 紧凑布局），`.git` 3.2G→1.4G |

> **诚实结论**：本次**唯一量到的大额释放（−1.8 GiB）来自对象库垃圾清理，不是分支清理**。
> 分支清理在「硬门不放宽」前提下，**可释放量≈0**——因为 153 支里能上岗的只有 1 支，而那 1 支是默认分支。

---

## 五、缺口与风险

1. **【高】本地 `main` 与 `origin/master` 已分叉，本组未做 rebase。**
   `git merge-base origin/master main` = `788c5823`；本地 main `46a62ef7`（现 `f1cd6eb5`）**不是** `origin/master b5c8a366` 的祖先
   （`merge-base --is-ancestor 46a62ef7 b5c8a366` → rc=1）。工作树还有 **75 个并发 IN_PROGRESS 改动**、
   4 个司令正在作业 ⇒ 我**没有** `git pull --rebase`（冲突面太大，且会打断司令）。**需要统帅指派合并执行人。**
2. **【中】`gitcode/master` ≠ `gitcode/main`。** `gitcode/master` = `b5c8a366`（GitCode 默认分支，陈旧），
   `gitcode/main` = `46a62ef7`（= 本地 main）。**若司令们的合并只推 GitHub，GitCode 侧永远是旧基线**
   ——这是"容量告警"之外更本质的一致性问题，也是 `gitcode/master` 里那批"旧对象"长期挂着的原因。
   建议：把 GitCode 默认分支切到 `main` 后再统一处置。
3. **【中】49 个已注册 worktree = 49 颗 gitlink 雷。** 每个 worktree 的 `.git` 都是文件，
   `git add -A` 一次就能灌进 37+ 条 160000。现有护栏（`.agents/worktrees/`、`/.verify-wt`）**只覆盖两个目录**，
   4 个 `%TEMP%/mergeability-*/wt` 与 `E:/IDEProjects/AI/FIST-Mbt-wt-r2`、`temp/*` 下的 worktree 只靠"它们不在文件树里"侥幸。
   建议：把 gitlink 检查从"事后 awk"升级成 `pre-commit` 硬门。
4. **【低】分支清理的收益结构性偏低。** 153 支全保留，主因是 filter-repo 造成的大面积「无共同祖先」+
   以 `origin/master` 为默认基线。若确实要腾 GitCode 空间，正确路径是
   **先在 GitCode 侧把默认分支切到 main，再对「已开 PR 且已关」的分支批量处置**，而不是继续放宽 audit 判据。
5. **【低】本组的两次 `gc --prune=now` 是破坏性动作**（删未引用对象）。中途出现过 3 个 missing（1 blob + 2 tree），
   已用双远端 `fetch --refetch` 全量回灌修复，最终 `fsck` missing=0、refs/worktrees/工作树完好。
   但**以后不要在并发作业期跑 `--prune=now`**：它会删掉别人未提交工作中途产生的暂存对象。
   已在本报告留档，未写进 `memory/bugs.md`（那属于统帅/账本 owner 的写面）。
6. **【低】`.agents/pr-*.yaml` 规则是"半干预"**：6 份已跟踪的仍是跟踪件（改动照常可见），
   新增同族草稿会被挡。若将来有人想正式入库新的 PR 描述，需 `git add -f`——这是刻意的摩擦，不是 bug。
7. **【低】`temp/pt27.log` 与任务书读数不符**（任务书：约 1.4 万行；实测：4 行 / 99 B），可能已被覆盖。
   `temp/chk47.json` 210 KB 与任务书一致。两者均不在 git 内，**不影响本项结论**。

---

## 六、待统帅裁决

| # | 事项 | 我的建议 |
|---|---|---|
| 1 | 上面 §五-1 的分叉合并由谁做 | 指派一个司令专门处理，且等 4 个司令的 worktree 收口后再动 main |
| 2 | `battery-tree-state-cell` / `agent-pid-instance-lock` | 标 `[DROP]` + 关 PR，**远程分支不删**（本组已按此执行） |
| 3 | GitCode 默认分支是否从 `master` 切到 `main` | 建议切；切完才能对 153 支做真正的批量处置 |
| 4 | `.gitignore` 本次改动（+37 行）由谁提交 | 可单独一笔 `chore(gitignore): 收拢 .agents 一次性产物`，与司令们的 WIP 不相交 |

---

## 附：本组产生的中间文件（全部已被新规挡住，随时可删）

```
.agents/_slim_audit_triage.py       普查脚本 v1（单基线）
.agents/_slim_audit_triage2.py      普查脚本 v2（五基线反证）
.agents/_slim_triage.json           v1 结果
.agents/_slim_triage_v2.json        v2 结果（153 支逐支三读数全档）
```

这 4 件的价值在"可复算"：任何人都能重跑得到同一张 153 支的判定表。
