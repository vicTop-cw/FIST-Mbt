# Round 128 报告 · 独立评审并发 agent 内建 compat 层

- 日期：2026-10-15
- 角色：独立技术评审（只读，未触碰并发 WIP）
- 提交：无（仅文档）

## 结果摘要

### 核心发现：内建 compat 的 protocolVersion 回写缺陷

**并发 agent 的 `src/server/stdio_js.mbt` 内建 compat 层有一个设计缺陷**——它无法把客户端请求的协议版本回写给客户端。

#### 证据链

**1. `compat_request` 的返回类型只带 2 个元素**

```moonbit
fn compat_request(message : String) -> (String, Bool) {
  // 返回：(改写后的消息, 是否 initialize)
  // 注意：不返回客户端请求的 protocolVersion！
  (Json::object(m).stringify(), was_init)
}
```

`compat_response` 只有 `was_initialize : Bool` 这个标志，**无法知道客户端请求的是 `2025-06-18` 还是 `2024-11-05`**。

**2. `compat_response` 用 `supportedVersions[0]` 回写**

```moonbit
match discover_result.get("supportedVersions") {
  Some(Json::Array(arr)) if arr.length() > 0 =>
    match arr[0] {
      Json::String(s) => legacy.set("protocolVersion", Json::string(s))
      ...
```

**3. `server/discover` 成功响应不回显客户端请求的版本**

直连 dist/fist-mbt.js serve 实探：

```
请求 _meta.protocolVersion = "2025-06-18" →
  error -32022 "Unsupported protocol version"
  data.supported = ["2026-07-28"]

请求 _meta.protocolVersion = "2026-07-28" →
  result.supportedVersions = ["2026-07-28"]
  result.capabilities = {tools/resources/prompts: listChanged}
  result._meta.serverInfo = {name:"fist-mbt", version:"0.3.8"}
```

**成功响应的 `supportedVersions` 是服务端支持的版本**（`["2026-07-28"]`），**不是客户端请求的那一档**。

**4. 影响**：标准客户端（Claude Desktop / VS Code / cursor）请求 `2025-06-18` 或 `2024-11-05`，内建 compat 会在 `initialize` 响应里回写 `protocolVersion: "2026-07-28"`。**严格客户端（多数实现）会因协商版本不匹配拒绝握手**。

### 我的 shim 是正确对照

```js
// scripts/mcp_compat_shim.js
if (msg.method === 'initialize') {
  const clientPV = msg.params?.protocolVersion || MCP_PROTOCOL_VERSION;
  pendingInits.set(msg.id, clientPV);   // ← 存储客户端请求的版本
  ...
}
// 响应侧
if (pendingInits.has(resp.id)) {
  const clientPV = pendingInits.get(resp.id);
  ... protocolVersion: clientPV  // ← 回写客户端请求的那一档
}
```

这就是标准 MCP 协议要求的协商语义。测试已实证两档协议（`2025-06-18` / `2024-11-05`）都能握手成功。

### 建议给并发 agent

`compat_request` 的返回类型应改为 `(String, Bool, String)`——第三元素是客户端请求的 protocolVersion；或用一个进程内 Map 按 request id 存储。`compat_response` 用它回写，而非 `supportedVersions[0]`。

## 资源消耗

| 项 | 值 |
|---|---|
| 工具调用 | read × 2、grep × 2、pwsh × 2、debug probe × 3 |
| 提交 | 无 |
| 触碰并发 WIP | 无（只读） |

## 任务分配记录

- 本会话 Round 128 完成：独立评审并发 agent 内建 compat 层，发现 protocolVersion 回写缺陷。

## 遗留风险

1. **内建 compat 的 protocolVersion 回写缺陷**——并发 agent 提交前须修（否则 BUG-163 未真正解决）。
2. **BUG-155 假绿持续**——HEAD 仍含 stale dist。
3. **BUG-161/163 内建修复未提交**。

## 后续建议

1. 把本报告回传给并发 agent（或在提交时提醒其修 `compat_request` 返回类型）。
2. 并发 agent 提交后，用 `python scripts/test_shim_handshake.py` 与内建 compat 双轨比对，能抓出类似协商语义差异。

## 超额内容

- 无（严格限于独立评审）。

## 来源

- `src/server/stdio_js.mbt`（只读，未提交的 WIP）
- `scripts/mcp_compat_shim.js`（我的 shim，正确对照）
- 直连 `dist/fist-mbt.js serve` 的 `server/discover` 探针（`temp/shim_debug_discover.py`）
- `scripts/test_shim_handshake.py`（R127 修好 `tools/call` check）
