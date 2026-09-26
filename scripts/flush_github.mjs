#!/usr/bin/env node
/**
 * flush_github.mjs — 通过 MCP stdio 协议调用 FIST-Mbt server 的 github_flush_execute
 *
 * 用法:
 *   node scripts/flush_github.mjs [--limit 50] [--timeout-ms 30000]
 *
 * 前置条件:
 *   1. moon build --target js 产出 build/js/main.js（cmd/main 入口）
 *   2. 环境变量 FIST_GITHUB_ENABLED / FIST_GITHUB_REPO / FIST_GITHUB_TOKEN 已设置
 *
 * 退出码:
 *   0 = 全部 sent 成功（或 pending 队列为空）
 *   2 = 部分 sent 失败（让 workflow 红，但不 hard fail）
 *   1 = 协议级错误 / server 启动失败 / force 未传等硬错误
 */

import { spawn } from "node:child_process";
import { pipeline } from "node:stream/promises";
import process from "node:process";
import readline from "node:readline";

// ---------- 参数解析 ----------
const args = process.argv.slice(2);
const limit = parseInt(takeArg(args, "--limit") ?? "50", 10);
const timeoutMs = parseInt(takeArg(args, "--timeout-ms") ?? "30000", 10);
const projectDir = takeArg(args, "--project-dir") ?? ".";
// force 硬门控：脚本自身也做一次强制断言
const force = takeArg(args, "--force") === "true" || process.env.FIST_FORCE_FLUSH === "true";

if (!force) {
  console.error("❌ flush_github.mjs 需要 --force=true 或 FIST_FORCE_FLUSH=true（硬门控，防误触发）");
  process.exit(1);
}

// ---------- MCP JSON-RPC over stdio ----------
function takeArg(list, flag) {
  const i = list.indexOf(flag);
  return i >= 0 ? list[i + 1] : null;
}

function fmt(id, method, params) {
  return JSON.stringify({ jsonrpc: "2.0", id, method, params });
}
function notify(method, params) {
  return JSON.stringify({ jsonrpc: "2.0", method, params });
}

let pendingId = 0;
function nextId() { return ++pendingId; }

async function run() {
  // 启动 MCP server（moon build 后是 build/js/cmd/main/main.js 或类似路径）
  // 先尝试常见路径
  const fs = await import("node:fs");
  const path = await import("node:path");

  const candidates = [
    "build/js/cmd/main/main.js",
    "build/js/main.js",
  ];
  let serverEntry = null;
  for (const c of candidates) {
    if (fs.existsSync(c)) { serverEntry = c; break; }
  }
  if (!serverEntry) {
    console.error(`❌ 未找到 moon build 产物。尝试过: ${candidates.join(", ")}`);
    console.error("   请先执行 moon build --target js");
    process.exit(1);
  }
  console.log(`🚀 启动 MCP server: node ${serverEntry}`);

  const child = spawn(process.execPath, [serverEntry], {
    stdio: ["pipe", "pipe", "pipe"],
    env: process.env,
  });

  // 收集 stderr（server 日志）
  child.stderr.setEncoding("utf8");
  child.stderr.on("data", (d) => process.stderr.write(`[server-stderr] ${d}`));

  const rl = readline.createInterface({ input: child.stdout });

  // 发送 initialize
  const initId = nextId();
  const initReq = fmt(initId, "initialize", {
    protocolVersion: "2024-11-05",
    capabilities: {},
    clientInfo: { name: "fist-flush", version: "1.0.0" },
  });
  child.stdin.write(initReq + "\n");

  // 等待 initialize 响应
  let initDone = false;
  const timeout = setTimeout(() => {
    if (!initDone) {
      console.error("❌ MCP initialize 超时");
      child.kill();
      process.exit(1);
    }
  }, 10000);

  // 行处理：匹配 id 回包
  const responseMap = new Map();
  for await (const line of rl) {
    if (!line.trim()) continue;
    let msg;
    try { msg = JSON.parse(line); } catch {
      // server 可能输出了非 JSON 日志
      process.stderr.write(`[server-nonjson] ${line}\n`);
      continue;
    }

    if (msg.id === initId && msg.result) {
      clearTimeout(timeout);
      initDone = true;
      console.log(`✅ MCP initialize ok, server=${msg.result?.serverInfo?.name ?? "?"}`);
      // 发 initialized notification
      child.stdin.write(notify("notifications/initialized") + "\n");
      break;
    }
    if (msg.id !== undefined) {
      responseMap.set(msg.id, msg);
    }
  }

  // 调用 github_flush_execute
  const callId = nextId();
  const callReq = fmt(callId, "tools/call", {
    name: "github_flush_execute",
    arguments: { project_dir: projectDir, force: true, limit },
  });
  console.log(`📤 调 github_flush_execute(project_dir="${projectDir}", force=true, limit=${limit})`);
  child.stdin.write(callReq + "\n");

  // 等待响应
  const callTimeout = setTimeout(() => {
    console.error("❌ github_flush_execute 超时");
    child.kill();
    process.exit(1);
  }, timeoutMs);

  let callResult = null;
  for await (const line of rl) {
    if (!line.trim()) continue;
    let msg;
    try { msg = JSON.parse(line); } catch { continue; }

    if (msg.id === callId) {
      clearTimeout(callTimeout);
      callResult = msg;
      break;
    }
  }

  // 关闭 server
  child.stdin.end();
  await new Promise((r) => child.on("close", r));

  // ---------- 解析结果 ----------
  if (!callResult) {
    console.error("❌ 未收到 github_flush_execute 响应");
    process.exit(1);
  }

  if (callResult.error) {
    console.error("❌ MCP error:", JSON.stringify(callResult.error));
    process.exit(1);
  }

  const content = callResult.result?.content ?? [];
  const textBlock = content.find((c) => c.type === "text")?.text;
  let data;
  try { data = JSON.parse(textBlock); } catch {
    console.error("❌ 响应 text 非 JSON:", textBlock);
    process.exit(1);
  }

  console.log("\n📋 flush 结果:");
  console.log(JSON.stringify(data, null, 2));

  // 根据 server 返回判定
  const sent = data.sent ?? data.sent_ok ?? [];
  const failed = data.failed ?? data.sent_fail ?? [];
  const skipped = data.skipped ?? [];
  const total = sent.length + failed.length + skipped.length;

  console.log(`\n📊 统计: total=${total} sent=${sent.length} failed=${failed.length} skipped=${skipped.length}`);

  if (failed.length > 0) {
    console.error(`⚠️ 有 ${failed.length} 条 failed，workflow 将标黄（退出码=2）`);
    process.exit(2);
  }
  console.log("✅ 全部 sent 成功");
  process.exit(0);
}

run().catch((e) => {
  console.error("💥 脚本异常:", e);
  process.exit(1);
});
