///|
/// commissar native 占位：政委体系事件驱动依赖 node fs.watch（js 目标）。
/// native 目标仅保证构建通过，运行提示使用 js 目标。
fn main {
  println(
    "commissar: 本命令仅支持 js 目标（node fs.watch 事件驱动），请使用 --target js 构建后以 node 运行",
  )
}
