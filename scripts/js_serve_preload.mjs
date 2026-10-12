// js_serve_preload.mjs — ESM require shim for the MoonBit JS bundle.
//
// WHY: FIST-Mbt's JS bundle (built by `moon build --target js`) is emitted as an
// ES module, but mizchi/sqlite's generated binding calls `require("node:sqlite")`
// at the top level. In ESM scope `require` is undefined, so `node cli.js serve`
// crashes with `ReferenceError: require is not defined` before the server starts.
// (Native builds are unaffected; this is a JS-target-only startup concern.)
//
// USE:
//   node --import <repo>/scripts/js_serve_preload.mjs <repo>/_build/js/debug/build/cmd/cli/cli.js serve
//
// The shim injects a CommonJS `require` resolved against this module, letting the
// bundle reach Node's built-in `node:sqlite` (Node >= 22.5). Node prints an
// ExperimentalWarning for SQLite; it is harmless.
import { createRequire } from 'node:module';
globalThis.require = createRequire(import.meta.url);
