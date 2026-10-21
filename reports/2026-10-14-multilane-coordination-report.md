# 多 Agent 同改一项目协调报告（Round 9–12 观测收敛）

- 日期：2026-10-14
- 观测人：本 lane（supervisor 白盒锁 + memory 收口），全程 `fist-mbt` 自迭代，开关全开
- 目标项目：FIST-Mbt 自身（多 agent 同目标、同分支、同工作树）
- 兄弟 lane：router 增强 + `self_search` 接线 + 模板控制字符 guard（`check_template_ctrl`）

## 结果摘要

在共享目标（实现 BACKLOG 计划 + 多 agent 文件锁机制观测）下，本 lane 与兄弟 lane 并发工作 4 轮（R9–R12），交叉验证得出：多 agent 操作同一目标项目文件时，可在「不互相破坏、可追责、自然合流」的前提下并发收口。全程无冲突提交、无测试回归、无翻账越界。

## 资源消耗

- 本 lane 提交：`ab46f42`（supervisor 白盒锁）、`d8f3aef`/`b16e9bc`/`0862f00`/`4b241fd`（R8–R11 memory+报告）、本轮 `4b241fd` 后继 `ffcf957` 为兄弟提交。
- 全量测试基线：`moon test --target js` = **1042/1042 failed 0**（R8 至今稳定在脏树复验一致）。
- scratch 产物：`temp/lock_demo.py`、`temp/lock_acquire_demo.py` 均为一次性、跑完即删，未污染仓库（BUG-122 合规）。

## 任务分配记录（观测对象，非本 lane 执行）

- 兄弟 lane 负责：`src/router/*` 模型路由增强、`src/server/model_router_ops.mbt`、`self_search` 接线、`check_template_ctrl` guard。
- 本 lane 负责：supervisor P1 白盒锁（已收口 `ab46f42`）+ 多 agent 协调观测与翻账。

## 多 Agent 协调三层结论

### 1. 工具层（Round 9 / Round 10，live 驱动项目自身 MCP）
- `reserve_scope` 家族：作用域预订（轻量，冲突只回 `held_by` 不落审计）——规划期「谁负责哪片」。
- `lock_acquire` 家族：持久文件锁（TTL/续租/接管/审计），冲突**显式记 `lock_denied` 违例**且 `lock_status` 可回读——真正落笔时的硬互斥 + 事后取证。
- 两者均走「后端裁决、非读后写」，live 持有者不被串行夺走，与 BUG-154 跨进程硬门同源。

### 2. 纪律层（Round 11，真脏树验证）
- lane 隔离：互不 `git add` / `commit` 对方署名文件；只 stage 自己 lane 产出。
- 谁提交谁翻账：BACKLOG 的责任行（如 L33 `self_search` 接线）由提交方连同工具数一并翻，旁观者不代翻半成品账。
- 验证：兄弟 10+ 文件 router WIP 在工作树未提交时，脏树 `moon check` 0 errors、`moon test` 1042/1042 全绿。

### 3. 合流层（Round 12，提交自然堆叠）
- 兄弟 lane 提交 `ffcf957 feat(guard): 模板「无裸控制字符」判据 check_template_ctrl` 在共享分支上自然落定，与本 lane `4b241fd` 顺序堆叠、无冲突。
- 含该新提交 + 兄弟在飞 router WIP 的合并脏树复验仍 1042/1042 全绿 → 两个 agent 的输出能在同一分支并发集成、互不破坏。

## 遗留风险

- BACKLOG L16（native 侧真实自驱巡检）：owner 决策「现在不建」，技术前置 BUG-133 已达成，但决策权在 owner，不由本 lane/旁观者翻账。
- BACKLOG L33（`self_search` 外部检索入库接线）：属兄弟 lane `src/evolve` 面，当前为未提交 WIP（工作树命中 `self_search_runner_default()` + `run_external_search`/`distill_candidates` 注释块），基线零调用者；待兄弟提交并落 DGM/`evolve_asset_register` 账后由其翻账。
- 兄弟 router 增强仍在工作树未提交（10 文件脏），合并前需其自行 `moon fmt` + 全绿收口。

## 后续建议

- 共享目标整体未达成，应保持 active 至兄弟 lane 收口（router 增强提交 + L33 接线落地 + L16 owner 决）。
- 收口后可补一份「lock 两族 × 跨 lane 集成」的对照归档（`docs/` 命名带 `YYYY-MM-DD-` 前缀，J15 合规）。
- 长期：将本观测收敛的「工具层 + 纪律层 + 合流层」三规则蒸馏为 DGM 原则（[principle]），供未来多 agent 会话复用以降低协调成本。

## 超额内容

- 顺带验证了项目自身 MCP 持久锁（`lock_acquire`/`lock_status`/`lock_release`）的运维坑：`cli.js serve` 须带 `serve` 参数且不实现 `initialize` 握手，已对齐 `mcp_smoke.py` 启动方式（含 ESM require shim），一次性脚本 PASS，跑完清理。

## 来源

- `memory/2026-10-14.md` Round 9–12 条目
- `BACKLOG.md` L16 / L33 责任与状态
- `git log`：`ab46f42` / `ffcf957` / `0862f00` / `4b241fd` 等
- 实证：`python scripts/mcp_smoke.py` 全绿（166 工具）、`temp/lock_acquire_demo.py` 持久锁观测 PASS、`moon test --target js` 1042/1042
