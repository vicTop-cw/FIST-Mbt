# Round 123 报告 · shim 补 ping + 扩展标准方法验证

- 日期：2026-10-15
- 提交：`89bf704`（`scripts/mcp_compat_shim.js` +8 -2）
- 角色：验证轮（第 3 轮，未触碰 `src/`，与并发 agent 零冲突）

## 结果摘要

补充 **`ping` 拦截** 到 `scripts/mcp_compat_shim.js`，并扩展标准 MCP 方法验证。至此**标准 MCP 客户端所需的关键方法已全部通过 shim 打通**。

### 扩展实测（发布版 dist/fist-mbt.js = v0.3.8）

| 标准方法 | 结果 | 说明 |
|---|---|---|
| `initialize`（2025-06-18 / 2024-11-05） | ✅ | 握手成功，protocolVersion 回写客户端档 |
| `ping` | ✅ `{}` | **本轮新增 shim 拦截**——server（colmugx/mcp@0.17.4）已移除该方法，直连吃 -32601 |
| `tools/list` | ✅ | 返回工具数组 |
| `tools/call`（status_summary / project_health） | ✅ | 真数据 |
| `resources/list` | ✅ | 返回 fist://map 等 3 条 |
| `resources/read fist://map` | ✅ | 返回真内容 |
| `prompts/list` | ✅ | 返回 2 个 prompts（fist:verify、fist:overview） |
| `logging/setLevel` | ⚠️ `-32601` | MCP 可选特性，server 未实现，非阻塞 |
| `completion/complete` | ⚠️ `-32601` | MCP 可选特性，server 未实现，非阻塞 |

## 为什么 shim 拦 ping 是必要的

- fist-mbt server 用 colmugx/mcp@0.17.4——该版本已移除 `ping` 方法。
- 并发 agent 的 `compat_request`（`src/server/stdio_js.mbt` L121-122）**已处理** ping 的 `_meta` 补全，但 server 层本身不实现 `ping`，内建 compat 也无法解决。
- 标准 MCP 客户端（尤其带健康检查的）依赖 `ping`；shim 拦截直接回 `{}` 是当前唯一可行出路。

## 资源消耗

| 项 | 值 |
|---|---|
| 工具调用 | ~6 次（`pwsh` × 3、`read` × 1、`edit` × 2） |
| 提交 | 1 个（`89bf704`） |
| 触碰并发 WIP | 无 |

## 遗留风险

1. `logging/setLevel`、`completion/complete` 未实现（MCP 可选特性）——强依赖日志级别或自动补全的客户端可能受限；绝大多数客户端不依赖。
2. 并发 agent 的 compat 层（`stdio_js.mbt`）仍未提交——BUG-161/163 的内建修复仍待他们 commit + `moon publish` 重发布。
3. BUG-155（dist 148 vs src 166 工具）仍待工具收口后重建 dist。

## 后续建议

1. **并发 agent 提交后**，用 `temp/shim_probe5.py` 改指内建 build（`node _build/js/... serve`）再跑一遍，验证内建 compat 是否同样覆盖全部标准方法（含 ping）。
2. **若内建 compat 也无法处理 ping**，可考虑在 `src/server/stdio_js.mbt` 的 `compat_request` 里对 `ping` 直接短路返回 `{}`（与 shim 同思路）；这是源码层的干净修法。

## 超额内容

- 无超额（严格限于 ping 修复 + 扩展验证）。

## 来源

- 探针：`temp/shim_probe5.py`
- 真源：`dist/fist-mbt.js`（发布版）、`src/server/stdio_js.mbt`（并发 agent 的 compat_request，只读 L85-129）
- 记忆：`memory/2026-10-15.md`（Round 123 条目）
