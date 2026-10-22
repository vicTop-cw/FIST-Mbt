# R115 交付报告：check_bug_refs 分面 --strict（TASK-020 裁决）

- 日期：2026-10-22
- 分支：`slave/fix/bug-refs-single-remit-r115`
- 提交：`21a883a9`
- 基线：`gitcode/master 803293c2`（推送前复查未前进）
- MR：https://gitcode.com/VictorTop/Fist-Mbt/merge_requests/new?source_branch=slave/fix/bug-refs-single-remit-r115

## 结果摘要

TASK-020 裁决落地：**两把 bug 引用尺并存、各钉一面**，不合并。

1. `check_bug_refs.py` 新增三面分类（comment / string / narrative）：`--strict` 只判**注释面 ORPHAN**；
   测试文件里注释面编号若在同文件字面量面出现，按 S1b 口径降档为夹具说明；CLOSED 仍仅信息。
2. 修好声明了却没生效的 `EXCL`：`reports/` 等排除面此前仍被扫描（169 条噪音的来源）。
3. 棘轮 `STRICT_ORPHAN_CEILING=3`（立单现读 3 条，全在 `commit_bug335_lock.ps1` 注释），只许降不许升；
   `--selftest` 含真语料校准格，读数漂移必须同批改常数。
4. 空扫描自拒：`git ls-files` 枚举失败/扫描面为空 ⇒ rc=2，绝不把「没测到」报成绿。
5. README 四处口径统一（含把一份重复条目收成指针）；TASK-020 台账转 `in_review` 并写入裁决小记。
6. `--selftest` 扩到 24 格真断言：三档计数、三面分类、夹具降档、排除面、退出码/棘轮、真语料校准。

判定分工：`check_bug_reference_integrity.py` 继续管 `.mbt` 注释面悬空（CI，J1=0）；
`check_bug_refs.py` 管全仓普查与跨文件类型的面分类（登记面，`--strict` 可选门）。

## 证据

| 项 | 命令 | 读数 |
|---|---|---|
| 自检 | `python scripts/check_bug_refs.py --selftest` | rc=0，24 格全过 |
| 默认普查 | `python scripts/check_bug_refs.py` | rc=0；7103 引用 / OK 667 / ORPHAN 206（comment 3、string 67、narrative 136）/ CLOSED 6230 |
| 严格门 | `python scripts/check_bug_refs.py --strict` | rc=0（判定面 3 == 棘轮 3） |
| 台账完整性 | `check_backlog_yaml_integrity.py` | rc=0 PASS |
| 状态滞后 | `check_backlog_status_staleness.py` | rc=0 落差 0（本单转 in_review 未制造新落差） |
| 索引/文档/编码 | `check_scripts_index` / `check_doc_surface` / `check_py_stdout_encoding --all` | 全 rc=0 |
| 全量电池（交付 tip） | `python scripts/run_guards.py` | 58 格 / 失败 1（预存红，见下）/ SKIP 5 / 缺执行面 0 |

预存红（不在本单修）：`check_backlog_status_staleness.py got=0 expect=1`——main 的电池期望仍写着
R111 前的旧读数；R114 分支 `0017069a` 已按「被检内容修好 ⇒ 期望改回 0」修过同一行，本单不重复改。
两单合并后该格自然转绿。

## 资源消耗

- 目标时间约 7.5 分钟（08:17–08:25，含两轮全量电池）。
- 改动 3 个文件（+241/−63）：`scripts/check_bug_refs.py`、`scripts/README.md`、TASK-020 YAML。
- 1 个交付提交 + 1 个报告/日志提交；无新增依赖、无网络调用。

## 任务分配记录

- 单源：主机任务池 TASK-020（P2，BUG-373 同族判据口径/合尺裁决）。
- 执行：指挥直接完成（脚本级改动 + 短验证闭环），未派子代理。
- 终审：自检 24 格 + 定向门禁 7 项 + 全量电池两轮；交付 tip 与远端 tip 一致（`21a883a9`）。

## 遗留风险

1. 棘轮 3 的三条是 `commit_bug335_lock.ps1` 注释里的两个编号（账本无抬头，README 已点名
   「脚本自述编号未入账，别当账本事实」）。要降到 0 需先裁决：补账或改注释，再同批下调常数。
2. narrative 136 / string 67 仍只报告：叙述面里可能有旧编号，本裁决明确不判红；
   若要清理应另立任务逐条核，不应把 `--strict` 扩成叙述面门。
3. `--strict-closed` 不能接 CI：现读 CLOSED 6230 处，接了就是永久红——裁决明确保持信息面。
4. `check_bug_refs.py` 仍未进电池/CI（只有登记面），本单未接线以免触发电池格数与文档计数联动；
   `--selftest` 可随时手动跑。

## 后续建议

1. 合并顺序：本单未动电池；R114 的 staleness 期望修复合入后，跑一次全量电池应到 58/0。
2. 若要把本尺纳入 CI，建议只接 `--selftest`（不接 `--strict` 全仓门），并把格数联动一并更新。
3. 清理三条棘轮引用的前置动作：先在账本核实这两个编号是否对应已有条目（补账走 verbatim 追加），
   确认是错号则改注释；任一路径都需要同批把 `STRICT_ORPHAN_CEILING` 下调到 0。

## 超额内容

- README 第 989–993 行的重复条目收成指针，消除「同一工具两份现读并存」的旧形状。
- `check_bug_refs.py` 自带校准格：真语料判定面 != 棘轮上限时 selftest 直接红，防读数静默漂移。

## 来源

- `docs/tasks/backlog/TASK-020-bug-373-check-bug-refs-vs-check-bug-refe.yaml`
- `scripts/check_bug_refs.py`（R115 改动主体）
- `scripts/check_bug_reference_integrity.py`（分工对端，J1 棘轮）
- `scripts/README.md`（四处口径）
- 电池日志：`/tmp/r115_battery2.log`（仓外临时面，不随提交分发）
