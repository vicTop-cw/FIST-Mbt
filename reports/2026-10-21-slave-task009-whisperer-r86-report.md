# 2026-10-21 · TASK-009 风语者巡检器 whisperer.py 报告（R86）

## 1. 结果摘要
- **交付**：`scripts/whisperer.py`（TASK-009 全项）——风语者（合入者定时雷达）：每拍把「发现的问题」写成 `docs/tasks/backlog/TASK-NNN-*.yaml` 交下游 agent 认领；自己只处理合并者层面的事。
  - 探测面四项：①分支巡检（远端分支 vs 基线：ahead / cherry 等价 / 冲突标记，四类处置 ABORT-CONFLICT-MARKERS / DROP-ALREADY-IN-BASE / FF-MERGE-CANDIDATE / REVIEW）②docs 散落普查（根/docs/reports/memory md 计数 + 「治理」主题散布）③scripts 命名普查 ④守卫电池格数（run_guards --list 读数）。
  - 模式：默认扫描+写 yaml（title 关键词幂等去重、TASK 编号递增）；`--scan-only` 只出报告；`--apply` 额外做 ff-only 无分叉快进合入（真合并仍是人的决定）；`--no-fetch` 离线档。
  - rc 契约：0=无事 / 1=判据无法自证（FATAL）/ 2=发现待办（发现是产出不是失败）。
- **fist-gate 接线（验收②）**：`scripts/fist-gate.py` 门链第 6 查 `whisperer`——只跑 `whisperer.py --selftest`（扫描产物是输出不是门，不把真发现判成门红）；自证格 G5 green-on-clean rc=0。
- **scripts/README.md**：补 `fist-gate.py` + `whisperer.py` 两条登记（main 上 fist-gate.py 本就未登记，check_scripts_index 预存红一并收口）。

## 2. 资源消耗
- 单会话内完成；轮次预算（goal 12/20 起步）内收尾。无外部网络依赖（验证全部 `--no-fetch` / 自建合成仓）。

## 3. 任务分配记录
- 副机亲自实现（单脚本 + 单接线点，轻任务不外派）；风语者角色按 TASK-009 描述定义为脚本化巡检器。

## 4. 验证证据（rc 实读）
- `python scripts/whisperer.py --selftest` → `SELFTEST OK (grid: clean-branch-probe=True clean-marker-probe=True 0-new-yaml: 0→0)` rc=0。
- `python scripts/whisperer.py --scan-only --no-fetch` → 29 远端分支 / 25 待注意 / 守卫格数 86 / rc=2（发现待办）。
- `python scripts/fist-gate.py --selftest` → G5 whisperer green-on-clean (rc=0)；其余格绿（G4 fmt 观察格红见 §6）。
- `python scripts/check_scripts_index.py` → PASS rc=0。`check_py_stdout_encoding.py` → PASS 38/38。

## 5. 现场发现（scan 实测，交 owner/合并 agent）
- **ABORT 级 3 条分支自带未解冲突标记**（`git grep` 复核属实）：`fix/guards-conflict-markers-from-clean-commits`、`slave/fix/battery-expectations-r73`、`slave/fix/ecc-selftest-r72`（后者 `src/server/issue_scan.mbt` / `issue_scan_test.mbt` / `issue_scan_wbtest.mbt` 内含 `<<<<<<<`/`>>>>>>>`）——合并 agent 不得对这三条直 cherry-pick。
- 治理主题散在 20 个 md（TASK-006 的 DOCS-STRUCTURE 治理线收敛对象）；scripts 命名待定 39 个（TASK-008 进料）。
- 本轮刻意不写 yaml（`--scan-only`）：发现先交人裁决，避免把 owner 待裁项自动灌进任务池。

## 6. 遗留风险（预存红点名，不代修）
- fist-gate `--selftest` G4 fmt 格 rc=4294967295 = **本机 moonc `\\?\` 路径 ICE**（env 红在先；G4 是 observe-real 格，CI ubuntu 不受累）。G4 build rc=1 同为本机无 moon 链路的观察读数。
- whisperer `probe_scripts` 命名白名单是现状面（`whisperer`/`fist-gate`/`fist.py` 等 6 个例外硬编码），新增正式脚本要记得同步——TASK-008 若立规则应改为规则文件驱动。
- `--apply` 的 ff-only 合入只对无分叉分支生效且逐支 checkout 回原分支，`detached` 状态下行为未专项测试（默认不用 `--apply`，无风险敞口）。

## 7. 后续建议
- 合并 agent 巡检改为先跑 `python scripts/whisperer.py --scan-only --no-fetch`，ABORT 三条分支先人工清标记再合。
- 风语者定时化（cron/pipeline）时用默认模式写 yaml，幂等去重已保证不重复灌池。
- TASK-008（scripts 命名规则）可借 `probe_scripts()` 的 39 条清单直接开工。

## 8. 超额内容
- 顺手修 whisperer 自身两个 bug（探测函数 cwd 未穿透导致 selftest 扫全仓挂死级慢——faulthandler 定位后改为 cwd 参数化 + 逐文件 `git show` 换单发 `git grep`；守卫格数 regex 不配 `尺 N 把` 形状）；fist-gate 门链 5→6 查并补 G5 自证格。

## 9. 来源
- 任务：`docs/tasks/backlog` TASK-009（合并 agent 风语者巡检器）；角色定义见 `scripts/fist-gate.py --scan` 输出的巡检 prompt 追加句；AGENTS.md 提交门禁与 rc 契约。
