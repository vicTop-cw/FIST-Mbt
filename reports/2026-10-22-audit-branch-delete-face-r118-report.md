# 交付报告 · 分支删除硬门补执行面（R118）

- 日期：2026-10-22
- 分支：`slave/fix/audit-branch-delete-face-r118`
- 提交：`HEAD`（代码：`scripts/run_guards.py` + `scripts/README.md`）+ 本报告所在提交（文档/日志）
- 性质：副机自立项（只接线与登记同步，不改被检脚本、不改任务池内容）

## 结果摘要

主线 `b5136899` 上全量电池现读红：`run_guards.py --list` rc=1，缺面清单点名 `audit_branch_delete.py`；它连带 `check_battery_count_doc.py` rc=2（`--list` 红时拒绝出结论）与 `check_selftest_inventory_doc.py` rc=2 一起红。**58 格 / 失败 2 / SKIP 5 / 缺执行面 1**。

成因不是脚本坏了，是**落仓漏接线**：`audit_branch_delete.py`（R50，通道分支删除的硬门）被 `slave-branch-merge.ps1` 的 5 处删除循环调用，却从未进过任何判定面（CI / 电池 / 登记三面皆无）⇒ G1 把它算「缺执行面」，下游两份记账尺随之红。

本单三处接线，均不改被检脚本：

1. 电池加 `case("audit_branch_delete.py", "--selftest")` —— 只有 `--selftest` 是只读面（temp 仓自建自清）；裸跑要分支参数且会写 `<git-dir>/fist/delete-audit.jsonl`，不进电池。
2. `GATE_PREFIXES` 补 `audit_branch_delete` —— 分类记账把它算门禁尺，否则会在「非判据」清单里多出一份假登记。
3. `--list` 的「非判据」清单加谓词：**已进电池的脚本不得再出现在「不进电池」清单**——修前同一支尺会被「门禁尺 56」与「非判据」两份互相矛盾的判据同时点名。

README 同步：机器可读锚点 `rulers=83 ci=40 battery=45 missing=0 gate=55 exempt=26 unclassified=4` → `rulers=84 ci=40 battery=46 missing=0 gate=56 exempt=26 unclassified=4`；`audit_branch_delete.py` 条目补 R118 接线来历。

收口：全量电池 **59 格 / 失败 0 / SKIP 5 / 缺执行面 0**，rc=0。

## 证据

| 项 | 读数 |
|---|---|
| 修前 `--list` | rc=1，缺面清单：`audit_branch_delete.py` |
| 修前全量电池 | 58 格 / 失败 2 / SKIP 5 / 缺执行面 1（`check_battery_count_doc` rc=2、`check_selftest_inventory_doc` rc=2） |
| 修后 `--list` | rc=0，`rulers=84 ci=40 battery=46 missing=0 gate=56 exempt=26 unclassified=4` |
| `check_battery_count_doc.py` | rc=0 `PASS 电池读数与 README 登记逐键一致` |
| `check_battery_count_doc.py --selftest` | rc=0（15 格） |
| `check_selftest_inventory_doc.py` | rc=0 `INVENTORY_SYNC=clean 判定族 25 条逐一对表通过` |
| `run_guards.py --selftest` | rc=0（34 格；现状读数 84 把尺 / CI 面 40 / 电池面 46 / 缺面 0 / 常驻豁免 2） |
| `audit_branch_delete.py --selftest` | rc=0（`SELFTEST OK（7 格：已合可删/未合拒删/缺失不可判 + 审计两行与字段齐备）`） |
| 全量电池（本分支 tip） | **59 格 / 失败 0 / SKIP 5 / 缺执行面 0**，rc=0（`$HOME/battery_r118.log`） |
| 预存红未动 | `check_scripts_naming.py` rc=1（判定面 2 > 棘轮 2 条上限）、`fist-gate.py` rc=2（store_path 段绿、其余段预存红）：电池里照原期望登记，本单不碰 |
| 工作树 | 仅 `scripts/run_guards.py`（15 增 2 删）与 `scripts/README.md`（锚点 + 条目），无 `.mbt`/构建产物 |

SKIP 5 与 R117 同形（缺 `temp/pt27.log` 2 格 / `temp/chk47.json` 3 格），不构成「这格过了」的证据。

## 资源消耗

- 分支 1 条，提交 2 笔（代码 1 + 报告/日志 1）。
- 未运行 `moon` 任何子命令（无 `.mbt` 改动）；全量电池 2 发（修前/修后）+ 若干尺子单发。

## 任务分配记录

- 无主机派单直接点名此格；线索来自主线全量电池的唯一成因面：缺执行面 1 连带 2 格红。
- 副机单 agent 完成：复现红面 → 判断「脚本无执行面」而非「脚本坏了」→ 三处接线 → 电池复跑 → 交单。
- 去重：开工前 `ls-remote` 核过并行支 `slave/fix/bug-refs-single-remit-r115` 已完整交付 TASK-020 同题（`scripts/check_bug_refs.py`），本单主动避开该文件。

## 遗留风险

1. **两套谓词仍可能再打架**：本单只让「非判据」清单不再列出已进电池者；`non_gate_reason()` 与「是否门禁」仍是两套判断，下一个落在门禁前缀族外、却手写进电池的脚本，展示面仍会自相矛盾。彻底收口应让 `nong` 只列「无执行面且非门禁」的脚本，留给后续单。
2. **裸跑面仍无判据**：电池只跑 `--selftest`；`slave-branch-merge.ps1` 的 5 处删除循环调用它时若参数拼错，判据面看不见（ps1 不在本仓 CI 面）。本单不造分支去测裸跑（造了就是给判据喂假执行面）。
3. **登记面是最热冲突点**：`scripts/run_guards.py` / `scripts/README.md` 与在飞各单同改概率高。解冲突时两段并排保留，锚点数字必须按合并后 `--list` 现读重写，不许手算。

## 后续建议

- TASK-010..015（backlog，P1，目标分支在 GitCode 已不存在，本地 tip 已合入主线）是下一类可机械取证的面：逐条 `ls-remote` + `merge-base` 取证后，由 owner 裁决转 `in_review`/`dropped`；本单不碰任务池，避免把「接线」扩成「台账改判」。
- 若要「非判据」清单变成判据而非提示，可在 `--selftest` 加一格：合成「进电池但非门禁前缀」的脚本，断言它不出现在 nong 清单。

## 超额内容

无。本单只做接线与两处登记同步。

## 来源

- `scripts/run_guards.py`（SPECIAL_CASES / GATE_PREFIXES / `--list` 非判据清单）
- `scripts/check_battery_count_doc.py`（锚点逐键对表）
- `scripts/check_selftest_inventory_doc.py`（判据族对表）
- `scripts/audit_branch_delete.py`（R50 硬门；本单未改）
- 仓外日志：`$HOME/battery_r118.log`
