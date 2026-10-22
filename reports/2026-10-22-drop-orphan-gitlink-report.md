# 交付报告 · 删除误入库的 worktree gitlink，Merge-marker 门归绿

- 日期：2026-10-22
- 分支：`slave/fix/drop-orphan-gitlink-merge-marker`
- 提交：`27900cb4`（代码） + 本报告所在提交（文档）
- 性质：副机自立项（既有预存红的收口，配方由 R106 前任 agent 写在 `scripts/run_guards.py` 注释里）

## 结果摘要

主线跟踪面里有一枚误入库的 **gitlink**（mode 160000）：`.agents/worktrees/fix/display-rank-boundary` → `fc46c25259795cfe46248c727167d2d59e35d965`，由 `4a7bf82a` 带入，仓库内无 `.gitmodules`。`scripts/blackbox/check_merge_markers.py` 的 L1 会读取**每一个 git 跟踪文件**的正文，读到 gitlink 时不可读 ⇒ 实扫 rc=1，Merge-marker 门红。R106 曾把它登记为预存红并写明收口配方（`git rm --cached` + `.gitignore` + 期望改回 0）。

本单按配方收口三步：
1. `git rm --cached .agents/worktrees/fix/display-rank-boundary`（只动索引，磁盘目录未删）；
2. `.gitignore` 追加 `.agents/worktrees/`；
3. `scripts/run_guards.py` 中该格由 `expected("blackbox/check_merge_markers.py", 1, "预存红：…")` 改回 `case("blackbox/check_merge_markers.py")`，并保留一段说明「为什么曾有这条期望」。

收口后：live 实扫 rc=0（`扫描 1327 个 git 跟踪文件`），`--selftest` rc=0（6 格），全量电池仅余 **1 条与本单无关的预存红**。

## 证据

| 项 | 读数 |
|---|---|
| 缺陷来源 | gitlink `fc46c252…` 由 `4a7bf82a` 带入；`.gitmodules` 不存在；`git ls-files -s` 中 mode 160000 |
| 收口前 | `check_merge_markers.py` live rc=1（L1 读 gitlink 失败） |
| 收口后 | live rc=0，`扫描 1327 个 git 跟踪文件`；跟踪面 gitlink 计数 0 |
| 判据自证 | `python scripts/blackbox/check_merge_markers.py --selftest` rc=0（6 格） |
| 电池自证 | `python scripts/run_guards.py --selftest` rc=0（34 格） |
| 全量电池（推后 tip `27900cb4`） | **58 格 / 失败 1 / SKIP 5 / 缺执行面 0** |
| 唯一失败 | `check_backlog_status_staleness.py got=0 expect=1` —— 现读 9 条 backlog 状态落差 > 上限 4，属**内容债**，分支基点即存在，非本单引入；R114 支 `0017069a` 已修但未合主线 |
| SKIP 5 | 缺 `temp/pt27.log` / `temp/chk47.json` 等执行面产物 |
| 远端对表 | `git ls-remote --heads gitcode slave/fix/drop-orphan-gitlink-merge-marker` == 本地 HEAD |

## 资源消耗

- 分支 1 条，提交 2 笔（代码 1 + 报告/日志 1）。
- 未运行 `moon build/check/test`：本单只动索引、`.gitignore`、电池期望表与文档，无 `.mbt` 改动。
- 电池全量 1 发（推后跑），单文件尺自证 2 发。

## 任务分配记录

- 无主机派单直接指向本缺陷；线索来自 R106 在 `scripts/run_guards.py` 留下的预存红登记（内含收口配方）。
- 全流程由副机单 agent 完成：定位 → 收口 → 自证 → 电池复跑 → 交单。

## 遗留风险

1. **预存红仍在**：`check_backlog_status_staleness.py got=0 expect=1`（9 条状态落差 > 上限 4）。按交付口径不代修、不代登期望，此处点名 rc 与成因；权威修法在主线的 R114 支。
2. **期望与修复必须同笔**：只删 gitlink 不改期望，会让电池反向红；只改期望不删 gitlink 则是洗红。本单两件同笔。
3. **合并顺序**：若与其它改 `scripts/run_guards.py` 同段的支并排，保留本单的 `case(...)` 与 R106 说明注释（两者是同一格的两半）。
4. 磁盘目录 `.agents/worktrees/fix/display-rank-boundary`（空）仍在工作树，已被新 ignore 覆盖；不影响判据。

## 后续建议

- 给 `check_merge_markers.py`（或脚本索引尺）补一格常驻判据：跟踪面出现 mode 160000 且无 `.gitmodules` 时**指名报红**——把这次的人工发现固化成门（本单不扩面，留给下一单）。
- `docs/tasks/backlog` 的 TASK-010..015 目标分支在 gitcode 与 origin 均不存在（实测），属死任务，建议下一单做台账清理（标 `done` 并附证据，或按 owner 裁决处理）。

## 超额内容

无。本单只做收口，不扩面、不加新判据。

## 来源

- `scripts/run_guards.py`（R106 预存红登记与收口配方）
- `scripts/blackbox/check_merge_markers.py`（L1 扫描实现与 `--selftest`）
- 本单提交 `27900cb4`、全量电池日志（仓外 `$HOME/battery_*.log`）
