# 轮 321 唤醒巡检报告

**日期**：2026-11-16
**轮次**：r321
**执行者**：wd-r321（FIST-Mbt-ExploreWatchdog）

## 结果摘要

**WIP 非冻结增长第 1 轮（新增长源：vq P7-3 外来账 BUG-636 落 `memory/bugs.md`，与 r318 R192 车道不同源）** ——
仅 `memory/bugs.md` 增长 **+8 行**（208/0 → 216/0，mtime 2026-11-15 23:40，晚于 r320 链 23:34）；
R192 车道 5 个已跟踪文件（`improvement-plan` 7/1、`target.md` 1/1、`README` 2/1、`run_guards` 9/0、
`engine_circuit_test` 5/0）**逐字同 r320**，2 个 untracked（`check_mcpcf_db_isolation.py`、
`pipeline_mode_loop.md`）未变。`src/**` + `scripts/run_guards.py` 仍 M ⇒ **巡检分支**（Round C 三件仍锁）。

增长行取证（`git diff memory/bugs.md` 末端）：**`## BUG-636 [2026-11-15T15:04:15Z] [high] FIXED`**
（`[P7-3/环境]` gnu 目标测试 exe 启动即 `STATUS_ENTRYPOINT_NOT_FOUND`，rustc 1.100 + MinGW 8.1.0 import lib 绑定
过时）+ 其 `### FIXED(2026-11-15T15:40:40Z / BUG-636)` 证据块 + 2 空行。内容全为 vq 项目（`crates/vq-cli`、
MinGW、`p7_multi_outlet.rs`），`reported_by: vq 统帅（P7-3）` ⇒ **vq 项目外来账落本纯 MoonBit 仓**，同
**BUG-565 跨项目误落账持续模式**；BUG 号与 FIST 自留临时号（r315 的 `check_tool_coverage` 缺陷临时号 BUG-636）
**撞号**（vq 项目自有 BUG 计数器独立推进到 636）。

换面巡检 `check_desc_enum_sync`（工具描述侧 enum 同步守卫，BUG-214 收口，r320 点名候选；r299 首跑后按轮换面复跑）
selftest **3 格 PASS**（干净 / 散文形 / 竖线形，闭集现读 `['critical','high','medium','low']`，闭集解析不到必自拒）
+ 实测 **PASS rc=0**（登记项描述未引用闭集外枚举值）。零漂移 `check_tools_sync` **183** /
`check_instruction_budget` **50440/65536** 均 rc=0。**无新发现（类型）、无新立账**（BUG-636 为 vq 外来账，
挂 owner 裁决，同 BUG-613~635 队列 +1）。Round C 三件维持过期不执行。

**FIST 闭环 T0r77 六步全链 rc=0**（wd-r321，ns watchdog，verify status=已完成、completed_by=wd-r321、
deliverable=本报告）。⚠️ **账实修正（诚实记账）**：T0r77 的 `publish` 描述发布早于本轮 numstat 复核，
误写「WIP 增长后静止第 3 轮（numstat 与 r318/r319/r320 逐字同）」——本轮复核实读 `bugs.md` 216/0（r320 记
208/0）后修正为「非冻结增长第 1 轮」。根因：首读 numstat 时只对了 r318~r320 提交信息里的聚合数「四件套核心
216+/2-」（=bugs 208 + improvement 7 + target 1），未逐文件比 r320 报告的 per-file 拆分（bugs.md 208/0），
把「核心三文件和」误当「bugs.md 单文件」。本报告与当日日志以复核后的实测为准。

## 巡检明细

1. **WIP 状态**（`git status --short` + `git diff --numstat`，本轮实读两次，均一致）：
   - `memory/bugs.md` **216+/0-**（r320 报告记 **208/0** ⇒ **+8 增长**）：新增 = vq P7-3 外来账 **BUG-636**
     （`[high] FIXED`，gnu/MinGW STATUS_ENTRYPOINT_NOT_FOUND）+ `FIXED(2026-11-15T15:40:40Z / BUG-636)`
     证据块 + 2 空行；mtime **2026-11-15 23:40**（晚于 r320 链 23:34，早于本轮 00:06）。
   - 其余 5 个已跟踪 WIP 文件**逐字同 r320**：`improvement-plan` 7/1、`target.md` 1/1、`README` 2/1、
     `run_guards` 9/0、`engine_circuit_test` 5/0 ⇒ R192 车道面**仍静止**（自 r318 后无再推进）。
   - 2 个 untracked（`check_mcpcf_db_isolation.py`、`pipeline_mode_loop.md`）未变。
   - 结论：**新 WIP 事件**（vq 外来账落 bugs.md），非 r318~r320 的 R192 车道增长 ⇒ **非冻结增长第 1 轮**。
   - 禁区处置：8 个 WIP 文件（含 bugs.md）**本轮零改、零提交**。

2. **换面巡检 `check_desc_enum_sync`**（r320「换面巡检轮换面」点名候选，本轮首轮到）：
   - 自检：`--selftest` **3 格 PASS rc=0**（干净不误红 / 散文形闭集外值必红〔抓住 bug_mark_status.status 列
     `CLOSED`，闭集 `['DUPLICATE','FALSE_POSITIVE','FIXED','OPEN']`〕/ 竖线形多值拆分 + 闭集外值必红〔抓住
     ocr_scan.subcmd 列 `exotic`〕）；
   - 实测：**PASS rc=0**（登记项全部一致，描述未引用闭集外的枚举值；闭集现读 `['critical','high','medium','low']`）。
   - 选面理由：r320 点名候选，严格参数面（未知旗标即拒 rc=2，R65 纪律），扫描面完全避开 WIP 面、读数干净。

3. **零漂移双检**：
   - `check_tools_sync` rc=0（server.mbt 注册 183，AGENTS/README/deliverable/scoring_rubric 对齐；R3b/R7 扫
     现状面 168 份、历史面豁免 25 份；R8 清单分组 19 组 ΣN=183 对表一致）；
   - `check_instruction_budget` rc=0（AGENTS.md 50440 / 65536 字节，全部章节可见）。

4. **Round C 三件**：维持过期不执行——BUG-527 摘 cc-link-flags 已 owner 否决（CI A/B 实证有害）、
   BUG-530 已 FIXED（3699f012a）、`check_usage_tool_count` 已注册（run_guards.py:175）；`src/**` +
   `run_guards.py` 仍 M ⇒ 队列仍锁。

5. **FIST 闭环 T0r77 六步全链一发收口**（wd-r321，ns watchdog）：
   - 链脚本 `temp/fist_r321_chain.sh`（沿 r320 稳健 TID 提取，逐行取能解析为 JSON 的那行，规避 r318 型
     `json.load(open(整文件))` 被 notice 行前缀破坏的坑）；
   - 六步 `publish / agent_acl_grant / claim / execute / submit / verify` 全 rc=0，TID=**T0r77**，verify 回执
     status=已完成、completed_by=wd-r321、deliverable=本报告（回盘 `temp/fist_r321_out/`）。
   - **账实修正**（见结果摘要）：T0r77 描述误写「静止第 3 轮」，发布早于复核，本轮报告/日志以实测修正。

## 资源消耗

- 判据 4 支（1 换面巡检 check_desc_enum_sync selftest + 实测 + 2 零漂移）+ WIP numstat 核验 2 支
  （首轮 + 矛盾后复核）+ bugs.md 增长行取证 1 支（`git diff` 末端 + mtime）+ FIST 六步链 1 发（后台串跑一次收全）；
- 本轮无子代理（巡检判据为轻量命令执行 + 只读核验 + FIST 链为网关记账，命令结果需指挥官亲阅终审，故直跑）。

## 任务分配记录

- **r321 FIST 闭环 T0r77 六步全链**（wd-r321，ns watchdog）：`temp/fist_r321_chain.sh`（稳健 TID 提取，
  六步全 rc=0），回盘 `temp/fist_r321_out/`（`1_publish..6_verify.txt` / `chain.log` / `task_id.txt`；
  verify status=已完成、completed_by=wd-r321）。

## 遗留风险

- **WIP 非冻结增长（vq 外来账第 1 轮）**：`memory/bugs.md` +8 = vq P7-3 外来账 **BUG-636**（`[high] FIXED`，
  gnu/MinGW），与 r318~r320 的 R192 车道增长**不同源**；同 **BUG-565 跨项目误落账持续模式**（vq 项目条目落本
  纯 MoonBit 仓，BUG 号与 FIST 自留临时 BUG-636 撞号）。**处置属 owner 裁决项**（搬移 vq 仓 / 带理由登记
  WHITELIST kind=foreign-adjudicated），指挥官不代行清理、不立新账。
- **四件套核心仍冻结**：除 bugs.md 的 vq 外来账外，其余 5 文件 R192 车道面仍逐字同 r320。
- **owner 裁决件**（同 r320，本轮无增减）：① WIP 四件套弃置 ③ r302 落账方式 ④ 外来账处置（BUG-613~635 +
  本轮 **BUG-636**，+1）⑤ BUG-636（FIST 自留临时号）known-red 登记口径（② check_mcpcf_db_isolation.py 缺
  执行面/未注册已被 R192 车道推进消解）。
- **FIST 链提取鲁棒性（r318 遗留）**：21 份 `temp/fist_r*_chain.sh` 同形脆弱提取；durable 修复在
  `scripts/fist.py`（notice→stderr / stdout 纯 JSON）或 tracked 链脚本模板稳健取 JSON 行，留专门轮次。本轮
  稳健提取是**临时绕过**，非 durable 修复。
- **账实一致性提示（本轮新增）**：巡检「静止/增长」判断不能只靠提交信息里的聚合数（「四件套核心 216+/2-」），
  必须**逐文件**比对上一轮报告的 per-file 拆分（r320 记 bugs.md 208/0）——聚合数「216」是核心三文件和
  （bugs 208 + improvement 7 + target 1），不是 bugs.md 单文件。本轮已踩中该坑，FIST T0r77 描述因此误写，
  建议后续轮次在 `git diff --numstat` 后**逐文件**列 per-file 拆分，与上一轮报告对照。

## 后续建议

- **最高优先仍为 BUG-636（FIST 自留临时号）**：待 `memory/bugs.md` WIP 解禁后专门轮次委派（含「加进
  `_tool_registry.consumers()` 收口格」最易漏环节）。
- **vq 外来账队列（BUG-613~636）owner 裁决**：同 BUG-565 持续模式，本轮 +1（BUG-636）。
- **FIST 链提取鲁棒性专门轮次修复**（口径见遗留风险）。
- **巡检判据补强**：换面巡检判读「WIP 静止/增长」时逐文件对表上一轮 per-file 拆分（本轮教训）。
- 继续按注册面轮换；Round C 三件维持过期（owner 已裁决面），唤醒轮继续非阻塞巡检。

## 超额内容

无。

## 来源

- `git status --short` / `git diff --numstat`（2026-11-16 本轮实读两次一致：bugs.md **216/0**、其余 5 文件逐字
  同 r320；`git diff memory/bugs.md` 末端 + mtime **2026-11-15 23:40** 取证增长行 = vq P7-3 外来账 BUG-636）
- `reports/2026-11-16-r320-wakeup-patrol.md`（r320 WIP 基线：bugs.md **208/0** + per-file 拆分 + 下一轮点名
  候选 check_desc_enum_sync）
- `python scripts/check_desc_enum_sync.py --selftest`（3 格 PASS）+ `python scripts/check_desc_enum_sync.py`
  （PASS rc=0）（本轮）
- `python scripts/check_tools_sync.py`（183 PASS）/ `python scripts/check_instruction_budget.py`
  （50440/65536 PASS）（本轮）
- `temp/fist_r321_out/`（六步回执 + `chain.log` + `task_id.txt`，TID=T0r77）
