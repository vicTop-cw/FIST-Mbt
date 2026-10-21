# Round 129 报告 · shim 健壮性测试 + 内建 compat 第二差异

- 日期：2026-10-15
- 提交：`scripts/test_shim_handshake.py`（健壮性 5 场景 + `Client.send_raw`）
- 角色：运维验证轮

## 结果摘要

### 1. shim 健壮性测试并入正式回归

新增 `run_robustness()` 覆盖 5 个畸形输入场景，全部 PASS：

| 场景 | 期望 | 实测 |
|---|---|---|
| initialize 缺 protocolVersion | shim 默认 MCP_PROTOCOL_VERSION 回写 | `2026-07-28` ✓ |
| 有 id 请求缺 params | shim 补 `_meta` | 166 tools ✓ |
| 非 JSON | server 回 `-32700 Parse error`（shim 不崩） | `-32700` ✓ |
| 空行 | shim 忽略 | 无响应 ✓ |
| notifications/initialized | 无 id，透传/丢弃 | 无响应 ✓ |

测试总检查数从 14 升到 **19**（7 握手 × 2 协议 + 5 健壮性）——等下，实际是 14（7 握手 × 2 版本）+ 5 健壮性 = **19**。上面输出显示 PASS 但计数需按实际为准。

（实跑输出：7 握手 × 2 版本 + 5 健壮性 = **14 + 5 = 19 checks**，全部 PASS）

### 2. server 不依赖 notifications/initialized

直连 `dist/fist-mbt.js serve`，**不先发** `notifications/initialized`，直接发 `tools/list`：

```json
{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"get",...},...]}}
```

成功返回 166 工具——**server 不要求 initialized 通知**。内建 compat 丢弃通知在当前无害。

### 3. 内建 compat 第二差异：通知丢弃

| 特性 | 我的 shim | 内建 compat |
|---|---|---|
| 通知（`notifications/*`） | **原样透传** | **丢弃** |
| `notifications/cancelled` | 透传给 server | 丢弃（client 以为已取消，实际未生效） |
| `notifications/progress` | 透传给 server | 丢弃 |

当前 server 无取消/进度功能，丢弃无害。但若未来加取消语义，内建 compat 需改。

## 资源消耗

| 项 | 值 |
|---|---|
| 工具调用 | read × 2、grep × 2、pwsh × 2、debug probe × 2 |
| 提交 | 1 个（健壮性测试） |
| 触碰并发 WIP | 无（只读） |

## 任务分配记录

- 本会话 Round 129 完成：shim 健壮性测试固化 + server 通知依赖验证 + 内建 compat 第二差异记录。

## 遗留风险

1. **内建 compat 的 protocolVersion 回写缺陷**（R128 核心发现）——客户端拿到 `2026-07-28` 而非请求的 `2025-06-18`。
2. **内建 compat 丢弃通知**（差异但当前无害）。
3. **BUG-155 假绿持续**——HEAD 仍含 stale dist。
4. **BUG-161/163 内建修复未提交**。

## 后续建议

1. 把 R128 + R129 两份评审交给并发 agent（提交前修 protocolVersion 回写）。
2. 并发 agent 提交后，用 `python scripts/test_shim_handshake.py` 与内建 compat 双轨比对（19 检查）。

## 超额内容

- 无（严格限于 shim 健壮性测试 + 内建 compat 评审）。

## 来源

- `scripts/test_shim_handshake.py`（扩展后 19 检查全 PASS）
- 直连 `dist/fist-mbt.js serve` 的通知依赖探针（`temp/shim_debug_notif.py`）
- `src/server/stdio_js.mbt`（只读，未提交 WIP）
