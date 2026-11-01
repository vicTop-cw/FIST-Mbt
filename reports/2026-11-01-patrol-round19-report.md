# 2026-11-01 · Round 巡检-19（WIP 未收口 · 非阻塞巡检）

## 结果摘要
WIP 未收口（35 文件 modified + `.opencode/` 未跟踪，另一 agent 工作现场），执行非阻塞巡检。核心面全绿，OFM 端点断连（BUG-537 已 FIXED，部署状态非代码问题），无新立账项。

| # | 检查项 | 证据 | 结论 |
|---|---|---|---|
| 1 | 构建基线 | `moon build --target js cmd/cli` — 0 errors, 33 warnings | 绿 |
| 2 | MCP 协议面 | `mcp_smoke.py` PASS — tools/list 182 / issue_scan / publish / get | 绿 |
| 3 | 宿主可装性 | `check_host_installable.py` PASS — DSH 严格档 + 宽松档双合规 | 绿 |
| 4 | 工具真源一致 | `check_tools_sync.py` PASS — server.mbt 182 对齐；现状面 165 / 历史豁免 24 | 绿 |
| 5 | 电池计数 | `check_battery_count_doc.py` PASS — rulers=148 ci=48 battery=107 missing=0 | 绿 |
| 6 | OFM 端点 | `check_ofm_endpoint.py` rc=1 — 127.0.0.1:18326 连接拒绝 (WinError 10061) | 部署状态 |

## 关键发现

### 1. WIP 未收口
`git status --short` 报出 35 文件 modified + `.opencode/` 未跟踪目录。另一 agent 的工作现场（含 `.opencode/AGENTS.md` / `mem-exp-config.json` / `package.json`）。按纪律不碰。

### 2. OFM 端点断连
`FIST_OFM_ENDPOINT=http://127.0.0.1:18326/v1` 已配置，但探活返回 `down`（WinError 10061 连接拒绝）。**BUG-537 已 FIXED**（探活判据已落地 `scripts/check_ofm_endpoint.py` + `run_guards.py` 注册），本次读数 rc=1 仅为部署状态（relay 服务未启动），非代码问题。无新立账项。

### 3. 账本口径
OPEN=107 / FIXED=1063 / 重复/误报=149。Round C 三件（BUG-527 治本 / BUG-530 修复存活 / run_guards 注册）等 src/** 解禁后由下一轮接手。

## 资源消耗
- 零代码改动（巡检轮）
- 19 次 bash 调用用于巡检

## 遗留
- BUG-527 OPEN（工具链语义分歧，非本仓可修）
- BUG-536 待 owner 裁决
- BUG-537 FIXED（判据已落地，本次读数仅为部署状态）
- Round C 三件等 src/** 解禁
