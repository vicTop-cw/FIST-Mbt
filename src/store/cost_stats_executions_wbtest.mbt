///|
// BUG-94 白盒锁：executions 表必须在**开库时就存在**，且只读聚合在**表被删掉的库**上也要能自保。
//
// 为什么这条必须存在（实测形状）：安装版一次 `cost_stats`（纯只读工具）就能打死整个 MCP server
// —— js 桥的 `Database.prepare` 遇缺表是**抛异常**而不是返回 None，未捕获异常一路终止进程。
// 2026-09-28 三格全复现（仓库根/无参、仓库根/带 ns、临时 box/无参），错误原文
// `Error: no such table: executions` @ SqliteStore::list_all_executions ← aggregate_stats。
// 旧代码只在**写**路径 `record_execution` 里 ensure 过表 ⇒ 任何"先写后读"的既有测试都碰不到；
// 这里两步都是**只读**，且第二格主动把表摘掉，才打得到那条路。
// 为什么是 wbtest 而不是 test：需要 `s.db` 与 `exec`（包内可见），黑盒拿不到"删表"这个动作。

///|
test "cost_stats: 开库即有 executions 表（建表清单漏它 ⇒ prepare 抛异常打死 server）" {
  match SqliteStore::open("temp/cost_stats_schema_wb.db") {
    None => fail("sqlite open 失败：判据根本没跑到被测面")
    Some(s) =>
      match s.db {
        None => fail("db 句柄为空：无法验证建表清单")
        Some(db) =>
          // 第一格：刚开完库，不做任何写动作，直接查表 —— 旧代码在这里就抛
          // assert_eq 而不是 assert_true：这一版的 assert_true 不接消息位，
          // 红的时候必须能看出是"表没建"而不是"断言写错了"
          assert_eq(db.exec("SELECT 1 FROM executions"), true)
      }
  }
}

///|
test "cost_stats: 表被摘掉后只读聚合必须自保并回零值" {
  match SqliteStore::open("temp/cost_stats_ensure_wb.db") {
    None => fail("sqlite open 失败：判据根本没跑到被测面")
    Some(s) =>
      match s.db {
        None => fail("db 句柄为空")
        Some(db) => {
          // 第二格：模拟"早于补表建号的老库"——表不存在时读聚合
          assert_eq(db.exec("DROP TABLE IF EXISTS executions"), true)
          let j = StoreBackend::sqlite(s).cost_stats()
          match j.value("total_records") {
            Some(Number(n, ..)) => assert_eq(n, 0.0)
            _ =>
              fail(
                "cost_stats 回执里没有 total_records：" + j.stringify(),
              )
          }
        }
      }
  }
}
