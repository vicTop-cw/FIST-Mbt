# 分支清理执行报告（阶段 1）

> **任务**：task-11 · **执行**：commander-alpha（执行组）· **日期**：2026-10-24
> **依据**：《资产保全证明书》`reports/2026-10-24-asset-preservation-proof.md` §5（`460026ba`）
> **授权面**：65 本地分支 + 21 worktree + 14 origin 远程分支 + **0 gitcode**（绝不动）
> **纪律**：逐条执行逐条记录 / 删前二次核验 / 只 add 明确路径 / 夹具 git 走 `isolated_git_env()` / 绝不 force push

---

## 0. 删前基线（2026-10-24 13:50 实测）

| 读数 | 值 |
|---|---|
| main HEAD | `5006d1cf8c317f32256310e16e972e0011f1b2dd` |
| 本地分支数 | **154** |
| worktree 登记数 | **54**（含主工作树） |
| origin 远程分支 | 52 |
| gitcode 远程分支 | 155 |
| `git ls-files -s \| awk '$1=="160000"'` | 空 |

---

## 1. 前置核验（未删除任何东西之前先跑完）

### 1.1 65 支本地分支 —— 二次核验 **65/65 通过**

判据：① `git log --format=%H main..<br>` 计数 = 0；② `git diff --name-only HEAD <br> --diff-filter=A` 过排除面后为空。

排除面（判例-6/8/10）：
```
\.md$|^memory/|^reports/|^docs/|^\.agents/|^\.dsh/|tmp_merge_batch|merge-prompt\.txt|\.verify-wt|^dist/
```

读数：**可删 65 / 跳过 0 / 共 65**。逐支 tip / committer date / subject / reflog 条数落在
`temp/cleanup_baseline.json`（只读普查，未做任何删除）。

**其中 4 支当前被 worktree 占用**（`git branch -D` 会拒绝，须先移除 worktree）：
`cmd-gamma`、`lightwt/cmd-alpha`、`lightwt/cmd-zeta`、`worktree/skill-docs2`。

> 证明书 §2.2 说「6 支被占用」，实测**现读只有 4 支**——`fix/battery-tree-state-cell`
> 与 `fix/merge-cleanup-content-based` 的 `.agents/worktrees/` 目录**已不存在于 `git worktree list`**。
> 该两处订正待回写证明书 v3（不由本报告改证明书原文）。

### 1.2 worktree —— 54 个登记项逐个取 dirty 读数

| 读数 | 值 |
|---|---|
| dirty = 0 | **37** |
| dirty > 0 | **16** |
| 主工作树 | 1 |

`.agents/worktrees/` 下：**37 个登记 / 28 个 dirty=0**，但**其中没有一个的分支在 §2.2 绿档 65 支里**
⇒ 证明书 §3.6「18 个 `.agents` 干净项」的 **18 这个数缺名单、无法照单执行**，已由统帅裁定**作废**，
改为「逐支按 ①dirty=0 + ②HEAD 已在 main 两条判据现算，不预设数量」。

---

## 2. 判例增补（本报告向审计组的输入，请回写证明书 v3）

> 本执行组在过程中抓到两条**假阴性**。证明书 §3.3 / §5.3 的 CRLF 幻影判据受第 2 条影响，
> **须用能看见 index 的命令复验**。

### 判例-10（沿用）：静默无输出
`git grep -c` 零命中时 **rc=1 且不打印任何行** ⇒ 判 **rc**，不判输出。

### 判例-10b（新增）：命令口径不全
`git diff [--numstat]` 读的是 **工作树 vs index**，**不含 index**。改动在 index 里时它必然读 0。

| 命令 | 比较面 | 用途 |
|---|---|---|
| `git diff --numstat` | 工作树 vs **index** | ❌ 不能判「相对 HEAD 有无改动」 |
| `git diff --cached --numstat` | **index** vs HEAD | ✅ |
| `git diff HEAD --numstat` | 工作树 **+ index** vs HEAD | ✅ 判「相对 HEAD」用这条 |
| `git status --porcelain` | 三者都含 | ✅ 判「有无未提交」 |

**复现**（`mergeability-zi2h77_h/wt`，2026-10-24 实测）：
```
git diff --numstat          = 0 行    ← 假阴性
git diff --cached --numstat = 42 行
git diff HEAD --stat        = 43 行
porcelain 分布 = M 28 / A 14，未跟踪 ?? = 0
```
⇒ **42 项全部在 index 里**。若按「numstat=0 ⇒ CRLF 幻影 ⇒ 可删」执行，会丢掉 8 个与 main 内容不同的文件。

**结论**：证明书 §3.3「全 M 无 untracked ⇒ 疑幻影」的 8 个 worktree、§5.3 的 8 个「须先验 `--numstat`」项，
**必须改用 `git diff HEAD --numstat` 或 `git diff --cached --numstat` 复验**，否则统计面系统性偏少。

---

## 3. 逐批执行记录

### 第 1 批 · worktree 删除（授权 21，实际执行 1 删 / 2 跳过）

#### ✅ 已删 1 个

| # | path | 删前三读数 | 结果 |
|---|---|---|---|
| 1 | `C:/Users/victo/AppData/Local/Temp/mergeability-f7_g687u/wt` | `status --porcelain` = **0 项**；HEAD = `3897d3783576cf8b4325cda6a8fd726542bc4dd4`；`merge-base --is-ancestor HEAD main` = **是**；`main..HEAD` = **0 提交** | `git worktree remove` **rc=0**，路径已不存在 |

命令：`git worktree remove "C:/Users/victo/AppData/Local/Temp/mergeability-f7_g687u/wt"`（**未用 `--force`**）

#### ⏭ 跳过 2 个（均因统帅裁决或判据不成立）

| # | path | 读数 | 跳过理由 |
|---|---|---|---|
| 1 | `mergeability-4am4tf7u/wt` | dirty=0；HEAD `b5c8a366`；**`is-ancestor main` = 否**；`main..HEAD` = 710 提交 | 统帅裁决②：**暂不删**——它是 master 镜像线 `b5c8a366` 的现成只读快照，留到末阶段一并清 |
| 2 | `mergeability-zi2h77_h/wt` | dirty=42（M 28 / A 14，index 面）；HEAD `b5c8a366` | 统帅裁决③：**先导出 8 个独有版本再删**（见第 2 批） |

> **第 1 批口径订正（重要）**：统帅初始清单列了 5 个 mergeability 且带 `--force`，
> 与「`status --porcelain` 非空即不删」的规则**自相矛盾**。执行组拒绝执行 `--force`，
> 实测确认 `bn5486xy`=103 / `xd7gqcjf`=57 / `zi2h77_h`=42 三项均非空，`--force` 会连未提交内容一起丢。
> 统帅已复核并认错，改判为「先核验后处置」。

**worktree 读数：删前 54 → 删后 53。**

### 第 2 批 · `zi2h77_h` —— 先导出再删（授权命令，已执行）

**为什么必须先导出**：该 worktree 的 42 项差异**全部在 index**（`M` 28 / `A` 14），
其中 **8 个文件的 index 内容与 main 内容不同**（其余 34 项或与 main 逐字节相同、或属噪音面）。
`git worktree remove --force` 会连 index 一起抹掉 ⇒ 先落 patch。

#### 导出读数

```
命令 : git -C <wt> diff --cached --binary HEAD -- <8 个文件>
落盘 : _archive/zi2h77_h-staged.patch
字节 : 90,767 B  |  diff 段 : 8 段（与 8 个文件一一对应）
自证 : 在 zi2h77_h 上 `git apply --cached --check --reverse <patch>` = rc 0（可逐字节还原）
```

| # | 文件 | index 字节 | main 字节 | 差异 |
|---|---|---|---|---|
| 1 | `.dsh/fist-mbt-plugin/cordis.patch.yml.tpl` | 256 | 1239 | 异 |
| 2 | `scripts/check_branch_ancestry.py` | 6,980 | 7,441 | 异 |
| 3 | `scripts/check_diff_scope.py` | 25,579 | 26,498 | 异 |
| 4 | `scripts/check_direct_push.py` | 1,110 | 3,214 | 异 |
| 5 | `scripts/check_hardcoded_paths.py` | 6,284 | 15,035 | 异 |
| 6 | `scripts/check_memory_log_size.py` | 5,709 | 6,683 | 异 |
| 7 | `scripts/check_selftest_call_face.py` | 14,692 | 15,068 | 异 |
| 8 | `scripts/render_dsh_patch.py` | 10,549 | 10,899 | 异 |

#### 删除结果

| # | path | 结果 |
|---|---|---|
| 2 | `C:/Users/victo/AppData/Local/Temp/mergeability-zi2h77_h/wt` | 前置三项（patch 非空 / 8 段齐 / 反向可还原 rc=0）全过后 `git worktree remove --force` **rc=0**，路径已不存在 |

> `_archive/` 已被 `.gitignore:213 /_archive/` 覆盖 ⇒ 该 patch 不进打包面（统帅 P0 收口后已确认）。

**worktree 读数：删前 53 → 删后 52。**

⚠️ **未删的同类（须审计组复验后另行处置）**：
`mergeability-bn5486xy/wt`（dirty 103）、`mergeability-xd7gqcjf/wt`（dirty 57）
—— 两者按判例-10b 必须用 `git diff HEAD --numstat` / `git diff --cached --numstat` 复验，
**执行组未对它们做任何改动**。

### 第 3 批 · 65 支本地分支（分批执行，每批 10 支）

**执行形态**：逐支「删前二次核验 → `git branch -D` → 记录」，**每批落盘**，不做一把梭。
二次核验两条（与 §1.1 同口径，删前现场重跑，不引用旧普查结果）：
① `git log --format=%H main..<br>` 计数必须为 0；
② `git diff --name-only HEAD <br> --diff-filter=A` 过排除面后必须为空。

**reflog 找回边界**：`git branch -D` 删的是 ref，提交对象仍在对象库里；
`HEAD` reflog 默认保留 **90 天**（`gc.reflogExpire=90 days`），
即被删分支的 tip 在该窗口内可经 `git reflog` / `git rev-parse <tip>` 找回。
本报告已逐支记录 **tip sha**（见下表），**即使 reflog 过期，只要对象未被 gc 仍可按 sha 恢复**。

#### 第 1 批（10 支）：删 9 / 跳过 1

| # | 分支 | tip | 结果 |
|---|---|---|---|
| 1 | `backup/layer3-clean` | `c6ac7705` | ✅ 已删 |
| 2 | `feat/slave-mergeability-guard` | `0fd98d24` | ✅ 已删 |
| 3 | `cmd-gamma` | `46a62ef7` | ✅ 已删（**先移 worktree**，见第 4 批） |
| 4 | `feat/task-007-run-guards-universe` | `1a5af460` | ✅ 已删 |
| 5 | `docs/native-uaf-rootcause` | `05c324da` | ✅ 已删 |
| 6 | `feat/tier2-pr3-gate-ci` | `2a665a6f` | ✅ 已删 |
| 7 | `feat/audit-branch-delete` | `ea003272` | ✅ 已删 |
| 8 | `fix/agent-map-battery-count-pointer` | `53495a07` | ✅ 已删 |
| 9 | `feat/delivery-gap-cross-remote` | `0b8e3cd2` | ✅ 已删 |
| 10 | `fix/audit-script-execution-face` | `bfa238e8` | ✅ 已删 |

**本批读数：本地分支 154 → 144**（第 3 行 `cmd-gamma` 已在第 4 批前置中删除，故本批计 9 删）

#### 65 支逐支执行表（tip 即回滚锚点）

| # | 分支 | tip | 提交日 | 结果 |
|---|---|---|---|---|
| 1 | `backup/layer3-clean` | `c6ac7705da` | 2026-10-21 | ✅ 已删 |
| 2 | `feat/slave-mergeability-guard` | `0fd98d240b` | 2026-10-22 | ✅ 已删 |
| 3 | `cmd-gamma` | `46a62ef75b` | 2026-10-24 | ✅ 已删 |
| 4 | `feat/task-007-run-guards-universe` | `1a5af4609e` | 2026-10-21 | ✅ 已删 |
| 5 | `docs/native-uaf-rootcause` | `05c324daeb` | 2026-10-22 | ✅ 已删 |
| 6 | `feat/tier2-pr3-gate-ci` | `2a665a6ff2` | 2026-10-21 | ✅ 已删 |
| 7 | `feat/audit-branch-delete` | `ea003272ac` | 2026-10-22 | ✅ 已删 |
| 8 | `fix/agent-map-battery-count-pointer` | `53495a079f` | 2026-10-22 | ✅ 已删 |
| 9 | `feat/delivery-gap-cross-remote` | `0b8e3cd264` | 2026-10-23 | ✅ 已删 |
| 10 | `fix/audit-script-execution-face` | `bfa238e81a` | 2026-10-22 | ✅ 已删 |
| 11 | `feat/merge-loss-detector` | `ef04420a9c` | 2026-10-23 | ✅ 已删 |
| 12 | `fix/battery-readonly` | `c9e3465e83` | 2026-10-22 | ✅ 已删 |
| 13 | `feat/repo-hygiene-guard-r45` | `3a715a4c49` | 2026-10-24 | ✅ 已删 |
| 14 | `fix/battery-tree-state-cell` | `2fe33ce019` | 2026-10-22 | ✅ 已删 |
| 15 | `fix/bug-refs-guard-semantics` | `86b260f871` | 2026-10-22 | ✅ 已删 |
| 16 | `fix/restore-issue-scan-merged-state` | `1046435359` | 2026-10-21 | ✅ 已删 |
| 17 | `fix/bug-refs-ledger-backfill` | `0ec67ec501` | 2026-10-22 | ✅ 已删 |
| 18 | `fix/restore-merged-registrations` | `2a4b9f71ed` | 2026-10-22 | ✅ 已删 |
| 19 | `fix/bug354-dead-params-report-bug-watchdog` | `5b9b86aae5` | 2026-10-22 | ✅ 已删 |
| 20 | `fix/restore-plan-landing-ratchet-gate` | `204eb0877c` | 2026-10-21 | ✅ 已删 |
| 21 | `fix/bug380-node-shim-test-runner` | `01544873ce` | 2026-10-22 | ✅ 已删 |
| 22 | `fix/restore-rhop-poll-impl` | `1678982e9b` | 2026-10-22 | ✅ 已删 |
| 23 | `fix/bug381-fmt-check-unmeasurable` | `79b59fce29` | 2026-10-22 | ✅ 已删 |
| 24 | `fix/restore-rhop-test-on-main` | `fb3b0dbce6` | 2026-10-22 | ✅ 已删 |
| 25 | `fix/claim-rank-gate-g4` | `2a64c8dac1` | 2026-10-22 | ✅ 已删 |
| 26 | `fix/rhop-native-fixture` | `6f6706dca8` | 2026-10-23 | ✅ 已删 |
| 27 | `fix/cli-native-link-flag` | `b211f48749` | 2026-10-22 | ✅ 已删 |
| 28 | `fix/task-003-ci-step-position` | `bde1632c28` | 2026-10-21 | ✅ 已删 |
| 29 | `fix/daqing-ffi-uaf-patch` | `66fca04a6c` | 2026-10-22 | ✅ 已删 |
| 30 | `fix/task-004-revert-diff-detector` | `a7540ab996` | 2026-10-21 | ✅ 已删 |
| 31 | `fix/dist-snapshot-guard` | `c99069dd3b` | 2026-10-22 | ✅ 已删 |
| 32 | `fix/task-004-revert-diff-detector-v2` | `c041572a46` | 2026-10-22 | ✅ 已删 |
| 33 | `fix/doc-dup-guard-and-dedupe` | `40f4871ca4` | 2026-10-22 | ✅ 已删 |
| 34 | `fix/tier2-delta-ratchet-and-ledger` | `ef2b7d86ff` | 2026-10-21 | ✅ 已删 |
| 35 | `fix/fist-gate-env-state-classification` | `a233d69aa3` | 2026-10-21 | ✅ 已删 |
| 36 | `fix/tier2-governance-bundle` | `5d2827aaf2` | 2026-10-22 | ✅ 已删 |
| 37 | `fix/guard-census-covers-blackbox` | `762e5664d7` | 2026-10-21 | ✅ 已删 |
| 38 | `fix/v0310-projection-closeout` | `cd54543670` | 2026-10-22 | ✅ 已删 |
| 39 | `fix/guard-docstring-correct-measurement` | `009e875a2e` | 2026-10-21 | ✅ 已删 |
| 40 | `fix/v0310-projection-closeout2` | `ef43192949` | 2026-10-22 | ✅ 已删 |
| 41 | `fix/guards-conflict-markers-from-clean-commits` | `08b3617555` | 2026-10-21 | ✅ 已删 |
| 42 | `fix/version-align-r2` | `4d19996fdc` | 2026-10-22 | ✅ 已删 |
| 43 | `fix/guards-parse-dead-after-marker-clear` | `49a4253470` | 2026-10-21 | ✅ 已删 |
| 44 | `fix/version-align-r3` | `27e05ae03a` | 2026-10-22 | ✅ 已删 |
| 45 | `fix/integrate-guard-repairs-verified` | `e16d279ea1` | 2026-10-21 | ✅ 已删 |
| 46 | `fix/version-align-r4` | `559b311925` | 2026-10-22 | ✅ 已删 |
| 47 | `fix/ledger-and-guard-cleanup` | `c30b856ba0` | 2026-10-22 | ✅ 已删 |
| 48 | `fix/whisperer-cherry-pick-not-overlay` | `8c72fc57c3` | 2026-10-22 | ✅ 已删 |
| 49 | `fix/ledger-close-358` | `a23ccd3783` | 2026-10-21 | ✅ 已删 |
| 50 | `handoff/r57-note` | `204eb0877c` | 2026-10-21 | ✅ 已删 |
| 51 | `fix/mbti-generic-fn` | `5e3bcf8d59` | 2026-10-22 | ✅ 已删 |
| 52 | `lightwt/cmd-alpha` | `46a62ef75b` | 2026-10-24 | ⏭ 未删（被 worktree 占用） |
| 53 | `fix/merge-cleanup-content-based` | `910562159f` | 2026-10-22 | ✅ 已删 |
| 54 | `lightwt/cmd-zeta` | `3897d37835` | 2026-10-24 | ⏭ 未删（被 worktree 占用） |
| 55 | `fix/merge-cleanup-remote-baseline` | `58677712b4` | 2026-10-22 | ✅ 已删 |
| 56 | `test-verify` | `e16d279ea1` | 2026-10-21 | ✅ 已删 |
| 57 | `fix/native-gate-repoint` | `78659c9809` | 2026-10-22 | ✅ 已删 |
| 58 | `tmp/replay` | `9e6b196f56` | 2026-10-23 | ✅ 已删 |
| 59 | `fix/orphan-rhop-test-compile-red` | `7b85f41de1` | 2026-10-22 | ✅ 已删 |
| 60 | `tmp/stack-test` | `9e6b196f56` | 2026-10-23 | ✅ 已删 |
| 61 | `fix/pre-commit-marker-gate` | `7fc6769ee2` | 2026-10-22 | ✅ 已删 |
| 62 | `worktree/skill-docs2` | `aa60bc20b9` | 2026-10-21 | ⏭ 未删（被 worktree 占用） |
| 63 | `fix/probe-attribution-daqing` | `0ff8ade69a` | 2026-10-22 | ✅ 已删 |
| 64 | `fix/ps1-bom-slave-merge` | `8df8789d0c` | 2026-10-21 | ✅ 已删 |
| 65 | `fix/readme-dedup-and-dist-refresh` | `d2e5e08f77` | 2026-10-22 | ✅ 已删 |

> **回滚锚点**：上表 `tip` 列即每支被删分支的原始提交 sha。`git branch -D` 只删 ref，**提交对象仍在对象库**——实测对全部已删 tip 跑 `git cat-file -e <sha>` 均成功。
> 恢复单支：`git branch <name> <tip>`；全量恢复可读本表逐行重建。
> 对象被 `git gc` 回收后才真正不可恢复（默认 `gc.reflogExpire=90 days`，`gc.pruneExpire=2 weeks` 只管不可达对象）。

---

## 4. 跳过清单（**最重要 —— 它告诉 owner「哪些还有争议」**）

**共跳过 3 支，全部属于「清单允许删，但前置条件未满足」**：

| # | 分支 | tip | 跳过理由 | 解除条件 |
|---|---|---|---|---|
| 1 | `lightwt/cmd-alpha` | `46a62ef7` | worktree `E:/IDEProjects/AI/light-wt/cmd-alpha` 仍登记占用。**该 worktree 的 detached HEAD 是 `c5fa9b17`（不在任何分支上，`main..c5fa9b17` = 1 提交）**，`git worktree remove` 会丢弃这个未被任何 ref 持有的提交 | 先决定 `c5fa9b17` 的去留（其内容已由统帅按内容落库 `f1cd6eb5`），再移 worktree → 删分支 |
| 2 | `lightwt/cmd-zeta` | `3897d378` | worktree `E:/IDEProjects/AI/light-wt/cmd-zeta` **dirty = 345**（`M` 344 / `M ` 1，`??` = 0） | 按判例-10b 用 `git diff HEAD --numstat` 复验是否 CRLF 幻影；**未复验前不删** |
| 3 | `worktree/skill-docs2` | `aa60bc20` | worktree `E:/IDEProjects/AI/FIST-Mbt/temp/wt-skill` **dirty = 378**（` M` 353 / `A ` 21 / `M ` 1 / `AM` 1 / **`??` 2**） | 有 **2 个真实未跟踪文件**（不在 git 里，删即永久丢失）⇒ 须先列出并裁决，再按判例-10b 复验其余 |

### 4.1 明确未列入本次动作面（不在授权内 / 授权前须裁决）

| 项 | 数量 | 未动原因 |
|---|---|---|
| **gitcode 远程分支** | 155 | **授权 0 支，绝对不许碰**（任务书与证明书 §5.4 双重明令） |
| origin 远程分支 | 52 | 统帅本轮明令「先别动」——需先裁决「清理期是否暂停 sync workflow」，否则删了 6 小时内会被 `sync-from-gitcode.yml` 的 `push --force` 还原 |
| `mergeability-bn5486xy/wt` | dirty 103 | 判例-10b 复验未做，**执行组未做任何改动** |
| `mergeability-xd7gqcjf/wt` | dirty 57 | 同上 |
| `mergeability-4am4tf7u/wt` | dirty 0 | 统帅裁决②：留作 master 镜像线 `b5c8a366` 的只读快照，末阶段一并清 |
| 其余 dirty > 0 的 worktree | 12 个 | 证明书 §5.4「所有 dirty > 0 的 worktree 禁止删」 |
| 兄弟目录 38 个 | 38 | 不在 task-11 授权面 |

---

## 5. 精确读数（删前 / 删后）

| 项 | 删前 | 删后 | 净变化 |
|---|---|---|---|
| 本地分支总数 | **154** | **92** | **−62** |
| └ 绿档 65 支已删 | 0 | **62** | −62 |
| └ 绿档 65 支跳过 | — | **3** | 见 §4 |
| worktree 登记数（含主工作树） | **54** | **51** | **−3** |
| └ 删除 | — | 3 个（`f7_g687u` / `zi2h77_h` / `cmd-gamma`） | |
| 绿档二次核验通过率 | **65 / 65** | — | 0 例违例 |
| `_archive/zi2h77_h-staged.patch` | — | 90,767 B / 8 diff 段 | 反向可还原 rc=0 |

> 本地分支 154 → 92 是本 **worktree 的**分支数。主仓 `git branch | wc -l` 同步为 92。

---

## 6. 回滚预案（**给 owner 的心理保险**）

### 6.1 本报告的信息保全

所有被删分支的 **原始 tip sha** 已逐支记录在 §3 的 65 行表中，**删除后仍逐支复核过 `git cat-file -e <tip>` 成功（62/62）**——即提交对象全部仍在对象库，ref 只是不再指向它们。

### 6.2 恢复窗口与边界

> **本地分支删除后可通过 `git reflog` / `git fsck --lost-found` 找回，窗口 90 天**（`gc.reflogExpire` 默认值）。
> **90 天后若执行 `git gc --prune=now` 则永久丢失。**

实测本仓配置（**未改过，全部走默认**）：
```
git config gc.reflogExpire              → (未设置，默认 90 days)
git config gc.reflogExpireUnreachable   → (未设置，默认 30 days)
```

### 6.3 单支恢复（最常用）

```bash
git branch <原分支名> <§3 表中的 tip sha>
# 例: git branch fix/battery-readonly c9e3465e
```

### 6.4 全量恢复

按 §3 的 65 行表逐行执行 §6.3 —— **该表本身就是完整的恢复脚本输入**，不依赖 reflog 是否过期。

### 6.5 保全面（worktree）

| 对象 | 保全方式 |
|---|---|
| `mergeability-f7_g687u/wt` | dirty=0 且 HEAD `3897d378` 是 main 祖先（`main..HEAD` = 0 提交）⇒ **无内容可丢** |
| `mergeability-zi2h77_h/wt` | 8 个与 main 内容不同的文件已导出 `_archive/zi2h77_h-staged.patch`（90,767 B），且**在该 worktree 上 `git apply --cached --check --reverse` = rc 0**（证明可逐字节还原）⇒ **内容已在 patch 里** |
| `light-wt/cmd-gamma` | dirty=0，HEAD `46a62ef7` = main 祖先 ⇒ 无内容可丢 |

---

## 7. 门禁读数

（见文末「8. 交差门禁」一节，统一列出）

---

## 8. 交差门禁（2026-10-24 14:35 实测）

| 门禁 | 读数 | 结论 |
|---|---|---|
| `moon check --target js` | `Finished. moon: ran 31 tasks, now up to date (501 warnings, 0 errors)` | ✅ **0 errors**（501 warnings 与 main 基线同读数） |
| 三端一致 | 报告提交 `d06f6542` 落 main；`gitcode/main` 同步待推 | ⏳ 提交仅本地，未推远端正（纪律：禁开 PR、禁 force push） |
| `git ls-files -s \| awk '$1=="160000"'` | 空 | ✅ 无 gitlink |
| `git cat-file -e <tip>` 对 62 支被删 tip | **62 / 62 成功** | ✅ 对象全在库，ref 可重建 |
| `_archive/zi2h77_h-staged.patch` | 90,767 B / 8 diff 段 / 反向还原 rc=0 | ✅ 可逐字节还原 |

---

## 9. 缺口与风险

| # | 缺口 / 风险 | 影响 | 建议 |
|---|---|---|---|
| R1 | **origin 远程分支 14 支未动** | 任务书授权内，但统帅本轮明令「先别动」 | 待 owner 裁决「清理期是否暂停 `sync-from-gitcode.yml`」，否则删了会被 6 小时内的 `push --force` 还原 |
| R2 | **gitcode 155 支一支未动** | 授权 0 支 | 按纪律执行，无缺口 |
| R3 | `lightwt/cmd-alpha` 的 `c5fa9b17` 未被任何 ref 持有 | 移 worktree 即丢该 commit 对象（内容已由统帅落库 `f1cd6eb5`） | 若要保留，先 `git branch <name> c5fa9b17` 再移 worktree |
| R4 | `lightwt/cmd-zeta`(345) / `worktree/skill-docs2`(378) 未复验 | 3 支绿档分支因此未删 | 按判例-10b 用 `git diff HEAD --numstat` 复验；`wt-skill` 另有 **2 个真实 `??` 文件**须先裁决 |
| R5 | `mergeability-bn5486xy`(103) / `xd7gqcjf`(57) 未处置 | 不影响授权内动作 | 同 R4，须先看 index 面 |
| R6 | 证明书 §3.6「18 个 `.agents` 干净项」无名单 | 已作废，改逐支现算 | 转审计组回写 v3 |
| R7 | 证明书 §2.2「6 支被占用」实测为 **4 支** | 已在本报告订正 | 转审计组回写 v3 |
| R8 | 主仓另有两个未跟踪件 `.agents/delta_probe2.sh` / `scripts/tmp_audit_preservation_scan.py` | 非本次产出，未动 | 属取证器/临时件，交瘦身组或审计组处置 |
| R9 | 报告提交 `d06f6542` 仅本地 | 远端未同步 | 按纪律未推；须统帅决定推送通道 |

---

## 10. 未执行项汇总（对账用）

| 授权动作 | 授权数 | 实际执行 | 差额与原因 |
|---|---|---|---|
| 删本地分支 | 65 | **62** | −3：均被 worktree 占用且 dirty ≠ 0（§4） |
| 删 worktree | 21 | **3** | −18：证明书 §3.6 的「21」无名单；按统帅新口径「逐支现算，不预设数量」，实际满足「dirty=0 + HEAD 已在 main」的只有 3 个 |
| 删 origin 远程分支 | 14 | **0** | 统帅本轮明令暂缓（R1） |
| 删 gitcode 远程分支 | **0** | **0** | ✅ 一支未动 |

---

**报告完成 · commander-alpha · 2026-10-24**

---

## 11. R3 / R4 / R5 复验（判例-10b 口径，2026-10-24 14:55）

### R3：`c5fa9b17` 保全 ✅ 已完成

```bash
git branch archive/cmd-alpha-c5fa9b17 c5fa9b17
# 实测: git for-each-ref --contains c5fa9b17 → refs/heads/archive/cmd-alpha-c5fa9b17
git worktree remove E:/IDEProjects/AI/light-wt/cmd-alpha      # 前置 dirty=0 → rc 0
git branch -D lightwt/cmd-alpha                                # rc 0 (was 46a62ef7)
```
**读后：本地分支 92（`lightwt/cmd-alpha` 已走到此前的 62 里）→ 仍 92（含新增 archive 分支）**；worktree 51 → **50**。

### R4/R5：三处判据读数（**结论：全部不是 CRLF 幻影**）

判据用能看见 index 的命令（判例-10b）：

| 对象 | dirty | `git diff --numstat` | `git diff --cached` | **`git diff HEAD`（判据）** |
|---|---|---|---|---|
| `cmd-zeta` | 345 | 2 行 | 0 行 | **2 行** |
| `wt-skill` | 378 | 355 行 | 22 行 | **376 行** |
| `mergeability-bn5486xy` | 103 | 158 行 | 103 行 | **103 行** |
| `mergeability-xd7gqcjf` | 57 | 64 行 | 57 行 | **57 行** |

逐文件比对 main（CRLF 归一化后比较）：

| 对象 | 改动文件 | 与 main 等价（含 CRLF 归一） | **真差异** | **main 无此文件** |
|---|---|---|---|---|
| `cmd-zeta` | 345 | 334 | **11** | 0 |
| `wt-skill` | 376 | — | 见下 | **2 个 `??`** |
| `bn5486xy` | 103 | 0 | **78** | **25** |
| `xd7gqcjf` | 57 | 0 | **31** | **26** |

**⇒ 没有一处是「删除行 = 新增行」的对称 CRLF 幻影。按统帅口径「有真改动 → 停下来报」，执行组停手。**

#### `cmd-zeta`：345 项里 334 项是幻影，**11 项是真差异**

```
.github/workflows/gate.yml          README.mbt.md
reports/2026-10-24-lead-pr-merge-manual.md
src/core/core_task.mbt              src/engine/engine.mbt
src/engine/engine_execute_r2_test.mbt   src/engine/engine_supervisor.mbt
src/engine/omega_strong.mbt         src/server/board_ascii_test.mbt
src/server/supervisor_tools_wbtest.mbt  src/store/store_sqlite.mbt
```
> 注意：这 11 项**名字与司令-δ 的 omega 工作面高度重合**（`core_task` / `engine` / `omega_strong` / `supervisor_tools` / `store_sqlite`），**但方向上需单独判断**（是 omega 差量的来源，还是旧基线残留）。**执行组不裁判**，交统帅/审计组。

#### `wt-skill`：2 个真实未跟踪文件（**不在 git 里，删即永久丢失**）

```
?? docs/loop-mode-skill.md
?? docs/phi-accrual-heal-skill.md
```

#### `bn5486xy` / `xd7gqcjf`：**25 / 26 个 main 里不存在的文件**

两处共同清单（`memory/*` 全部）：
```
memory/2026-09-24.md … memory/2026-10-22-version-align.md, memory/2026-10-22.md, memory/thinking.md
.dsh/fist-mbt-plugin/cordis.patch.yml   (0 B，空文件)
```
`xd7gqcjf` 另有 `memory/2026-10-23.md`（1,330 B）。
**`memory/2026-2026*.md` 在 main 的 `.gitignore` 里被规则 `memory/2026-*.md` 挡住** ⇒ 这些是 worktree 本地产物，不是跟踪面。

> **一处须点名的异常**：`xd7gqcjf` 的 `memory/2026-10-22.md` 达 **384,918,972 字符 / 3,698,202 行**，
> 其中 **`## R70 fix/whisperer-selftest-and-scan-gitdir` 标题出现 19,110 次**，单个行首片段重复 1,549 次
> ⇒ 这是**日志被反复 append 的污染文件**，不是有价值的独有史料。但它体积过大，**导出代价与风险都高**，交统帅裁决。

---

## 12. 需裁决清单（R4/R5 全部停留在此）

| # | 对象 | 停留理由 | 建议 |
|---|---|---|---|
| 1 | `cmd-zeta` / `lightwt/cmd-zeta` | 11 项真差异（含 omega 工作面同名文件） | 先判那 11 项是「omega 差量来源」还是「旧基线残留」——**前者要先摘取，后者才可 clean 后删** |
| 2 | `wt-skill` / `worktree/skill-docs2` | 2 个真实 `??`（`docs/loop-mode-skill.md` / `docs/phi-accrual-heal-skill.md`） | 先 `git add` 进某分支或 `mv _archive/`，再 clean 后删 |
| 3 | `mergeability-bn5486xy` | 78 项真差异 + 25 个 main 无的文件 | 那 25 个都是 `.gitignore` 挡住的本地 `memory/*` 产物 ⇒ 可安全丢；78 项真差异需逐个看 |
| 4 | `mergeability-xd7gqcjf` | 31 项真差异 + 26 个 main 无的文件（含 384 MB 污染日志） | 同 3；384 MB 文件本身无保全价值（已证污染），但删除前建议保留一份头部样本 |

**执行组本轮在上述四处的动作：0。未删、未 clean、未导出。**
