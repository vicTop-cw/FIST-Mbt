# 2026-11-03 · 唤醒轮巡检（Round C 复核 + 三探 + 零代码改动）· 报告

## 结果摘要
唤醒轮：核查并发 WIP → 复核 Round C 队列 → 跑三探 → 登记一条新观察（跨项目 WIP 共存）。
Round C 三条全 resolved/superseded（BUG-527 治本被 2026-11-02 追记3 回滚、BUG-530 已 FIXED、
check_usage_tool_count 已注册），无委派面；三探两绿一环境态（check_host_installable PASS /
mcp_smoke PASS 182 工具闭环 / OFM 18326 未起非回归）；MCP 引擎当前健康。零代码改动、零新账。

## 三探读数
| # | 判据 | 读数 | 判定 |
|---|---|---|---|
| 1 | check_host_installable | PASS，v0.3.11；3 条 `timeout_ms` 信息级 WARN | 绿（信息级留人终审）|
| 2 | mcp_smoke | tools/list 182；issue_scan 2 命中；publish→T0r45 / get 闭环 | 绿（引擎健康）|
| 3 | check_ofm_endpoint | RC=1，18326 WinError 10061 连接拒绝 | 环境态（本机未起，非回归）|

## Round C 队列复核（引用面 = `reports/2026-10-31-explore-r2-roundb-report.md` §遗留风险）
| 队列项 | 现状 | 依据 |
|---|---|---|
| ① BUG-527 治本（13 库包摘 link） | **已否决/回滚，不得执行** | 2026-11-02 追记3 改判：CI A/B 实证摘 link 致 nightly native test exe `undefined reference to sqlite3_*`（runs 41305804775/54）；cc-link-flags 现逐字在库包（10 src + 根/atgc/atgc-old/omega）+ 可执行包（cmd/cli·cmd/main）+ 测试消费方（tests/smoke·external_executor）；唯一主行动 = 出路②（上游 issue，文本已备 `reports/2026-11-02-bug527-native-link-decision-sheet.md`），挂 owner |
| ② BUG-530 修复 | **已 FIXED** | 2026-11-01，commit 3699f012a（播种落盘）+ 3acdcca7f（断言翻面） |
| ③ run_guards 注册 check_usage_tool_count | **已落** | `run_guards.py:175` case，随 f9a264ab3 入库 |

⇒ 队列无可执行面，按唤醒规则转巡检。

## 新观察（非新账）
`memory/bugs.md` WIP 的 +131 行（`git diff HEAD` 纯追加）是**另一项目 vq** 的账本条目 BUG-544~563
（`crates/vq-*`、`apps/web`、`packages/sql-editor`、`chroma_db`、`maturin`/`cargo`；均
`Qoder-agent 2026-11-02T15:41`）。这些路径在本 MoonBit 仓零命中（glob 实测 `apps/packages/crates/vq-pyo3` 全无）；
HEAD 最高 BUG id = 543，此批**未入库** ⇒ 属另一 agent 在共享工作树的未提交 WIP。
按禁区意识不碰不删（append-only）。

**污染风险**：若 20 条外来条目（13 FIXED + 7 OPEN）被计入本仓计数面，
`BUG-1~543` 真源计数（AGENTS.md 现状面 528 条/3 待修）会漂成 548 条/10 待修。
处置归该 agent/owner，非本轮管辖。

## 3 条待修现状（全部 owner 门控）
| 单 | 摘要 | 卡点 |
|---|---|---|
| BUG-527 | native 库包带 cc-link-flags 与 moon 世代语义分歧 | 出路②上游 issue 文本已备，等 owner 决定提交 |
| BUG-538 | MCP server 长驻进程死亡、无落盘日志 | 工程半已落地（server.log 全链）；运维半等 owner 重连连接器 |
| BUG-542 | 宿主技能副本 ledger 计数滞后 | A/B 两档等 owner 裁决；症状半已手工刷新 |

## 任务分配记录
本唤醒轮无 MCP 任务发布 / 无子代理委派（无可执行面 + 3 OPEN 全 owner 门控）。
指挥官亲做：WIP 面核查、Round C 复核、三探、跨项目 WIP 定性、记账。

## 遗留风险
- 3 条 OPEN 全 owner 门控：BUG-527（上游 issue 一句话）、BUG-538（连接器重连）、BUG-542（A/B 裁决）。
- 跨项目 WIP 共存：另一 agent 的 vq 账本条目（BUG-544~563）未提交；若混入本仓 bugs.md 将污染计数面——建议该 agent 收口时单独提交、不入 FIST-Mbt 账本。
- 共享工作树 4 把守卫脚本 + 插件态 + AGENTS.md/docs 为另一 agent WIP，本轮零接触。

## 后续建议
1. owner 一句话：是否把 BUG-527 出路②上游 issue 文本提交到 moon 上游（`reports/2026-11-02-bug527-native-link-decision-sheet.md` §证据包 已备）。
2. owner 裁决 BUG-542 A/B（宿主同步脚本 vs 仓外豁免 + 边界登记）。
3. 唤醒轮模板的 Round C 队列引用已连续多轮全灭，建议从唤醒模板移除该引用、改为「现读账本 OPEN 集 + 三探」，避免每轮重复复核同一份过期队列。
4. 跨项目 WIP 共存若持续，建议在共享工作树层面立一条「账本条目只归本仓」的守卫（如校验 bugs.md 新条目引用的路径在本仓存在），防止外来条目污染计数面。

## 超额内容
无。

## 来源
- 盘面：`git status` / `git log` / `git show HEAD:memory/bugs.md`（HEAD 最高 BUG id=543；WIP diff +131）
- 判据（本轮实跑）：`scripts/check_host_installable.py` / `scripts/mcp_smoke.py` / `scripts/check_ofm_endpoint.py`
- 账本：`memory/bugs.md` BUG-527 追记3 / BUG-538 / BUG-542；`reports/2026-10-31-explore-r2-roundb-report.md` §遗留风险；`reports/2026-11-02-bug527-native-link-decision-sheet.md`
- 日期：2026-11-03
