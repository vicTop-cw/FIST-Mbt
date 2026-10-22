# 2026-10-22 · 副机 R94 合序裁决材料 · 四支同伴 slave 分支 × r94 集成分支

> 这份不修任何代码，只交付**实测的冲突面与裁点**。金条四：合序与不可逆动作的执行权在指挥官/owner。

## 结果摘要

`slave/integrate/r93-on-cef1e9c-r94`（HEAD 940ba77，基点 cef1e9c）与 gitcode 上四支同伴分支逐对做
`git merge-tree --write-tree --name-only`：**四支全部相冲**，其中两处不是文本擦碰，而是**同一张 backlog 单的两份设计**。

| 同伴分支 | 顶部提交 | delta | 与我 HEAD 的冲突文件 | 性质 |
|---|---|---|---|---|
| `slave/feat/task-004-revert-diff-detector` | bdedc73 | 3 文件 +147/−16 | `memory/2026-10-21.md`、`scripts/fist-gate.py` | **TASK-004 双份实现** |
| `slave/fix/battery-readonly` | 2be0c89 | 3 文件 +105/−5 | `memory/2026-10-21.md`、`scripts/README.md`（`run_guards.py` 能 auto-merge） | **电池面反向设计** |
| `slave/fix/pre-commit-marker-gate` | a457aea | 7 文件 +225/−17 | `memory/2026-10-21.md`、`scripts/README.md` | 互补，低风险可叠 |
| `slave/fix/whisperer-selftest-and-scan-gitdir` = `fix/whisperer-selftest-and-scan-gitdir` | 4da1126（同一提交两条 ref） | 5 文件 +75/−8 | `memory/2026-10-22.md`（add/add）、`scripts/README.md`（`fist-gate.py` 能 auto-merge） | 与 TASK-004 那支的 gitdir 修重复 |

## 两个必须裁的点

**① TASK-004（REVERT-PATTERN 检测）做了两遍。**
副机侧在 40d303f（已含于 r94 分支）；同伴 bdedc73 是另一份，判据阈值与 yaml 落点写法不同，
且**附带修了一个真 bug**：`fist-gate.py --scan` 在 worktree 里崩溃（gitdir 不是目录而是文件）。
那个 gitdir 修 4da1126 也修了一遍 ⇒ 同一真 bug 两份补丁。
裁点：两份 REVERT-PATTERN 选一份为准（建议按自证格数与误报阈值比），gitdir 修单独留一份。

**② 守卫电池的两种反向设计。**
- 副机 TASK-007 线：自动发现整个 `scripts/` 宇宙 + `EXCLUDE_EXACT` 排除危险脚本 ⇒ 尺 88→84、缺执行面 0。
  好处：新脚本入仓不会漏格；代价：危险脚本一入仓就自动拿一格无参跑法（这正是本轮抓到的险）。
- 同伴 2be0c89 线：把电池改成**只读白名单** ⇒ 自述 96 格/45 红/会改工作树，收成 41 格/0 红/只读。
  好处：结构性杜绝「把改码工具当门禁跑」；代价：新尺不入白名单就永远没人跑，`缺执行面` 这类普查也读不到它。
- **共同点**：两种设计都会封掉 `whisperer.py` 的无参强推格 ⇒ 无论谁赢，R94 抓到的那条险都关闭。
  这条是本轮最重要的结论，写进 TASK-018 的裁决背景。

## 建议合序（只给方案，不执行）

1. 先合 r94 集成分支（已 rebase 到 cef1e9c，`merge-tree` 对 main 零冲突，收口守卫 rc 全 0）——
   它把 TASK-006/009/004/001 四单 + cef1e9c 两把红尺的修复一次性落齐，后续单都从这条线开。
2. 再叠 a457aea（只撞 README 与日志，文件面互补）。
3. 然后裁 ①/② 两组双份实现，各留一份：留者把另一份的**独有价值**（bdedc73 的 gitdir 修、
   2be0c89 的只读纪律）以单独提交补进来。
4. `4da1126` 与 `slave/fix/whisperer-selftest-and-scan-gitdir` 同提交双 ref，合一条、删另一条。
5. 每次合入都会撞 `memory/2026-10-2x.md`（add/add 或 content）。**工艺已固化**：日志类文件按并集保留双方正文、
   只丢标记行（副机在 `memory/2026-10-21.md` 上实做过一次，778→775 行），不要用 `checkout --ours/theirs` 整边丢内容。

## 资源消耗

- 5 次 `git merge-tree`（只读，不动工作树）+ 1 次 `git diff --stat` 逐支取证；1 次入池写 yaml；本会话预算内 2 轮。
- 无网络写操作、无合并执行。

## 任务分配记录

- 副机本轮交付：r94 集成分支（TASK-006/009/004/001 + cef1e9c 两红修复 + 新尺接线）＝已推分支已交 MR 链接。
- 入池：TASK-022（本材料对应的裁决单，P1，assignee=commander）。
- 同伴交付（非副机 lane）：bdedc73 / 2be0c89 / a457aea / 4da1126 —— 全部只登记不代改。

## 遗留风险

1. 若先合 2be0c89 再合 r94，`run_guards.py` 的 SPECIAL_CASES 结构差异会让 r94 的三条点名格
   （`check_bug_refs` 两格 + `fist-pr-automator --selftest`）落进白名单外的面 ⇒ 需要手工搬。
2. 同伴两份 TASK-004 的阈值不同（删≥50 且 删>增×1.5 是我的口径），留哪份就要把 README 与 yaml
   `status: failed` 落点对齐，否则 REVERT-PATTERN 单会出现「代码一份、文档另一份」。
3. `memory/2026-10-22.md` 是 add/add：双方各自新建了当天日志。合并时只丢标记行会静默吃掉一方整篇日志，
   必须逐段并（这一支的 add/add 与前面的 content 冲突不是同一种处理）。

## 后续建议

1. 把「电池里有危险无参格」做成判据而不是纪律：patrol 加一格普查
   正文含 `push --force` / `reset --hard` / `merge` 字样的脚本是否已在 `EXCLUDE_EXACT` 或被 SPECIAL_CASES 点名。
   `EXCLUDE_EXACT` 靠人想起加，下一支带不可逆动作的脚本入仓照样中招。
2. 一单一分支纪律已在 r94 上被现实压弯（四单压一条线）——若 owner 认可，把这条例写成
   「集成单允许叠，功能单必须单支」，否则下次普查还会把它当违例报。

## 超额内容

- 顺带取证了 `4da1126` 与 `slave/fix/whisperer-selftest-and-scan-gitdir` 是同提交双 ref（没人点过名）。
- 未做：不代裁、不代合、不动同伴分支；TASK-008 改名专项仍未开工（需新会话量）。

## 来源

- 冲突面：`git merge-tree --write-tree --name-only 940ba77 <ref>` 五组原始输出（rc=1 即冲突并逐文件点名）。
- delta 体量：`git diff --stat <merge-base>..<ref>` 逐支读数。
- 真源位置：`scripts/whisperer.py:32-54`（step0 强推）、`scripts/whisperer.py:204`（分流前调用）、
  `scripts/run_guards.py:73-97`（自动发现与排除表）、`scripts/fist-gate.py`（第 6 查改址，R93）。
- 关联单：`docs/tasks/backlog/TASK-018-*.yaml`（R94 追记）、`TASK-019-*.yaml`、`TASK-020-*.yaml`、
  `TASK-021-*.yaml`、`TASK-022-*.yaml`；日志 `memory/2026-10-22.md` R94 段。
