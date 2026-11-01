# 2026-11-01 · 巡检 R15 · OFM 探活缺口立账（BUG-537）+ 双守卫补跑

## 结果摘要
WIP 未收口（src/** 与 13 份库包 moon.pkg 仍被 BUG-527 摘 link 工作占用，diff 实证），按第 3 条走非阻塞巡检。三路子代理并发 + 统帅补跑终审：新立 BUG-537 一单（low，OPEN），两支守卫实测绿，mcp_smoke FAIL 判为产物缺失非回归。

## 资源消耗
- 子代理 ×3（mcp_smoke / check_host_installable / OFM 探活），OFM 路发现真缺口；两路无执行面只出静态预判，实测由统帅补跑。

## 任务分配记录
| 单元 | 内容 | 终审证据 |
|---|---|---|
| 巡检-A | mcp_smoke 实跑 | 真实 rc=1，FAIL「main.js 未找到」——WIP 未 build 的正常态，不立案 |
| 巡检-B | check_host_installable 两步 | selftest rc=0 + 主检 rc=0（仅信息级 timeout_ms WARN）；子代理静态预判与实测一致 |
| 巡检-C | OFM 探活判据盘点 | **BUG-537**：scripts/ 189 份 grep ofm/18326/18899 = 0 命中，无入库判据 |

## BUG-537 要点（OPEN）
1. OFM 端点可用性零入库判据，探活只存在于 USAGE.md 手工规程，端点失效静默（18899 已实际失效过一次，现行 18326）。
2. 伴生文档缺陷：USAGE.md §6.15 示例端点仍写 18899（漂移）；patrol-round3 报告把 `pol_keeper_run`（任务池 keeper）误标为「OFM 端点探活」。
3. 修复：新增 `scripts/check_ofm_endpoint.py`（env 无值时 SKIP 不判红不判绿）+ USAGE 同步 + 误标勘误，可先于 src/** 解禁落地。

## 遗留风险
- BUG-537 待派（scripts/USAGE 不在 WIP 面，可独立落地）。
- BUG-536 待 owner（方案 A ff 推 master / B owner 配 token）。
- Round C 三件（527 治本 → 530 修复 → run_guards 注册）等 src/** 解禁。

## 后续建议
- 下一唤醒若 WIP 已收口：走 Round C 队列；否则优先派 BUG-537 修复单元。

## 超额内容
无（巡检属本轮目标内）。

## 来源
- 子代理回传 ×3 + 统帅实测（check_host_installable / mcp_smoke 补跑读数）
- FIST 闭环：账本 BUG-537 登记；memory/2026-11-01.md R15 段
