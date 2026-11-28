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

version = "0.3.16"

readme = "README.mbt.md"

repository = "https://github.com/vicTop-cw/FIST-Mbt"

license = "Apache-2.0"

keywords = [ "MCP", "task-orchestration", "multi-agent", "FIST" ]

preferred_target = "js"

description = "FIST commander task orchestration rewritten in pure MoonBit, exposed as an MCP server."

import {
  "daqing/sqlite@0.4.0",
  "colmugx/mcp@0.18.1",
  "moonbitlang/async@0.22.11",
  "moonbitlang/x@0.5.5",
  "cc06b/mooncry@0.13.1",
  "vicTop-cw/RX-MBT@0.5.1",
  "vicTop-cw/mcp-watcher@0.2.5",
  // vsql-w3-spike: vsql-mbt 本地 mooncakes 缓存依赖（.mooncakes/vicTop-cw/vsql-mbt，gitignore；
  // 供 spike/vsql_preflight 在任务发布前跑 preflight 门。完整模块另需 x@0.5.9/async，FIST-Mbt 上下文锁 x@0.5.5，
  // spike 只 import core+analyze，零第三方依赖，不升级 FIST-Mbt 的 x）。详见 reports/vsql-w3-spike.
  "vicTop-cw/vsql-mbt@0.1.0",
}
