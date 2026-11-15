# 轮 323 唤醒巡检报告

**日期**：2026-11-16
**轮次**：r323
**执行者**：wd-r323（FIST-Mbt-ExploreWatchdog）

## 结果摘要

**WIP 非冻结增长后静止第 4 轮（numstat 与 r322 逐字同）** —— `memory/bugs.md` 维持 **216/0**
（r322 后零再增长），其余 5 个已跟踪 WIP 文件（`improvement-plan` 7/1、`target.md` 1/1、`README` 2/1、
`run_guards` 9/0、`engine_circuit_test` 5/0）与 2 个 untracked（`check_mcpcf_db_isolation.py`、
`pipeline_mode_loop.md`）**逐字同 r322**；R192 车道自 r318 后持续停摆。`src/**` + `scripts/run_guards.py`
仍 M ⇒ **巡检分支**（Round C 三件仍锁）。

换面巡检 `check_host_installable`（deepseek-harness 宿主可装性守卫，扫描面 `plugins/**` 完全避开 WIP 面，
与 r321/r320/r319 的三把点名候选 + r322 store 接线守卫错开轮换）selftest **rc=0**（DSH 严格档相对路径 /
`timeout_ms` / `reconnect` 键名 / 未定义占位符必红、干净 DSH + 默认模板 + 宽松档不误红、输入面退化自拒、
字段白名单反解自真源）+ 实测 **PASS rc=0**（DSH manifest/patch 合规、宽松档 MCP JSON 合规、默认模板合法性
合规、`moon.mod` 版本 0.3.11；仅 3 处 `timeout_ms` 信息级 WARN 为既有已知项，由人终审）。零漂移
`check_tools_sync` **183** / `check_instruction_budget` **50440/65536** 均 rc=0。**无新发现（类型）、无新立账**
（vq 外来账 BUG-636 维持 owner 裁决，同 BUG-613~635 队列）。Round C 三件维持过期不执行。

**FIST 闭环 T0r79 六步全链 rc=0**（wd-r323，ns watchdog，verify status=已完成、completed_by=wd-r323）。

## 巡检明细

1. **WIP 状态**（`git status --short` + `git diff --numstat`，本轮实读，逐文件对表 r322）：
   - `memory/bugs.md` **216+/0-**（与 r322 报告记的 **216/0 逐字同** ⇒ **零增长**）；
   - 其余 5 个已跟踪 WIP 文件**逐字同 r322**：`improvement-plan` 7/1、`target.md` 1/1、`README` 2/1、
     `run_guards` 9/0、`engine_circuit` 5/0 ⇒ R192 车道面**仍静止**（自 r318 后无再推进）；
   - 2 个 untracked（`check_mcpcf_db_isolation.py` / `pipeline_mode_loop.md`）未变。
   - 结论：**WIP 非冻结增长后静止第 4 轮**（r321 记非冻结增长第 1 轮 = vq BUG-636 落账；r322 静止第 2 轮；
     r323 本轮 = 静止第 4 轮，r318 以来 R192 车道四件套核心无再推进）。
   - 禁区处置：8 个 WIP 文件（含 bugs.md）**本轮零改、零提交**。

2. **换面巡检 `check_host_installable`**（deepseek-harness 宿主可装性守卫，扫描面 `plugins/**` + `.mcp*.json`
   完全避开 WIP 面〔WIP 仅触及 `src/engine/engine_circuit_test.mbt` 等 6 个非插件文件〕；该守卫 ci.yml
   「Host-installable guard」步真门禁、电池面由 `discover_scripts` 自动收录，非漏接线）：
   - 自检：`--selftest` **rc=0**（DSH 严格档相对路径 / `timeout_ms` / `reconnect` 键名 / 未定义占位符必红、
     干净 DSH + 默认模板 + 宽松档不误红、输入面退化自拒、字段白名单反解自真源）；
   - 实测：**PASS rc=0**（DSH manifest/patch 严格档合规 + 宽松档 MCP JSON 合规 + 默认模板合法性合规 +
     `moon.mod` 0.3.11；3 处 `timeout_ms` 信息级 WARN——`是否改真源由人终审`，既有已知项，不判红）。
   - 选面理由：r321/r320/r319 三把点名候选（desc_enum / ns_write_gate / 上一批）+ r322 store 接线守卫均已
     轮换，`check_host_installable` 自 2026-11-01 patrol-round14 后未在唤醒轮复跑，扫描面与 WIP 面零交叠。

3. **零漂移双检**：
   - `check_tools_sync` rc=0（server.mbt 注册 183，AGENTS/README/deliverable/scoring_rubric 对齐；R3b/R7
     扫现状面 168 份、历史面豁免 25 份；R8 清单分组 19 组 ΣN=183 对表一致）；
   - `check_instruction_budget` rc=0（AGENTS.md 50440 / 65536 字节，全部章节可见）。

4. **Round C 三件**：维持过期不执行——BUG-527 摘 cc-link-flags 已 owner 否决（CI A/B 实证有害）、
   BUG-530 已 FIXED（3699f012a）、`check_usage_tool_count` 已注册（run_guards.py:175）；`src/**` +
   `run_guards.py` 仍 M ⇒ 队列仍锁。

5. **FIST 闭环 T0r79 六步全链一发收口**（wd-r323，ns watchdog）：
   - 链脚本 `temp/fist_r323_chain.sh`（沿 r321/r322 稳健 TID 提取，逐行取能解析为 JSON 的那行，规避 r318 型
     `json.load(open(整文件))` 被 notice 行前缀破坏的坑）；
   - 六步 `publish / agent_acl_grant / claim / execute / submit / verify` 全 rc=0，verify 回执
     status=已完成、completed_by=wd-r323、deliverable=本报告（回盘 `temp/fist_r323_out/`）。

## 资源消耗

- 判据 4 支（1 换面巡检 check_host_installable selftest + 实测 + 2 零漂移）+ WIP numstat 核验 1 支
  + FIST 六步链 1 发（后台串跑一次收全，本轮 node server 温热，链路快于 60s）；
- 本轮无子代理（巡检判据为轻量命令执行 + 只读核验 + FIST 链为网关记账，命令结果需指挥官亲阅终审，故直跑）。

## 任务分配记录

- **r323 FIST 闭环 T0r79 六步全链**（wd-r323，ns watchdog）：`temp/fist_r323_chain.sh`（稳健 TID 提取，
  六步全 rc=0），回盘 `temp/fist_r323_out/`（`1_publish..6_verify.txt` / `chain.log` / `task_id.txt`；
  verify status=已完成、completed_by=wd-r323）。

## 遗留风险

- **WIP 非冻结增长后持续静止（vq 外来账 BUG-636 落定后）**：`memory/bugs.md` 216/0 无再增长；vq 外来账
  **BUG-636**（`[high] FIXED`，gnu/MinGW）仍为 owner 裁决项（搬移 vq 仓 / 带理由登记 WHITELIST
  kind=foreign-adjudicated），指挥官不代行清理、不立新账。
- **四件套核心仍冻结**：5 个已跟踪 WIP 文件 R192 车道面仍逐字同 r322（自 r318 后无再推进）。
- **owner 裁决件**（同 r321/r322，本轮无增减）：① WIP 四件套弃置 ③ r302 落账方式 ④ 外来账处置
  （BUG-613~636）⑤ BUG-636（FIST 自留临时号）known-red 登记口径（② check_mcpcf_db_isolation.py
  缺执行面/未注册已被 R192 车道推进消解）。
- **FIST 链提取鲁棒性（r318 遗留）**：22 份 `temp/fist_r*_chain.sh` 同形脆弱提取；durable 修复在
  `scripts/fist.py`（notice→stderr / stdout 纯 JSON）或 tracked 链脚本模板稳健取 JSON 行，留专门轮次。本轮
  稳健提取是**临时绕过**，非 durable 修复。
- **check_host_installable `timeout_ms` 信息级 WARN**：3 处（`.mcp.json` / `.mcp.dev.json` /
  `plugins/claude/.mcp.json`）用 `timeout_ms`，部分客户端按自身 schema 忽略；是否统一改 `toolCallTimeoutMs`
  由人终审，本轮不判红、不立新账（既有已知项，2026-10-10 terminal-review 已记录同形）。

## 后续建议

- **最高优先仍为 BUG-636（FIST 自留临时号）**：待 `memory/bugs.md` WIP 解禁后专门轮次委派（含「加进
  `_tool_registry.consumers()` 收口格」最易漏环节）。
- **vq 外来账队列（BUG-613~636）owner 裁决**：同 BUG-565 持续模式。
- **FIST 链提取鲁棒性专门轮次修复**（口径见遗留风险）。
- 继续按注册面轮换；Round C 三件维持过期（owner 已裁决面），唤醒轮继续非阻塞巡检。

## 超额内容

无。

## 来源

- `git status --short` / `git diff --numstat`（2026-11-16 本轮实读：bugs.md **216/0**、其余 5 文件逐字同
  r322；2 untracked 未变）
- `reports/2026-11-16-r322-wakeup-patrol.md`（r322 WIP 基线：bugs.md **216/0** + per-file 拆分）
- `python scripts/check_host_installable.py --selftest`（rc=0）+ `python scripts/check_host_installable.py`
  （PASS moon.mod 0.3.11 rc=0）（本轮）
- `python scripts/check_tools_sync.py`（183 PASS）/ `python scripts/check_instruction_budget.py`
  （50440/65536 PASS）（本轮）
- `temp/fist_r323_out/`（六步回执 + `chain.log` + `task_id.txt`，TID=T0r79，verify status=已完成）
