# 2026-10-22 · 副机 R94 报告 · 落到最新主线 cef1e9c 并接线主机新入仓的两把尺

## 结果摘要

分支 `slave/integrate/r93-on-cef1e9c-r94`（基点 cef1e9c，merge r93 交付 d03027d）。本轮交付三件：

1. **把 r85/r93 的四单交付（TASK-006/009/004/001）重新落在最新主线上**。merge-tree 预先实测零冲突，
   `git merge --no-ff` 真跑 rc=0；r93 那条 MR 分支自此可作废，其全部提交已含于本分支。
2. **修掉 cef1e9c 自身的两把红尺**：`check_scripts_index.py` rc=1（4 支脚本未登记）与
   `check_doc_surface.py` rc=1（USAGE.md 版本落后 moon.mod）。前者补 `check_bug_refs.py`、
   `fist-pr-automator.py` 两条 README 登记（`fist-gate.py`/`whisperer.py` 由 r93 侧已登），后者在 r93 侧已同步。
3. **封掉一条实测到的强推面**（本轮最重的发现，见下）+ 给两把新尺点名电池格，
   并入池 TASK-020/021 两张裁决单。

核心发现：**在 cef1e9c 上跑守卫电池 `python scripts/run_guards.py`，等于让定时脚本对共享线 force push**。
main 的 `EXCLUDE_EXACT` 只有 `{__init__.py, run_guards.py}`，TASK-007 的自动发现因此给 `whisperer.py` 补了
一个**无参**格；而 `whisperer.py:main()` 在分流 `--scan-only`/`--auto-merge` 之前先调 `step0_head_safety()`：
`git checkout master` → 判据 `gc == og and gc != local` 成立即 `git reset --hard <gitcode/main>` +
`git push --force HEAD:main HEAD:master` 打两个远端。副机侧的封堵是排除 + 点名（不改判据本体），
裁决面挂 TASK-018（已按实测升级证据）。

## 资源消耗

- 会话轮次：本目标 40 轮预算内的 3 轮（fetch/取证 → 分支与合并 → 接线/登记/入池/读数/提交）。
- 命令：`git fetch`、`git merge-tree`、`git merge`、1 次隔离 worktree（`temp/wt-main`，只读 + `--list`，未跑电池本体）、
  8 次守卫调用直取 rc；1 次 python 内联调 `whisperer_patrol.write_yaml` 入池两单。
- 网络：只 `git fetch gitcode`；无 push 之外的写操作，无第三方 API 调用。
- 磁盘 delta：6 个文件（scripts/run_guards.py、scripts/README.md、TASK-018 证据追记、
  新入池 TASK-020/021、memory/2026-10-22.md + 本报告）；**无 `.mbt` 改动** ⇒ `moon fmt` / `moon info` 门不参与本轮。

## 任务分配记录

| 单 | 归属 | 本轮动作 |
|---|---|---|
| TASK-006/009/004/001 | 副机（已交） | 重放基到 cef1e9c，交付面不变 |
| TASK-007（run_guards 宇宙） | 副机（已交） | 追加：新入仓脚本的格位安排 + 危险格排除 |
| TASK-018（whisperer Step 0 强推门） | commander | 追记 R94 实测：电池自动补无参格，`--list` 读数 88 把 |
| TASK-019（whisperer 双实现） | commander | 状态不变，双活解已在本分支 |
| **TASK-020**（BUG-373 双实现：`check_bug_refs` vs `check_bug_reference_integrity`） | commander | 本轮入池 P2 |
| **TASK-021**（`fist-pr-automator.py` 默认 merge 与金条四冲突） | commander | 本轮入池 P1 |
| TASK-008（脚本改名专项） | 副机 | 未开工（需新会话预算） |

## 遗留风险

1. **TASK-021 那支脚本仍带不可逆 merge 的三参跑法**——我移除了它的自动无参格，但任何 agent 照 README
   手动跑 `<pr.yaml> github` 就会 push + 开 PR + squash merge。金条四要求这条路的执行权留人。
2. `check_bug_refs.py` 默认档只报告（rc=0），命中量大到「…还有 7177 处」，绝大多数是 CLOSED。
   **若有人把 `--strict` 直接接进 CI，那是当场永久红**；README 已写明这一条，但红不红取决于后来人是否读文档。
3. 本机预存红未修（按裁决不代修）：`fist-gate.py --selftest` rc=2，G4 fmt/build 两格红，根因是 moonc
   长路径 `\\?\` ICE（工具链面，非代码面）。CI 侧以 `moon fmt --check` / native 门自证。
4. `whisperer_patrol.py --apply` 的 ff-only 面仍未实测——属未验证面，不得据自述宣称可用。
5. 主机新分支 `fix/whisperer-selftest-and-scan-gitdir`（4da1126，基于 9e0064a）动了
   `scripts/whisperer.py`(+28) 与 `scripts/fist-gate.py`(14)，与本分支的 fist-gate 第 6 查改址面重叠；
   合并序由 owner 裁（它那格修的是 worktree 里 `--scan` 的 gitdir 恒红，与本单不同因）。

## 后续建议

1. 优先裁 TASK-018/021：两支脚本都带不可逆动作，一个已被电池接上、一个已被 README 教给人跑。
   最小修向：Step 0 只报警、`--recover` 显式动；pr-automator 默认 `merge: false` + `--dry-run`。
2. TASK-020 二选一：合尺（CLOSED 降为报告项）或并存（README 已写分工，悬空硬门留在已接 CI 的那把）。
3. 把 `run_guards --list` 的「电池面含危险脚本」做成判据而不只是注释——
   `EXCLUDE_EXACT` 是白名单纪律，新脚本入仓不会有人想起加它；建议 patrol 加一格普查「带 push/reset/merge/force 字样的脚本是否在排除表或已点名」。
4. 收掉旧 MR 分支 `slave/docs/task006-docs-structure-r85` 与 `slave/integrate/r85-on-v0.3.10-r93`（内容全在本分支）。

## 超额内容

- 未在本次接线任务范围内、但顺手取证并落档的：TASK-018 证据升级（`--list` 读数 + 无参格因果链）、
  `check_py_stdout_encoding` 的 E2 预告点名 `fist-pr-automator.py`（正文纯 ASCII 今天不红，下一句中文即踩 E1）
  ——只在 README 里登记，未改那支脚本本体。
- 未做：TASK-008 改名专项、`--apply` 实测、fist-gate 与主机 4da1126 的合尺。

## 来源

- 取证命令与读数：本报告「结果摘要」「遗留风险」段所有数字来自本轮 `temp/wt-main`（detached at cef1e9c）
  与本分支工作树的实测 rc/输出，逐条可回溯；日志见 `memory/2026-10-22.md` R94 段。
- 真源代码位置：`scripts/whisperer.py:32-54`（step0_head_safety，强推在 51-52）、`scripts/whisperer.py:204`
  （main 在分流旗之前调用它）、`scripts/fist-pr-automator.py:171`（pipeline）/`:185`（`git push -u`）/`:155`（merge）、
  `scripts/run_guards.py:73-97`（discover_scripts，EXCLUDE_EXACT 在 :85）。
- 入池单：`docs/tasks/backlog/TASK-020-bug-373-check-bug-refs-vs-check-bug-refe.yaml`、
  `docs/tasks/backlog/TASK-021-fist-pr-automator-py-merge.yaml`（均带 `dedupe_key` 机器锚）。
- 前序：`reports/2026-10-22-slave-task009-whisperer-write-side-r90-report.md`（R90 写侧 + R93 双活解）。
