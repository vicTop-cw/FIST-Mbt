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

version = "0.3.10"

readme = "README.mbt.md"

repository = "https://github.com/vicTop-cw/FIST-Mbt"

license = "Apache-2.0"

keywords = [ "MCP", "task-orchestration", "multi-agent", "FIST" ]

preferred_target = "js"

description = "FIST commander task orchestration rewritten in pure MoonBit, exposed as an MCP server."

import {
  "daqing/sqlite@0.4.0",
  "colmugx/mcp@0.18.1",
  "moonbitlang/async@0.22.3",
  "moonbitlang/x@0.5.5",
  "cc06b/mooncry@0.13.1",
  "vicTop-cw/RX-MBT@0.4.0",
}
