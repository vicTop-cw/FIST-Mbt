#!/usr/bin/env node
// FIST-Mbt MCP 协议兼容 shim（BUG-161 / BUG-163 的**外部**缓解层）
//
// 背景：fist-mbt server 讲非标协议 2026-07-28（要求 params._meta 三元组），
//       标准 MCP 客户端（Claude Desktop / VS Code / cursor 等，讲 2024-11-05 或 2025-06-18）
//       直接连 `fist serve` 会被 -32022 Unsupported protocol version 拒。
//       并发 agent 在 src/server/stdio_js.mbt 里用 compat_request / compat_response
//       在 server 内部做同一件事（源码层修复，未提交）。
//
// 本 shim 是**发布版（dist/fist-mbt.js）**的外部等价层：
//   - 拦截客户端标准 `initialize` → 补 _meta 三元组 → 改写为 `server/discover`
//   - 拦截 server 的 discover 响应 → 重写为标准 `initialize` 响应（protocolVersion 回写客户端请求的那一档）
//   - 其余**有 id 的请求**也补 _meta（fist-mbt server 每个请求都强制要求 _meta 三元组，不只握手）
//   - 通知（notifications/*，无 id）原样透传
//
// 实测（2026-10-15 Windows，发布版 dist/fist-mbt.js = 148 工具 / v0.3.8）：
//   - 标准协议 2025-06-18 与 2024-11-05 都能完成 initialize 握手
//   - tools/list / tools/call / resources/list / resources/read / prompts/list 均正常返回
//   - shim 拦截并直接回 {result:{}} 的方法（server 侧未实现）：ping / logging/setLevel / completion/complete（后者回空 values）
//   - stderr 走 stdio 'inherit'，server 的 stderr 直通终端（无需额外透传）
//   - 子进程被 signal 终止时 shim 退出非零（不再 `code ?? 0` 误报成功）
//
// 用法（MCP 客户端把 command 指向本 shim）：
//   node scripts/mcp_compat_shim.js                       # 默认连 dist/fist-mbt.js serve
//   node scripts/mcp_compat_shim.js --server node dist/fist-mbt.js serve
//
// 客户端侧 .mcp.json 示例（Claude Desktop / Claude Code，把 shim 作为 MCP server 启动）：
// {
//   "mcpServers": {
//     "fist-mbt": {
//       "command": "node",
//       "args": ["<repo绝对路径>/scripts/mcp_compat_shim.js", "--server", "node", "<repo绝对路径>/dist/fist-mbt.js", "serve"],
//       "env": { "FIST_DB_PATH": "<你的库路径>" }
//     }
//   }
// }
// 说明：
//   - 不传 --server 时默认连同仓 dist/fist-mbt.js serve
//   - FIST_DB_PATH 用于隔离演示/正式台账；不设则落在仓库根的 fist-mbt.db（不建议）
//
// A7 · 标准客户端可直接落盘的 fist.mcp.json（由发布版 mcp_config_scaffold 校验生成，
//      只写环境变量名占位，真值走 server 进程环境变量——不写密钥、不写 token）：
// {
//   "mcpServers": {
//     "fist-mbt": {
//       "command": "node",
//       "args": [
//         "<repo绝对路径>/scripts/mcp_compat_shim.js",
//         "--server",
//         "node",
//         "<repo绝对路径>/dist/fist-mbt.js",
//         "serve"
//       ],
//       "cwd": "<repo绝对路径>",
//       "toolCallTimeoutMs": 60000,
//       "failOnStartupError": false,
//       "reconnect": { "intervalMs": 500, "maxRetries": 30, "delayMs": 30000 },
//       "env": { "FIST_DB_PATH": "<你的库路径>", "FIST_PROJECT_DIR": "<repo绝对路径>" }
//     }
//   }
// }
// 用 `mcp_config_scaffold`（工具名 mcp_config_scaffold）传入上面的偏好即可生成同款正文；
// 它会把未知字段回显到 unknown_keys 供调试，但**拒绝**含 api_key/token/secret 形状的表单。

import { spawn } from 'node:child_process';
import readline from 'node:readline';

const MCP_PROTOCOL_VERSION = '2026-07-28';
const MCP_META_PV = 'io.modelcontextprotocol/protocolVersion';
const MCP_META_CAPS = 'io.modelcontextprotocol/clientCapabilities';
const MCP_META_INFO = 'io.modelcontextprotocol/clientInfo';
const MCP_META_SERVER_INFO = 'io.modelcontextprotocol/serverInfo';

// ---- 解析命令行 ----
const args = process.argv.slice(2);
let serverCmd = ['node', 'dist/fist-mbt.js', 'serve'];
const serverIdx = args.indexOf('--server');
if (serverIdx >= 0 && serverIdx + 1 < args.length) {
  serverCmd = args.slice(serverIdx + 1);
}

// ---- 启动 server 子进程 ----
const child = spawn(serverCmd[0], serverCmd.slice(1), {
  stdio: ['pipe', 'pipe', 'inherit'],
  env: process.env,
});
child.on('error', (err) => {
  console.error('[shim] server spawn failed:', err.message);
  process.exit(1);
});
child.on('exit', (code, signal) => {
  // signal 崩溃时 code 为 null，旧写法 `code ?? 0` 会误报成功退出——必须非零
  if (signal) {
    console.error(`[shim] server terminated by signal ${signal}`);
    process.exit(1);
  }
  process.exit(code ?? 1);
});

// id -> 客户端请求的协议版本（用于响应回写）
const pendingInits = new Map();

// id -> 请求超时计时器（A4：server 长时间不响应时回 -32000，避免客户端永久挂起）
const pendingTimers = new Map();
// A4：默认 30s；可用环境变量 FIST_SHIM_TIMEOUT_MS 覆盖（测试/长任务用）
const REQUEST_TIMEOUT_MS = parseInt(process.env.FIST_SHIM_TIMEOUT_MS || '30000', 10);

function armTimeout(id) {
  // 同一 id 重复转发（罕见）先清掉旧计时器
  clearTimeout(pendingTimers.get(id));
  const t = setTimeout(() => {
    pendingTimers.delete(id);
    pendingInits.delete(id);
    process.stdout.write(JSON.stringify({
      jsonrpc: '2.0', id,
      error: { code: -32000, message: `Request timed out after ${REQUEST_TIMEOUT_MS}ms (shim A4 timeout)` },
    }) + '\n');
  }, REQUEST_TIMEOUT_MS);
  // 计时器不阻止进程退出（server 死掉时 shim 也能立即 exit）
  t.unref?.();
  pendingTimers.set(id, t);
}

function disarmTimeout(id) {
  const t = pendingTimers.get(id);
  if (t) { clearTimeout(t); pendingTimers.delete(id); }
}

// 给 params 补 _meta 三元组（fist-mbt server 每个请求都强制要求）
function ensureMeta(params, isInit) {
  params = params || {};
  params._meta = params._meta || {};
  if (params._meta[MCP_META_PV] == null) {
    params._meta[MCP_META_PV] = MCP_PROTOCOL_VERSION;
  }
  if (params._meta[MCP_META_CAPS] == null) {
    params._meta[MCP_META_CAPS] = params.capabilities || {};
  }
  if (params._meta[MCP_META_INFO] == null) {
    params._meta[MCP_META_INFO] = isInit
      ? (params.clientInfo || { name: 'legacy-client', version: '0.0.0' })
      : (params.clientInfo || { name: 'legacy-client', version: '0.0.0' });
  }
  return params;
}

// ---- 客户端 stdin → 改写 → server stdin ----
const stdinRl = readline.createInterface({ input: process.stdin });
stdinRl.on('line', (line) => {
  if (!line.trim()) return;
  let msg;
  try { msg = JSON.parse(line); } catch { child.stdin.write(line + '\n'); return; }

  if (msg.method === 'initialize') {
    // 记录客户端期望的协议版本
    const clientPV = msg.params?.protocolVersion || MCP_PROTOCOL_VERSION;
    pendingInits.set(msg.id, clientPV);
    // 改写为 server/discover（server 已移除标准 initialize）
    msg.method = 'server/discover';
    msg.params = ensureMeta(msg.params, true);
  } else if (msg.method === 'ping') {
    // fist-mbt server（colmugx/mcp@0.17.4）已移除 ping，直连会吃 -32601；
    // 标准 MCP 客户端用它做健康检查。此处直接回空 result，不转发。
    process.stdout.write(JSON.stringify({ jsonrpc: '2.0', id: msg.id, result: {} }) + '\n');
    return;
  } else if (msg.method === 'logging/setLevel') {
    // MCP 可选特性：server 未实现 logging。返回空结果告知客户端"已接受"（无害 no-op，
    // server 本来就不发 notifications/message），比 -32601 更友好。
    process.stdout.write(JSON.stringify({ jsonrpc: '2.0', id: msg.id, result: {} }) + '\n');
    return;
  } else if (msg.method === 'completion/complete') {
    // MCP 可选特性：server 未实现 completion。返回空补全列表（合法响应）。
    process.stdout.write(JSON.stringify({
      jsonrpc: '2.0', id: msg.id, result: { completion: { values: [] } },
    }) + '\n');
    return;
  } else if (msg.id !== undefined) {
    // 非通知请求（有 id，期待响应）都要补 _meta，否则 -32602；
    // ping 这类无 params 的方法也要补 params，否则 server 解析不到 _meta
    msg.params = ensureMeta(msg.params, false);
  }
  // notifications/* 无 id，不需要响应，也无需补 _meta，原样透传
  // A4：有 id 的请求启动超时计时器（通知不计时）
  if (msg.id !== undefined) armTimeout(msg.id);
  child.stdin.write(JSON.stringify(msg) + '\n');
});

// ---- server stdout → 改写 → 客户端 stdout ----
const childRl = readline.createInterface({ input: child.stdout });
childRl.on('line', (line) => {
  if (!line.trim()) return;
  let resp;
  try { resp = JSON.parse(line); } catch { process.stdout.write(line + '\n'); return; }

  // A4：收到响应（不管 id 是否 pendingInits），解除超时计时器
  disarmTimeout(resp.id);

  if (pendingInits.has(resp.id)) {
    const clientPV = pendingInits.get(resp.id);
    pendingInits.delete(resp.id);
    if (resp.error) {
      // server 报错：原样透传（客户端能看到真实错误）
      process.stdout.write(line + '\n');
      return;
    }
    // 构建标准 initialize 响应
    const result = resp.result || {};
    const meta = result._meta || {};
    const legacyResult = {
      serverInfo:
        meta[MCP_META_SERVER_INFO] || result.serverInfo || {},
      protocolVersion: clientPV, // 回写客户端请求的那一档，让客户端认为协商成功
      capabilities: result.capabilities || {},
    };
    process.stdout.write(JSON.stringify({ ...resp, result: legacyResult }) + '\n');
  } else {
    process.stdout.write(line + '\n');
  }
});