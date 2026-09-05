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

repository = ""

license = "Apache-2.0"

keywords = []

preferred_target = "wasm"

description = ""

import {
  "mizchi/sqlite@0.3.1",
  "colmugx/mcp@0.17.4",
  "moonbitlang/async@0.21.0",
}

