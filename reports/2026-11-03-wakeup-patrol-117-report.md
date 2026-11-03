# 唤醒轮 117 巡检报告（2026-11-03）

## 结果摘要

本轮**零新代码缺陷**：CI 轨守卫批 **11 面全 PASS**（轮 116 只跑了电池 JS 轨），
探针三面绿/一面环境态，账本形态 PASS。

两件值得记录的事：

1. **上轮挂起的遗留候选「AGENTS 摘要面漂移 2 处」证伪** —— `wt_create` /
   `agent_register_key` 根本不在 `AGENTS.md`，而在 R212 搬出的
   `docs/AGENTS-mcp-inventory.md`（L135 / L168），逐字核对与真源
   `src/server/server.mbt` 的 inputSchema 一致（前者 5 参数、后者 8 参数）
   ⇒ **无漂移，不立账**。挂起项清空。
2. **自造脏面 + 收口**：探网关时误用 `report_bug` 直打真账本，写入 **BUG-568**。
   按 append-only 纪律**不静默删除**，登记 `FALSE_POSITIVE` + 补更正行；
   按 AGENTS 硬规则「改账本或计数面 ⇒ 同批重投影插件态」重跑 `gen_plugins.py`
   ⇒ **cl7 PASS**。

| # | 项 | 性质 | 处置 |
|---|---|---|---|
| 1 | AGENTS 摘要面漂移候选 | **证伪**（条目在清单文件、与真源一致） | 不立账，挂起项清空 |
| 2 | BUG-568（探针误写真账本） | **操作面失误**（非代码缺陷） | FALSE_POSITIVE + 同批重投影 |
| 3 | CI 轨守卫 11 面 | 全 PASS | 无新增红 |
| 4 | mcp_smoke / 账本形态 / usage 计数 / 电池文档 | PASS | — |
| 5 | OFM 18326 down | 环境态（服务未起） | 非回归，同轮 111/113/114/116 |
| 6 | 交付断层 ahead=188 / 211 | 真实交付态（owner 门控） | +1 = 轮 116 报告提交 |

## 复核记录

### 1. 并发 WIP 与队列入口

- 树面：工作树净，仅 `.workbuddy/`（未跟踪，他人 WIP 面，**未触碰**）。
- HEAD=`0aeac742`（轮 116 报告）；`src/**` 与 `scripts/run_guards.py` 门控确认解除。
- 按标准动作第 3 条走非阻塞巡检。

### 2. Round C 队列复核（连续第 6 轮死态）

- **① BUG-527 治本**：**已改判**，出路①被 CI A/B 实证证伪并回滚（`e0ef45c5e`）。
  带 link 的 `8da9f920b` 两条 native 臂绿，摘 link 的 `d43a06a28` 测试 exe 链接即死
  `undefined reference to sqlite3_*` ⇒ 两个 moon 世代语义相反。
  唯一主行动 = 出路②（上游 issue），等 owner 表态。
- **② BUG-530 修复**：**已 FIXED**（`3699f012a`）。
- **③ run_guards.py 注册 check_usage_tool_count**：**已落地**（`scripts/run_guards.py:175`）。
- ⇒ 三项全部不再是可执行项。

### 3. 遗留候选证伪：AGENTS 摘要面漂移

上轮（压缩前）挂起一项待判：`AGENTS.md` 的工具表条目 `wt_create` / `agent_register_key`
是否构成「摘要漂移」。本轮逐面核实：

| 面 | 读数 |
|---|---|
| `AGENTS.md` 明文 | **无** `wt_create` / `agent_register_key`（`grep` 零命中，全文 421 行 / 50,660 字节） |
| 实际所在 | `docs/AGENTS-mcp-inventory.md`（R212 搬出的清单，L135 / L168） |
| 与真源对表 | `wt_create` = 5 参数（project_dir/path/branch/detach/timeout_ms）**逐字一致**；`agent_register_key` = 8 参数（agent_id/namespace/pubkey_hex/challenge/proof_sig/rotate_challenge/rotate_sig/by）**逐字一致** |
| 编码 | `docs/AGENTS-mcp-inventory.md` = UTF-8 无 BOM，54,051 字节 / 283 行（前次工具输出乱码为显示层问题，非文件缺陷） |

⇒ **证伪，无漂移，不立账**。另：`python scripts/check_instruction_budget.py` =
`PASS`（AGENTS.md 50,239 字节 / 预算 65,536，全部章节可见）。

### 4. CI 轨守卫批（轮 116 未覆盖面）

| 守卫 | 读数 |
|---|---|
| check_mcp_stdio_purity | PASS |
| check_release_asset_names | PASS（R1~R14 全覆盖） |
| check_demo_isolation | PASS（36 个 spawn `serve` 全把 FIST_DB_PATH 交给子进程） |
| check_entry_paths | PASS（R1 退役入口引用 0 / R2 裸 serve 启动器 0 / R3 裸相对产物读 0） |
| check_ps_encoding | PASS（10 个 .ps1 全带 BOM 或纯 ASCII） |
| check_store_tables_wired | PASS（32 表 = 31 有写入点 + 1 显式预留 runs） |
| check_publish_payload | PASS（1935 文件，未被 git 跟踪 0） |
| check_model_auth_no_key | PASS（143 文件无凭据形状） |
| check_host_installable | PASS |
| check_skill_inject | PASS（lookup_injected_assets_in 按 goal/note 子串匹配） |
| check_scripts_index | PASS |

### 5. 自造脏面 + 收口（本轮唯一代码面动作）

- **事件**：探 FIST 网关链路时执行
  `python scripts/fist.py call report_bug --project_dir . --summary probe-test-delete-me`，
  **该命令是真写入**，落账 `BUG-568`（非探针沙箱）。
- **处置（按账本记账规则）**：
  - 账本**叙述面只追加、不改写、不删除**（抹掉证伪材料 = 把自己改写成「一直是对的」）
    ⇒ **不静默删除**，登记 `FALSE_POSITIVE`；
  - `bug_mark_status` 置 `FALSE_POSITIVE`，证据行写明「操作面失误、非代码缺陷：
    summary 接受自由文本是设计，不设缺陷单」，并引同族前例 BUG-250/251/414/415；
  - 补一行**更正**：证据文本里被 shell 反引号当命令执行而吞掉的调用面原文补回。
- **强制联动**：AGENTS.md 硬规则「改 `memory/bugs.md` 或任何计数面 ⇒ 同批重投影插件态」
  ⇒ `python scripts/gen_plugins.py` 重跑，**9 文件**计数传播（552→553 条 / BUG-1~567→568 /
  26→27 误报），逐文件 diff 核对**全为纯计数传播、无内容夹带**。
- **验证**：`python scripts/check_plugin_sync.py`（cl7）**PASS**
  （4 宿主 / 64 生成文件 / 182 工具 / v0.3.11）；`check_bug_ledger_shape.py` **PASS**。

### 6. 探针

- **MCP 冒烟**（`scripts/mcp_smoke.py`）：**PASS** —— tools/list 182 工具、issue_scan 命中 2 条、
  publish T0r64、get T0r64 [待领取]。
- **账本形态**（`check_bug_ledger_shape.py`）：**PASS**（只查形态不查事实）。
- **USAGE 计数**（`check_usage_tool_count.py`）：**PASS** —— 真源 182 工具 × §6 表 83 行
  参数名集零漂移，豁免 0 条。
- **电池文档**（`check_battery_count_doc.py`）：**PASS** —— rulers=153 ci=48 battery=113
  missing=0 gate=125 exempt=23 unclassified=7。
- **OFM 端点**（`check_ofm_endpoint.py`）：`http://127.0.0.1:18326/v1/models` → **down**
  （WinError 10061 拒绝连接）—— **环境态**，OFM 服务未起，非回归（轮 111/113/114/116 同读数）。
- **交付断层**（`check_delivery_gap.py`）：`main`/`HEAD` = `0aeac742`，ahead=**188**、files=**211**；
  较轮 116 的 187/210 **+1** = 轮 116 报告提交 ⇒ **读数稳定，无新变化**，仍是 owner 门控的双向分叉。

### 7. 账本现状

- **OPEN 5 条**：BUG-527 / 538 / 542 / 565 / 566，**逐条复核全外部门控**（连续第 6 轮）。
  - 527：owner 裁决决策单（`reports/2026-11-02-bug527-native-link-decision-sheet.md`）。
  - 538：owner 在 Qoder 重连 fist-mbt MCP 连接器。
  - 542：owner 裁决 A/B 档（仓内会话不可写宿主目录，沙箱约束）。
  - 565：owner 裁决 A 半 + B 半（launcher 补丁）部署待审批门。
  - 566：harness 侧根因，仓内不可修。
- **本轮新增 1 条**：BUG-568（FALSE_POSITIVE，自造脏面登记）⇒ 计数 552→553、误报 26→27。
- ⇒ 仓内无可修面，零新实质缺陷。

## 遗留风险

| 风险 | 等级 | 说明 |
|---|---|---|
| **交付断层（双向分叉）** | **高** | 本地 main 领先远端 188 提交 / 211 文件，tip 不在任何远端分支；gitcode/main 另有本地缺失提交 ⇒ 合并需 cherry-pick，pre-push hook 挡 direct push，交付通路需 owner 决策 |
| **explore-r3 幻影任务** | 低 | 3+1 条任务描述为已失效的 Round C 旧口径（本轮复核仍在），无人值守轮会反复认领；方案 A/B/C 待 owner 裁决（轮 116 §6） |
| BUG-527 | 中 | 等 owner 对决策单表态；CI 两 native 臂在 Linux 唯一在绿，本地 Windows 全量 native 必崩 |
| BUG-538 | 中 | 等 owner 重连 Qoder 连接器；判因面本地已实证 |
| BUG-542 | 中 | 宿主四副本落后，仓内会话不可写宿主目录（沙箱约束） |
| BUG-565 / 566 | 低 | owner 裁决 / harness 侧根因 |

## 后续建议

1. **交付断层（最优先）**：owner 明确交付通路（轮 115 §后续建议 1 的方案 A/B）。
2. **幻影任务**：按轮 116 §6 方案 A/B/C 择一，建议 C（零风险 + 记账）。
3. **BUG-565 B 半**：launcher 补丁部署待审批门放行。
4. **降低探活频率**：连续 6 轮零新实质缺陷（轮 115 的 3 红、轮 116 的 1 红均为账实/口径漂移），
   后续唤醒轮先复核账本现状再行动，不空转。
5. **探针纪律**：本轮自造脏面的教训 —— 探 FIST 网关时**先 `--help` / `list-tools` 反解参数面**，
   不凭猜测拼 `call` 参数（`report_bug` 是**真写入**工具，无 dry-run）。建议后续把
   「探测用命名空间/只读工具」与「真写入工具」在 SKILL 清单里显式分级。

## 资源消耗

- CI 轨守卫批 1 轮（11 面，后台）、探针 4 次、账本/计数/电池判据 3 次、
  生成器 +1 轮、cl7 复跑 1 次、FIST 网关读数 3 次。
- 代码改动：`memory/bugs.md` +6 行（自造条目 + 更正）、9 个插件投影文件纯计数传播。
- 无构建产物、无长驻进程。

## 来源

- 唤醒指令标准动作 1/3/4/5；`reports/2026-11-03-wakeup-patrol-116-report.md`（轮 116）；
- `reports/2026-11-02-bug527-native-link-decision-sheet.md`（BUG-527 决策单）；
- `memory/bugs.md` 账本（记账规则 + BUG-527/538/542/565/566/568）；
- `AGENTS.md` / `docs/AGENTS-mcp-inventory.md` / `src/server/server.mbt`（参数面对表）；
- `scripts/run_guards.py` / `scripts/gen_plugins.py` / `scripts/check_plugin_sync.py` /
  `scripts/check_bug_ledger_shape.py` / `scripts/check_usage_tool_count.py` /
  `scripts/check_battery_count_doc.py` / `scripts/check_instruction_budget.py` /
  `scripts/mcp_smoke.py` / `scripts/check_ofm_endpoint.py` /
  `scripts/check_delivery_gap.py` 实跑读数；
- FIST 网关 `task_triage` / `report_bug` / `bug_mark_status` / `bug_list` 实回。
