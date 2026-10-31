// docs/examples/fetch/http_api.mjs — 多语言接入的 fetch (Node 18+ / 浏览器同形) 示例
// 计划 multilang §4「HTTP 直连：curl / requests / HttpClient / fetch 二选一即可」的 fetch 格。
// 契约真源 docs/openapi/fist.yaml；桥起法：python scripts/run_fist_mbt_http.py [port]
// 用法：node docs/examples/fetch/http_api.mjs [port]     # 默认 3137
// 无依赖（fetch 是 Node 18+ 全局；浏览器里去掉 process 行即可原样跑）。
const BASE = `http://127.0.0.1:${process.argv[2] ?? "3137"}`;

// 1) 自描述：清单 + inputSchema 就是参数真源，别硬编码参数表
const { tools } = await (await fetch(`${BASE}/tools`)).json();
console.log(`[1] GET /tools => ${tools.length} 个工具；示例 ${tools[0].name} 参数:`,
  Object.keys(tools[0].inputSchema?.properties ?? {}));

// 2) 调用：body 就是该工具的 arguments（无参传 {}）；回执已剥壳（data 便利，result 原样）
const r = await (await fetch(`${BASE}/tools/mode_list/call`, {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: "{}",
})).json();
console.log(`[2] POST /tools/mode_list/call => ok=${r.ok} 模式:`,
  (r.data ?? []).map((m) => m.mode).join(", ") || "（见 result）");

console.log("FETCH-EXAMPLE PASS");
