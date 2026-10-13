# mcpcf.* 内置化接入 FIST-Mbt serve 模式（收尾记录）

日期：2026-10-12
范围：mcpconftest 的 mcpcf.* 工具链以 vendor 方式内置进 FIST-Mbt serve 模式。

## 接入内容

- `src/server/mcpcf_embed.mbt`：mcpcf 工具链嵌入层（16347 B），依赖 `@engine` / `@core` 本地 API，
  避免跨模块循环依赖。含 EngineHolder 可变引擎持有者、`ensure_engine` / `reset_engine` / `now_utc`、
  参数解析、7 个工具函数与 `embed_mcpcf_tools` 链式注册。
- 数据隔离：默认 `%LOCALAPPDATA%\mcpconftest\data\mcpconftest-ops.db`，`MCPCONFTEST_DATA_DIR` 可覆盖。
- 挂载点：`src/server/stdio_js.mbt` 与 `src/server/stdio_native.mbt` 均调用 `embed_mcpcf_tools(s)`。
- 7 工具固定：`mcpcf.ops_init / run_batch / verify / watchdog / report / circuit / review`。

## 验证结论

native 与 js 双端均通过 `tools/list`（147 工具含 7 个 mcpcf.*）+ 实操验证：

| 项 | native (cmd/cli cli.exe) | js (cmd/cli cli.js) |
|---|---|---|
| tools/list 含 7 个 mcpcf.* | PASS | PASS |
| mcpcf.ops_init | sqlite 后端 ok | sqlite 后端 ok |
| mcpcf.run_batch | T0 创建 ok | T0 创建 ok |
| mcpcf.report | - | total=1 查询 ok |

> 入口注记（2026-10-13 补）：本表 native 端当时以 cmd/main 构建（该入口其后已退役）。
> 现役发布入口统一为 cmd/cli，且它**同时支持 native 与 js 两端**
> （cmd/cli/moon.pkg 的 supported_targets = "js+native"）；本表已按现役入口改写，
> 实测 moon build cmd/cli --target native rc=0、产物 _build/native/debug/build/cmd/cli/cli.exe。
> 历史构建命令见本文件「相关命令」的注记。

## JS 端启动须知（重要）

1. JS bundle 顶层 `require("node:sqlite")` 在 ESM 作用域未定义（mizchi/sqlite 生成代码），
   `node cli.js serve` 直接启动会 `ReferenceError`。这是 FIST-Mbt JS target 既有问题
   （`src/server/server.mbt` 模块顶层 `SqliteStore::new()`），非 mcpcf 引入回归。
2. 启动需注入 require shim：
   ```
   node --import <repo>/scripts/js_serve_preload.mjs <repo>/_build/js/debug/build/cmd/cli/cli.js serve
   ```
   要求 Node >= 22.5（`node:sqlite` 内置模块）。Node 会打印 SQLite ExperimentalWarning，无碍。
3. 协议注意（2026-07-28）：
   - `initialize` 已从协议移除，发送会得到 -32601 "Method not found: initialize"（预期行为，非错误）；
   - 每个请求 `params` 必须携带 `_meta`：`io.modelcontextprotocol/protocolVersion` +
     `io.modelcontextprotocol/clientCapabilities`，否则 -32602。

## 相关命令

```
moon build cmd/cli --target native   # native 端 serve：_build/native/debug/build/cmd/cli/cli.exe
moon build cmd/cli --target js       # js 端 serve：_build/js/debug/build/cmd/cli/cli.js
`

> 注（2026-10-13）：上面的 native 行原以退役入口 cmd/main 构建（产物落在该包目录下的可执行文件）——
> cmd/main 已退役，现役入口统一为 cmd/cli（supported_targets = "js+native"，两端同一入口）。
> 两行均已按现役入口实测：--target native rc=0 ⇒ …/cmd/cli/cli.exe；--target js ⇒ …/cmd/cli/cli.js。``
