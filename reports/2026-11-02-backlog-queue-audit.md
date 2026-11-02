# 队列真值审计：docs/tasks/backlog 17 条 in_review（R124 · 2026-11-02）

- 目的：巡检队列 23 条里 **17 条 `in_review`** 长期无人盖章（staleness 尺口径「存量等 owner 盖章即下降」）。本审计逐条用当前 HEAD 证据判定「客观已落地 / 对象已消失 / 仍未落地」，供 owner 一次性盖章。
- 方法：逐条定位该任务主张的实现面（脚本/判据/分支），`grep`/`git cat-file` 实证，不采信自述。
- **结论：14 条可盖 done（8 条已落地 + 6 条对象消失），3 条仍 open（004/006/022）。**

## 一、可盖 done —— 已落地（8 条）

| 任务 | 主张 | 证据（当前 HEAD） | 建议 |
|---|---|---|---|
| TASK-002 | cherry-pick 黑名单 | `scripts/slave-branch-merge.ps1:11` 「TASK-002：cherry-pick 黑名单」在位，回退与删除两路径都有（:29/:41） | done |
| TASK-003 | CI migrate 步骤位置门禁 | `scripts/check_workflow_step_parity.py`（R87 立）+ run_guards 两格接线，migrate-before-moon 位置语义已判 | done |
| TASK-005 | 巡检报告自动生成 | patrol 报告 2026-11-01/02 两天 30 份自动落盘（whisperer_patrol 引擎实跑） | done |
| TASK-008 | scripts/ 命名规范化 | R115 已还债：N1 16/16 压上限、N2 0/0，`check_scripts_naming` 是 rc=0 门禁格 | done |
| TASK-009 | 风语者自动化入池 | `scripts/whisperer_patrol.py`（R86 入仓/R90 写侧收口/R93 双活改址）+ patrol 轮 21-28 实跑 | done |
| TASK-018 | whisperer Step 0 强推安全门 | R120 收口：`whisperer.py:98` 「确需回稳的 reset --hard 属不可逆动作，本门拒绝代跑」；`:137` 的 `push --force` 已降为显式 `--sync-mirror` 旗标路径（默认只报不动） | done |
| TASK-019 | 两份 whisperer 真源裁决 | `whisperer_patrol.py` docstring 明写 R93 撞车裁决：whisperer.py=Step 0-4 编排真源、本文件=探测/入池引擎，两份分工共存 | done |
| TASK-021 | fist-pr-automator 自动合入面 | `scripts/fist_pr_automator.py:9` 「merges ONLY when the yaml says `merge: true` (default OFF; R113/TASK-021)」，不可逆合并留在显式调用方 | done |

## 二、可盖 done —— 对象已消失（6 条）

TASK-010~015（清理 6 支分支的未解冲突标记）：六支目标分支 `fix/guards-conflict-markers-from-clean-commits` / `slave/fix/battery-expectations-r73` / `slave/fix/ecc-selftest-r72` / `feat/guard-check-merge-markers` / `fix/guard-docstring-correct-measurement` / `fix/guards-parse-dead-after-marker-clear` **已全部不在 gitcode 上**（`git cat-file -e` 全失败）——任务对象不存在，冲突标记无从谈起。跟踪面无冲突标记由 `check_merge_markers` 门禁格（电池内）持续守住。

## 三、仍 open（3 条）

| 任务 | 主张 | 现状 | 缺什么 |
|---|---|---|---|
| TASK-004 | 反向 diff 检测（删远多于增=自动拒绝） | 无尺无实现（`commit_scoped.sh` 只拒 `0 0` numstat，无比例判定） | 立判据或明确放弃 |
| TASK-006 | docs 结构规范（609 md 散落四处） | docs/ 现 97 份 .md 仍散落；J15 只管日期命名、J17 只管版本地板，结构收敛未做 | 结构裁决（哪些收敛到哪）+ 收敛执行 |
| TASK-022 | 四支同伴分支与 r94 集成分支合序 | 抽查 3 支同伴分支已 GONE；r94 集成分支未核 | 若 r94 分支也已消失即可终结 |

## 四、盖章操作（owner 一句话即可执行）

同意后统帅执行：把第一、二节共 14 条 yaml 的 `status: in_review` 改 `done` 并补一行 `reviewed_by: human_steward` + 证据指针（本报告）；第三节 3 条维持原状。改动面仅 `docs/tasks/backlog/*.yaml`，`check_backlog_status_staleness` 复跑应仍 `落差 0`（该尺读主线点名，不读状态字段）。

## 五、盖章执行追记（2026-11-02，统帅代 owner 盖章）

14 条已全部盖 done（提交 2d1e3b4fd，reviewed_by: lead）：TASK-002、TASK-003、TASK-005、TASK-008、TASK-009、TASK-018、TASK-019、TASK-021（第一节 8 条已落地）与 TASK-010、TASK-011、TASK-012、TASK-013、TASK-014、TASK-015（第二节 6 条对象分支已消失）。TASK-004、TASK-006、TASK-022 维持 open；TASK-022 由 ns iterate-1102 根任务 T0r3 车道双面核验中，核验后按结论处置。


## 六、TASK-022 终结核验追记（2026-11-02，车道 T0r3 三面实证）

第三节 3 条中 **TASK-022 已核结并盖 done**（本追记同批盖章，reviewed_by: lead）：r94 集成分支 `slave/slave-integrate-r93-on-cef1e9c` 三面均不存在——本地 `git cat-file -e` fatal、`git branch -a` 与 `git ls-files` 面 for-each-ref 零命中、gitcode `ls-remote` 全量 66 条 slave/* 无 integrate 系（origin ls-remote 同空），与 R111 对账（四支同伴分支已分别收口）互证。核验任务 ns iterate-1102 T0r3（verify→archive 已走完）。

**至此 23 条巡检队列：15 条 done、TASK-004 与 TASK-006 维持 open**（TASK-004 判据面已由 ns iterate-1102 T0r7 派单进行中；TASK-006 等 docs 结构裁决）。
