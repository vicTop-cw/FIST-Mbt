# 交付报告 · 兑现 backlog 状态落差的预存红期望

- 日期：2026-10-22
- 分支：`slave/fix/staleness-expectation-cashout-r117`
- 提交：`HEAD`（代码：`scripts/run_guards.py`）+ 本报告所在提交（文档）
- 性质：副机自立项（预存红期望到期兑现，不改被检脚本、不改任务池内容）

## 结果摘要

`scripts/run_guards.py` 里 `check_backlog_status_staleness.py` 一格仍登记着 `expected(..., 1, "现读 9 条状态落差 > 上限 4 …")`。而该尺的现读已经是 **`扫描面=gitcode/main | 落差 0 条 / 上限 0 条`，rc=0**——R111 那一单（`slave/fix/backlog-status-reconcile-r111`，已在主线）把 9 条落差逐条核过转 `in_review/done`，并把尺内棘轮 `STALE_CEILING` 降到 0。于是这条「预存红登记」变成**过期期望**：电池在正确的工作树上报 `got=0 expect=1`，把一条已修好的面读成失败。

本单按本文件自订的律「被检内容修好 ⇒ 把期望改回 0，依据一起删」：
- `expected("check_backlog_status_staleness.py", 1, …)` → `case("check_backlog_status_staleness.py")`；
- 注释保留来历（R111 对账 + 棘轮降 0 + 现读读数），供下一位读者理解「这里为什么曾经有一条期望」。

收口后全量电池 **58 格 / 失败 0 / SKIP 5 / 缺执行面 0**，这是本会话内第一次拿到零失败读数。

## 证据

| 项 | 读数 |
|---|---|
| 尺裸跑 | `扫描面=gitcode/main \| backlog 23 份 \| 主线点名 15 个 \| 落差 0 条 / 上限 0 条`，rc=0 |
| 尺自证 | `--selftest` rc=0（`SELFTEST OK: 11 格（M×2 / P×2 / R×4 / V×3）`） |
| 电池自证 | `run_guards.py --selftest` rc=0（34 格，含「自动补格纯函数七面」「真源现状全绿」） |
| 全量电池（本分支 tip） | **58 格 / 失败 0 / SKIP 5 / 缺执行面 0**，电池 rc=0 |
| SKIP 5 | 缺 `temp/pt27.log`（2 格）/ `temp/chk47.json`（3 格），不计失败也不构成证据 |
| 期望未变的两格 | `check_ci_step_position.py`（rc=1/2）、`check_scripts_naming.py`（rc=1）本单未动，仍与现读一致 |
| 工作树 | 仅 `scripts/run_guards.py` 一处改动（4 增 3 删），无 `.mbti`/构建产物噪声 |

## 资源消耗

- 分支 1 条，提交 2 笔（代码 1 + 报告/日志 1）。
- 未运行 `moon` 任何子命令（无 `.mbt` 改动）；电池全量 1 发 + 两把尺自证各 1 发。

## 任务分配记录

- 无主机派单直接指向本格；线索来自 R116 全量电池读到的唯一失败格：`check_backlog_status_staleness.py got=0 expect=1`。
- 副机单 agent 完成：判断「期望过期 vs 面回退」→ 裸跑取证 → 改期望 → 电池复跑 → 交单。

## 遗留风险

1. **与 R116 gitlink 单的合并面（已实测）**：`git merge-tree --write-tree --name-only slave/fix/drop-orphan-gitlink-merge-marker HEAD` 实测 rc=1，唯一冲突是 `memory/2026-10-22.md`（两支都在当日日志尾部追加自己的段，属尾追加撞点）；`scripts/run_guards.py` 两处改动（第 179 行附近 / 第 228 行附近）**auto-merge 干净**。解冲突时两段并排保留、谁的都不覆（本仓既有工艺）。
2. **SKIP 5 仍是证据缺口**：`temp/pt27.log` / `temp/chk47.json` 不存在时，`check_badge` / `check_test_sync` / `check_deprecated_*` 五格不跑。本单不代造这些前置件（造了就是给判据喂假执行面）。
3. **尺的扫描面取 `gitcode/main`**：若主线后续新增点名 TASK-0NN 的提交而 yaml 不盖章，这条尺会重新红——这正是期望改回 0 后应有的现形机制，不是回归。

## 后续建议

- 任务池还有 5 条 `backlog`（TASK-010..016、TASK-020）与多条 `in_review`，其中 TASK-010..015 的目标分支在远端已不存在（需逐条取证后由 owner 裁决是否标 done/dropped）；本单不碰任务池状态，避免把「期望兑现」扩成「台账改判」。
- `expected()` 目前只比 rc 不比成因（R110 报告已点名这一结构性盲区）；本单的取证方式是**直接读被检面点名读数**（落差 0/上限 0），而不是只看 rc 相同。

## 超额内容

无。本单只做一格期望兑现。

## 来源

- `scripts/run_guards.py`（该格的原登记与 R108/R106 同类兑现先例）
- `scripts/check_backlog_status_staleness.py`（R102 立尺、R111 对账与棘轮降 0）
- 仓外日志：`$HOME/battery_r117.log`
