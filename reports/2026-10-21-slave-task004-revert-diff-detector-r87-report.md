# 2026-10-21 · TASK-004 反向 diff 检测 REVERT-PATTERN 报告（R87）

## 1. 结果摘要
- **交付**：`scripts/fist-gate.py` `--scan` 分支普查加 **REVERT-PATTERN** 判定（合入者前置过滤器）：
  - 分支级：src/scripts/cmd numstat 满足「删 ≥50 行 且 删 > 增×1.5」→ 判疑似 revert（把合入者已合的内容砍回旧版 / rebase 取错方向）。
  - 文件级：单文件删 ≥20 且 删 > 增×1.5 收进证据 Top5，yaml `revert_files: ["path(-删/+增)"]` + 巡检日志逐条点名（验收③：差值可见）。
  - 队列隔离（验收②）：REVERT-PATTERN 分支 yaml `status: failed`，不进 claimable `backlog` 队列。
  - 判定序：ABORT 冲突标记 > DROP（已在 base）> **REVERT-PATTERN** > MERGE-LOW-RISK/MERGE-CODE。
  - yaml 新增字段：`del_lines` / `add_lines` / `revert_pattern` / `revert_files`。
- 未动 `scripts/slave-branch-merge.ps1`（scope 第二项）：批合并驱动器读取的是 yaml 的 suggested_action/status，failed 状态分支天然被 claimable 面排除；给 ps1 加硬门属合并 agent 侧改动，交 owner 裁是否需要。

## 2. 资源消耗
- 单会话、纯脚本面（无 .mbt 改动，不触发 moon 工具链）；无网络依赖（自证全离线合成仓）。

## 3. 任务分配记录
- 副机亲自实现（单文件单特性，轻任务不外派）。

## 4. 验证证据（rc 实读）
- `python scripts/fist-gate.py --selftest`：19 格——新增 **S7**（合成 -60/+1 分支必进 `status: failed` + `revert_files: ["src/lib.mbt(-60/+1)"]` 精确字段）与 **S8**（小删 10 行不误红，status 仍 backlog）全绿；仅 G4 fmt 格红 = 本机 moonc `\\?\` ICE 预存环境红（观察格，CI ubuntu 不受累）。
- `python scripts/fist-gate.py --scan` 实跑全树：0 误报、0 漏报面变化——`battery-expectations-r73` 对**当前**基线如实读 `+523/-20`（revert_pattern: 0；其原 -718/+191 反向形状已被合入侧吸收，且该支现因 3 个冲突文件本就 ABORT）。

## 5. 现场发现
- r73 的证据形状（-718/+191）是对**当时 HEAD** 的 diff；对最新 gitcode/main 该支只剩 +523/-20——说明合入者已把冲突面部分吸收。检测器按「对基点的实时 numstat」判定，不会追打已失效的历史形状。
- ABORT 级 3 支（见 R86 报告）本轮 scan 复现一致。

## 6. 遗留风险（预存红点名，不代修）
- G4 fmt rc=4294967295 = 本机 moonc `\\?\` 路径 ICE（env 红在先）。
- 阈值 1.5×/50 行/20 行是按 r73 实证形状（3.76×）+ 常识下界标定，非常量棘轮；若 owner 要改判据松紧属人的决定。
- `slave-branch-merge.ps1` 未加显式 REVERT-PATTERN 硬门（见 §1）。

## 7. 后续建议
- 合并 agent 巡检照常跑 `fist-gate.py --scan`，`status: failed` 的 yaml 不要提升为可认领任务。
- 未来若再出现 r73 形状分支，yaml 的 revert_files 直接给出该砍哪个文件的证据。

## 8. 超额内容
- scan yaml 结构增强四字段（任务只要求标记+隔离+日志，字段化是为下游可机读）。

## 9. 来源
- 任务：`docs/tasks/backlog/TASK-004-revert-diff-detector.yaml`（discovered_by: lead，evidence: r73 -718/+191）；TASK-009 whisperer 扫描面同源。
