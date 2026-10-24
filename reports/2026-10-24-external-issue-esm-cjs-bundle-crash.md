# fist-mbt 问题报告：CLI/`serve` 因 ESM/CJS 混用**整体崩溃**（`require is not defined in ES module scope`）

> **入库说明（统帅/司令-ε，2026-10-24）**：本报告由外部项目 Pentad 统帅提交，原文保留，仅把本机绝对路径脱敏为 `<repo>`（原文是真实崩溃输出，路径形状不影响结论）。
> **现状核对**：`patch_esm_main.py` 的 LOCAL-SHIM 已注入并通过 `version`/`doctor` 实测；但**账本 `memory/bugs.md` 里查不到 BUG-406**（最大编号 BUG-404）——本报告正文提到的"登记为 BUG-406"与账本现状不符，需主人裁决分配正式编号。


- **报告时间**：2026-10-24
- **报告人**：Pentad 统帅（在 Pentad 项目 `E:\IDEProjects\AI\Pentad` 中使用 fist-mbt 时发现）
- **fist-mbt 版本**：`0.3.10`（`E:\IDEProjects\AI\FIST-Mbt`）
- **严重度**：**高（阻断性）**——`fist-mbt doctor` / `version` / `serve` 全部崩溃，**SQLite store 完全不可用**
  （`publish`/`claim`/`execute`/MCP 持久化层都走 `SqliteStore`）

## 复现

```powershell
cd E:\IDEProjects\AI\FIST-Mbt
fist-mbt doctor     # 或 fist-mbt version / fist-mbt serve
```

**实际输出**（stderr，exit 1）：

```
file:///<repo>/_build/js/debug/build/cmd/cli/cli.js:2454
const _M0FP26daqing6sqlite19new__database__sync = (path, opts) => new (require("node:sqlite").DatabaseSync)(path, opts);
                                                                  ^
ReferenceError: require is not defined in ES module scope, you can use import instead
This file is being treated as an ES module because it has a '.js' file extension and
'\?\<repo>\package.json' contains "type": "module".
```

## 根因（已定位到具体一行）

- `<repo>\package.json` 声明 **`"type": "module"`** ⇒ Node 把所有 `.js` 当 **ESM**。
- 打包产物 `_build/js/debug/build/cmd/cli/cli.js:2454` 却使用了 **CommonJS 的 `require("node:sqlite")`**：
  ```js
  const _M0FP26daqing6sqlite19new__database__sync = (path, opts) =>
      new (require("node:sqlite").DatabaseSync)(path, opts);
  ```
- ESM 作用域里没有 `require` ⇒ `ReferenceError`。
- 该 bundle 里 `require(` **恰好只有这 1 处**（`node:sqlite` 的互操作层），说明是**打包器生成 CJS 互操作时
  漏了 ESM 垫片**（`createRequire(import.meta.url)`），而非源码里到处用 `require`。

## 影响面

| 命令 | 结果 |
|------|------|
| `fist-mbt doctor` | 💥 崩溃（`SqliteStore.open` 路径） |
| `fist-mbt version` | 💥 崩溃 |
| `fist-mbt serve` | 💥 崩溃（MCP server 起不来） |
| `fist-mbt demo` | ✅ 可用（纯内存 store，不碰 SQLite） |

⇒ **MCP server 与全部持久化能力当前不可用**；之前用 MCP 记账的流程已实际中断（Pentad 侧本轮改用 CLI 探测才
发现 CLI 也崩）。

## 建议修复（任选其一）

1. **在 bundle 的 ESM 作用域里补 `require` 垫片**（最小改动）：
   在 `cli.js` 顶部（`"use strict"`/导入之后）加：
   ```js
   import { createRequire } from "node:module";
   const require = createRequire(import.meta.url);
   ```
   或让打包器对 `node:sqlite` 生成 `createRequire` 包装。
2. **把 `node:sqlite` 的调用改成 ESM 形态**：`import { DatabaseSync } from "node:sqlite"`（Node 22+）。
3. **检查打包配置**：`moon`/esbuild/rspack 的产物若目标为 `.js` 且 `type: module`，
   CJS 互操作必须显式垫片；建议加一条 **启动自检**（`node _build/js/debug/build/cmd/cli/cli.js doctor`）进 CI，
   免得这种"打包产物坏了但源码看着对"的问题拖到发布后。

## 根因定位（R35 追加）——上游依赖 `daqing/sqlite`

追到 **`daqing/sqlite@0.4.0`** 的 MoonBit JS FFI 声明 `sqlite_js.mbt:13`：

```mbt
extern "js" fn new_database_sync(path : String, opts : JsAny) -> NodeDatabaseSync =
  #| (path, opts) => new (require("node:sqlite").DatabaseSync)(path, opts)
```

该 `require("node:sqlite")` 是 **CJS 语法**；MoonBit 把它原样打进 **ESM** 产物（`package.json` 是 `"type": "module"`）
⇒ ESM 作用域没有 `require` ⇒ `ReferenceError`。

**根治**：上游 `daqing/sqlite` 把该行改成 ESM 形态（Node 22+ `import { DatabaseSync } from "node:sqlite"`，
或 MoonBit 的 `#external` FFI 声明），重发新版本；FIST-Mbt 升依赖。

**本仓无法在打包配置层根治**（缺陷在依赖源码里），故本仓的 `require` 垫片是唯一可立即解锁的手段，
且 rebuil 会覆盖——**保持 BUG-406 OPEN，标注"局部解锁，待上游根治"**。

## 本仓构建层修复（R36 追加）

仓库既有 `scripts/patch_esm_main.py`（BUG-138 同族）原本只 patch **最大的**一个 bundle，
漏了 `cmd/cli/cli.js` / `cmd/commissar/commissar.js` / `smoke/smoke.js`。已改为 **patch 全部**可执行 bundle，
并把 R31 的手动垫片移除、统一交该脚本（单一真源）。实测 patch 4/4，`fist-mbt doctor` 5/5。

**注意**：这是**构建层**的稳定解锁；**根治仍在上游 `daqing/sqlite`**（须把 FFI 改 ESM 形态重发 + 升依赖）。

## 附加观察（非本条阻塞，供参考）

- 同一次探测还发现：`doctor` 的 `[4/5] 七态机闭环` 报失败，而 `fist-mbt demo`（同一七态闭环）**全绿** ——
  两处对同一闭环的断言/实现不一致（`demo` 与 `doctor` 的检查函数不同），建议对齐。
