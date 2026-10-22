# R112 · 电池读数 ↔ README 登记对表门（TASK-017）

- 日期：2026-10-22
- 分支：`slave/gate/battery-count-doc-r112`（基线 `gitcode/master` 0338a6b8）
- 交付方式：推分支 + GitCode MR 链接（副机不代开 MR）
- MR：`https://gitcode.com/VictorTop/Fist-Mbt/merge_requests/new?source_branch=slave/gate/battery-count-doc-r112`

## 结果摘要

1. 新增 `scripts/check_battery_count_doc.py`：把 `run_guards.py --list` 的 7 个规模读数
   （尺 / CI 面 / 电池面 / 缺执行面 / 门禁尺 / 豁免 / 未归类）与 `scripts/README.md` 的
   机器可读锚点 `BATTERY-REGISTRATION` 逐键对表；**两向都红**（现读少于登记 = 欠格；
   现读多于登记 = 登记落后），锚点缺失 / 缺键 / 非整数 / 多抄本打架 / `--list` 读不出数 ⇒ 2 号档自拒。
2. `scripts/README.md`：`run_guards.py` 条目增加 `BATTERY-REGISTRATION：rulers=83 ci=40 battery=45
   missing=0 gate=55 exempt=26 unclassified=4`；并登记新守卫条目（含 15 格自证）。
3. 执行面两处：`ci.yml` 在 Migrate 之前增加 `Battery-count registration guard` 步
   （`--selftest` + 全量）；`run_guards.py` 自动补格把它纳入电池。
4. `TASK-017` 转 `in_review`（未转 done：本提交尚未进主线，转 done 会触发 R2 UNPROVEN-DONE）。

## 证据（逐条实跑）

| 命令 | 读数 |
|---|---|
| 基线（0338a6b8 干净树）`run_guards --list` | 尺 82 / CI 39 / 电池 44 / 缺 0；门禁 54 / 豁免 26 / 未归类 4 |
| 本单后 `run_guards --list` | 尺 83 / CI 40 / 电池 45 / 缺 0；门禁 55 / 豁免 26 / 未归类 4 |
| `check_battery_count_doc.py` | rc=0，7 键逐键一致 |
| `check_battery_count_doc.py --selftest` | rc=0，15 格（G×3 / M×11 / R），含 7 键逐键漂移必红 + 4 类自拒 + 真源现状绿 |
| `check_selftest_inventory_doc.py` | rc=0，判定族 25 条逐一对表通过（本尺 3 族 15 格） |
| `run_guards --selftest` | rc=0，34 格 |
| `check_scripts_index.py` / `check_doc_surface.py` | rc=0 / rc=0 |
| `check_backlog_status_staleness.py` | rc=1（主线存量 9 条落差，R111 分支修好但未合入，本单不代修） |

- 人工变异核验（真跑后已还原，`git status` 干净）：README 锚点 `rulers=83`→`82` ⇒ 全量 rc=1
  （「登记落后」逐键点名）；整行删掉 ⇒ rc=2（「条目里没有 BATTERY-REGISTRATION 锚点」）。

## 资源消耗

- 单个副机执行会话，无子代理；本单不改 `.mbt`，未跑 `moon` 工具链（CI 侧仍会跑）。
- 全量电池（推后跑，`FIST_DB_PATH` 改道）：rc=0 / 58 格 / 失败 0 / SKIP 5 / 缺执行面 0。

## 任务分配记录

- 主机任务 T0 / T0r2 / T0r3 按既有台账已收口；本单为自主拉主线找到的 TASK-017（P3）。
- 全程避开并发 agent 分支 `slave/fix/supervisor-bool-flags-schema-r110` 及其文件面。

## 遗留风险

1. `BATTERY-REGISTRATION` 仍是手抄数：新增/删除尺、加格子、加 CI 引用都会让电池红，直到同批改数
   ——这是设计意图（数字变了不改进期望就现形），但对不熟悉的人是一次额外红灯。
2. 全量电池的总格数（`=== 电池 N 格 ===`）未纳入对表：取该数必须真跑全量，代价高于本门收益。
3. 主线仍带 R111 之前的 9 条任务池落差红；R111 分支合入后自然转绿（本单已按预存红登记，不代修）。

## 后续建议

- 给 `run_guards.py` 增 `--json` 读数出口，后续守卫可直接消费结构化读数，少一层正则。
- TASK-020（两把 BUG 引用判据同族并存）仍需 commander 裁口径；属裁决面，不在本单代裁。

## 超额内容

- 抄本一致性两格：README 未来若再被复制成多份条目，多份锚点数值一致不误红、打架自拒。

## 来源

- `docs/tasks/backlog/TASK-017-882468bb41.yaml`（whisperer `probe_guards()` 入池）
- `scripts/README.md` R106 登记读数（宇宙 81 份 = 尺 79 把）与 2026-10-22 实测对照
- `scripts/run_guards.py --list` 基线/本单两次读数；`scripts/check_battery_count_doc.py --selftest`
