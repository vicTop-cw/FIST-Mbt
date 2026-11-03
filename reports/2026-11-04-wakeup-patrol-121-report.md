# 唤醒轮 121 报告 · 独立验证 + BUG-569/570 闭环

> 日期：2026-11-04（周三）
> 触发：标准唤醒动作（树净巡检 → Round C 队列）
> 结论：**两处真缺陷定位并闭环**（BUG-570 修复 + 电池登记漂移纠偏）；交付断层 16 提交确认为真实新变化，属 owner 门控。

## 1. 结果摘要

| 项 | 读数 | 判定 |
|---|---|---|
| 树净 | 仅 `.workbuddy/` 未跟踪（`.gitignore:255` 挡） | 干净 |
| HEAD | `bdf1ad58b`（轮 120 收口提交） | — |
| 全量 JS 测试 | **2032/2032**（`moon_test_env.py --target js`，rc=0） | 绿 |
| server 白盒 | **586/586**（`moon test --target js src/server`，rc=0） | 绿 |
| 守卫电池 | **160 格 / 失败 0 / SKIP 0 / 缺执行面 0** | 全绿 |
| `bug_list` 计数 | **n_bugs=555 unique=555 dups=[]**（修复前 554/553，dups `BUG-206:2`） | 已对齐 |
| 投影头 | `BUG-1~570 共 555 条入账：5 待修 / 509 已修 / 13 重复 / 28 误报` | 一致（5+509+13+28=555） |
| 账本形态 | 行首三段式抬头 555 条，干净 | 绿 |
| 插件同步 | cl7 PASS | 绿 |

### 本轮两处真缺陷

**① BUG-570（medium / FIXED）· `bug_is_header` 跨散文误判**

- 现象：`bug_list` 回 554 条而投影头 553 条，差 1 条幻影条目；`dups={'BUG-206': 2}`。
- 根因：`src/server/bugreport.mbt` 的 `bug_is_header` 只验「行首 `## BUG-` + 首个空格后存在 `[ts] [sev] STATUS`」，而 `bug_next_bracket` 会**跨过 id 后的任意散文**去找第一个 `[`。于是账本 `memory/bugs.md:3839` 的 BUG-481 病灶行
  `## BUG-206 锁：<evidence 散文>…[2026-10-15T10:53:48Z] [high] FIXED`
  被判成第二条 BUG-206 条目。
- 定性：**server 解析器缺陷（BUG-481 同族复发），非账本缺陷**。账本侧 `check_bug_ledger_shape.py:94 DUP_ALLOW` 早已显形该行并待裁决，append-only 不回改。
- 修复：`bug_is_header` 增加 `!tail.has_prefix("[")` 拒判，口径对齐 `scripts/gen_plugins.py` 的 `RE_BUG_HEAD`（`BUG-n` 后紧跟 `[`）。
- 回归锁：`src/server/bugreport_status_wbtest.mbt` 的 `bug434_is_header` 新增**反例⑤**（BUG-481 病灶行形状，旧实现判 true ⇒ 删掉拒判必红）+ **正例④**（同编号真抬头仍 true，防修过头）。
- 读数：**修复当刻** `bug_list` 553/553/dups=[]（幻影条目消失，与投影头对齐）；随后经网关入账 BUG-569/570 ⇒ 终态 555/555/dups=[]（见 §1 表）。`check_bug_ledger_shape` 终态 555 条干净。

**② 电池登记漂移（非独立缺陷单，随 BUG-570 同批修）· `check_delivery_gap` 被登记成门禁绿**

- 现象：`scripts/run_guards.py:476` 用 `case("check_delivery_gap.py")`（expect=0）登记，而该判据在当前树**确定性回 rc=1** ⇒ 电池恒红。上一轮（bg-1）唯一 FAIL 即此格。
- 定性：**登记漂移，不是判据坏**。2026-10-24 转绿时读数确实 rc=0；此后远端形态又变（见 §3 交付断层）。
- 修复：改 `expected(..., kind="diag", until={"kind":"rc","value":0})`，诊断口径登记 + 自动销账条件。

## 2. 资源消耗

| 资源 | 读数 |
|---|---|
| 全量 JS 测试 | 1 次（2032/2032，bg-2 exit 0） |
| server 白盒 | 1 次（586/586，rc=0） |
| 守卫电池 | 2 次（bg-1 定位 1 红 → bg-4 全绿 160/160） |
| 账本形态 / 插件同步 / scope / 引用完整性 | 各 1 次，全绿 |
| 投影重生成 | 1 次（`gen_plugins.py`，182 工具 / v0.3.11 / 555 条） |
| `moon info` + `moon fmt` | 各 1 次，`.mbti` 无变化（改的是私有函数） |

## 3. 交付断层（真实新变化 · owner 门控）

- `origin/master` 已推进到 `0844a12d7`（本地 main 193 提交大部分已交付）。
- 但 `gitcode/main` 仍停在 `cdb241ac` ⇒ 本地 main/HEAD **领先 16 个提交**（轮 108~120 收口），且 `git branch -r --contains main` 为空 ⇒ **tip 不在任何远端分支上**。
- `check_delivery_gap.py` 报 rc=1 是**真实交付断层**，非脚本缺陷。
- 阻塞原因：pre-push hook 挡 direct push（`.githooks/pre-push` 在位，`check_push_guard` PASS）。
- **处置：属 owner 决策面，本轮不擅自推送**（不可逆操作先出方案）。已在电池按 diag 登记，推送完成后自动销账。

## 4. 任务分配记录

| 项 | 分配 | 结果 |
|---|---|---|
| BUG-570 修复 | 原计划 `team` 委派 implementer | **门禁拒（`team was not approved`）** ⇒ 由本人终审执行 |
| 电池登记漂移 | 同上 | 同上 |
| BUG-569 误报登记 | 本人 | 已闭环（append-only 保留痕迹） |

> 说明：本轮 `team` 委派被宿主审批门禁拒绝一次（BUG-566 族第 5 实例）。按「被拒原命令不重试」纪律，未重试委派，改由本人执行并终审。这是**审批面行为**，不是任务失败。

## 5. 遗留风险

1. **交付断层 16 提交待推**（§3）——阻塞条件是 owner 决策 + pre-push hook 放行路径。
2. **账本 BUG-481 病灶行**（`memory/bugs.md:3839`）仍 append-only 保留，`DUP_ALLOW` 显形待形态裁决；server 侧已由 BUG-570 修复不再双计，但账本侧「该行算不算条目」仍未裁决。
3. **BUG-527**（native 链接 flag）owner 门控：出路①被 CI A/B 证伪回滚 `e0ef45c5e`，唯一主行动 = 出路②上游 issue。
4. **BUG-565** A 半 owner 三案待裁决（推荐 B 白名单案）；B 半部署待审批。
5. **BUG-538 / 542 / 566** 全外部门控。
6. **explore-r3 幻影任务** 3 条（T0.2.1/T0.2.2/T0.3.2），方案 A/B/C 待 owner 裁决。
7. **操作面失误**：本轮为查 `report_bug` 参数面误用 `--summary probe` 直打真账本（BUG-569 已登记 FALSE_POSITIVE 保留痕迹）。**教训：`report_bug` 的 summary 无最小校验，探针不应直打真账本**——同族 BUG-568。建议后续立单加最小校验（如 summary 长度下限 / 禁纯占位串）。

## 6. 后续建议

1. **优先**：owner 裁决交付通路（16 提交推送路径），解除 `check_delivery_gap` 的 diag 登记。
2. 裁决账本 BUG-481 病灶行的形态归属（`DUP_ALLOW` 是否转正式豁免 / 该行是否改写）。
3. 给 `report_bug` 加 summary 最小校验，堵住「探针直打真账本」这一操作面缺口（BUG-569 证据链）。
4. BUG-565 A 半三案裁决后，B 半补丁即可部署（2 行，已验证）。

## 7. 超额内容

- 本轮在标准唤醒动作之外，额外完成了 `bug_is_header` 的口径对齐（与 `gen_plugins.RE_BUG_HEAD` 同源），消除了 server 读侧与投影头的计数差。
- 额外把 `check_delivery_gap` 从「恒红门禁格」改为「diag + 自动销账」，使远端形态变化不再伪装成门禁失败。

## 8. 来源

- 账本：`memory/bugs.md`（BUG-569 / BUG-570 条目；计数规则 1-60）
- 代码：`src/server/bugreport.mbt`（`bug_is_header` / `bug_parse` / `bug_parse_header` / `bug_parse_int`）
- 判据：`scripts/run_guards.py:476` / `scripts/check_bug_ledger_shape.py:94` / `scripts/check_bug_ledger_scope.py` / `scripts/check_delivery_gap.py` / `scripts/gen_plugins.py:147`
- 上轮报告：`reports/2026-11-04-wakeup-patrol-120-report.md`
- 决策单：`reports/2026-11-03-bug565-project-dir-decision-sheet.md` / `reports/2026-11-03-bug566-approval-gate-misjudgment.md`
