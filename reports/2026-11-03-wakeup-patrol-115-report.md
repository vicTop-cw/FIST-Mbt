# 唤醒轮 115 巡检报告（2026-11-03）

## 结果摘要

本轮抓 **3 条真红**，其中 2 条已修复并验证转绿、1 条定性后出方案（不执行）：

| # | 判据 | 性质 | 处置 |
|---|---|---|---|
| 1 | `check_warning_ledger.py` rc=1 | **真红** — BUG-567 修复连带账实漂移 | 修 `omega_strong.mbt:177` `to_string()`→`to_owned()`；判据 50/50=100% 转绿 |
| 2 | `check_badge.py` rc=1 | **真红** — BUG-567 新增 2 反例后计数漂移 | 10 文件 41 处 `2030`→`2032` 同步；`check_test_sync` + `check_badge --fresh` 双绿 |
| 3 | `check_delivery_gap.py` rc=1 | **真实交付态** — 非口径误报 | 出方案待 owner 决策（见「遗留风险」） |

代码改动 1 处（`src/engine/omega_strong.mbt`），文档/徽章同步 10 文件 41 处。

## 复核记录

### 1. 并发 WIP 与队列入口

- 树面：11 文件 ` M`（含本轮改动），仅 `.workbuddy/` 未跟踪；HEAD=`ae6fa241`（轮 114 报告）。
- src/** 与 `scripts/run_guards.py` 门控确认解除（前轮 WIP 已落库）⇒ 按标准动作 3 走非阻塞巡检，
  先跑真实探针与判据电池独立复核，不复读报告空转。

### 2. 账本现状

- count=553（bug_list API）/ 557（grep 条目抬头）；OPEN 5 条：BUG-527 / 538 / 542 / 565 / 566。
- 逐条复核：**全部外部门控**，仓内无可修面（与轮 114 结论一致，连续第 4 轮）。
  - 527：卡在 owner 裁决（决策单 `reports/2026-11-02-bug527-native-link-decision-sheet.md`）；
    出路①已被 CI A/B 实证证伪并回滚（`e0ef45c5e`），出路③建议否决，唯一主行动=出路②上游 issue。
  - 538：前置=owner 在 Qoder 重连 fist-mbt MCP 连接器恢复服务面。
  - 542：需 owner 裁决 A（宿主同步脚本）/ B 档。
  - 565：owner 裁决 + B 半部署待审批。
  - 566：harness 侧根因，仓内不可修。

### 3. 真红 1：warning 台账漂移（已修）

- **判据**：`python scripts/check_warning_ledger.py` rc=1
  - L1 未覆盖 `(deprecated) src/engine/omega_strong.mbt:177`
  - L2 数量不符（实测 17 vs 台账 16）
- **根因**：BUG-567 修复（`d6ec706f0`）引入 `StringView::to_string()`（deprecated 面），
  未同步台账。
- **修复**：`src/engine/omega_strong.mbt:177` `part.to_string()` → `part.to_owned()`
  （同文件其他 to_owned 用例 :59/61/116/150/190/303/305/394/412 已是正确形态）。
- **验证**：判据转绿 50/50=100%；engine 测试 391/391 零回归；FMT_OK；moon 96 tasks up to date。

### 4. 真红 2：测试徽章/计数漂移（已修）

- **判据**：`python scripts/check_badge.py --fresh` rc=1 — README 徽章 `tests-2030%2F2030`
  ≠ 实际 `2032/2032`。
- **根因**：`d6ec706f0`（BUG-567 修复当轮）新增 2 条反例
  `preserve_plan_markers_repairs_prefix_marker_full_segment` / `parent_marker_not_duplicated`
  ⇒ 全量测试 2030→2032，而 README/文档面未同步。快照 `temp/pt27.log` 已 2032，README 落后。
- **修复**：按 `check_test_sync.py` 扫描面与豁免律同步 **10 文件 41 处** `2030`→`2032`：
  README.md 9 / README_EN.md 12 / AGENTS.md 6 / ARCHITECTURE.md 2 / README.mbt.md 2 /
  docs/SOP.md 2 / docs/agent-map.md 1 / docs/deliverable.md 2 / docs/known-boundaries.md 3 /
  scripts/scoring_rubric.md 2。**native 572/572 与历史记录面未误伤**（豁免律生效）。
- **验证**：
  - `check_test_sync.py` PASS「测试总数单一真源一致：实测 2032；扫描现状面」；残留 2030 跟踪面扫描无命中。
  - `check_badge.py --fresh` PASS「README tests-2032%2F2032 == 快照 temp/pt27.log @ 2026-11-03 19:16:33」；
    README + README_EN 均 PASS；自检 18 支对照全按预期。

### 5. 真红 3：交付断层（定性完成，方案待决策）

- **判据**：`python scripts/check_delivery_gap.py` rc=1 — 本地 main 领先 `origin/master`
  **185 提交 / 209 文件**，tip 不在任何远端分支上。
- **定性**：这是**真实交付态**，非 base 口径误报。证据链：
  - `origin/main == gitcode/main == cdb241acf`；本地 tip=`ae6fa241`。
  - `gitcode/main..main` = **8 提交**（纯快进）；`main..gitcode/main` = **1 提交**（`5ba7123d8`
    BUG-488/510 修复）⇒ **双向分叉**。
  - `git branch -r --contains <tip>` 空 ⇒ 8 提交未到达**任何**远端。
  - `--selftest` 8 格 RC=0 ⇒ 判据自身健康，读数可信。
- **历史口径**：轮 10/95 报告有「继续冻结」表述；轮 21 曾把同类读数记为「诊断级 — 预期行为」。
  本轮按仓库律（`run_guards.py:476` 已转回门禁格 `case`，非 `expected`）**不登记期望、不豁免**，
  交付动作留 owner。
- **既有交付通路**（读 `.github/workflows` + `scripts/pre-push` 核实）：
  - pre-push hook 挡 `refs/heads/main` + url 含 `gitcode` ⇒ **direct push to gitcode/main 被挡**，
    只允许指挥官 merge。
  - GitHub Actions「Sync from GitCode」：cron `0 */6 * * *`、workflow_dispatch、contents: write；
    clone gitcode master 检查 `.sync-to-github` 旗标；add-only 同步到 GitHub。
  - ⇒ 本仓既定交付方向是 **GitCode → GitHub**（单向），本地 main 是整合线。

### 6. 电池与探针

- **判据电池**（`run_guards.py`，后台跑）：**160 格 / 失败 3** —— 即上述 3 条真红
  （warning_ledger 已修、badge 已修、delivery_gap 待决策）。
- **全量测试**（`moon test --target js`，后台跑）：**2032/2032，RC=0**。
- **FIST 网关**：store_open 成功（182 工具）；MCP-SMOKE PASS。
- **格式门**：`moon fmt` + `check_fmt_gate.py` PASS（`moon fmt --check rc=0`）。
- **文档面守卫复跑**：`check_warning_ledger` / `check_instruction_budget` / `check_doc_surface` /
  `check_plugin_sync` 四支取终态读数（详见提交前复核）。

## 遗留风险

| 风险 | 等级 | 说明 |
|---|---|---|
| **交付断层（双向分叉）** | **高** | 本地 main 独有 8 提交（含 BUG-567 修复）未达任何远端；gitcode/main 独有 1 提交（BUG-488/510 修复）本地缺失 ⇒ 两侧各有独有面，合并需 cherry-pick，**pre-push hook 挡 direct push**，交付动作需 owner 决策通路（GitHub Actions 旗标 or 指挥官 merge） |
| BUG-527 | 中 | 等 owner 对决策单表态；CI 两 native 臂在 Linux 唯一在绿，本地 Windows 全量 native 必崩 |
| BUG-538 | 中 | 等 owner 重连 Qoder 连接器；判因面本地已实证 |
| BUG-542 | 中 | 宿主四副本落后，仓内会话不可写宿主目录（沙箱约束） |
| BUG-565 / 566 | 低 | owner 裁决 / harness 侧根因 |

## 后续建议

1. **交付断层（最优先）**：owner 明确交付通路——
   - 方案 A：在 gitcode/master 打 `.sync-to-github` 旗标，让 GitHub Actions 定时同步把本地整合面
     推到 GitHub（需先把本地 8 提交落到 gitcode 整合线）。
   - 方案 B：指挥官 merge（本地 main → gitcode/main 的 cherry-pick + 快进），走 pre-push hook
     允许的路径。
   - 需同步把 gitcode 独有 `5ba7123d8`（BUG-488/510）cherry-pick 回本地 main，避免两侧漂移。
2. **BUG-527**：owner 对决策单表态后即可派单（issue 文本已备）。
3. **BUG-565 B 半**：launcher 补丁部署待审批门放行。
4. **降低探活频率**：连续 4 轮零新发现（本轮 3 红均为账实漂移，非新缺陷），后续唤醒轮先复核账本
   现状再行动，不空转。

## 资源消耗

- 判据电池 1 轮（160 格，后台）、全量测试 1 轮（2032/2032，后台）、FIST 网关 1 次、
  探活/读数约 20 次、格式门 1 次。
- 无构建产物、无长驻进程。

## 来源

- 唤醒指令标准动作 1/3/4/5；`reports/2026-11-03-wakeup-patrol-114-report.md`（轮 114）；
  `reports/2026-11-02-bug527-native-link-decision-sheet.md`（BUG-527 决策单）；
  `scripts/check_delivery_gap.py` / `scripts/check_warning_ledger.py` / `scripts/check_badge.py`
  实跑读数；`memory/bugs.md` 账本；`.github/workflows` + `scripts/pre-push` 交付通路核实。
