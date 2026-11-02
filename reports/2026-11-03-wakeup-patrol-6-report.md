# 2026-11-03 · 唤醒轮 6 巡检（两把新判据均绿）· 报告

## 结果摘要
WIP 仍冻结（00:23，~1h36m，无新提交，HEAD=b59d02d1c）。防空转换**本会话未跑过**的两把判据：`check_store_tables_wired` 与 `check_publish_payload` **均绿**。新信号：store 写入面无孤儿表（32 表 = 31 写入点 + 1 显式预留）；**发布打包面 0 件未跟踪**——WIP 混装下无文件会随 `moon publish` 泄漏。零代码改动、零新账。

## 探针读数
| # | 判据 | 读数 | 判定 |
|---|---|---|---|
| 1 | check_store_tables_wired | rc=0：32 张表 = 31 张有写入点 + 1 张显式预留（runs） | 绿（store 写入面无孤儿表，BUG-28 族完好） |
| 2 | check_publish_payload | rc=0：公开打包面 1825 件，其中**未被 git 跟踪 0 件**（另 37 件点号条目 moon 本来就不打包） | 绿（发布载荷无凭据/泄漏面，BUG-127 族完好） |

## 意义
- 巡检健康面累计（轮 1~6）：实跑判据全绿 = host_installable / mcp_smoke（182 工具）/ doc_surface（J1-J19）/ tools_sync（182）/ store_tables（32）/ publish_payload（1825）；1 环境态（OFM 18326 未起）；1 门禁误判（cl7，投影推定替代）。**提交面六轮无红。**
- `check_publish_payload` 的「未跟踪 0 件」值得记：WIP 11 文件全为已跟踪修改（不进发布面）、本轮 temp/ 产物在 ignore 面 ⇒「发布面 = 工作树 − ignore」纪律当前成立。

## 任务分配记录
无派单（无委派面）；指挥官亲跑探针 + 记账。

## 遗留风险
无变化（轮 4/5 四件）：(1) bugs.md 先提必 cl7 红（§5.2 前置）；(2) 21 条 vq 条目待裁决定终态；(3) 双流共享树提交纪律；(4) 3 条旧 OPEN 维持 owner 门控。

## 后续建议
无变化：owner 裁决 BUG-565 §4（推荐 B 白名单案）+ §3 部署审批；收口前把拆批建议（轮 3 报告 §收口警示）传达两 agent。下一轮：已收口 ⇒ 核拆批 + 补 cl7 实跑；未收口 ⇒ 换余下判据（check_demo_isolation / check_entry_paths / cli_flag_probe / mcp_tool_tour --surface-selftest）或仅观察。

## 超额内容
无。

## 来源
- 判据（本轮实跑）：`scripts/check_store_tables_wired.py`（rc=0，`temp/round6_store_tables.txt`）/ `scripts/check_publish_payload.py`（rc=0，`temp/round6_publish_payload.txt`）
- 盘面：`git status` / `git log` / mtime（本轮实跑）
- 决策单：`reports/2026-11-03-bug565-project-dir-decision-sheet.md` §5.2
- 日期：2026-11-03
