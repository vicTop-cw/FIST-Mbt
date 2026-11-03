# 唤醒轮 116 巡检报告（2026-11-03）

## 结果摘要

本轮**零新红、零代码改动**：判据电池 160 格唯一失败仍是 `check_delivery_gap.py`
（轮 115 已定性的双向分叉，owner 门控），全量 JS 测试 2032/2032 RC=0，MCP/宿主探针两绿。

新发现一条**非代码缺陷**：FIST 自驱池 `explore-r3` 残留 3 条**幻影任务**
（T0.2.1 / T0.2.2 / T0.3.2），其描述是**已被后续实证取代的 Round C 旧口径**。
属记账面卫生问题，已给出定性，不擅自归档（不可逆操作）。

| # | 项 | 性质 | 处置 |
|---|---|---|---|
| 1 | `check_delivery_gap.py` rc=1 | **真实交付态**（轮 115 已定性） | 读数复核一致，维持 owner 门控 |
| 2 | `explore-r3` 池内 3 条幻影任务 | **记账面卫生**（非缺陷） | 定性 + 出方案，不擅自归档 |
| 3 | 判据电池 160 格 / 失败 1 | 即 #1 | 无新增红 |
| 4 | 全量 JS 测试 2032/2032 RC=0 | 零回归 | — |
| 5 | mcp_smoke PASS / check_host_installable PASS | 探针健康 | — |

## 复核记录

### 1. 并发 WIP 与队列入口

- 树面：工作树净，仅 `.workbuddy/`（未跟踪，他人 WIP 面，**未触碰**）。
- HEAD=`3ecefcc9`（轮 115 报告）；`src/**` 与 `scripts/run_guards.py` 门控确认解除。
- 按标准动作第 3 条走非阻塞巡检，先跑真实探针与判据电池独立复核。

### 2. Round C 队列复核（连续第 5 轮死态）

- **① BUG-527 治本**：**已改判，出路①被 CI A/B 实证证伪并回滚**（`e0ef45c5e`）。
  带 link 的 `8da9f920b` 两条 native 臂绿，摘 link 的 `d43a06a28` 测试 exe 链接即死
  `undefined reference to sqlite3_*` ⇒ 两个 moon 世代语义相反，单侧整改在另一侧必红。
  唯一主行动 = 出路②（上游 issue），等 owner 表态（决策单
  `reports/2026-11-02-bug527-native-link-decision-sheet.md`）。
- **② BUG-530 修复**：**已 FIXED**（`3699f012a`，三处修复 + 全量回归 2004/2004）。
- **③ run_guards.py 注册 check_usage_tool_count**：**已落地**（`scripts/run_guards.py:175`
  `case("check_usage_tool_count.py")` + USAGE §6.15 已补齐 + battery 锚点已补登）。
- ⇒ 三项全部不再是可执行项。轮 112 已建议「勿按 Round B 报告『遗留风险』节逐字执行，
  先复核账本现状」——本轮再次确认该建议成立。

### 3. 账本现状

- OPEN 5 条：BUG-527 / 538 / 542 / 565 / 566，**逐条复核全外部门控**（连续第 5 轮）。
  - 527：owner 裁决决策单（见上）。
  - 538：owner 在 Qoder 重连 fist-mbt MCP 连接器。
  - 542：owner 裁决 A/B 档（仓内会话不可写宿主目录）。
  - 565：owner 裁决 + B 半部署待审批。
  - 566：harness 侧根因，仓内不可修。
- ⇒ 仓内无可修面，零新账。

### 4. 判据电池与全量测试

- **判据电池**（`scripts/run_guards.py`）：**160 格 / 失败 1 / SKIP 0**。
  唯一失败 = `check_delivery_gap.py`（见 §5）。
- **全量 JS 测试**（`python scripts/moon_test_env.py --target js`）：
  **Total tests 2032 / passed 2032 / failed 0**，exit 0 —— 零回归。
- **格式门**：未触发（本轮无 `.mbt` 改动）。

### 5. 唯一红复核：交付断层（维持 owner 门控）

- `python scripts/check_delivery_gap.py` 读数：
  - `main` = `3ecefcc9`，ahead=**187**、files=**210**、pushed=False ✗
  - `master` = `ae1d410b`，ahead=0、pushed=True ✓
  - HEAD = `3ecefcc9`（同 main）
- 与轮 115 读数（ahead=185 / files=209）相比 +2，增量即轮 115 报告与日志两笔提交
  ⇒ **读数稳定，无新变化**，仍是轮 115 定性的双向分叉（`origin/main == gitcode/main
  == cdb241acf`，本地 tip 不在任何远端分支）。
- 既定交付通路核实（轮 115 已核）：pre-push hook 挡 `refs/heads/main` + gitcode url，
  只允许指挥官 merge；GitHub Actions「Sync from GitCode」单向 GitCode→GitHub。
  ⇒ **交付动作需 owner 决策通路**，本轮不擅自执行不可逆操作。

### 6. 新发现：`explore-r3` 池内 3 条幻影任务（定性，不擅自归档）

- `python scripts/fist.py call task_triage --namespace explore-r3` → count=3：
  T0.2.1（易）/ T0.2.2（中）/ T0.3.2（中），另有 T0.1.2 已被 `selfdrive_pick_next` 认领。
- **三条描述逐字相同**，均为 Round C 打包：① BUG-527 治本（13 份库包摘 link）
  ② BUG-530 修复（播种落盘）③ run_guards.py 注册 check_usage_tool_count。
- **三条全部已被后续实证取代**：① 被 CI A/B 证伪改判（见 §2）；② 已 FIXED；③ 已落地。
  ⇒ 这是**任务池与账本漂移**（描述写于 2026-11-01T01:16:56Z，早于三项收口），
  不是代码缺陷，也**不是新缺陷**——但会让**无人值守自驱轮反复认领已失效任务**，
  属「同一规则多份实现」的漂移面，应记账。
- **不擅自处置的理由**：`archive` 是**不可逆**操作（`Task::reopen` 对 Archived 明确拒绝，
  见 `src/core/core_task.mbt:547`；BUG-471 因此给它补了 ACL 门）。归档会丢掉历史 id 与
  子树关联，且这批任务由 `explore-r3` 流水线产生，属**他人 WIP 面**（本轮纪律：
  另一 agent 的 WIP 文件绝不碰）。⇒ **只出方案，等 owner 裁决**。

**处置方案（择一，等 owner）**：

| 方案 | 动作 | 代价 |
|---|---|---|
| A | `archive`（force=false）逐条归档 T0.2.1/T0.2.2/T0.3.2 + 已认领的 T0.1.2 | 不可逆，丢历史 id/子树 |
| B | `reopen_task` 重开并改写描述为「Round C 三项已收口，本单仅作账实记录」 | 保留 id，但描述改写需工具支持 |
| C | 保留现状，仅在账本记一条「幻影任务」条目，无人值守轮认领时按账本判废 | 零风险，但池面继续脏 |

**建议**：C 优先（零风险 + 记账），A 次之（需 owner 明确授权不可逆归档）。

### 7. 探针

- **MCP 冒烟**（`scripts/mcp_smoke.py`）：**PASS** —— tools/list 182 工具、issue_scan 命中 2 条、
  publish T0r63、get T0r63 [待领取]。
- **宿主可装性**（`scripts/check_host_installable.py`）：**PASS** —— DSH manifest/patch
  （严格档）合规；宽松档 MCP JSON 合规；默认模板合法性合规；moon.mod 版本 0.3.11。
  三条 `timeout_ms` WARN 为信息级（部分客户端按自身 schema 忽略该字段，是否改真源由人终审）。
- **OFM 端点**（`check_ofm_endpoint.py`）：rc=1 `down`（`127.0.0.1:18326` 拒绝连接）——
  **环境态**，OFM 服务未起，非回归（轮 111/113/114 同读数）。

## 遗留风险

| 风险 | 等级 | 说明 |
|---|---|---|
| **交付断层（双向分叉）** | **高** | 本地 main 领先 origin/master 187 提交 / 210 文件，tip 不在任何远端分支；gitcode/main 另有 1 提交本地缺失 ⇒ 合并需 cherry-pick，pre-push hook 挡 direct push，交付通路需 owner 决策 |
| **explore-r3 幻影任务** | **低** | 3+1 条任务描述为已失效的 Round C 旧口径，无人值守轮会反复认领；已出方案 A/B/C 待 owner 裁决 |
| BUG-527 | 中 | 等 owner 对决策单表态；CI 两 native 臂在 Linux 唯一在绿，本地 Windows 全量 native 必崩 |
| BUG-538 | 中 | 等 owner 重连 Qoder 连接器；判因面本地已实证 |
| BUG-542 | 中 | 宿主四副本落后，仓内会话不可写宿主目录（沙箱约束） |
| BUG-565 / 566 | 低 | owner 裁决 / harness 侧根因 |

## 后续建议

1. **交付断层（最优先）**：owner 明确交付通路（方案 A：gitcode/master 打 `.sync-to-github`
   旗标走 GitHub Actions 定时同步；方案 B：指挥官 merge，本地 8+ 提交 cherry-pick 到
   gitcode/main 后快进；需同步把 gitcode 独有 `5ba7123d8` cherry-pick 回本地）。
2. **幻影任务**：按 §6 方案 A/B/C 择一，建议 C（零风险）或 A（需授权）。
3. **BUG-527**：owner 对决策单表态后即可派单（issue 文本已备）。
4. **BUG-565 B 半**：launcher 补丁部署待审批门放行。
5. **降低探活频率**：连续 5 轮零新发现（轮 115 的 3 红均为账实漂移，非新缺陷），
   后续唤醒轮先复核账本现状再行动，不空转。

## 资源消耗

- 判据电池 1 轮（160 格，后台）、全量测试 1 轮（2032/2032，后台）、
  MCP/宿主探针 2 次、FIST 网关读数 5 次、判据复核 2 次。
- 无构建产物、无长驻进程、无代码改动。

## 来源

- 唤醒指令标准动作 1/3/4/5；`reports/2026-11-03-wakeup-patrol-115-report.md`（轮 115）；
  `reports/2026-11-02-bug527-native-link-decision-sheet.md`（BUG-527 决策单）；
  `scripts/run_guards.py` / `scripts/check_delivery_gap.py` / `scripts/mcp_smoke.py` /
  `scripts/check_host_installable.py` 实跑读数；`memory/bugs.md` 账本；
  FIST 网关 `task_triage` / `selfdrive_pick_next` / `get` 实回；
  `src/server/server.mbt`（archive/retry/selfdrive_pick_next schema）；
  `src/core/core_task.mbt:547`（Archived 不可 reopen）。
