# Round 122 报告 · mcp_compat_shim（BUG-161 / BUG-163 外部缓解层）

- 日期：2026-10-15
- 提交：`f7fc940`（`scripts/mcp_compat_shim.js` 新建 + `scripts/README.md` 登记）
- 角色：验证轮（第 2 轮，未触碰 `src/`，与并发 agent 零冲突）

## 结果摘要

新增 **`scripts/mcp_compat_shim.js`** —— 让**发布版 `dist/fist-mbt.js`（v0.3.8，148 工具）** 能被标准 MCP 客户端（Claude Desktop / VS Code / cursor）连上的外部协议兼容层。**免改 server 源码，立即可用**。

### 端到端实测（发布版 dist，2026-10-15 Windows）

| 标准客户端操作 | 结果 |
|---|---|
| `initialize`（`2025-06-18`） | ✅ `serverInfo` = fist-mbt 0.3.8，`protocolVersion` 回写 `2025-06-18`，capabilities 完整 |
| `initialize`（`2024-11-05`） | ✅ 同上 |
| `notifications/initialized` | ✅ 透传 |
| `tools/list` | ✅ 返回工具数组 |
| `tools/call status_summary` | ✅ `{"version":"0.3.8","total_tasks":0,...}` 真数据 |
| `tools/call project_health` | ✅ `{"version":"0.3.8","grade":"empty",...}` 真数据 |
| `resources/list` | ✅ 返回 `fist://map` 等 3 条 |
| `ping` | ⚠️ `-32601 Method not found: ping`（colmugx/mcp 移除，非 shim 问题） |

## 根因（实测确认）

1. fist-mbt server 讲**非标协议 `2026-07-28`**（colmugx/mcp@0.17.4 移除 `initialize` 方法）。
2. server **每个请求**（不只 `initialize`）都强制要求 `params._meta` 三元组，否则返回 `-32602 Missing required _meta field: io.modelcontextprotocol/protocolVersion`。
3. 标准客户端发的 `initialize` 不带 `_meta`，且用的是 `2024-11-05` / `2025-06-18`，直连 `fist serve` 会被 `-32022 Unsupported protocol version` 拒。

## Shim 做了什么

```
标准客户端                     shim                       fist-mbt server
  initialize                →  补 _meta 三元组           →  server/discover
  (protocolVersion 2025)        → 改 method               (protocol 2026-07-28)
  
  标准 initialize 响应      ←  serverInfo                 ←  discover 结果
  protocolVersion 回写           protocolVersion = client
  2025-06-18                   capabilities
  tools/list / tools/call   →  补 params._meta          →  tools/list / tools/call
  resources/list                (有 id 的请求都要补)       →  resources/list
  notifications/*           →  原样透传                  →  notifications/*
```

## 与并发 agent 的关系

- 并发 agent 在 `src/server/stdio_js.mbt` 的 `compat_request` / `compat_response`（L108-150）是**同一思路的内建路线**——已写好并接线到主循环（L202/204），但**未提交、无单测**。
- 本 shim 是**外部路线**：用 Node.js 包装发布版 server，拦截并改写 JSON-RPC 消息。**不依赖并发 agent 的提交**，发布版用户今天就能用。
- 两条路线互补：shim 立即可用；内建 compat 需等源码提交 + `moon publish` 重发布。
- 我在 `stdio_js.mbt`、`issue_scan*.mbt`、`memory/bugs.md` 上**零改动**。

## 资源消耗

| 项 | 值 |
|---|---|
| 工具调用 | ~25 次（`pwsh` × 10、`read` × 3、`edit` × 3、`write` × 1、`mcp list` × 2、其余为探针脚本执行） |
| 提交 | 1 个（`f7fc940`，2 文件 +131 行） |
| 触碰并发 WIP | 无 |
| `moon test` | 未跑（不涉 `src/`） |

## 任务分配记录

- 本会话 Round 122 未通过 FIST `publish` / `plan` / `claim` 派单（直接执行——shim 属轻量独立交付物，不需要拆解）。
- 上一轮 Round 121 的 FIST 任务树仍保持；本交付不新增任务。

## 遗留风险

| # | 风险 | 处置建议 |
|---|---|---|
| 1 | `ping` 不被 server 支持（`-32601`），个别强依赖健康检查的客户端会报错 | 后续可在 `compat_request` 里把 `ping` 映射到 `server/health` 或空响应；非阻塞 |
| 2 | shim 把 `protocolVersion` 伪装成客户端请求档（server 实际讲 `2026-07-28`） | 标准客户端不做后续校验，无实际影响；`compat_response` 内建版同样如此 |
| 3 | 并发 agent 的 `compat_request` / `compat_response` 无单测 | 建议他们提交前加 2-4 条白盒测试（握手 + 透传 + `_meta` 缺失路径） |
| 4 | `check_scripts_index` 暂红（并发 WIP 5 项未登记） | 并发 agent 提交时应在 `scripts/README.md` 登记；我的 `mcp_compat_shim.js` 已登记 ✓ |
| 5 | `dist/` 已 stale（148 vs src 166 工具，BUG-155） | 并发 agent 的工具收口后需 `moon publish` 重发布；本轮不碰 |

## 后续建议

1. **并发 agent 提交 compat 层后**，用本轮的 `temp/shim_probe3.py` / `temp/shim_probe4.py` 改指向 `node _build/js/... serve`（或 `fist serve`）再跑一次，验证**内建 compat** 是否同样通过标准 `initialize` 握手——这是 BUG-163 的验收判据。
2. **`ping` 支持**：若标准客户端报 `Method not found: ping`，在 `compat_request` 里把 `ping` 改写为已知方法（或返回空 `{}`）；非阻塞增强。
3. **`dist` 重建**：并发 agent 工具面收口后，`moon build --target js` + `moon publish` 把 166 工具 + 内建 compat 一起发出去，然后可淘汰本 shim（或保留作为备用）。

## 超额内容

- 无超额（本轮严格限于 shim 交付 + 登记 + 报告）。

## 来源

- 探针脚本：`temp/mcp_probe7.py`、`temp/shim_probe3.py`、`temp/shim_probe4.py`
- 真源：`dist/fist-mbt.js`（发布版）、`src/server/stdio_js.mbt`（并发 agent 的 compat 层，只读）
- 守卫：`scripts/check_scripts_index.py`
- 记忆：`memory/2026-10-15.md`（Round 122 条目）