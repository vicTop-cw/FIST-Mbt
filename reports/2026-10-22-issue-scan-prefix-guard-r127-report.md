# R127 · issue_scan 形态 F 自守卫 + 近邻窗口单源（12 行）

- 日期：2026-10-22
- 分支：`slave/fix/issue-scan-prefix-guard-r127`（开工基线 `gitcode/master` = `ede53f30`；交单前叠到 `dcefdeb8`）
- 性质：副机自驱迭代自找项（主机任务池无活跃指派：`T0r52` 已完成，其余归档）

## 结果摘要

- `issue_scan` 对 `engine.extract_needs` 的 6 条 substring-overrun 假阳性新增**形态 F** 守卫：
  同一窗口内 `sv.has_prefix("需要:")`（或 `has_suffix`）与 `let s = sv.to_owned()`
  同时成立 ⇒ `s.substring(start="需要:".length())` 的 start 必 ≤ 长度，豁免。
- 顺带修掉守卫窗口的**两套实现**：生产路径只取 10 行，测试可见的 `scan_filter_guarded` 取 12 行；
  第 6 条（`能力：` 分支）距副本定义恰好 12 行，生产少取一行就丢副本关系。抽出
  `scan_prev_window`（12 行上限、遇 `fn ` 停、最近优先）单一构造，生产与白盒锁共用。
- 实扫 `src/`（`min_severity=medium`）：**7 → 1**；剩 1 条为已确认假阳性
  `src/ops/ops_ts.mbt:60` secs-overflow——`year > 2091` 上界把 days 钳在 24820（< 24855），
  但规则不识「年上界 ⇒ days 上界」的间接约束，按口径不代修（见「预存红」与「后续建议」）。

## 判据自证

- 白盒锁两条（`src/server/issue_scan_wbtest.mbt`）：
  - `scan_guard_prefix_literal_字面量前后缀守卫`：正例覆盖同变量 `has_prefix`、`to_owned()` 副本、
    `has_suffix` 三支；反例覆盖无守卫、守卫别的字面量、副本经过 `trim`（可能缩短）、守卫别的变量四支。
  - `scan_prev_window_十二行窗口保住副本关系`：按真实行距铺 14 行，12 行窗口必须抑制；
    同一批行只取前 10 行（旧生产上限）必须仍判真阳性——把上限改回 10 这格会红；
    跨 `fn ` 行不取旧函数的副本定义。
- 生产实扫即端到端判据：`issue_scan --dir src --min-severity medium` 读数 7 → 1（见「证据」）。

## 证据

    python scripts/fist.py call issue_scan --dir src --min-severity medium --max-findings 50

| 时点 | 读数 |
|---|---|
| 修复前 | `total_findings=7`：6 条 `substring-overrun`（engine.mbt 1638/1640/1642/1644/1646/1648）+ 1 条 `secs-overflow`（ops_ts.mbt:60） |
| 修复后 | `total_findings=1`：仅 `secs-overflow`（ops_ts.mbt:60），`filtered_out=974`，`scanned_files=132` |

临时库 `%TEMP%/r127_scan.db`，不碰仓库根台账。

## 读数

- `MOONC_OVERRIDE=~/.moon-shim/shim.exe moon check --target js`：rc=0（0 errors）。
- `env -u MOONC_OVERRIDE python scripts/moon_test_env.py src/server`：368/368 passed。
- 叠线后全量 `env -u MOONC_OVERRIDE python scripts/moon_test_env.py`：**1389/1389 passed**，failed 0。
- 电池 `python scripts/run_guards.py`（叠线后 66 格）：**66 格 / 失败 0 / SKIP 5 / 缺执行面 0**，rc=0。
  （叠线前 64 格同读数：失败 0 / SKIP 5；首跑时本报告尚未 `git add`，`check_publish_payload.py`
  按 P1 点名「未跟踪又未被 ignore ⇒ `moon publish` 会公开它」，入库后该格转绿——是自指红，不是代码红。）
- `moonfmt.exe` 直调两文件：格式化零差异；CRLF 保持（issue_scan.mbt 2833 CRLF / wbtest 554 CRLF，
  `bareLF=0`、`tabs=0`、`endsCRLF=True`）。

## 预存红（不代修）

- `moon fmt` 本机 rc=127：moonfmt 自身撞同一颗 `\?\` ICE（BUG-329），改用 `moonfmt.exe` 直调逐文件对照。
- `check_scripts_naming.py` rc=1（N1/N2 上限），电池已按期望红登记，非本单引入。

## 资源消耗

- 构建：`moon build --target js cmd/cli` 1 次（shim 覆盖下冷建）＋ `moon check` 2 次；全量测试 2 次、
  server 包测试 2 次；电池 2 次（叠线前 64 格、叠线后 66 格，各约 2.5 分钟）。
- 无子代理；e2e 复用仓库既有 `fist.py` 与 `%TEMP%` 临时 SQLite，仓内无残留。

## 任务分配记录

- 自找项，无主机指派；未触碰并行 agent 的任务/分支/文件（R126 未并入主线，文件面与本单不相交）。
- 改动 2 份文件：`src/server/issue_scan.mbt`（形态 F + 窗口单源）、
  `src/server/issue_scan_wbtest.mbt`（2 条白盒锁）。

## 遗留风险

- 形态 F 只认 `let v = src` / `let v = src.to_owned()` 两种副本；`trim`/切片等可能缩短的副本不放行，
  宁可保留少量假阳性也不误抑制真阳性。
- 窗口上限 12 行是行距上限而非语义上限：副本定义更远的形态仍会漏抑制（拿不准不抑制）。
- `ops_ts.mbt:60` 的 secs-overflow 假阳性仍在报告面，规则层未收敛。

## 后续建议

- `scan_secs_suppressed` 增「常量年上界 ⇒ days 上界」形态：需同时证明守卫在表达式之前、
  且 `(Y-2024)*365+334+31 <= 24855`（Y=2091 时 24820）成立，再豁免。
- 形态 F 不建议放宽到 trim 副本：无法证明 start ≤ trim 后长度。
- 若后续再出现「守卫窗口不同步」，应直接扩 `scan_prev_window` 的锁，不另起旁路。

## 超额内容

- 删掉已无调用点的 `scan_filter_guarded`（旧第二套 12 行窗口实现）——它让「测试窗口 12 行」与
  「生产窗口 10 行」长期各说各话，也是本次 6 条里最后 1 条漏抑制的真正原因。

## 来源

- `src/engine/engine.mbt`（`extract_needs` 1623-1671：副本与 6 条 has_prefix 守卫）
- `src/server/issue_scan.mbt`（`scan_guard_prefix_literal` / `scan_prev_window` / `scan_finding_guarded`）
- `src/server/issue_scan_wbtest.mbt`（R127 两条白盒锁）
- 实测产物：`%TEMP%/r127_scan.db`、`%TEMP%/r127_battery.log`（仓外留档）
