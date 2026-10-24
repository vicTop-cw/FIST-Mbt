# tests/ —— 非入口的验收辅助包

本目录承载**不作为用户面入口**的 MoonBit 可执行包（`pkgtype(kind: "executable")`
但不在 `cmd/` 下、不进发布面、不被 `check_entry_paths.py` 登记为入口）。

| 包 | 用途 |
|---|---|
| `smoke/` | SQLite smoke walker（M1 验收辅助，非交付代码；`tests/smoke/main.mbt:2` 自述）|

**为什么不放 `cmd/`**：`check_entry_paths.py` 把 `cmd/*` 下非发布入口一律判为「退役入口」
（`retired = [e for e in entries if e != ship]`，`ship` 恒为 `cmd/cli`），迁入会被登记成退役
入口并造出假红——2026-10-24 实测：迁入后入口清单读作 `退役 cmd/commissar, main, smoke`，
且任何指向 `cmd/smoke` 的文档当天判红。

**为什么不用 `src/`**：本包是 `pkgtype(executable)`；`src/` 下按库（`@lib` 等）被导入，
放进去会让「库面」与「可执行面」混在一起。

**同类先例**：根级包目录 `atgc/`、`atgc-old/`、`omega/` 也都不在 `cmd/`/`src/` 下，各自
`moon.pkg` 自成一包、`moon build` 照常认、`check_entry_paths` 不登记为入口。

## 运行

```bash
moon build --target js tests/smoke
python scripts/patch_esm_main.py _build/js/debug/build/tests/smoke/smoke.js
node _build/js/debug/build/tests/smoke/smoke.js
```

`moonc` 对 `cmd/cli` 一类包输出 ESM，而 `mizchi/sqlite` 的 JS 桩用 CJS `require` ⇒ 产物必须先过
`patch_esm_main.py` 注入 require shim，否则跑起来是
`ReferenceError: require is not defined in ES module scope`。
