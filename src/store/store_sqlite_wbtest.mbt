///|
/// store_sqlite_wbtest.mbt —— P11 第 1 轮：file_binds 缺列导致 MCP server crash 的回归锁。
///
/// 缺陷本体：`fb_purge_expired` / `fb_release_task` 的 DELETE 分别引用
/// `ttl_secs`/`bound_at` 与 `task_id`，但旧 create_schema 的 file_binds 建表只有
/// id/ns/project_dir/path/bind_json。js 侧 prepare 遇 "no such column" 抛**未捕获异常**
/// ⇒ MCP server 退出（日志 fist_server.log:2-13：
/// `crash.uncaughtException Error: no such column: ttl_secs` / `server.exit code=1`），
/// CLI 报 `MCP server closed stdout (did it crash?)`。
///
/// 本文件锁三格：
///   (a) 新库 file_binds 含 task_id/bound_at/ttl_secs 三列；
///   (b) 旧 schema 库 open 后自动补列，且两个 DELETE 的 prepare 不再抛；
///   (c) 幂等：反复 open/close 同一库，三列各只出现一次（ADD COLUMN 不重复执行）。
///
/// 为什么 (b) 的判据是「直接调用不崩」：prepare 失败在 js 侧是**抛异常**而非返回 None，
/// 一旦没补列，测试进程当场未捕获退出——这本身就是最强判据，无需 mock。

///|
/// 读 file_binds 各列出现次数（PRAGMA table_info，列索引 1 = name）。
/// 用计数而非存在性，才能锁住 (c)「不重复加列」。
fn fb_wb_cols_count(st : SqliteStore) -> Map[String, Int] {
  let counts : Map[String, Int] = Map([])
  match st.db {
    None => counts
    Some(db) =>
      match db.prepare("PRAGMA table_info(file_binds)") {
        None => counts
        Some(stmt) => {
          while stmt.step() {
            let name = str_from_bytes(stmt.column_text(1))
            let prev = match counts.get(name) {
              Some(v) => v
              None => 0
            }
            counts.set(name, prev + 1)
          }
          stmt.finalize()
          counts
        }
      }
  }
}

///|
/// 取某列出现次数，缺列记 0。
fn fb_wb_col_n(counts : Map[String, Int], col : String) -> Int {
  match counts.get(col) {
    Some(v) => v
    None => 0
  }
}

///|
/// 造一个「旧 schema」file_binds 库：只有旧五列，无 task_id/bound_at/ttl_secs。
/// 直接对路径用 @sqlite.Database::open + exec，绕开 create_schema 的新建表 SQL。
fn fb_wb_make_legacy_db(path : String) -> Unit {
  let old_sql = "CREATE TABLE file_binds (id INTEGER PRIMARY KEY AUTOINCREMENT, ns TEXT NOT NULL DEFAULT '', project_dir TEXT NOT NULL DEFAULT '', path TEXT NOT NULL DEFAULT '', bind_json TEXT NOT NULL DEFAULT '', UNIQUE(ns, project_dir, path))"
  match @sqlite.Database::open(path) {
    None => abort("P11 旧库夹具打开失败: " + path)
    Some(db) => {
      if !db.exec(old_sql) {
        abort("P11 旧库夹具建表失败: " + path)
      }
      // Windows 上未关闭的句柄会把 .db 钉住，后续用例末尾清理删不掉。
      db.close()
    }
  }
}

///|
/// (a) 新库：file_binds 必须含 task_id/bound_at/ttl_secs 三列，各恰好一次。
test "P11_fb_new_db_has_three_columns" {
  let path = bug462_unique_db("fb_new_cols")
  match SqliteStore::open(path) {
    None => abort("P11 新库打开失败: " + path)
    Some(st) => {
      let counts = fb_wb_cols_count(st)
      assert_eq(fb_wb_col_n(counts, "task_id"), 1)
      assert_eq(fb_wb_col_n(counts, "bound_at"), 1)
      assert_eq(fb_wb_col_n(counts, "ttl_secs"), 1)
      st.close()
    }
  }
}

///|
/// (b) 旧 schema 库：open 后自动补列，且 fb_purge_expired / fb_release_task
/// 的 DELETE prepare 不再抛。未补列时这两个调用会让 js prepare 抛未捕获异常，
/// 整个测试进程当场崩——正是本格要防的 server crash 形状。
test "P11_fb_legacy_db_auto_migrates_and_prepare_ok" {
  let path = bug462_unique_db("fb_legacy_cols")
  fb_wb_make_legacy_db(path)
  match SqliteStore::open(path) {
    None => abort("P11 旧库 open 失败（补列不该拒载）: " + path)
    Some(st) => {
      let counts = fb_wb_cols_count(st)
      assert_eq(fb_wb_col_n(counts, "task_id"), 1)
      assert_eq(fb_wb_col_n(counts, "bound_at"), 1)
      assert_eq(fb_wb_col_n(counts, "ttl_secs"), 1)
      // 这两句曾抛 "no such column"；prepare 成功时两函数都返回 1（见实现）。
      assert_eq(st.fb_purge_expired("fb-legacy", 2000000000), 1)
      assert_eq(st.fb_release_task("fb-legacy", "/proj", "T1"), 1)
      st.close()
    }
  }
}

///|
/// (c) 幂等：反复 open/close 同一库，三列各只出现一次（ADD COLUMN 不重复执行）。
test "P11_fb_reopen_is_idempotent" {
  let path = bug462_unique_db("fb_reopen_idem")
  let mut i = 0
  while i < 3 {
    match SqliteStore::open(path) {
      None => abort("P11 第 \{i} 次 open 失败: " + path)
      Some(st) => {
        let counts = fb_wb_cols_count(st)
        assert_eq(fb_wb_col_n(counts, "task_id"), 1)
        assert_eq(fb_wb_col_n(counts, "bound_at"), 1)
        assert_eq(fb_wb_col_n(counts, "ttl_secs"), 1)
        st.close()
      }
    }
    i = i + 1
  }
}
