# 轮 412 唤醒巡检报告

- **日期**：2026-11-18（Wed）
- **轮次**：r412
- **模式**：FIST 指挥官模式 · 唤醒巡检（**无新发现确认轮**）
- **FIST 闭环**：T0r168（ns=watchdog，agent=wd-r412）—— 6 步 + 终审 get（详见 §5）

## 1. 结果摘要

本轮为**无新发现确认轮**：Round C 队列空、10 条 OPEN bug 全部挂 owner 裁决 / 已否决 / harness 侧 / 待远端，无一条本看门轮可单边修。巡检面零漂移全绿，换面判据 check_exit_code_contract 工作正常。

**换面 · check_exit_code_contract（BUG-369 退出码契约「承诺面 ↔ 实现面」· 全历史从未单巡的 CI 硬门）**：
- `--selftest` rc=0：28 格全过（24 逻辑格 + calib 5 格按名现数 + 自指格），**可红可绿含变异对照**——
  - 红面：`headless-phantom-caught-by-R1`（幻影承诺 rc=2 但 ast 给不出 ⇒ R1）、`site-rc-text-lie-caught-by-R3-not-R1`（文案自写 rc=2 实给 1 ⇒ R3 而非 R1）、`ratchet-over-ceiling-is-red`（上限+1 必红）、`empty-universe-fatal-rc-2`（空宇宙自拒真给 2）；
  - 绿面：`real-contract-no-false-positive`（真契约不误红）、calib 5 格（check_plan_landing / check_mbti_sync / check_pkg_imports / simulate_head_commit / check_template_ctrl）按名字现数全归零。
- 实跑 rc=0：宇宙 181 份 scripts/**.py、有 `N=` 契约块 81 份；**判定面（R1 模块面幻影 + R2 站点类指派 + R3 站点自述码）= 0 条 = 棘轮上限 0**（BUG-369 立案那批存量已清完，无容忍带，任何一条新假契约必红）；只报不判 190 条（S 沉默出口 100 ｜ U 未认作契约 83 ｜ O 不透明/让位 7）——如实出数，不静默丢弃。

**零漂移常设面（全 rc=0）**：

| 判据 | 读数 |
|---|---|
| check_tools_sync | 183 工具 / 19 组 ΣN=183（R8 分组对表在跑，server.mbt 注册 183 对齐）|
| check_instruction_budget | AGENTS.md 50440 / 预算 65536（全部章节可见）|
| patch_esm_main | 0/10 全 up-to-date（只碰 _build/ 构建产物、幂等不写、不碰 WIP 的 dist/；FIST 链前内存压力探针未复现）|

**WIP 禁区零碰**：iter-r192 车道 6M unstaged + 1untracked（dist/fist-mbt.js、memory/bugs.md、memory/target.md、scripts/README.md、scripts/check_plan_landing.py、templates/pipeline_mode_loop.md、reports/2026-11-17-iter-r192-report.md），暂存面空、无 flux，**冻结第 19 轮**（bugs.md mtime 2026-11-15 23:40:40、dist mtime 2026-11-17 10:32:48 均未动）。

**Round C 队列空态确认**（r385 实证，勿重核）：BUG-527 治本被 owner A/B 裁决**否决（严禁重跑）** / BUG-530 已 FIXED / check_usage_tool_count 已注册 run_guards.py。

## 2. 10 条 OPEN bug 全量分诊（无新发现 · 全挂 owner · 沿用 r411 无变化）

| BUG | 级 | 阻塞面 | 结论 |
|---|---|---|---|
| 527 | medium | 治本被 owner A/B 裁决**否决** | 严禁重跑 |
| 542 | medium | 出路 A/B 挂 owner + 宿主路径沙箱拒写 | 本仓不可修 |
| 565 | medium | A 半挂 owner 裁决 + B 半部署待审批（沙箱）| 本仓不可修 |
| 566 | medium | 根因在宿主 harness 侧 | 本仓不可修 |
| 582 | low | 整体处置方向挂 owner（三类分流）| 挂 owner |
| **583** | **high** | 修复方向 ①②③ 挂 owner 裁决；行为锁已就位（7+4 格）| 挂 owner（最高优先，建议 owner 裁决）|
| 587 | medium | 修法候选 ①②③ 挂 owner 裁决 | 挂 owner |
| 589 | medium | 剩 11 条 C 档"只登记未处置"，收紧上限是人的决定 | 挂 owner |
| 590 | medium | ② 已收口 / ① 待比对 / ③ 归 587 | 挂 owner + 待比对 |
| 591 | low | ①⑤ 已落地 / ②③④ 挂 owner/远端 | 挂 owner |

**无一条本看门轮可单边修**——BUG-583 是 high 级，但其修复方向明确"待 owner/后续批次裁决"，本轮不单边决定（金条四：不可逆 / 需裁决的只出方案）。

## 3. 本轮误判更正

- 无（本轮巡检面全绿、分诊沿用 r411，未造出新假发现）。

## 4. 资源消耗

- 巡检判据：check_exit_code_contract（selftest + 实跑）+ check_tools_sync + check_instruction_budget + patch_esm_main —— 全纯 Python / 离线，零 spawn。
- FIST 闭环：7 次 fist.py call（每发独立拉 node MCP server），后台串跑（node 冷启动 ~2min，勿前台硬等）。
- 未跑 moon build / moon test / 全量重跑（常设面是纯文本对表，不动测试计数面）。
- 未动任何产品码（零 src/**、零 run_guards.py）——10 条 OPEN 全挂 owner，本轮无单边可修项；WIP 禁区 7 件零碰。

## 5. 任务分配记录

- 本轮为统帅 solo 巡检（只读判据 + FIST 记账），**未派子代理**——10 条 OPEN 全挂 owner 裁决，无单边可决的可派活，巡检面全是纯只读判据（金条四：不派不能派的）。
- FIST 闭环：T0r168（ns=watchdog，agent=wd-r412）—— publish / agent_acl_grant / claim / execute / submit / verify / 终审 get。

## 6. 遗留风险

1. **BUG-583（high）** 修复方向 ①②③ 挂 owner 裁决——若 owner 裁 ①（mcpcf 边界换时基，2 处 + 沙箱库清表），下一轮即可落地；若悬而未决，2038 正性哨兵假态持续（当前 2026，尚余 12 年裕量，无近期危害）。
2. **WIP iter-r192 车道冻结第 19 轮**——6M+1untracked 全 unstaged 无动作。未跟踪报告 `reports/2026-11-17-iter-r192-report.md` 在 check_publish_payload 的 P1 红面（下次 `moon publish` 会公开）；归该车道 `git add` / 提交，本轮不抢。
3. **BUG-591 ②③（check_usage_tool_count 是否接 CI）** 挂 owner 裁决——若 owner 定接 CI，须动 ci.yml，归后续专门轮。

## 7. 后续建议

1. **建议 owner 裁决 BUG-583 修复方向**（high 级，行为锁已就位，① 代价最低）——OPEN 清单里唯一的 high 项。
2. **建议 owner 裁决 BUG-591 ②③（check_usage_tool_count 接 CI）与 BUG-587（修法候选 ①②③）**——三者都是"廉价修法"，owner 一裁即可落地。
3. **建议 iter-r192 车道收口其 WIP**（冻结 19 轮、未跟踪报告在 P1 红面）——或明确放弃交接。
4. 若 owner 未设新目标，下一轮继续空队列态巡检（换面 + 常设面），不空转。

## 8. 超额内容

- 无（本轮为纯巡检 + 记账，无超出巡检范围的超额改动）。

## 9. 来源

- 巡检判据实跑：check_exit_code_contract（selftest rc=0 28 格 / 实跑 rc=0 判定面 0=上限 0 只报不判 190）/ check_tools_sync（rc=0 183/19/183）/ check_instruction_budget（rc=0 50440/65536）/ patch_esm_main（rc=0 0/10）。
- WIP 态：`git status --short`（6M unstaged + 1untracked，iter-r192 车道）+ `stat` mtime 核对（bugs.md 11-15 23:40:40 / dist 11-17 10:32:48 未动）。
- Round C 队列空态：r385 实证 + 轮 404~411 复核。
- 10 条 OPEN bug 分诊：memory/bugs.md（沿用 r411 全 detail 分诊，本轮无变化）。
- FIST 闭环：temp/fist_r412_out/1..7_*.txt。
