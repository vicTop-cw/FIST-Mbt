# 轮 388 巡检报告

> FIST-Mbt ExploreWatchdog 唤醒轮（Windows 计划任务，每 30 分钟无窗）。
> 生成时刻：2026-11-17。报告文件即本轮 FIST 任务的 deliverable。

## 一、WIP 收口核查（巡检分支判定）

`git status --short` 与 r387 一致：**6 M + 1 untracked**，无新收口、无新起 WIP：

| 文件 | numstat | 状态 |
|---|---|---|
| dist/fist-mbt.js | 76721 变更 | M（中止轮再生，r384 记录，未提交） |
| memory/bugs.md | 216+ | M（外来账冻结，r378 起，第 66+ 轮） |
| memory/target.md | 1/1 | M（巡检 WIP，冻结面） |
| scripts/README.md | 1/1 | M（iter-r192 车道 F 提交③在途：R192 T0r2 登记同步） |
| scripts/check_plan_landing.py | 144（+/−） | M（iter-r192 车道 F 在途：:864 子串排除修复 + selftest 64→71 格） |
| templates/pipeline_mode_loop.md | 1/1 | M（J8 修复：run_check 示例补必填 task_id/cmd，排提交③） |
| reports/2026-11-17-iter-r192-report.md | untracked | iter-r192 收口报告（**在途**，自述车道 M/X/Y 未回传） |

⇒ **iter-r192 收口进行中**（车道 F 提交③未落库），禁区零碰。`src/**` 与 `scripts/run_guards.py`
维持 r385 确认的已解禁态，但 **Round C 队列（既定迭代目标）已由 r385 逐项核实全消并移交 owner 设
下一目标** ⇒ 本轮无既定目标可执行，走**巡检分支**：非阻塞换面 + FIST 闭环记账，不代设目标、不重跑
已否决动作（BUG-527 治本，重跑必红 CI native）。

## 二、换面巡检：check_tool_required_sync（schema required↔必填描述 源↔源 对表 · 新面）

**为何选此面**：r387 跑 check_host_installable、r386 跑 check_battery_count_doc、r385 跑
check_store_tables_wired、r378 跑 check_mbti_eol；近 2 周（r373~r387）换面面清单里
check_tool_required_sync **未覆盖** ⇒ 不撞面。该面守的是 `src/server/server.mbt` 工具面「schema
`required` 数组 ↔ 描述里的「必填」措辞」双向对表：漏写（描述必填但 required 没列 ⇒ 空参漏到服务端
才炸）/ 多写（required 列了但描述可选 ⇒ 合法调用被客户端误拒）两类漂移，**源↔源**解析、不起 server、
CI 可裸跑，与 check_usage_tool_count（USAGE 文档面）互补。

### selftest（判据健康性，先判尺子不坏）

`SELFTEST PASS（14/14）`，`RC=0`。

⇒ **判据健康**：14 格含漏写/多写变异对照、干净不误红、条件必填抑制双向、白名单过期三向、
bug_fix.evidence 具体对照、零工具失锚、未知旗标 rc=2，非恒绿。

### 实跑（现状面）

`required↔必填 对表 PASS：解析 168 工具；required 数组与必填描述零漂移；条件必填 2 处（白名单 3 条，
三向未过期）`，`RC=0`。

⇒ **零漂移**：168 工具的 required 数组与必填描述完全自洽，无漏写/多写。

## 三、附核：check_fist_list_tools_sync（commissar_gc 182→183 后的 CLI 入口面）

**为何附核**：commit `8b1a0fd11` 把 `commissar_gc` 接线 182→183，而 `fist.py list-tools` 曾自写正则
只扫 server.mbt 一个文件、`[a-z_]+` 不认点号（漏 18 工具，判例-16 家族）。本次改工具数后，核 CLI 入口
是否仍与真源一致（防「守卫绿、入口少」复发）。

- **selftest**：`SELFTEST OK (grid: S1-干净不误红 / S2-变异①旧口径真源必红 / S3-变异②CLI缺一名必红 /
  S4-变异③stdout混汇总行必红 / S5-空真源必红)`，`RC=0`。
- **真跑**：`PASS CLI list-tools ↔ 真源一致：183 个工具，stdout 纯清单 183 行，集合逐名相等，stderr
  汇总行 = 183`，`RC=0`。

⇒ **182→183 面零漂移**：`fist.py list-tools` 现委托 `_tool_registry.real_tools()`（旧正则已修），
CLI 报 183、集合逐名相等，入口无漏报。

## 四、零漂移常设面

- `check_tools_sync`：`PASS 工具单一真源一致：server.mbt 注册 183 个，AGENTS/README/deliverable/
  scoring_rubric 对齐；R8 清单分组 19 组 ΣN=183`，`RC=0`。
- `check_instruction_budget`：`AGENTS.md = 50440 字节 / 预算 65536`，`PASS 指令文件在预算内`，`RC=0`。

## 五、FIST 闭环

**T0r144 六步全链 rc=0**（wd-r388 / ns watchdog / `temp/fist_r388_chain.sh` 稳健 TID 提取后台串跑，
patch_esm_main 探针先行 10 bundle 全 up to date / total patched 0）：
publish rc=0 → TID=T0r144 → acl rc=0 → claim rc=0 → execute rc=0 → submit rc=0 → verify rc=0。
verify 字段：`status=已完成`、`completed_by=wd-r388`、`assignee=wd-r388`、
`deliverable=reports/2026-11-17-r388-wakeup-patrol.md`、`namespace=watchdog`、
`created_at=2026-11-17T07:15:44Z` / `updated_at=2026-11-17T07:15:50Z`。

## 六、禁区与立账

- **禁区零碰**：6 个 WIP 修改文件 + 1 个 untracked 报告零改零提交；插件态 / 构建产物 / PATH 垫片
  本轮均未写。patch_esm_main 探针只动 `_build/`（gitignore 面），不碰 dist/ WIP。
- **无新立账**：换面（check_tool_required_sync）+ 附核（check_fist_list_tools_sync）+ 零漂移两面
  全零漂移、无新发现；bugs.md 属 WIP 冻结面不代改；Round C 队列空属「既定目标完成/过时、非代码
  缺陷」，不立 BUG 号（同 BUG-636 临时立账口径逆向）。

## 七、结论

本轮换面巡检三面均干净：**check_tool_required_sync**（新面，selftest 14/14 + 真跑 PASS rc=0，
168 工具 required↔必填描述零漂移）⇒ 工具 schema 自洽面无新发现；**check_fist_list_tools_sync**
（182→183 面，selftest 5/5 + 真跑 PASS rc=0，CLI=183 逐名一致）⇒ 入口无漏报；**零漂移**
check_tools_sync 183 / check_instruction_budget 50440/65536 均 rc=0。WIP 面 6M+1untracked 与 r387
一致 ⇒ **iter-r192 收口进行中**、禁区零碰。既定迭代目标（Round C 队列）维持 r385 移交态：不代设、
不重跑已否决动作（BUG-527 治本）。FIST 闭环见第五节。
