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
//   - tools/list / tools/call / resources/list 均正常返回
//   - 已知 server 侧限制：`ping` 返回 -32601 Method not found（colmugx/mcp 移除），非 shim 问题
//
// 用法（MCP 客户端把 command 指向本 shim）：
//   node scripts/mcp_compat_shim.js                       # 默认连 dist/fist-mbt.js serve
//   node scripts/mcp_compat_shim.js --server node dist/fist-mbt.js serve
//
// 客户端侧 .mcp.json 示例：
//   "command": "node",
//   "args": ["<repo>/scripts/mcp_compat_shim.js"],
//   "env": { "FIST_DB_PATH": "<你的库路径>" }

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
child.on('exit', (code) => process.exit(code ?? 0));

// id -> 客户端请求的协议版本（用于响应回写）
const pendingInits = new Map();

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
  } else if (msg.id !== undefined) {
    // 非通知请求（有 id，期待响应）都要补 _meta，否则 -32602；
    // ping 这类无 params 的方法也要补 params，否则 server 解析不到 _meta
    msg.params = ensureMeta(msg.params, false);
  }
  // notifications/* 无 id，不需要响应，也无需补 _meta，原样透传
  child.stdin.write(JSON.stringify(msg) + '\n');
});

// ---- server stdout → 改写 → 客户端 stdout ----
const childRl = readline.createInterface({ input: child.stdout });
childRl.on('line', (line) => {
  if (!line.trim()) return;
  let resp;
  try { resp = JSON.parse(line); } catch { process.stdout.write(line + '\n'); return; }

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