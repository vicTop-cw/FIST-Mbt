// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "vicTop-cw/fist-mbt"

version = "0.1.0"

readme = "README.mbt.md"

repository = "https://github.com/vicTop-cw/FIST-Mbt"

license = "Apache-2.0"

keywords = ["MCP", "task-orchestration", "multi-agent", "FIST"]

preferred_target = "wasm"

description = "FIST commander task orchestration rewritten in pure MoonBit, exposed as an MCP server."

import {
  "mizchi/sqlite@0.3.1",
  "colmugx/mcp@0.17.4",
  "moonbitlang/async@0.21.0",
  "moonbitlang/x@0.4.40",
}

