/// multi_store_bug649_wbtest.mbt —— BUG-649「default 路由统一」的白盒锁。
///
/// 病灶：`MultiStore::get("default")` 对任意合法 ns 惰性建 `<data_dir>/<ns>.db`，
/// 于是 task_query/task_events/file_bind 等直连本函数的调用点对 default 全部
/// 落到 0 字节幽灵库 `data/default.db`，与 `engine_for_ns` 的「default=主库」
/// （BUG-433 锁定的语义）形成两套真相。
///
/// 修法：MultiStore 注入主库句柄（`main`），get/open 对 default 特判回主库；
/// 无主库句柄（纯 MultiStore 测试/内存后端）时保持旧惰性语义零回归。
///
/// 锁 1：有主库句柄 ⇒ get("default") 返回主库句柄（行为证据：主库写入的审计
///       行能从 get("default") 的句柄读出），且**不产生** data/default.db。
/// 锁 2：open("default") 直接 true（幂等，不落幽灵库文件）。
/// 锁 3：无主库句柄 ⇒ 保持旧惰性语义（data/default.db 照建，零回归格）。

///|
test "bug649_default_routes_to_main" {
  // BUG-462 去共享：固定路径跨运行累积 T-BUG649 行（event_list 上限 10，
  // 跑满 10 轮后必红）⇒ 每次运行唯一路径（bug462_unique_db/unique_dir 同源）
  let main_path = bug462_unique_db("bug649_main")
  let main = match SqliteStore::open(main_path) {
    Some(s) => s
    None => abort("bug649: 主库句柄打不开")
  }
  let data_dir = bug462_unique_dir("bug649_data")
  let ms = MultiStore::new(
    data_dir=data_dir,
    main=Some(main),
  )
  // 主库写入一条审计行 —— 行为探针（store 层可观察，不依赖 @core）
  ignore(
    main.event_append(
      "default", "T-BUG649", "submitted", "t", "", "2026-01-01T00:00:00Z",
    ),
  )
  // get("default") 必须拿到主库句柄：能读到刚写的那一行
  let got = match ms.get("default") {
    Some(s) => s
    None => abort("BUG-649：get(default) 应返回主库句柄")
  }
  let ev = got.event_list("default", "T-BUG649", 10)
  if ev.length() != 1 {
    abort(
      "BUG-649：get(default) 拿到的不是主库句柄（审计行读不出，实得 " +
      ev.length().to_string() +
      " 条）",
    )
  }
  // 幽灵库不得产生
  if db_file_exists(data_dir + "/default.db") {
    abort("BUG-649：get(default) 仍创建了 data/default.db 幽灵库")
  }
  // open("default") 直接 true（主库已打开）
  if !ms.open(ns="default", data_dir=data_dir) {
    abort("BUG-649：open(default) 应直接 true")
  }
}

///|
test "bug649_no_main_keeps_legacy" {
  // 无主库句柄（纯 MultiStore 使用方，既有测试/内存后端场景）：旧惰性语义零回归
  // BUG-462 去共享：同样唯一目录（避免跨运行的幽灵库文件互相干扰）
  let data_dir = bug462_unique_dir("bug649_legacy")
  let ms = MultiStore::new(data_dir=data_dir)
  match ms.get("default") {
    Some(_) => ()
    None =>
      abort(
        "BUG-649：无主库句柄时应保持旧惰性语义（能打开 data/default.db）",
      )
  }
  if !db_file_exists(data_dir + "/default.db") {
    abort(
      "BUG-649：零回归格 —— 旧惰性行为丢失（data/default.db 未建）",
    )
  }
}
