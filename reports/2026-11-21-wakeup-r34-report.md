# 2026-11-21 唤醒巡检 R34 报告 — WIP 同形避让 + 接线半七轮复核 + 新探活面（ExploreWatchdog 自身日志面发现）+ T0r9 闭环

- 轮次：R34（Windows 计划任务 FIST-Mbt-ExploreWatchdog 唤醒，findings-only 非阻塞巡检）
- 前序：[R33 报告](2026-11-21-wakeup-r33-report.md)（WIP 同形避让 + 接线半六轮复核 + T0r8 闭环）
- 模式：fist-commander；本轮**未改任何跟踪面代码**（零改码轮，原因见 §五）
- 本轮特点：树面无新发现延续轻轮，但按 R33 §七遗留清单之外**首次把巡检发起者自身纳入探活**（ExploreWatchdog 调度器 + wrapper + 运行日志），拿到一项新发现（§3.3）

## 一、结果摘要

| # | 事项 | 结论 |
|---|---|---|
| 1 | 并发 WIP | 与 R33 快照**同形、零新落盘**（live `git status` 逐项一致：M 39 + 未跟踪 6；定点 mtime 复核 run_guards.py 11-20 21:44 / server.mbt 20:36 / 最新源 tool_cov_query_tools_test.mbt 仍 02:40:03 / cli.js 03:33:54）——f094 收口方持续暂停期，全程避让零接触 |
| 2 | HEAD | `0034874c7`（R33 报告提交）——**预期轮内推进**，无他方新提交 |
| 3 | BUG-636 接线半 | **仍未认领**（`grep _tool_registry scripts/check_tool_coverage.py` 零命中，extract_tools 仍直读 server.mbt，:119）——跨 R28→R34 **七轮**未动 |
| 4 | 新鲜度探针 | 按 R30 §3.3 固化口径第四轮复用：`_build/js/debug/build/cmd/cli/cli.js` 03:33:54 > 最新源 02:40:03 ⇒ **产物新鲜，零 autobuild 触发**（T0r9 链 7 秒跑完为旁证） |
| 5 | 新探活面（首次） | **ExploreWatchdog 自身**：调度节奏健康（11-21 05:00→08:00 七个 30 分钟档日志齐全）；但**运行日志面有一项真发现**——`watchdog_*.jsonl` 名不副实（详见 §3.3，BUG-109/BUG-88 同族） |
| 6 | 三尺复跑 | **主动跳过**：树面与 R33 同形 ⇒ 读数必然复写 R29，跑了就是空转 |
| 7 | FIST 闭环 | **T0r9 六步首发即全绿**（链脚本复用 r33 模板，7 秒，§六） |

## 二、并发 WIP 与提交面

- HEAD 由 R33 轮的 `856ed61c6` 推进到 `0034874c7`——这是 **R33 报告自己的提交**，属唤醒轮预期推进，非他方新提交；除此之外 `git log` 无新提交。
- M 面 39 文件 + 未跟踪 6 项与 R33（及 R28~R32）完全一致；关键文件定点 mtime 复核（run_guards.py 11-20 21:44:55 / server.mbt 11-20 20:36:06 / tool_cov_query_tools_test.mbt 11-21 02:40:03 / tool_cov_wt_async_test.mbt 11-20 22:59:10 / cli.js 11-21 03:33:54）——**自 02:40 后跟踪面无新写入**，与 R33 读数逐项一致。
- 本轮落盘面仅三处：本报告（唯一提交物）+ `memory/2026-11-21.md` 追加 R34 段（本地留置不入库）+ `temp/fist_r34_chain.sh` / `temp/fist_r34_chain.log`（temp 面不提交）。

## 三、本轮三查明细

### 3.1 BUG-636 接线半复核（七轮零进展）

- `scripts/check_tool_coverage.py` 全文 `grep _tool_registry` **零命中**，extract_tools（:119）仍直读 server.mbt——接线半（extract_tools 委托 `_tool_registry` 真源 + `consumers()` 收口）维持无人认领，与 R28~R33 结论一致。
- 处置维持 R29~R33 口径：**WIP 收口后按 r315 规格委派中任务**（接线落地须同批处理 7 盲区工具 known-red，BUG-455 先例；账面按 170 口径重算并修正「165 口径」引用面）；规格锚点（run_guards.py / scripts/README.md / battery 锚）全在他方 WIP 修改面，本轮不认领。

### 3.2 新鲜度探针（R30 §3.3 口径第四轮复用，成立）

- 锚定 `fist.py MAIN_CANDIDATES` 的运行态真入口 `_build/js/debug/build/cmd/cli/cli.js`：mtime **03:33:54**（R28 轮 autobuild 所产）> 最新源 02:40:03 ⇒ **产物新鲜，本轮链零 autobuild 触发**。
- R30 §3.3 两条教训（参照必须先验存在、口径锚 `_build` 入口）与 R31 §3.3 修正口径（同形判定 = git status 快照比对 + 定点 mtime，不跑全树 mtime 扫描）本轮全部免疫生效，无新伪影。

### 3.3 新探活面：ExploreWatchdog 自身（本轮唯一新信息）

**背景**：R26→R33 八轮巡检的对象全是树面/判据面/产物面，巡检基础设施本身从未被检查过。本轮首次自诊断：调度器节奏、wrapper 脚本、运行日志。

**① 调度节奏（健康）**：`temp/explore_watchdog/` 下 11-21 当日日志齐全——05:00 / 05:30 / 06:00 / 06:30 / 07:00 / 07:30 / 08:00 七个 30 分钟档无缺失，与 R29~R33 报告的落盘时刻一一对应（05:33 / 06:03 / 06:33 / 07:02 / 07:32），计划任务本身按 30 分钟节奏正常触发。重叠锁与轮换文件名机制工作正常。

**② 日志面发现（真问题）**：`watchdog_*.jsonl` **名不副实**——根因在 `scripts/explore_watchdog_wrapper.ps1:23`：

```powershell
& $atom -C $root --prompt-file ... --output-format jsonl *> $log
```

PS 5.1 的 `*>` 重定向按 Out-File 语义落盘，默认编码 **UTF-16LE**，且原生命令 stderr 被包装成 ErrorRecord（BUG-109 同族形状：`atomcode.exe : ... NativeCommandError` 四行块 + `所在位置/字符/CategoryInfo/FullyQualifiedErrorId`），atomcode 启动告警（"Console code pages before TUI setup: input 65001, output 936"）也以错误记录形态混入。实测证据（0730 日志）：

| 指标 | 读数 |
|---|---|
| 文件编码 | UTF-16LE（非 UTF-8）——任何按 UTF-8 读 jsonl 的消费者**字节层即断**（首字节即 BOM/宽字节） |
| 转码后行数 | 9070 非空行 |
| 真 JSON 事件行 | 8151（90%）——atomcode stdout 的 jsonl 事件本身是好的，坏在包装 |
| 非 JSON 行 | **919 行**（10%）——PS 错误块/流头，第 1 行即非 JSON |
| 目录体积 | **53MB** 无界增长，单次过夜跑（20261120_2001）单文件 **37MB** |
| 机器消费方 | **零**——全仓仅 `scripts/explore_watchdog_prompt.md`（人读指引）提及该目录 |

**定性**：中低危（诊断面退化 + 磁盘无界增长 + 误导性 `.jsonl` 命名），非巡检主链路缺陷（巡检闭环照常工作，本轮即旁证）。同族：BUG-109（原生命令 stderr 经重定向变错误记录）、BUG-88（PS5.1 编码陷阱）。

**③ 处置**：本轮零改码，理由见 §五；发现固化本报告 + 当日日志，**账本不立**（plugins/** 他方 WIP 不可同批 gen_plugins，R26→R34 连续九轮回避口径），落账待 plugins/ 收口后用 **≥649 新号**（r28 复核口径）。修复方向（供修复轮参考，本轮不实施）：改 `*>` 为显式流分离（`Start-Process -RedirectStandardOutput/-RedirectStandardError` 或 `2>&1 | Out-File -Encoding utf8` 并处理 ErrorRecord 包装），文件名改 `.log` 或确保真 UTF-8 jsonl，另补 temp/explore_watchdog/ 保留策略（防无界增长）。

## 四、三尺与换面巡检边界

- 三尺复跑主动跳过（树面与 R33 同形 ⇒ 读数必然复写 R29，跑了就是空转，R30 口径第五轮延续）。
- R29 §八.2 候选判据（check_effective_catch / check_ns_write_gate_coverage / check_ci_step_position）仍**不启用**：check_ci_step_position 读 `.github/workflows/release.yml`（他方 WIP 修改面），现在跑会红在他方 WIP 上，制造噪声读数——维持「树面收口后恢复」口径。

## 五、本轮不改码边界（任务分配记录）

| 事项 | 处置 | 不动手原因 |
|---|---|---|
| BUG-636 接线半 | 留 WIP 收口轮按 r315 规格委派中任务 | 规格锚点全在他方 WIP 修改面；接线落地须同批 7 盲区工具 known-red（BUG-455 先例）——R29~R33 五轮同款回避，本轮续 |
| BUG-636 落账（≥649 新号） | 不落，findings 固化本报告 | 账本/计数面改动须同批 gen_plugins.py 重投影，plugins/** 在他方 WIP 内（R26~R33 连续八轮同款回避，本轮续第九轮） |
| wrapper 日志面修复 | 不修，发现固化报告 | wrapper 是**巡检基础设施**（本轮正由它拉起）；虽不在他方 WIP 修改面，但巡检轮纪律为 findings-only 零改码，且修 wrapper 涉及调度面行为变更，归修复轮/上游 |
| temp/explore_watchdog/ 清理 | 不清，仅建议保留策略 | 删除是破坏性操作，且旧日志是本轮发现的证据面 |
| 三尺复跑 | 主动跳过 | 树面与 R33 同形 ⇒ 读数必然复写 R29，跑了就是空转 |
| f094 WIP 全部文件 | 零接触 | 他方活跃 WIP（暂停期 ≠ 收口，收口以提交为准） |
| `website/` / `.trae-html-share-packages/` / `_moonbit_兼容性反馈.txt` / `reports/2026-11-20-tnr-ascend-round2-report.md` 等未跟踪面 | 零接触 | 非本轮建立、归属不明（tnr-ascend 报告自述「主工作树 48 文件 WIP 仍属另一作者」），巡检轮只记录不处置 |

## 六、FIST 闭环记账（T0r9，首发即全绿）

- ns=`wakeup-patrol`，agent=`commander-atomcode`；task_id=**T0r9**。
- 六步 rc：publish=0 / acl=0 / claim=0 / execute=0 / submit=0 / verify=0——**首发即绿，零补跑**；7 秒跑完（08:04:50→08:04:58，产物新鲜免 autobuild）。
- 任务终态「已完成」（verify 步回执实测，completed_by=commander-atomcode）；链日志 `temp/fist_r34_chain.log`（含完整回执）。
- 工程面复用成立第六次：链脚本 `temp/fist_r34_chain.sh` 直接复用 r33 模板，TID 提取继续复用 `temp/fist_r28_tid.py`（r318 稳健口径、argv 参数化、notice 行免疫）。

## 七、遗留风险

1. **BUG-636 接线半无人认领**（中危，CI 门禁盲区，跨 R28→R34 七轮未动）：处置与 R33 §六.1 相同，不重复展开。
2. **f094 WIP 未收口**（39 M + 6 未跟踪，暂停期持续）：本轮报告单文件 scoped 提交避让；当日日志按惯例留本地不提交。
3. **ExploreWatchdog 日志面缺陷待修复**（新，中低危）：`.jsonl` 实为 UTF-16LE 混合流 + 10% 错误块，诊断面不可机读、53MB 无界增长——修复归巡检基础设施轮/上游（修复方向见 §3.3③），落账待 ≥649 新号。

## 八、后续建议

1. **WIP 收口轮次序**维持 R33 §七.1（上溯 R29 §八.1）：三红同批（EP-03 域）→ gen_plugins.py 重投影 → 委派 BUG-636 接线中任务（子代理执行 + 指挥官终审：`--selftest` + 本体 170 口径新期望 + `_tool_registry --selftest` 收口格 + `check_battery_count_doc` + 全量 `moon test --target js`）；落账 ≥649 新号并修正「165 口径」引用面。
2. 唤醒轮维持：publish 成功绝不重发、链模板直接复用（含 r28_tid.py）、新鲜度探针参照 = `_build/js/debug/build/cmd/cli/cli.js`、同形判定 = git status 快照比对 + 定点 mtime（R31 §3.3）。
3. **新探活面固化**：ExploreWatchdog 自诊断纳入巡检轮低频复用面（节奏档齐全性 + 日志体积增量），无需每轮全查；wrapper 修复轮落地后再补「日志可机读」一格。
4. 树面收口后（下轮若见他方新 HEAD）：恢复三尺 + R29 §八.2 候选判据换面轮巡。
