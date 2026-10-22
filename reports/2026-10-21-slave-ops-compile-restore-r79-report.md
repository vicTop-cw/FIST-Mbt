# R79 报告 — slave/fix/ops-compile-restore-r79（新 master src/ops 编译修复）

## 结果摘要

master 被 force push 重写（259b56a → 9299611）后仍带病：`src/ops` 8 处 `Error [4021]` unbound，
全量构建即崩。本单把 r71 已验证的 src/ops 三件修复按同形搬到新 master 基点，恢复 master 线可编译：

- 新增 `src/ops/rhop_poll.mbt`（66 行）：`rhop_poll_once` 定义（@rhop 外部包解码纪律，wbtest 6 处引用的实源）
- `src/ops/ops_test.mbt` +12 行：补两处被 cherry-pick 丢掉的绑定（check_claim 断言/claim/dup 三行 + `heal_stale_tasks` 的 `let healed` 六行）
- `src/ops/moon.pkg` +1 行：`moonbitlang/core/ref` 导入（rhop_poll.mbt 的 `@ref.Ref` 依赖）
- 文档面计数同步：1348→1347（8 文件 27 处）+ docs/agent-map.md 1302→1347（新 master 线首个实测数）

## 资源消耗

本机全量 `moon test --target js` 两轮（master 基线取证 + 修复后验证）+ moon info 一次（全仓 .mbti 重排已按坑位协议还原）+ 守卫电池 7 把尺。

## 任务分配记录

指挥官亲做（取证 + 搬运 + 终审）；无子代理。

## 关键取证

1. **对主机 TASK-002「rhop_poll.mbt 是 poison」的反证**：gitcode master 的 src/ops **不存在 rhop_native.mbt**
   （只有其 wbtest 引用 `rhop_poll_once` + moon.pkg 的 @rhop 导入）——「与 rhop_native.mbt 重复定义」
   在 master 线上不成立，现状是**缺定义**。合入者的 rhop_native.mbt 在他们自己的集成线；两线修向需 owner 裁决。
2. **master 重写内容**：marker 已清（2357ff9 替 259b56a）、r74 的 ci.yml 步骤移位被 cherry-pick（2b00764）、
   主机自有 fist-gate.py + docs/tasks/ 5 个 backlog yaml（assignee 全为 atomcode）。
3. **测试数 1347**：新 master 线实测（警告 701 条与 r71-r77 试金石树完全同数 = 本单零新增）。

## 遗留风险

- **预存红①（本单不代修）**：`check_scripts_index` rc=1——主机 454aea3 落的 `fist-gate.py` 未在 scripts/README.md 登记。
- **预存红②（本单不代修）**：`check_bug_reference_integrity` rc=1——J1 悬空 17 条（ocr_scan.mbt/server.mbt 注释引 BUG-327/327b，
  主机账本重写丢了 327/336 抬头）。**已推送的 r76 分支（slave/docs/bug373-ref-integrity-r76）修的正是这一面**。
- 七链合序问题原样在案：r71 的 issue_scan 改动 vs 主机重写版（2714 行）的冲突归 owner 裁决；本单刻意不碰 issue_scan。

## 后续建议

- 合序：**r79 先行**（恢复 master 线可编译基点）→ r76 随后（收口 J1 悬空）→ r77 → r72/r73（与主机重写版的
  issue_scan/run_guards 冲突需 owner 裁决）→ r75。r74 已被吸收，MR 可关。
- fist-gate.py 登记与 J1 棘轮可由 owner 顺手在本单之上补一笔，或留给 AtomCode 的 TASK-005 扫描面。

## 超额内容

无。文档计数同步属本单「首个实测数落盘」的必要面（check_test_sync/check_badge 门要求）。

## 来源

- 分支 `slave/fix/ops-compile-restore-r79`（基点 gitcode/master 9299611）
- 测试日志 `temp/r79_test.log`（1347/1347）
- 前置取证：temp/r78_master_test.log（master 8×4021）、试金石报告（同日）
