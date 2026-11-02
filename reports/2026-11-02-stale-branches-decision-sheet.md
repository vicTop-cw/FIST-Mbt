# 陈旧分支处置决策单（R124 · 2026-11-02）

- 状态：待 owner 裁决（A/B/C 三选一；删除类操作按金条四不先行）
- 触发：patrol 轮 28 诊断 + `scripts/check_branch_ancestry.py` 现读（run_guards.py:453 是 expected(1) 诊断档）
- 证据底稿：`temp/lane_branch/branches_evidence.tsv`（199 refs 全量树同一性扫描）+ `temp/lane_branch/summary.txt`

## 一、现状

- 远端 `gitcode/*` 105 支 + 本地 97 支 = **199 支分支 ref**（`main`/`master` 除外）。
- 判据现读：**75 支「失基」**（与现 main 无共同祖先，`git merge` 拒 unrelated histories）；其余「可合并」支多为领先 1~4 提交的旧通道支。
- 根因（已在 `run_guards.py:450` 与 `scripts/README.md:680` 登记）：**2026-10-22 filter-repo 主线重写**（`92d0edba → 788c5823`，613MB 事故收口）。重写只动了主线，分支 ref 全部指向重写前对象 ⇒ 基点成孤儿。这是**合并形态事实**不是缺陷；本项目当时的结论是「合并只能走 cherry-pick」。

## 二、实测证据（本轮）

1. **树同一性全量扫描**（199 refs，方法 = 分支 tip 树是否出现在 main 历史的提交树集合中）：
   `TIP-IS-MAIN = 0 / LANDED = 21 / UNLANDED = 178`。
   **注意这个 UNLANDED 是方法性低估的反面——不可当真**：重写后 main 的树哈希系统性变化，重写前的分支 tip 树几乎不可能精确命中 ⇒ 树同一性跨重写边界**失效**。
2. **提交主题抽查**（5 支，`git log main --grep <token>`）：0 命中。但反例存在——`gitcode/slave/feat/selftest-call-face-guard-r171` 的提交「立 check_selftest_call_face.py」在 main 历史无同主题提交，**而该脚本真实存在于 main**（R118 我还在改它的棘轮）⇒ 内容当年经 cherry-pick **换主题落地**，主题检索也**失效**。
3. 结论：**重写后的 git 机器无法机械证明「某支分支的内容已/未落 main」**（R66 实测代价 2 小时，已文档化）。能证明的只有当前事实面：电池 153 格全绿、账本 0 待修、脚本面逐把自证——**现况质量不依赖这些分支 ref**。

## 三、出路

### A) 归档束 + 删通道支（推荐）
1. `git bundle create temp/backup/channels-20261102.bundle --all`（单文件含全部 ref 可达对象）；
2. 把 bundle 作为**单个 blob** 提交到一支归档分支（如 `archive/channel-snapshot-20261102`）并推到 gitcode ⇒ 永久可 fetch 恢复（`git bundle unbundle`）；
3. 删 gitcode 上 75 支失基支 + 本地 97 支残留支（逐支列名，不走 `-A` 通配）；
4. 依「预存红被修好 ⇒ 期望改回 0」律把 `run_guards.py:453` 的 expected(1) 转回 `case(...)`，失基检测从此守「通道面为空」。
- 收益：失基诊断格退役、分支面清零、合并机器不再有陷阱面；**零信息丢失**（bundle 兜底）。
- 风险：bundle 丢失且归档分支被误删 ⇒ 恢复不可（双保险后风险趋零）；本地 `git branch -D` 丢 reflog 外的悬空提交（同被 bundle 覆盖）。

### B) 全部保留（现状不动）
- 收益：零操作风险。
- 代价：失基 expected(1) 永久占诊断档；184+ 支噪声；未来任何合并面工作都要先读 README:680 的 2 小时教训。

### C) 只删机械可证的 21 支（LANDED）
- 收益极小（剩 178 支仍是失基），不建议单做；可并入 A。

## 四、统帅建议

**A**。判据机械失效（证据二）+ 现况质量不依赖分支 ref（证据三）+ bundle 兜底消除恢复风险 ⇒ 保留这些 ref 的唯一价值是「万一有没 cherry-pick 过的活」，而 bundle 让这个万一零成本可逆。等你一句 A/B/C；选 A 我就执行（bundle → 归档分支 → 删支 → 判据转正 → 电池复跑）。
