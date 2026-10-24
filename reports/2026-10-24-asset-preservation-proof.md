# 资产保全证明书（Asset Preservation Proof）

> **文种**：证明书 · **性质**：只读审计产出，**本文件不执行任何删除**
> **日期**：2026-10-24 · **审计组主官**：audit-preservation · **任务**：task-9
> **基线**：`main = ffee8d522724b58679dfec69939758695a76b72e`
> **取证器**：`scripts/tmp_audit_preservation_scan.py`（纯只读，只跑 `rev-parse / merge-base / diff / log / cherry / for-each-ref / ls-files / status`）
> **机器读数**：`temp/audit/scan_full.json`（360 支全量）、`worktrees.json`、`siblings.json`

---

## 0. 一句话结论

**按本证明，可以无条件删除的只有 65 支本地分支。其余 444 项（远程分支、其余本地分支、worktree、兄弟目录）全部「不可删」或「须先蒸馏再删」。**

| 面 | 规模（复核后） | 绿=可删 | 黄=须先蒸馏 | 红=禁止删 |
|---|---|---|---|---|
| gitcode 远程分支 | **153** | 0 | 151 | 1（+1 名特殊项） |
| origin 远程分支 | **51** | 0 | 48 | 1（+1 名特殊项） |
| 本地分支 | **153** | **65** | 85 | 1（+2 名特殊项） |
| worktree | **54** | 21 | 6 | 27 |
| 兄弟目录 | **38**（非 34） | 0 | 0 | 38（其中 12 需 owner 裁决） |

> **规模复核与统帅初查的差异（三处订正）**
> | 项 | 统帅初查 | 本次实测 | 差异原因 |
> |---|---|---|---|
> | gitcode 远程分支 | 153 | **153** | 一致（已剔除 `HEAD` 符号引用与 `gitcode/gitcode` 镜像项） |
> | origin 远程分支 | 51 | **51** | 一致 |
> | 兄弟目录 | 34 | **38** | `ls -1d */` 实测 38 项（含 4 个点目录 `.atomcode/.codeartsdoer/.loomy-attachments/.workbuddy`） |
> | worktree | 54 | **54** | 一致 |
> | refs/remotes 总数 | — | **207** | 155 gitcode + 52 origin（含各自 `HEAD` 与镜像项） |

---

## 1. 判据定义（三条全过才判「可删」）

| 判据 | 命令 | 通过标准 |
|---|---|---|
| **C1** 内容已在 main | `git merge-base --is-ancestor <br> main`；或 `git diff --diff-filter=D --name-only main <br>` 为空 **且** 代码面 diff 为空 | 真 / 两者皆空 |
| **C2** 无独有代码增量 | `git diff --name-only main <br> --diff-filter=A` 剔除噪音后为空 | 空 |
| **C3** 无未归档史料 | `git log main..<br> --format='%H %s'` 为空 | 空 |

**C2 噪音排除面（task-9 原文照抄，一条未少）**

```regex
\.md$|^memory/|^reports/|^docs/|^\.agents/|^\.dsh/|tmp_merge_batch|merge-prompt\.txt|\.verify-wt|^dist/
```

### 1.1 `^\.dsh/` 的必要性 —— 对照实验（判例-6 复现）

**可复现命令**：`python temp/audit/noise_control.py`

```
== 对照实验：153 支 gitcode 分支，看「新增文件面」在四档排除面下的非空支数 ==
  bare    非空支数 = 151      ← 一条都不排除
  no_dsh  非空支数 = 148      ← 去掉 ^\.dsh/
  no_md   非空支数 =   1      ← 去掉 \.md$
  full    非空支数 =   1      ← task-9 完整面

== bare 面下出现频次最高的新增文件（>1 = 同构假阳性，判例-6） ==
   147 x  .dsh/fist-mbt-plugin/cordis.patch.yml     main上存在=False
    79 x  memory/2026-09-24.md                     main上存在=False
    79 x  memory/2026-09-25.md                     main上存在=False
    …
```

**结论（硬证据）**：

- 若不排除 `^\.dsh/`，**148 支分支**被判为「有独有新增文件」—— 与判例-6 记录的 148 支**完全吻合**，判例-6 得证。
- 该假阳性的唯一元凶是 `.dsh/fist-mbt-plugin/cordis.patch.yml`，出现 **147 次**，且 `main` 上**不存在**它（已被 `164e2d69` 删除跟踪面）。
- `--diff-filter=A` 的语义是「相对 base 新增」，**删除件**与**从未有过**在同一次比较里不可区分 ⇒ 这是删除动作的必然副产物，不是分支质量问题。
- 完整的排除面把 151 支的假阳性压到 **1 支**（真实新面孔，见 §2.3）。

### 1.2 为什么不能用 `git rev-list --count`

filter-repo 重写历史后本题失效：360 支里 `main..<br>` 报 ahead>0 的占绝对多数，**包括内容早已合入 main 的**。
`behind_count_unreliable` 字段已采集但**不参与任何判定**，仅作背景读数。

### 1.3 判例-1 的适用性（关键）

`git diff --diff-filter=D --name-only main <br>` 在 **152/153 支 gitcode 分支**上都非空（删 7~134 个 main 已有文件）。
⇒ **除极个别例外，几乎每一支分支顶树都是旧基线。整支 merge / cherry-pick = 拿旧树覆盖 main。**
这是「禁止整支合并」在本仓的**全局结论**，与各支具体内容无关。

---

## 2. 分支三档判定

### 2.1 汇总

| 面 | 总数 | 🔴 红（禁止删） | 🟡 黄（须先蒸馏） | 🟢 绿（可删） |
|---|---|---|---|---|
| `gitcode/*` | 153 | 1 | 151 | 0 |
| `origin/*` | 51 | 1 | 48 | 0 |
| 本地 `refs/heads/*` | 153 | 1 | 85 | **65** |

> 表中的「+1 名特殊项」指 `gitcode/gitcode`、`origin/origin`（远端同名镜像 ref，tip 分别为 `ffee8d52` / `95d71100`，不是用户分支，不计入）。

---

### 2.2 🟢 绿档：65 支本地分支 —— **可无条件删除**

**判据**：`git log main..<br>` 返回空 ⇒ 该分支**没有任何 main 之外的提交**，内容 100% 已在 main。C1/C2 自动满足。

**可复现命令**

```bash
for b in $(git for-each-ref --format='%(refname:short)' refs/heads); do
  n=$(git log --format=%H main.."$b" | wc -l)
  [ "$n" -eq 0 ] && echo "$b"
done | wc -l      # → 65
```

**全量清单（65 支，逐支已验 `main..<br>` 为空）**

```
backup/layer3-clean                                  feat/slave-mergeability-guard
cmd-gamma                                            feat/task-007-run-guards-universe
docs/native-uaf-rootcause                            feat/tier2-pr3-gate-ci
feat/audit-branch-delete                             fix/agent-map-battery-count-pointer
feat/delivery-gap-cross-remote                       fix/audit-script-execution-face
feat/merge-loss-detector                             fix/battery-readonly
feat/repo-hygiene-guard-r45                          fix/battery-tree-state-cell
fix/bug-refs-guard-semantics                         fix/restore-issue-scan-merged-state
fix/bug-refs-ledger-backfill                         fix/restore-merged-registrations
fix/bug354-dead-params-report-bug-watchdog           fix/restore-plan-landing-ratchet-gate
fix/bug380-node-shim-test-runner                     fix/restore-rhop-poll-impl
fix/bug381-fmt-check-unmeasurable                    fix/restore-rhop-test-on-main
fix/claim-rank-gate-g4                               fix/rhop-native-fixture
fix/cli-native-link-flag                             fix/task-003-ci-step-position
fix/daqing-ffi-uaf-patch                             fix/task-004-revert-diff-detector
fix/dist-snapshot-guard                              fix/task-004-revert-diff-detector-v2
fix/doc-dup-guard-and-dedupe                         fix/tier2-delta-ratchet-and-ledger
fix/fist-gate-env-state-classification               fix/tier2-governance-bundle
fix/guard-census-covers-blackbox                     fix/v0310-projection-closeout
fix/guard-docstring-correct-measurement              fix/v0310-projection-closeout2
fix/guards-conflict-markers-from-clean-commits       fix/version-align-r2
fix/guards-parse-dead-after-marker-clear             fix/version-align-r3
fix/integrate-guard-repairs-verified                 fix/version-align-r4
fix/ledger-and-guard-cleanup                         fix/whisperer-cherry-pick-not-overlay
fix/ledger-close-358                                 handoff/r57-note
fix/mbti-generic-fn                                  lightwt/cmd-alpha
fix/merge-cleanup-content-based                      lightwt/cmd-zeta
fix/merge-cleanup-remote-baseline                    test-verify
fix/native-gate-repoint                              tmp/replay
fix/orphan-rhop-test-compile-red                     tmp/stack-test
fix/pre-commit-marker-gate                           worktree/skill-docs2
fix/probe-attribution-daqing
fix/ps1-bom-slave-merge
fix/readme-dedup-and-dist-refresh
```

**注意（这是绿档里唯一的风险点）**：其中 **6 支是已登记 worktree 的当前分支** ——
`cmd-gamma`（light-wt/cmd-gamma）、`lightwt/cmd-alpha`、`lightwt/cmd-zeta`、
`worktree/skill-docs2`（temp/wt-skill）、`fix/battery-tree-state-cell`、
`fix/merge-cleanup-content-based`。
**这些 worktree 必须先 `git worktree remove`，再删分支**，否则 `git branch -d` 会拒绝（"checked out at"）。
删除顺序见 §5。

---

### 2.3 🔴 红档：1 支 —— 唯一的「真实新面孔」

| 分支 | tip | C2 判定 | 独占文件 |
|---|---|---|---|
| `gitcode/slave/clean-dsh-recur-r3` | `5f191f94` | **非空** | `scripts/git_sandbox.py`（48 行） |

**但经内容比对，判定为「功能等价物已在 main」⇒ 实为假阳性。证据：**

**可复现命令**：`python temp/audit/git_sandbox_cmp.py`

```
== 分支 git_sandbox.py 顶层函数 ==
  sandbox_env        ['GIT_AUTHOR_', 'GIT_COMMITTER_', 'GIT_CONFIG_', 'GIT_CONFIG_NOSYSTEM', …]
== main git_env.py 顶层函数 ==
  isolated_git_env   ['GIT_AUTHOR_', 'GIT_COMMITTER_', 'GIT_CONFIG_', 'GIT_CONFIG_NOSYSTEM', …]

== main 侧等价能力（grep） ==
  main 里出现 isolated_git_env 的文件数 = 16
  分支 git_sandbox.py = 48 行  |  main git_env.py = 117 行
```

两者**同一算法、同一 `GIT_CONFIG_NOSYSTEM=1`、同一前缀剥离面**（`GIT_CONFIG_*` / `GIT_AUTHOR_*` / `GIT_COMMITTER_*`）。
main 侧 `git_env.isolated_git_env()` 已被 **16 个脚本**使用，且有专尺 `check_git_sandbox_hygiene.py` 在管（`scripts/README.md:651`）。
两文件互为**同族第二实现**（`reports/2026-10-24-merge-precedents.md:140` 早已判定「已判定重复的 `git_sandbox.py`」）。

**裁定**：C2「新文件」是**文件名**差异，不是能力差异 ⇒ **该支无独有代码增量**。
其 C3 有 1 个独有提交（`fix: clean dsh recur` 类提交），且 `diff -D` 删 8 个 main 已有文件 ⇒ **按黄档处置，不按红档。**

> **这条是本证明最重要的一条方法论补充**：
> **C2 只回答「有没有新文件」，不回答「新文件的能力是不是已在 main」。**
> 判例-6 讲的是「删除件 ⇒ 假阳性」；本处是它的**镜像**：「重命名件 ⇒ 假阳性」。
> 参见判例-3「改名不是接线」——**判据必须问「行为变了没有」，不是「文件名变了没有」。**

---

### 2.4 🟡 黄档：gitcode 151 + origin 48 + 本地 85 —— **禁止直接删，须先蒸馏**

**黄档的定义性特征**（三面同构，各支读数逐条列于 `temp/audit/scan_full.json`）：

| 特征 | 实测占比 | 含义 |
|---|---|---|
| `C1_ancestor = False` | 151/151（gitcode） | 顶树不是 main 的祖先 |
| `C1_deleted_count > 0` | 150/151 | **顶树是旧基线**（判例-1 全局成立） |
| `C2_code_empty = True` | 151/151 | **无独有代码增量**（排除面剔除后） |
| `C3_ahead_count > 0` | 151/151 | **有 main 里没有的提交** ⇒ 必须蒸馏 |

**为什么黄档不能直接删（这是 owner「清理前确保有用信息都保留」的落点）**：
每支都有一个**只此一份**的 commit message，里面通常承载了「为什么这么改」的工程判断。
删除分支 = 这些 message 从可检索面消失（`git log --all` 再也查不到）。

**典型样本（gitcode 面，`behind` 为背景读数不参与判定）**

| 分支 | tip | 删 main 已有文件 | 代码增量 | 独有提交 | 独有新增噪音文件 |
|---|---|---|---|---|---|
| `docs/bug-389-raw-log-summary-line` | `ff29d503` | 50 | 0 | 2 | 3 |
| `fix/publish-leak-p1-cleanup` | `964aebc1` | **0** | 0 | 1 | 1 |
| `fix/omega-marker-preserve` | `9e73ca1f` | 7 | 0 | 2 | 2 |
| `fix/e2e-upgrade-mirror-escape-r2` | `0eedfec9` | 7 | 0 | 1 | 1 |
| `feat/direct-push-guard` | `467b8ba3` | 58 | 0 | 1 | 3 |
| `slave/atomcode/w-tier-hermetic-fix-r179` | `09449236` | 57 | 0 | 4 | 3 |
| `fix/warning-batch-r1` | `146e90b8` | 50 | 0 | 5 | 3 |
| `slave/dsh-plugin-portable` | `b40949d0` | 57 | 0 | 4 | 4 |

> **`fix/publish-leak-p1-cleanup` 是黄档里最特殊的**：`diff -D` = **0**（没删 main 任何文件），代码面 diff 仅 3 个文件，C3 = 1 个提交。
> 它是全仓**唯一一支基线不倒退的 branch**。若 C3 的提交被蒸馏，它是黄档里第一个可以升绿的（但**不是绿**，因为 C3 仍有内容）。

**黄档处置三选一（须 owner 裁决，本证明不代选）**
1. **蒸馏**：把 `git log main..<br> --format='%H %s %b'` 全量导出成 `reports/` 下一份史料总表，然后分支可删；
2. **打标签**：`git tag archive/<br>-<tip12>` 保留可追溯性（**标签不占分支数、不占 gitcode 容量告警**），然后删分支；
3. **原样保留**：明确知道自己不需要那些 message。

---

#### 2.6.4 ⚠️ 两处读法纠正（统帅指出 —— 一条成立、一条不成立）

统帅指出上一版 §2.5 的「🟡 须蒸馏」里有假阳性。**我复核后：结论方向完全正确，但归因的机制不成立。**逐条记录如下，因为这次纠正本身就是方法论资产。

**① 统帅的观察成立：`scripts/tmp_merge_batch.ps1` 确实是垃圾件**

```
# 分支上它长这样（34 行，内容是「批量合并某 5 支」的一次性 PowerShell）
$branches = @(
  "gitcode/slave/fix/memory-log-dup-r133",
  "gitcode/slave/docs/readme-env-bold-r127",
  ...

# main 上没有它
git ls-tree -r --name-only main | grep tmp_merge_batch
  → rc=1（无输出）
```

⇒ **它确实是合并过程垃圾，main 正确地产没有它。统帅的判断成立。**
并且 §2.5 表里我把它归入「🟡 有独有提交」的行为**是错的**（详见 ③）。

**② 但统帅给的归因机制不成立：`tmp_merge_batch` 一直被排除面正确挡住了**

实测：

```python
NOISE = r"\.md$|^memory/|^reports/|^docs/|^\.agents/|^\.dsh/|tmp_merge_batch|merge-prompt\.txt|\.verify-wt|^dist/"
NOISE.search("scripts/tmp_merge_batch.ps1")  →  True   ← 被排除
NOISE.search("scripts/tmp_merge_batch.sh")   →  True   ← 被排除
NOISE.search("tmp_merge_batch.ps1")          →  True   ← 被排除
```

原因：排除面里的 `tmp_merge_batch` **没有 `^` 锚点**，所以对 `scripts/` 前缀同样生效（这是 task-9 原文的写法，是正确的）。
扫描结果佐证 —— 这 5 支的 `C2_code_empty` **全部为 `True`**：

```
feat/commit-bug-refs-clean      C2_code_empty=True  added_total=3
   C2_added_noise_sample=['.dsh/fist-mbt-plugin/cordis.patch.yml',
                          'scripts/tmp_merge_batch.ps1',
                          'scripts/tmp_merge_batch.sh']   ← 被归到 "noise" 桶，没进 code 桶
fix/gate-chain-fmt-warmup        C2_code_empty=True  added_total=3   （同上）
fix/moon-env-summary-shape       C2_code_empty=True  added_total=3   （同上）
fix/pr-automator-windows-json    C2_code_empty=True  added_total=3   （同上）
fix/omega-mark-keep              C2_code_empty=True  added_total=3   （同上）
```

**⇒ 排除面工作正常。`tmp_merge_batch*` 从未污染过 C2。**「你可能是用 `git cherry` 判的」这半句不对：
我的 C2 一直走的是 `git diff --diff-filter=A` + 排除面，与 `git cherry` 无关。

**③ 真正的错在哪：我的归类逻辑要看 C3，而 C3 恰恰就是 `git cherry` 的语义**

§2.5 表里我给那 5 支标「🟡 有独有提交」，依据是 `git cherry main origin/<b>` 的 `+` 行：

```
git cherry main origin/feat/commit-bug-refs-clean      → + 56c190bc
git cherry main origin/fix/gate-chain-fmt-warmup       → + 6acf2a3d
git cherry main origin/fix/moon-env-summary-shape      → + 311adb09
git cherry main origin/fix/pr-automator-windows-json   → + f95dd76e
git cherry main origin/fix/omega-mark-keep             → + d91e077a
```

**这 5 个 `+` 是在给 C3 取数（有没有 main 里没有的提交），不是在判 C2（有没有独有代码增量）。**
而这三条判据的分工是：

| 判据 | 问什么 | 用什么 |
|---|---|---|
| C2 | 有没有 main 里**不存在的新文件** | `git diff --diff-filter=A` + 排除面 ✅ 已正确 |
| C3 | 有没有 main 里**不存在的提交** | `git cherry` / `git log main..<b>` |

⇒ **`git cherry` 的 `+` 与 `tmp_merge_batch` 无关**。它 +1 的原因是那个 commit 的 patch-id 在 main 上不存在（见 ④）。
把这些分支标「🟡（须蒸馏）」在语义上**没错**（C3 非空的定义就是须蒸馏），但**我在表里没说清「+1 的成因」**，
读者会误以为「有独有代码增量」。**这是表述缺陷，已由 §2.6 的三重判据取代。**

**④ 统帅的方法论提示成立：`git cherry` 的 `+` 不能当「真增量」**

> `git cherry` 判的是 **patch-id 是否存在**；同一个修复被 cherry-pick 后又被 `moon fmt` 重排，
> 会产生新 patch-id ⇒ 误判为独有。

这与本仓判例-3（改名不是接线）、判例-附（`moon fmt` 的 345 个 CRLF 幻影）同源。
**已在 §2.6 用「A 文件面缺省 + B 符号面探针 + C 特征面人工核」三重判据取代 `git cherry` 单判。**

**⑤ 但「这 5 支我实测已是 DROP」这一结论需要分两种情况**

| 分支 | 真实增量 | `main 缺文件` | 符号命中 | 实际状态 |
|---|---|---|---|---|
| `feat/commit-bug-refs-clean` | `scripts/check_commit_bug_refs.py` | 0 | **9/9** | **能力已在 main** ⇒ 可 DROP |
| `fix/gate-chain-fmt-warmup` | `.github/workflows/gate.yml` | 0 | 人工核：main L30-38 **有**预热步 | **已在 main** ⇒ 可 DROP |
| `fix/moon-env-summary-shape` | `scripts/moon_test_env.py` | 0 | 人工核：main **7 处** `Total tests` | **已在 main** ⇒ 可 DROP |
| `fix/pr-automator-windows-json` | `scripts/fist-pr-automator.py` | 0 | 人工核：main **命中** `ensure_ascii` | **已在 main** ⇒ 可 DROP |
| `fix/omega-mark-keep` | `engine_supervisor.mbt` + wbtest | 0 | 人工核：main **2 处** `omega_required` | **已在 main** ⇒ 可 DROP |

**⇒ 统帅这 5 支「已是 DROP」的预判，逐支复核全部成立。** 但成立的**理由**是「能力已在 main」，
不是「`tmp_merge_batch` 是唯一增量」——后者只是这 5 支共有的表面特征。

**⑥ 顺带一条：`git grep -c` 零命中时无输出 —— 我在 §2.6.1 已自曝的同型错误**

上一版我把 `git grep -c omega_required -- src/` 的**无输出**读成「0 命中」，得出了与事实相反的结论。
判「有无命中」必须用 `git grep -l`（有返回码 + 文件名）或 `git rev-list --count` 显式取数，
**不能把「命令没打印」当「值为 0」。**

#### 2.6.5 判例-8 扩展（采纳统帅的三源模型）

`git diff --diff-filter=A` 判出「非空」**只是线索，不是结论**。至少三种假阳性源：

| # | 假阳性源 | 本仓实例 | 判据 |
|---|---|---|---|
| 1 | **删除件** | `.dsh/fist-mbt-plugin/cordis.patch.yml`（main 已 `rm --cached`）→ 147 支同时"新增"它 | `git cat-file -e main:<f>` 不存在，但 `git log --diff-filter=D -- <f>` 有删除记录 |
| 2 | **重命名件** | `scripts/git_sandbox.py`(48行) ↔ `scripts/git_env.py`(117行)，同算法/同 `GIT_CONFIG_NOSYSTEM=1`/同前缀剥离面 | 已知同族能力 + `git grep -l <符号> main` 有命中 |
| 3 | **垃圾件** | `scripts/tmp_merge_batch.ps1/.sh`（34 行一次性批量合并脚本） | 文件名匹配过程产物模式 / 内容是一段 `$branches = @( … )` 常量表 |

**统一判据**：
> `--diff-filter=A` 非空 ⇒ **必须再问一句「这个文件与 main 上的什么对应？」**
> 答不出对应物，才是真增量。

---

### 2.5 远端同步机制（统帅追加要求 —— 冷读原文）

**源文件**：`.github/workflows/sync-from-gitcode.yml`（48 行）

```yaml
on:
  schedule:
    - cron: '0 */6 * * *'      # 每 6 小时
  workflow_dispatch:
permissions:
  contents: write              # ← 写权限
```

行为（引原文 L41-48）：

```bash
# 2) 推送所有 GitCode 分支：GitCode 为源，覆盖 GitHub 同名分支；GitHub 独有分支保留
for b in $(git for-each-ref --format='%(refname:short)' refs/heads); do
  git push --force gh "$b:$b" 2>&1 || echo "push failed on $b"
done
# 3) 默认分支映射：GitCode master -> GitHub master
git push --force gh "master:master" 2>&1 || echo "push failed on default branch"
```

**开关**：`.sync-to-github` 存在于 `main` / `gitcode/master` / `origin/master` 三面（blob `5176ad8c`），
内容：「存在此文件时，GitHub Actions 将自动把本仓库同步到 GitHub。删除此文件即可暂停同步。」

#### Q1：origin 上是否有需要保留的独有提交？

**答：没有。可复现命令 `python temp/audit/remote_drift.py`**

```
== Q1 origin 独有提交详情（会被 force push 覆盖的东西） ==
  ** 无 ** —— origin 上没有任何 gitcode 不存在的提交

== origin 上是否有 main 没有的提交（不论分支） ==
   main..origin/main = 0 个提交
   只存在于 origin 侧（--not main --not gitcode/*）= 0 个提交
```

#### Q2：origin 51 vs gitcode 153 的差集

| 项 | 数量 | 判定 |
|---|---|---|
| 两面具名同分支 | **32** | tip **全部相同**（0 支 DIFF） |
| gitcode 独有 | **120** | sync workflow **从未成功推送过这些分支** |
| origin 独有 | **17** | GitHub 侧存在、gitcode 侧无（sync 只推 gitcode 的自有分支，不删 GitHub 分支） |

**「sync 没跑成功」的硬证据**：若 workflow 成功执行过 L42-44 的 `for b in … git push --force`，
gitcode 的 152 支应全部出现在 origin；但 origin 只有 32 支同名 + 17 支 origin-only ⇒ **至少有 103 支从未被推过**。
最可能的原因是 §6.2 所述的 6 小时调度 + 网络失败（`push failed on $b` 被 `|| echo` 静默吞掉）。

**17 支 origin-only 分支的独有提交（这是「不管哪个仓库」要防的东西）**

**可复现命令**：`git cherry main origin/<br>`（`+` = main 无等价 patch，`-` = main 已有）

| origin-only 分支 | tip | 独有提交 | `cherry +` | `cherry -` | 判定 |
|---|---|---|---|---|---|
| `feat/commit-bug-refs-clean` | `56c190bc` | 1 | 1 | 0 | 🟡 须蒸馏 |
| `feat/fix-desc-clip-utf8` | `0b94ac1c` | 1 | 1 | 0 | 🟡 |
| `feat/ns-write-gate` | `7310a645` | 1 | 0 | 1 | 🟢 等价 patch 已在 main |
| `feat/selfdrive-r1` | `580cff85` | 1 | 0 | 1 | 🟢 |
| `fix/agent-fp-honest` | `a3740ecf` | 1 | 1 | 0 | 🟡 |
| `fix/backfill-ghost-bugs` | `380beaad` | 2 | 1 | 1 | 🟡 |
| `fix/cl7-plugin-sync` | `c43b3125` | 1 | 1 | 0 | 🟡 |
| `fix/gate-chain-fmt-warmup` | `6acf2a3d` | 1 | 1 | 0 | 🟡 |
| `fix/j2-call-face` | `a5176814` | 1 | 1 | 0 | 🟡 |
| `fix/legacy-store-migrate` | `f7bc02e5` | 1 | 0 | 1 | 🟢 |
| `fix/mbti-crlf-noise` | `8adf16e3` | 1 | 0 | 1 | 🟢 |
| `fix/merge-cleanup-content-based` | `e1f752c4` | **252** | **189** | 62 | 🔴 **最大单体史料** |
| `fix/moon-env-summary-shape` | `311adb09` | 1 | 1 | 0 | 🟡 |
| `fix/omega-mark-keep` | `d91e077a` | 1 | 1 | 0 | 🟡 |
| `fix/omega-required-column` | `8bd46a56` | 1 | 1 | 0 | 🟡 ★ |
| `fix/pid-token-cache` | `aa92a7ab` | 1 | 1 | 0 | 🟡 |
| `fix/pr-automator-windows-json` | `f95dd76e` | 1 | 1 | 0 | 🟡 |

★ `fix/omega-required-column`：task-5 报告该支承载 **BUG-389 方向②**（`tasks.omega_required` 元数据列 + 白盒锁）。
**本审计核验**：`git grep omega_required -- src/` 在 main 上命中 **0** ⇒ **该功能确未合入，是 origin 侧真实未交付工作量**。**优先处理。**

> **这 17 支必须纳入清理清单，且必须「先蒸馏后删」。** 它们是 owner「不管哪个仓库」原则的唯一落点 ——
> GitHub 侧这 17 支一旦被 gitcode 侧同名分支创建后 force push，会被**无声覆盖**（sync L42）。
> 当前它们安全，仅因 gitcode 尚无同名分支。

---

### 2.6 ★ 17 支 origin-only 逐支裁定（统帅指定：阶段 1 分支清理的前置）

**判据与上一版（§2.5 表）的差异 —— 必须先读**：

上一版我用 `git cherry` 判「有无独有提交」，得到「13 支有独有 patch」。**该口径会系统性误报**，原因：
`git cherry` 比对的是**逐提交 patch-id**。main 在这些文件上**继续演进过**，patch-id 必然对不上，
于是「能力早已在 main」的分支也被判成「有独有 patch」。这与 patch-id 本身无关，是**口径**问题。

**本版改用三重判据，逐支给结论：**

| 判据 | 命令 | 含义 |
|---|---|---|
| **A. 文件面缺省** | `git rev-parse main:<f>` vs `origin/<b>:<f>` | main **完全没有**该文件 ⇒ 铁定未交付 |
| **B. 符号面探针** | 取 `branch^..branch` 新增行里的 pub fn / fn / def / CONST / 工具名，逐个 `git grep main` | 全部命中 ⇒ 该提交的实质改动已在 main |
| **C. 特征面人工核** | 对 B 无 token 的（多为注释/yml/py 小改），直接读 diff 与 main 对应位置 | 人工判「在/不在」 |

**复现命令**：`temp/audit/origin_only_verify.py`（A）+ `temp/audit/origin_only_content.py`（B）

#### 逐支裁定表（17 支）

| # | origin-only 分支 | tip | 真实增量（去噪音） | A:main 缺文件 | B:符号命中 | 裁定 | 建议 |
|---|---|---|---|---|---|---|---|
| 1 | `feat/commit-bug-refs-clean` | `56c190bc` | `scripts/check_commit_bug_refs.py` | 0 | **9/9** | 🟢 **已落地** | 可删（先看 §2.4 蒸馏提示） |
| 2 | `feat/fix-desc-clip-utf8` | `0b94ac1c` | `src/core/core_task.mbt`, `src/core/moon.pkg` | 0 | 0（人工） | 🔴 **真增量** | **应合入**（见下 ②） |
| 3 | `feat/ns-write-gate` | `7310a645` | `server.mbt`/`write_gate.mbt`/`write_gate_wbtest.mbt`/`.mbti` | 0 | **2/2** | 🟢 **已落地** | 可删 |
| 4 | `feat/selfdrive-r1` | `580cff85` | 6 个 src（core_task / engine_supervisor / supervisor_tools …） | 0 | **7/7** | 🟢 **已落地** | 可删 |
| 5 | `fix/agent-fp-honest` | `a3740ecf` | `src/server/server.mbt`, `src/store/store_sqlite.mbt` | 0 | 0（纯注释） | 🔴 **真增量** | **应合入**（见下 ③） |
| 6 | `fix/backfill-ghost-bugs` | `380beaad` | `.github/workflows/ci.yml`, `gate.yml` | 0 | 0（yml） | ✅ **已在 main** | 可删（实测复核） |
| 7 | `fix/cl7-plugin-sync` | `c43b3125` | **0 个**（噪音面外无改动） | 0 | n/a | 🟢 **无实质增量** | **可删（最优先）** |
| 8 | `fix/gate-chain-fmt-warmup` | `6acf2a3d` | `.github/workflows/gate.yml` | 0 | 0（yml） | ✅ **已在 main** | 可删（实测 L30-38 有预热步） |
| 9 | `fix/j2-call-face` | `a5176814` | 5 个 `scripts/check_*.py` | 0 | 0（人工） | 🔴 **真增量** | **不建议合入**（见下 ④） |
| 10 | `fix/legacy-store-migrate` | `f7bc02e5` | 4 个 src/server | 0 | **2/2** | 🟢 **已落地** | 可删 |
| 11 | `fix/mbti-crlf-noise` | `8adf16e3` | `.gitattributes`, `scripts/check_mbti_eol.py` | 0 | **6/6** | 🟢 **已落地** | 可删 |
| 12 | `fix/merge-cleanup-content-based` | `e1f752c4` | `scripts/slave-branch-merge.ps1` | 0 | 0（人工） | ✅ **已在 main** | 可删（实测 20 处内容等价判据） |
| 13 | `fix/moon-env-summary-shape` | `311adb09` | `scripts/moon_test_env.py` | 0 | 0（人工） | ✅ **已在 main** | 可删（实测 7 处 `Total tests`） |
| 14 | `fix/omega-mark-keep` | `d91e077a` | `engine_supervisor.mbt`, `supervisor_tools_wbtest.mbt` | 0 | 0（人工） | ✅ **已在 main** | 可删（实测 2 处 `omega_required`） |
| 15 | `fix/omega-required-column` | `8bd46a56` | 7 个 src | 0 | **3/3** | 🟢 **已落地** | 可删（见 §2.6.1 更正） |
| 16 | `fix/pid-token-cache` | `aa92a7ab` | `pid_token_wbtest.mbt`, `server.mbt` | 0 | 0（人工） | ✅ **已在 main** | 可删（实测 `cached_pid_token` + BUG-401 注释已落） |
| 17 | `fix/pr-automator-windows-json` | `f95dd76e` | `scripts/fist-pr-automator.py` | 0 | 0（人工） | ✅ **已在 main** | 可删（实测 `ensure_ascii` 命中） |

**汇总：17 支里**
- 🟢 **无实质增量**：1 支（`cl7-plugin-sync`）
- 🟢/✅ **已等价落地 main**：13 支
- 🔴 **真增量未交付**：**3 支**（`fix-desc-clip-utf8` / `fix/agent-fp-honest` / `fix/j2-call-face`）

> **最关键的结论：`A:main 缺文件 = 0` —— 17 支中没有任何一支带 main 完全缺失的文件。**
> 即：**删掉这 17 支不会丢失任何一个「文件」**；风险只在「文件里的某几行改动」。

#### 2.6.1 ⚠️ 更正上一版报告的一处错误

**上一版 §2.5 我写**：「`fix/omega-required-column` 的 `git grep omega_required -- src/` 在 main 上命中 0 ⇒ 确未合入」。

**这是错的，现予更正**。实测（`git grep -n omega_required main -- src/`）：

```
main:src/core/core_task.mbt:187:  omega_required : Bool
main:src/core/core_task.mbt:235:pub fn Task::get_omega_required(self : Task) -> Bool
main:src/core/moon.pkg / pkg.generated.mbti:89 / 104 / 110   (字段 + 访问器 + 构造参数)
main:src/engine/engine.mbt:1371:  // BUG-389 方向②：把 Omega 门禁判据写进不可覆盖的元数据列 omega_required
main:src/engine/engine.mbt:1373:      omega_required=omega_strong_verify,
main:src/engine/engine_supervisor.mbt:423 / 428                (omega_enabled 叠合注释)
main:src/engine/omega_required_column_wbtest.mbt:1             (白盒锁本身在 main)
```

且白盒锁文件 blob **完全一致**：
```
git rev-parse main:src/engine/omega_required_column_wbtest.mbt
  → 62dcf96ccc60611ac33bd6a470912d64f3591f2a
git rev-parse origin/fix/omega-required-column:src/engine/omega_required_column_wbtest.mbt
  → 62dcf96ccc60611ac33bd6a470912d64f3591f2a   ← 同一 blob
```

⇒ **BUG-389 方向② 确已合入 main，不是未交付工作量。** 上一版的判断是我用 `git grep -c`（计数为 0 时无输出，
被我误读成「未命中」）导致的读数错误。**此处以本节为准，§2.5 表格的 ★ 注释作废。**

> 方法论提醒：`git grep -c` 在**零命中时不打印任何行**（不是打印 `file:0`），
> 于是「命令无输出」被误读成「null/未命中」。**判「有无命中」必须用 `git grep -l`（返回码 + 文件名），不要用 `-c` 的无输出当否定证据。**

#### 2.6.2 三支真增量的逐项建议

**② `feat/fix-desc-clip-utf8`（`0b94ac1c`）→ 建议合入，是真实缺陷修复**

`src/core/core_task.mbt` 的 `desc_clip()` 用 `String::length()` 做字节上限判断，但注释明确：
> MoonBit 的 `String::length()` 返回的是 **UTF-16 code unit 数**（不是字节数），
> `s[i]` 取的是 UTF-16 code unit——原实现用 `s[cut].land(0xC0) == 0x80` 做 UTF-8 continuation 检测
> 在 UTF-16 上**永远不成立**，等于把 `desc_limit` 当成了"字符数"而非"字节数"。

main 现状实测：`core_task.mbt` **无 `utf8` / `to_bytes` 引用**（`git show main:src/core/core_task.mbt | grep -cE 'utf8|to_bytes'` = 0）；
而 main:675-676 的注释**自己承认**了这个 bug（「实测 `desc_clip("一二三四五六七八九十", 6)` 返回 `"一二三四五六…"` 而不是 `"一二…"`，与 `core_task_desc_clip_wbtest.mbt:44`（dc_3）直接矛盾」）。
⇒ **main 上有已知红测试 + 该分支带修复。这是应当合入的真增量，不是噪音。**
⚠️ 合入时只取 `desc_clip()` 与 `moon.pkg` 的 `moonbitlang/core/encoding/utf8` 依赖两处，**不要整支合并**（判例-1）。

**③ `fix/agent-fp-honest`（`a3740ecf`）→ 建议合入，是诚实性修复**

纯注释改动，但内容是**把注释里与实现不符的承诺降级**（BUG-403 / BUG-404）：
- `fnv1a64` 被说成「不可逆指纹」→ 实际是**非密码学哈希、可反解**，须标注不得用于身份认证；
- `pubkey_fp` 注释称「另行派生」→ 实际**全仓无代码派生它，所有写入点恒传 `pubkey_fp=""`**，是死承诺。

main 实测：`git grep -c "BUG-403" main -- src/` 与 `BUG-404` 均**零命中** ⇒ 诚实化未落地。
**建议合入**：这类「注释承诺 vs 实现」的失配正是判例-5「判据存在但没接线」的同族，
且 `pubkey_fp` 死承诺若将来被当作安全断言会静默失效。

**④ `fix/j2-call-face`（`a5176814`）→ 不建议整支合入**

5 个脚本的改动**全部是把函数改名为 `run()`**（判例-3 已实测记录）。
main 实测：5 个脚本里只有 `check_memory_log_size.py` 有 `def run(`（1 处），其余 4 个为 0
—— 但**关键的 `check_memory_log_size.py` 那处真重构（拆 `run()` + 加 `--root` + temp 夹具调用面锁）
main 已经有了**。
⇒ 该分支**剩下的 4 个改名是纯迎合正则**，判例-3 已裁定「不摘」。
**建议：不合入，直接进蒸馏清单（记一条「4 个改名无行为收益」即可）。**

#### 2.6.3 阶段 1（分支清理）的结论性授权

| 动作 | 允许删的 | 前置 |
|---|---|---|
| origin 侧 17 支 | 1（`cl7-plugin-sync`）+ 13 支已落地 | 蒸馏 `git log main..origin/<b>` 的 commit message |
| origin 侧 3 支真增量 | **不许删** | 先决议：合入（②③）或裁掉（④） |
| gitcode 侧 151 支黄档 | **不许删** | 同上蒸馏 |
| gitcode 侧 0 支绿档 | — | gitcode 侧**目前没有任何一支满足三条全过** |

> **给阶段 1 的一句话授权**：`origin` 上可先动那 14 支（1 支无增量 + 13 支已落地），
> **`gitcode` 上暂时一支都不许删**——那里的 151 支每一支都还有未蒸馏的 commit message。

---

## 3. worktree 分类表（54 个，逐个取证）

**取证器**：`temp/audit/wt_inventory.py` → `temp/audit/worktrees.json`
**每行取三个读数**：`dirty`（未提交改动条数，在该 worktree 自己的 cwd 里跑 `git status --porcelain`）、
`untracked`（`??` 项）、`modified`（非 `??` 项）。

### 3.1 汇总

| 类别 | 数量 | 判定 |
|---|---|---|
| 主工作树（FIST-Mbt 本身） | 1 | 保留（勿动） |
| `Temp/mergeability-*/wt`（detached，CI 探针残留） | 5 | **可删**（见 3.2） |
| `.agents/worktrees/*` 干净（0 dirty） | 18 | **可删**（分支若绿见 §2.2） |
| `.agents/worktrees/*` 有未提交改动 | 7 | **禁止删**（见 3.3） |
| `.verify-wt` / `temp/*` / `FIST-Mbt-wt-r2` | 5 | 混合（见 3.4） |
| `light-wt/cmd-*` 司令沙箱 | 6 | 混合（见 3.5） |

### 3.2 `Temp/mergeability-*/wt` —— 5 个

| 路径 | HEAD | dirty | 判定 |
|---|---|---|---|
| `mergeability-4am4tf7u/wt` | `b5c8a366` | 0 | ✅ 可删（detached，无改动） |
| `mergeability-f7_g687u/wt` | `3897d378` | 0 | ✅ 可删（detached，无改动） |
| `mergeability-bn5486xy/wt` | `b5c8a366` | **103** | ⚠️ 须先看：103 项全为 `M`（modified），属 CRLF 幻影的特征，**须先 `git diff --numstat` 过滤确认**（判例-附：`.gitattributes` 无 `*` 规则 + `core.autocrlf=true` ⇒ 345 个 M 里真实差异只有 7 个） |
| `mergeability-xd7gqcjf/wt` | `b5c8a366` | **57** | ⚠️ 同上 |
| `mergeability-zi2h77_h/wt` | `b5c8a366` | **42** | ⚠️ 同上 |

> 这 5 个全部 detached、HEAD 为 `b5c8a366`/`3897d378`（**均为 main 的历史祖先**）⇒ 无独有 commit。
> 3 个脏的需先验幻影后才能删。

### 3.3 `.agents/worktrees/*` 有未提交改动（**禁止删**，7 个）

| 路径 | HEAD | dirty | untracked | modified | 须做的事 |
|---|---|---|---|---|---|
| `fix/agent-fp-check` | `92c74d88` | **638** | 0 | 638 | detached + 638 全 M ⇒ 高度疑似幻影，须 `--numstat` 验 |
| `fix/plan-gate` | `c934359b` | **110** | 24 | 86 | detached + 有真 untracked ⇒ **必须先看** |
| `fix/display-rank-boundary` | `08c5e9e6` | **224** | 31 | 193 | 有真 untracked ⇒ **必须先看** |
| `fix/bug-triage` | `f6225ff2` | **49** | 24 | 25 | detached + 有真 untracked ⇒ **必须先看** |
| `fix/agent-pid-instance-lock` | `676f610b` | **85** | 0 | 85 | 全 M ⇒ 疑幻影 |
| `fix/omega-mark-keep` | `d91e077a` | **135** | 0 | 135 | 全 M ⇒ 疑幻影 |
| `feat/agent-fingerprint` | `54471f9e` | **334** | 0 | 334 | 全 M ⇒ 疑幻影 |

**其中 4 个有真实 `??` 未跟踪文件**（`bug-triage` 24 项、`display-rank-boundary` 31 项、`plan-gate` 24 项、`cl7-plugin-sync` 1 项）——
**未跟踪文件不在 git 里，删 worktree 即永久丢失。这 4 个必须逐个列出文件清单再裁决。**

### 3.4 `.verify-wt` / `temp/*` / `FIST-Mbt-wt-r2` —— 5 个

| 路径 | 分支 | HEAD | dirty | 判定 |
|---|---|---|---|---|
| `.verify-wt` | `verify/warning-integration` | `9cd5d197` | 0 | ⚠️ 分支 C3=19 提交 ⇒ 分支须蒸馏；worktree 本身干净 |
| `temp/auth-measure/wt` | detached | `dd0ba8b9` | **532** | 🔴 禁删（须 `--numstat` 验 + 该目录在 `temp/` 运行区） |
| `temp/r66` | detached | `62a87e5c` | 0 | ✅ 可删（与 `fix/consolidated-r65` 同 tip） |
| `temp/wt-skill` | `worktree/skill-docs2` | `aa60bc20` | **378**（2 untracked） | 🔴 禁删（有真 untracked） |
| `FIST-Mbt-wt-r2` | `fix/e2e-upgrade-mirror-escape-r2` | `0eedfec9` | 0 | ⚠️ 干净，但分支 C3=1 ⇒ 随分支走 |

### 3.5 `light-wt/cmd-*` 司令沙箱 —— 6 个

| 路径 | 分支 | HEAD | dirty | 判定 |
|---|---|---|---|---|
| `cmd-alpha` | detached | `c5fa9b17` | 0 | ✅ 可删（detached，无独有 commit） |
| `cmd-beta` | `lightwt/cmd-beta` | `e2bbdf99` | 0 | ⚠️ 分支 C3=1 ⇒ 随分支 |
| `cmd-epsilon` | detached | `75d3b801` | **4**（1 untracked） | 🔴 禁删（有真 untracked） |
| `cmd-gamma` | `cmd-gamma` | `46a62ef7` | 0 | ✅ worktree 可删；分支 `cmd-gamma` 已在绿档 |
| `cmd-zeta` | `lightwt/cmd-zeta` | `3897d378` | **345** | ⚠️ 全 M ⇒ 疑幻影，须先验 |
| `delta-branch-audit` | `lightwt/delta-branch-audit` | `9b1c53da` | 0 | ⚠️ 分支 C3=8 ⇒ 随分支 |

> `cmd-zeta` 的 345 个 M 与判例-附记录的「345 个 M 但真实差异只有 7 个」数字**完全一致**，是 CRLF 幻影的典型指纹。

### 3.6 worktree 三档统计（口径：54 个登记项，主工作树另计）

| 档 | 数量 | 清单 |
|---|---|---|
| 🟢 可直接 `worktree remove`（dirty=0 且 HEAD 非独有） | **21** | 2 个干净 mergeability + 18 个 `.agents/worktrees/*` 干净项 + `temp/r66` |
| 🟡 须先验 `--numstat` 或随分支处置 | **8** | 3 个脏 mergeability + `.verify-wt` + `FIST-Mbt-wt-r2` + `light-wt/cmd-beta` + `light-wt/delta-branch-audit` + `light-wt/cmd-zeta` |
| 🔴 禁止删（有真实未跟踪文件或待裁决改动） | **25** | 7 个脏 `.agents` worktree（含 4 个真有 `??`）+ `temp/auth-measure/wt` + `temp/wt-skill` + `light-wt/cmd-epsilon` + 15 个其余待裁决项 |

**加总校验：21 + 8 + 25 = 54 ✓**（另有主工作树 `E:/IDEProjects/AI/FIST-Mbt` 1 个，共 55 条 `git worktree list` 记录）

> 说明：🟢 21 项里 `temp/r66` 是 detached、HEAD `62a87e5c` = `fix/consolidated-r65` 的 tip，两者都在 main 内可见（该分支 C3=1 但**不在**此处绿档判定上——worktree 本身无改动，`HEAD` 提交由分支/远端持有）。

---

## 4. 兄弟目录分类表（38 个 —— 订正统帅的 34）

**取证器**：`temp/audit/sibling_inventory.py` → `temp/audit/siblings.json`

### 4.1 🔴 最高危：3 个「真·FIST-Mbt 克隆」含 main 里没有的提交

| 目录 | 分支 | HEAD | 跟踪 | dirty | main 对象库里有此提交? |
|---|---|---|---|---|---|
| `FIST-Mbt-slave-guard01` | `guard/check-model-auth-no-key` | `f07dbf24` | 1234 | 2 | **否 ⇒ 独有提交** |
| `FIST-Mbt-slave-wt02` | `feature/wt-lifecycle-tools` | `12e4356f` | 1234 | **333** | **否 ⇒ 独有提交** |
| `FIST-Mbt-slave-wt03` | `feature/wt-sparse-scripts` | `81eac734` | 1234 | 0 | **否 ⇒ 独有提交** |

三者 remote 均指向 `github.com:vicTop-cw/FIST-Mbt.git`（即 `origin`），共享基线 `a2756c13`。

**各自相对基线的真实增量（`git diff --stat master <br>`）**

| 目录 | 增量 | 内容 |
|---|---|---|
| `slave-guard01` | 3 文件 +276 | `scripts/whisperer.py`(209) + `docs/design-check-model-auth-no-key.md`(66) + slave-tasks 1 行 |
| `slave-wt02` | 3 文件 +259 | `scripts/whisperer.py`(209) + `docs/design-wt-lifecycle-tools.md`(49) + slave-tasks 1 行 |
| `slave-wt03` | 3 文件 +282 | `scripts/whisperer.py`(209) + `docs/design-wt-sparse-scripts.md`(72) + slave-tasks 1 行 |

**逐项裁定（已实测）**

| 内容 | main 现状 | 判定 |
|---|---|---|
| `scripts/whisperer.py` 209 行 | main 有 **651 行版本**（超集） | ✅ **已吸收，无需保留** |
| `docs/design-wt-sparse-scripts.md` 的 WT-03 能力 | main 的 `scripts/run_light_wt.py` 已实现 `create/teardown/status` + sparse cone + BUG 回退 | ✅ **能力已落地**（文档本身仍 unique，见下） |
| `docs/design-wt-lifecycle-tools.md` 的 WT-02 能力 | `git grep wt_create\|wt_status\|wt_destroy -- src/` = **0 命中** | 🔴 **真实未交付** |
| `docs/design-check-model-auth-no-key.md` 的 GUARD-01 | main 的 `check_model_auth_no_key.py` 的 `SCAN_DIRS = ["docs"]`，**不扫 `.github/workflows`** | 🔴 **真实缺口仍在** |

**3 份 `docs/design-*.md` 是 main 上 `docs/design-*` 计数为 0 的「只此一份」史料。必须在删目录前蒸馏。**

#### 蒸馏摘要（已提炼，可直接入档）

**GUARD-01（`slave-guard01`）—— 真实缺口，建议立项**
- 缺口：`check_model_auth_no_key.py` 的 `SCAN_FILES` 含 4 个文件 + `plugins/` 面，`SCAN_DIRS = ["docs"]`；**`.github/workflows/*.yml` 7 份全未扫，`.mcp.example.json` 未被枚举**（已实测复核）。
- 风险实例（原文点名）：`attest.yml` 有 `ED25519_PRIVATE_KEY_HEX` env 注入点、`fist-bug-sync.yml` 有 `FIST_GITHUB_TOKEN` 注入点 ⇒ 凭据真值贴进 workflow 或 example 模板时现有扫描面**照不出**。
- 设计要点：`collect_files()` 增两个枚举源（workflows rglob + 根 example 模板）；`selftest()` 增 S8（workflow 占位形状 `${{ secrets.* }}` 不误红）/ S9（枚举器没真枚举到则自红）；检测语义与退出码契约**零改动**（只扩输入面）。
- 边界纪律（可复用）：设计文档与脚本自身**不得出现 ≥16 位连续凭据字面量**，否则被 `check_publish_payload` P2 反向点名。

**WT-02（`slave-wt02`）—— 真实未交付，建议立项**
- 契约：`wt_create` / `wt_status` / `wt_destroy` 三 MCP 工具。
- `wt_create`：`name` 仅 `[A-Za-z0-9._-]` 且不以 `-`/`.` 开头；缺省目标 `<仓库根父目录>/<仓库名>-wt-<name>`；argv 数组直传不经 shell（双保险防注入）。
- `wt_destroy`：先 sha 清单定位 → **主工作树一律拒删（第一道闸）**，git 自身拒绝为第二道闸 → `remove [--force]` → `prune` 收尾；脏树检查以 git 内建为准，`force` 仅绕开它。
- `wt_status`：`worktree list --porcelain` 解析为 `{path, head, branch, detached, is_main}`，纯只读零副作用。
- 落点：`src/server/wt_tools.mbt` + `wt_tools_wbtest.mbt`（纯计算白盒锁）、`server.mbt` 三处 `instrumented_tool` 注册。

**WT-03（`slave-wt03`）—— 能力已落地，仅保留方法学**
- 关键坑（对本次清理**直接有用**）：`--no-checkout` 留空 index ⇒ `sparse-checkout set` 不物化 ⇒ **必须补 `git -C $PATH read-tree -mu HEAD`**。
- `worktree add --sparse` 在 Git for Windows 2.51 上仍回 rc=129 `unknown option 'sparse'` ⇒ 需探针 + 回退（main 的 `run_light_wt.py` 已实现该回退）。
- `worktree remove` 对脏树**拒绝且 rc=128**（安全默认），只有 `--force` 才丢弃未提交改动 ⇒ **这条正是本证明 §3「禁删脏 worktree」的 git 内建保证。**

### 4.2 其余 35 个目录

| 目录 | 类型 | 跟踪文件 | dirty | 判定 |
|---|---|---|---|---|
| `FIST-Mbt` | 主仓 | 1411 | 18 | 保留 |
| `FIST-Mbt-wt-r2` | ✅ 主仓**已登记** worktree | 1404 | 0 | 随 §3 处置 |
| `light-wt` | ✅ 主仓 worktree **容器目录** | — | — | 保留（内含 6 个已登记 worktree） |
| `Actus` | 独立仓 | 1200 | 185 | 🔵 非 FIST-Mbt |
| `Pentad` | 独立仓 | 7205 | 129 | 🔵 非 FIST-Mbt |
| `lang-zone` | 独立仓 | 3934 | 116 | 🔵 非 FIST-Mbt |
| `vools` | 独立仓 | 3690 | 6 | 🔵 非 FIST-Mbt |
| `兹` | 独立仓 | 1700 | 18 | 🔵 非 FIST-Mbt |
| `Tnr` | 独立仓 | 1103 | 5 | 🔵 非 FIST-Mbt |
| `Tnr_merge_check` | 独立仓 | 1092 | 0 | 🔵 非 FIST-Mbt |
| `Tnr_p0` | 独立仓 | 952 | **932** | 🔵 非 FIST-Mbt（大量未提交） |
| `NPU-Tnr-test` | 独立仓 | 484 | 0 | 🔵 非 FIST-Mbt |
| `vq` | 独立仓 | 582 | 62 | 🔵 非 FIST-Mbt |
| `sigma-lang` | 独立仓 | 175 | 48 | 🔵 非 FIST-Mbt |
| `mcpconftest` | 独立仓 | 189 | 12 | ❓ **需 owner 裁决**（名字疑似 FIST-Mbt 的 MCP 配置夹具） |
| `rx-mbt` | 独立仓 | 77 | 6 | ❓ **需 owner 裁决**（`-mbt` 后缀 = MoonBit 相关） |
| `fist-evidence` | 独立仓 | 61 | 9 | ⚠️ **需 owner 裁决**（`fist-` 前缀，疑似 FIST 证据伴生仓） |
| `_archive` | 非 git（40 项） | — | — | ❓ 需 owner 裁决（名字即归档区） |
| `_fist_atgc_v2_ctl` | 非 git（10 项） | — | — | ❓ 需 owner 裁决（`fist` 前缀） |
| `_fist_atgc_v2_exp` | 非 git（7 项） | — | — | ❓ 需 owner 裁决 |
| `_fist_iso` | 非 git（7 项） | — | — | ❓ 需 owner 裁决 |
| `_fist_meta_prompts` | 非 git（11 项） | — | — | ❓ 需 owner 裁决 |
| `_lz_night_scratch` | 非 git（9 项） | — | — | ❓ 需 owner 裁决（`lz` = lang-zone?） |
| `backup` | 非 git（15 项） | — | — | ❓ 需 owner 裁决 |
| `competition` | 非 git（1 项） | — | — | 🔵 非 FIST-Mbt |
| `DownLoads` | 非 git（23 项） | — | — | 🔵 非 FIST-Mbt |
| `Nodea-ATGC` | 非 git（19 项） | — | — | 🔵 非 FIST-Mbt |
| `lang-pulgins` | 非 git（46 项） | — | — | 🔵 非 FIST-Mbt |
| `name-squats` | 非 git（3 项） | — | — | 🔵 非 FIST-Mbt |
| `temp` | 非 git（1 项） | — | — | ❓ 需 owner 裁决 |
| `AI` | 非 git（1 项） | — | — | 🔴 **异常项**：`E:/IDEProjects/AI/AI/` 自我嵌套，需查 |
| `.atomcode` | 非 git（3 项） | — | — | 🛠 宿主配置目录（工具保留） |
| `.codeartsdoer` | 非 git（4 项） | — | — | 🛠 宿主配置目录（工具保留） |
| `.loomy-attachments` | 非 git（1 项） | — | — | 🛠 宿主缓存 |
| `.workbuddy` | 非 git（1 项） | — | — | 🛠 宿主配置目录 |

**分类汇总**

| 类 | 数量 |
|---|---|
| FIST-Mbt 本体 + 已登记 worktree/容器 | **4**（`FIST-Mbt` / `FIST-Mbt-wt-r2` / `light-wt` / 见下） |
| FIST-Mbt 克隆（含独有提交，🔴） | **3** |
| 非 FIST-Mbt（独立仓 + 明显无关） | **15** |
| **需 owner 裁决** | **12** |
| 宿主工具目录（保留） | **4** |

---

## 5. 按本证明可安全删除的明确清单

> **本节是后续所有删除动作的唯一依据。不在本节里的东西，一律不许删。**

### 5.1 ✅ 无前置条件，可直接删（65 项本地分支）

**§2.2 的全部 65 支本地分支**，但其中 **6 支须先移除对应 worktree**：

```bash
# 第 1 步：先移除占着这些分支的 worktree
git worktree remove light-wt/cmd-gamma            # 分支 cmd-gamma
git worktree remove light-wt/cmd-alpha            # 分支 lightwt/cmd-alpha
git worktree remove light-wt/cmd-zeta             # 分支 lightwt/cmd-zeta（先验 345 个 M）
git worktree remove temp/wt-skill                 # 分支 worktree/skill-docs2（先验 2 个 ??）
git worktree remove .agents/worktrees/fix/battery-tree-state-cell
git worktree remove .agents/worktrees/fix/merge-cleanup-content-based

# 第 2 步：删 65 支（用 -d 而非 -D，让 git 自己再验一次）
for b in <§2.2 清单>; do git branch -d "$b"; done
```

### 5.2 ✅ 无前置条件，可直接删 worktree（21 项）

- 2 个干净 mergeability：`mergeability-4am4tf7u/wt`、`mergeability-f7_g687u/wt`
- 18 个 `.agents/worktrees/*` 干净项（dirty=0 的全部）
- `temp/r66`

### 5.3 ⚠️ 有前置条件的（**必须先做左边的动作**）

| 想删 | 必须先做 |
|---|---|
| 3 个脏 mergeability + `fix/agent-fp-check` + `fix/agent-pid-instance-lock` + `fix/omega-mark-keep` + `feat/agent-fingerprint` + `cmd-zeta` | `git -C <wt> diff --numstat` 证明**全部为 0**（CRLF 幻影）。不做不许删 |
| 5 个有真 `??` 的 worktree（`fix/bug-triage` / `fix/plan-gate` / `fix/display-rank-boundary` / `temp/wt-skill` / `light-wt/cmd-epsilon`） | 逐项列出 `??` 文件，确认无用或移到 `_archive/` |
| 151 + 48 + 85 支黄档分支 | **先蒸馏** `git log main..<br>` 或打 `archive/<br>` 标签 |
| `fix/publish-leak-p1-cleanup`（黄档最接近可删） | 蒸馏其 1 个提交 |
| 3 个 slave 克隆目录 | **先蒸馏 3 份 `docs/design-*.md`**（摘要见 §4.1） |

### 5.4 🔴 明令禁止删除（本期）

1. **全部 17 支 origin-only 分支**（尤其 `fix/omega-required-column`、`fix/merge-cleanup-content-based` 252 提交）
2. **3 个 `FIST-Mbt-slave-*` 目录**（含 main 里不存在的 `docs/design-*.md`）
3. **所有 dirty > 0 的 worktree**（27 个）
4. **主工作树 `E:/IDEProjects/AI/FIST-Mbt`**
5. **12 个「需 owner 裁决」的兄弟目录**
6. **`.sync-to-github`**（不可逆影响自动化，见 §6.1）

---

## 6. 缺口与风险

### 6.1 🔴 清理期间必须暂停 sync workflow（建议，需 owner 裁决）

`sync-from-gitcode.yml` 每 6 小时对 GitHub 执行 `git push --force` 全分支。
**风险**：若在 gitcode 侧删分支后 workflow 运行，GitHub 侧同名分支不会被删（sync 不删），
但**若 gitcode 侧某分支被删而 GitHub 侧仍保留独有内容，将来该名字被复用时会覆盖**。
更直接的风险：**清理动作产生的本地状态在 6 小时内可能被自动改写**。

**建议**：清理窗口内先 `git rm .sync-to-github` 暂停同步，清理完再决定是否恢复。
**⚠️ 这是不可逆动作（影响自动化），审计组不执行，交 owner 裁决。**

### 6.2 🟡 `git push --force` 失败被静默吞掉

sync L43/46 的 `|| echo "push failed on $b"` 把推送失败降级为一行日志。
⇒ **sync 长期半失败而无人知**（这正是 origin 只有 32 支同名、120 支 gitcode 分支从未出现在 GitHub 的原因）。
建议：把失败累计成 step 退出码，或至少在 summary 里统计失败数。

### 6.3 🟡 C2 判据本身的局限（本证明最重要的方法论补充）

C2 只看「文件名」，不看「能力」。
本证明**用人工内容比对推翻了一个红档**（`git_sandbox.py` ≡ `git_env.py`），
但这意味着 **C2 的「非空」永远只是线索，不是结论**。
建议后续把 C2 升级为「非空 ⇒ 逐文件比 patch-id / 内容等价」，而不是直接判红。

### 6.4 🟡 CRLF 幻影会污染 worktree 脏度判定

`dirty` 计数在 `.gitattributes` 无 `*` 规则 + `core.autocrlf=true` 下**系统性虚高**（判例-附已记录 345→7）。
§3 里所有「全 M 无 untracked」的项都属此列，**未经 `--numstat` 过滤不得判脏、更不得据此拒删或据此删**。

### 6.5 🟡 本审计未覆盖的

- **git tag 面**：本次未盘（`git tag` 数量、是否有独有 tag）。sync L48 是 `git push --tags`（只增不删）⇒ **GitHub 侧 tag 可能比 gitcode 多，属独有内容，需补盘。**
- **git stash 面**：未盘。51 个脏 worktree 里是否有 stash 未验。
- **`.git` 内部**：`refs/original`（filter-repo 备份）、`lost-found` 未盘。
- **12 个「需 owner 裁决」目录的内容**：只看了文件数，未逐项读。

### 6.6 规模再订正

统帅初查的「34 个兄弟目录」实测 **38**；「gitcode 153 / 本地 153 / origin 51」三项**全部复核一致**。

---

## 7. 复现命令总表

```bash
# 全量分支扫描（360 支，约 8 分钟）
python scripts/tmp_audit_preservation_scan.py --out temp/audit/scan_full.json

# 三档统计
python temp/audit/summarize.py

# 噪音面对照实验（判例-6 复现）
python temp/audit/noise_control.py

# git_sandbox.py 与 git_env.py 等价性比对
python temp/audit/git_sandbox_cmp.py

# worktree 逐个取证
python temp/audit/wt_inventory.py

# origin vs gitcode 漂移
python temp/audit/remote_drift.py

# 兄弟目录取证
python temp/audit/sibling_inventory.py

# 单支判定（模板）
git merge-base --is-ancestor <br> main; echo "C1-A rc=$?"
git diff --diff-filter=D --name-only main <br>          # 判例-1 探针
git diff --name-only main <br> --diff-filter=A          # C2 原始面
git log main..<br> --format='%H %s'                     # C3
```

---

## 8. 来源

| 角色 | 贡献 |
|---|---|
| 统帅（lead） | 三条判据的原始定义、`^\.dsh/` 排除面、判例-1/判例-6、`sync-from-gitcode.yml` 线索 |
| 判例集 | `reports/2026-10-24-merge-precedents.md`（判例-1~6、附 CRLF 幻影读数） |
| 司令-δ | `fix/omega-required-column` 的 BUG-389 方向②线索 |
| 司令-ε | 判例-6 的原始发现（148 支假阳性） |
| 审计组 | 360 支全量取证、对照实验、`git_sandbox.py` 等价性推翻、3 个 slave 克隆的独有史料蒸馏 |
