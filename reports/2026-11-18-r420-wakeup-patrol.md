# 轮 420 唤醒巡检报告

- **日期**：2026-11-18（Wed）
- **轮次**：r420
- **模式**：FIST 指挥官模式 · 唤醒巡检（**全绿零漂移确认轮**——换面 selftest + 实跑双 rc=0，无环境性读数）
- **FIST 闭环**：T0r176（ns=watchdog，agent=wd-r420）—— 6 步 + 终审 get 全 rc=0（详见 §5，TID 与逐步 rc 以 temp/fist_r420_out/1..7_*.txt 回包为准）

## 1. 结果摘要

本轮为**全绿零漂移确认轮**：Round C 队列空、10 条 OPEN bug 全部挂 owner 裁决 / 已否决 / harness 侧 / 待远端，无一条本看门轮可单边修。换面判据 **check_fist_list_tools_sync**（CLI 入口 `fist.py list-tools` 计数 ↔ 真源 `_tool_registry.real_tools()` 三面（C1 stdout 行数 / C2 集合 / C3 stderr 汇总行）对表判据，run_guards.py:186-187 注册 case + selftest 两格，**最近 25 轮换面未含此面**——grep 2026-11-1x 巡检报告「换面 check_fist_list_tools_sync」零命中）：**selftest rc=0 健康**（5/5 格）+ **实跑 rc=0 零漂移**（CLI list-tools ↔ 真源一致 183 工具，stdout 纯清单 183 行、集合逐名相等、stderr 汇总=183）。零漂移常设面全绿，非本仓回归。

**换面 · check_fist_list_tools_sync（CLI list-tools ↔ 真源 real_tools() 三面 · run_guards.py:186-187 注册，最近 25 轮换面未含此面）**：
- `--selftest` rc=0：**5/5 格通过**（S1 干净不误红 / S2 变异①旧口径真源必红 / S3 变异②CLI缺一名必红 / S4 变异③stdout混汇总行必红 / S5 空真源必红）——含判例-29/30 要求的三处变异对照（旧口径真源 / CLI 缺名 / stdout 混汇总）+ 空真源自拒锁（判例 R207 族：尺子空转必自拒不报绿）。
- 实跑 rc=0：**CLI list-tools ↔ 真源一致 183 工具**（stdout 纯清单 183 行、集合逐名相等、stderr 汇总行 = 183）——`fist.py list-tools` 是纯 Python 子命令（委托 `real_tools()`，零 node spawn、离线），非 WIP 文件面。
- **判读**：selftest rc=0（判据本身健康）+ 实跑 rc=0（被检面零漂移）⇒ 无判据失效、无回归、不立新账。

**零漂移常设面（全 rc=0）**：

| 判据 | 读数 |
|---|---|
| check_tools_sync | 183 工具 / 19 组 ΣN=183（server.mbt 注册 183 对齐，R3b/R7 扫现状面 169 份、历史面豁免 25 份）|
| check_instruction_budget | AGENTS.md 50440 / 预算 65536（全部章节可见）|
| patch_esm_main | 0/10 全 up-to-date（只碰 _build/ 构建产物、幂等不写、不碰 WIP 的 dist/）|

**WIP 禁区零碰**：iter-r192 车道 6M unstaged + 1untracked（dist/fist-mbt.js、memory/bugs.md、memory/target.md、scripts/README.md、scripts/check_plan_landing.py、templates/pipeline_mode_loop.md、reports/2026-11-17-iter-r192-report.md），暂存面空（`git diff --cached` 空、无 flux），**冻结第 27 轮**（bugs.md mtime 2026-11-15 23:40:40 未动）。WIP `bugs.md` 相对 HEAD 新增 **BUG-592~636 共 45 条**在飞账本条目（R192 车道在飞，非本轮处置面）。

**Round C 队列空态确认**（r385 实证，勿重核）：BUG-527 治本被 owner A/B 裁决**否决（严禁重跑）** / BUG-530 已 FIXED（3699f012a）/ check_usage_tool_count 已注册 run_guards.py。

## 2. 10 条 OPEN bug 全量分诊（无新发现 · 全挂 owner · 沿用 r411~r419 无变化）

| BUG | 级 | 阻塞面 | 结论 |
|---|---|---|---|
| 527 | medium | 治本被 owner A/B 裁决**否决** | 严禁重跑 |
| 542 | medium | 出路 A/B 挂 owner + 宿主路径沙箱拒写 | 本仓不可修 |
| 565 | medium | A 半挂 owner 裁决 + B 半部署待审批（沙箱）| 本仓不可修 |
| 566 | medium | 根因在宿主 harness 侧 | 本仓不可修 |
| 582 | low | 整体处置方向挂 owner（三类分流）| 挂 owner |
| **583** | **high** | 修复方向 ①②③ 挂 owner 裁决；行为锁已就位 | 挂 owner（最高优先，建议 owner 裁决）|
| 587 | medium | 修法候选 ①②③ 挂 owner 裁决 | 挂 owner |
| 589 | medium | 剩 11 条 C 档"只登记未处置"，收紧上限是人的决定 | 挂 owner |
| 590 | medium | ② 已收口 / ① 待比对 / ③ 归 587 | 挂 owner + 待比对 |
| 591 | low | ①⑤ 已落地 / ②③④ 挂 owner/远端 | 挂 owner |

**无一条本看门轮可单边修**——OPEN 抬头 10 条与 r411~r419 逐字一致（本轮 `check_bug_ledger_shape` 实跑权威复核重数 = 10：行首三段式抬头 621 条 · 行内 `## BUG-` 命中 17 行 · OPEN（行首抬头）10 · `] OPEN$` 行 10，rc=0 形态干净），BUG-583 是 high 级但其修复方向明确"待 owner/后续批次裁决"，本轮不单边决定（金条四：不可逆 / 需裁决的只出方案）。

## 3. 本轮误判更正

- 无（换面 selftest rc=0 健康、实跑 rc=0 零漂移、OPEN 权威重数实跑复核 = 10 与沿用面一致，未造出新假发现）。

## 4. 资源消耗

- 巡检判据：check_fist_list_tools_sync（selftest + 实跑，纯 Python 对表）+ check_tools_sync + check_instruction_budget + patch_esm_main（probe）+ check_bug_ledger_shape（OPEN 权威重数复核）——全纯 Python / 离线，零 moon spawn（换面是纯 Python 子命令，零 node spawn）。
- FIST 闭环：7 次 fist.py call（每发独立拉 node MCP server），后台串跑 job bg-1，整链秒级收口（热 server）。
- 未跑 moon build / moon test / 全量重跑（常设面是纯文本对表，不动测试计数面）。
- 未动任何产品码（零 src/**、零 run_guards.py）——10 条 OPEN 全挂 owner，本轮无单边可修项；WIP 禁区 7 件零碰。

## 5. 任务分配记录

- 本轮为统帅 solo 巡检（只读判据 + FIST 记账），**未派子代理**——10 条 OPEN 全挂 owner 裁决，无单边可决的可派活，巡检面全是纯只读判据（金条四：不派不能派的）。
- FIST 闭环：**T0r176**（ns=watchdog，agent=wd-r420）—— publish / agent_acl_grant / claim / execute / submit / verify / 终审 get，六步 + 终审全 rc=0，终审 `get` status=**已完成**、completed_by=wd-r420、created_at=2026-11-18T06:38:51Z / updated_at=2026-11-18T06:38:57Z（整链秒级收口，server 热）；状态链 已领取→执行中→待验收→已完成 逐格 rc=0；publish 回执 writable_agents 175（r419=174，+1 为本轮 wd-r420 授权）。（TID 与逐步 rc 以 temp/fist_r420_out/1..7_*.txt 回包为准。）

## 6. 遗留风险

1. **BUG-583（high）** 修复方向 ①②③ 挂 owner 裁决——OPEN 清单里唯一的 high 项；若 owner 裁 ①（mcpcf 边界换时基，2 处 + 沙箱库清表），下一轮即可落地；若悬而未决，2038 正性哨兵假态持续（当前 2026，尚余 12 年裕量，无近期危害）。
2. **WIP iter-r192 车道冻结第 27 轮**——6M+1untracked 全 unstaged 无动作；WIP `bugs.md` 已含 45 条在飞条目（BUG-592~636）。未跟踪报告 `reports/2026-11-17-iter-r192-report.md` 在 check_publish_payload 的 P1 红面（下次 `moon publish` 会公开）；归该车道 `git add` / 提交，本轮不抢。
3. **BUG-591 ②③（check_usage_tool_count 是否接 CI）** 挂 owner 裁决——若 owner 定接 CI，须动 ci.yml，归后续专门轮。

## 7. 后续建议

1. **建议 owner 裁决 BUG-583 修复方向**（high 级，行为锁已就位，① 代价最低）——OPEN 清单里唯一的 high 项。
2. **建议 owner 裁决 BUG-591 ②③（check_usage_tool_count 接 CI）与 BUG-587（修法候选 ①②③）**——三者都是"廉价修法"，owner 一裁即可落地。
3. **建议 iter-r192 车道收口其 WIP**（冻结 27 轮、45 条在飞账本、未跟踪报告在 P1 红面）——或明确放弃交接。
4. 若 owner 未设新目标，下一轮继续空队列态巡检（换面 + 常设面），不空转。

## 8. 超额内容

- 无（本轮为纯巡检 + 记账，无超出巡检范围的超额改动）。

## 9. 来源

- 巡检判据实跑：check_fist_list_tools_sync（selftest rc=0 5/5（S1 干净不误红 / S2 变异①旧口径真源必红 / S3 变异②CLI缺一名必红 / S4 变异③stdout混汇总行必红 / S5 空真源必红）/ 实跑 rc=0 CLI list-tools↔真源一致 183 工具 stdout 纯清单 183 行 集合逐名相等 stderr 汇总=183）/ check_tools_sync（rc=0 183/19/183）/ check_instruction_budget（rc=0 50440/65536）/ patch_esm_main（rc=0 0/10）/ check_bug_ledger_shape（rc=0 OPEN 重数=10）。
- WIP 态：`git status --short`（6M unstaged + 1untracked，iter-r192 车道）+ `stat` mtime 核对（bugs.md 2026-11-15 23:40:40 未动）+ `git diff --cached` 空（暂存面无 flux）+ WIP `bugs.md` 相对 HEAD 新增 BUG-592~636 共 45 条（沿用 r413~r419 读数）。
- Round C 队列空态：r385 实证 + 轮 404~419 复核。
- 10 条 OPEN bug 分诊：memory/bugs.md（沿用 r419 全 detail 分诊，本轮权威重数实跑复核 = 10，无变化）。
- 换面 freshness：grep reports/「换面 check_fist_list_tools_sync」零命中（该面仅在 2026-10-25 创建报告 / selftest 审计 / 11-14 r278~r281 zerochange / r388 等历史报告被提及，均非换面轮）⇒ 本面最近 25 轮换面未覆盖。
- FIST 闭环：temp/fist_r420_out/1..7_*.txt（T0r176）。
