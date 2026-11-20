///|
/// store_fb_test.mbt —— F094 Phase 1 file_binds 跨进程账本的黑盒回归。
/// 「重开库再读回」是跨进程可见性的进程内代理（真两进程黑盒判据在
/// scripts/blackbox/e2e_filebind_xproc.py，见 F094 验收 §七）。
///
/// 键 = (ns, project_dir, path)；载荷 = bind_json（archive.task_json 同款模式）。
/// 唯一真相 = 持久化表；进程内状态不许冒充落库（BUG-119 同族哲学）。

///|
/// 构造一条绑定（走 fb_of_json 与服务端同一条解析路径，不抄字段表）。
fn fb_test_bind(
  ns : String,
  pd : String,
  path : String,
  holder : String,
) -> @filebind.FileBind? {
  let j : Json = {
    "ns": Json::string(ns),
    "project_dir": Json::string(pd),
    "path": Json::string(path),
    "holder": Json::string(holder),
    "task_id": Json::string("T1"),
    "kind": Json::string("file"),
    "scope": Json::string("edit"),
    "intent": Json::string("F094 roundtrip"),
    "bound_at": Json::number(100.0),
    "ttl_secs": Json::number(3600.0),
  }
  @filebind.fb_of_json(j)
}

///|
test "fb_roundtrip_reopen_persists" {
  let path = bug462_unique_db("fb_roundtrip")
  let ns = "fb-roundtrip"
  let pd = "/proj/fb"
  // 进程 A：事务写一笔绑定
  match SqliteStore::open(path) {
    Some(st) => {
      let b = fb_test_bind(ns, pd, "src/a.mbt", "agent-A")
      let ok = st.fb_txn(ns, pd, fn(_ledger) {
        match b {
          Some(b) => [b]
          None => []
        }
      })
      assert_true(ok)
      st.close()
    }
    None => assert_true(false)
  }
  // 进程 B：重开（跨进程代理）——绑定仍在
  match SqliteStore::open(path) {
    Some(st) => {
      let rows = st.fb_list_rows(ns, pd)
      assert_eq(rows.length(), 1)
      assert_eq(rows[0].path, "src/a.mbt")
      assert_eq(rows[0].holder, "agent-A")
      assert_eq(rows[0].task_id, "T1")
      st.close()
    }
    None => assert_true(false)
  }
}

///|
test "fb_replace_all_semantics" {
  let path = bug462_unique_db("fb_replace")
  let ns = "fb-replace"
  let pd = "/proj/fb2"
  match SqliteStore::open(path) {
    Some(st) => {
      // 第一笔：两条绑定
      let b1 = fb_test_bind(ns, pd, "src/a.mbt", "agent-A")
      let b2 = fb_test_bind(ns, pd, "src/b.mbt", "agent-B")
      let ok1 = st.fb_txn(ns, pd, fn(_ledger) {
        match (b1, b2) {
          (Some(x), Some(y)) => [x, y]
          _ => []
        }
      })
      assert_true(ok1)
      assert_eq(st.fb_list_rows(ns, pd).length(), 2)
      // 第二笔：裁决后只剩一条（release = 删行，replace-all 落库）
      let keep = st.fb_list_rows(ns, pd)
      let ok2 = st.fb_txn(ns, pd, fn(_ledger) {
        match keep[0] {
          _ => [keep[0]]
        }
      })
      assert_true(ok2)
      let rows = st.fb_list_rows(ns, pd)
      assert_eq(rows.length(), 1)
      assert_eq(rows[0].path, "src/a.mbt")
      st.close()
    }
    None => assert_true(false)
  }
}

///|
test "fb_ns_isolation" {
  let path = bug462_unique_db("fb_ns")
  let pd = "/proj/fb3"
  match SqliteStore::open(path) {
    Some(st) => {
      let b = fb_test_bind("ns-x", pd, "src/a.mbt", "agent-A")
      let ok = st.fb_txn("ns-x", pd, fn(_ledger) {
        match b {
          Some(x) => [x]
          None => []
        }
      })
      assert_true(ok)
      // 跨 ns 不可见
      assert_eq(st.fb_list_rows("ns-y", pd).length(), 0)
      assert_eq(st.fb_list_rows("ns-x", pd).length(), 1)
      st.close()
    }
    None => assert_true(false)
  }
}
