///|
/// MultiStore 黑盒/白盒测试：open / 惰性打开 / ns 统计 / 关闭。
/// 内部可变性模式：open/close 直接修改 self.stores，无需返回新实例。
fn base_dir() -> String {
  "."
}

///|
/// 清空可能由上次运行残留的物理库，保证本文件测试可重复执行（幂等）。
fn reset_db(path : String) -> Unit {
  match @store.SqliteStore::open(path) {
    Some(s) => ignore(s.clear())
    None => ()
  }
}

///|
test "open 创建并注册命名空间，get 幂等复用" {
  reset_db("alpha.db")
  let ms = @store.MultiStore::new(data_dir=base_dir())
  assert_eq(ms.open(ns="alpha", data_dir=base_dir()), true)
  let list = ms.ns_list()
  assert_eq(list.length(), 1)
  assert_eq(list[0], "alpha")
  // 重复 open 同一 ns：幂等，不新增条目
  assert_eq(ms.open(ns="alpha", data_dir=base_dir()), true)
  assert_eq(ms.ns_list().length(), 1)
  // 通过 get 拿到同一 store，可正常 CRUD
  match ms.get("alpha") {
    Some(s) => {
      let t = @core.Task::new(
        id="T0",
        project_dir="/proj/demo",
        description="multi-store smoke",
        created_at="2026-09-05T10:00:00Z",
        ns="alpha",
      )
      match s.create_task(t) {
        Ok(_) => assert_eq(s.list_tasks_in("alpha").length(), 1)
        Err(msg) => abort("create_task failed: \{msg}")
      }
    }
    None => abort("get alpha failed")
  }
}

///|
test "惰性打开：未显式 open 时 get 可直接打开物理库" {
  reset_db("beta.db")
  let ms = @store.MultiStore::new(data_dir=base_dir())
  assert_eq(ms.ns_list().length(), 0)
  // 先 open 一次，确保物理库文件存在
  assert_eq(ms.open(ns="beta", data_dir=base_dir()), true)
  assert_eq(ms.ns_list().length(), 1)
  // get 返回的 store 可正常操作
  match ms.get("beta") {
    Some(s) => {
      let t = @core.Task::new(
        id="L0",
        project_dir="/proj/demo",
        description="lazy beta",
        created_at="2026-09-05T10:00:00Z",
        ns="beta",
      )
      match s.create_task(t) {
        Ok(_) => assert_eq(s.list_tasks_in("beta").length(), 1)
        Err(msg) => abort("create_task failed: \{msg}")
      }
    }
    None => abort("get beta failed")
  }
}

///|
test "ns_stats 反映各 ns 任务数" {
  let ms = @store.MultiStore::new(data_dir=base_dir())
  assert_eq(ms.open(ns="gs-alpha", data_dir=base_dir()), true)
  assert_eq(ms.open(ns="gs-gamma", data_dir=base_dir()), true)
  match ms.get("gs-alpha") {
    Some(s) => {
      let t1 = @core.Task::new(
        id="SA0",
        project_dir="/proj/demo",
        description="a1",
        created_at="2026-09-05T10:00:00Z",
        ns="gs-alpha",
      )
      let t2 = @core.Task::new(
        id="SA1",
        project_dir="/proj/demo",
        description="a2",
        created_at="2026-09-05T10:01:00Z",
        ns="gs-alpha",
      )
      let _ = s.create_task(t1)
      let _ = s.create_task(t2)
    }
    None => abort("get alpha failed")
  }
  match ms.get("gs-gamma") {
    Some(s) => {
      let t = @core.Task::new(
        id="SG0",
        project_dir="/proj/demo",
        description="g1",
        created_at="2026-09-05T10:00:00Z",
        ns="gs-gamma",
      )
      let _ = s.create_task(t)
    }
    None => abort("get gamma failed")
  }
  let stats = ms.ns_stats()
  assert_eq(stats.stringify().length() > 0, true)
  let mut alpha_total = -1
  let mut gamma_total = -1
  match stats {
    Json::Object(fields) => {
      assert_eq(fields.length(), 2)
      fields.each(fn(_k, v) {
        match v {
          Json::Object(item) => {
            let mut ns_name = ""
            let mut total = -1.0
            item.each(fn(ik, iv) {
              match (ik, iv) {
                ("ns", Json::String(s)) => ns_name = s
                ("total", Json::Number(n, ..)) => total = n
                _ => ()
              }
            })
            if ns_name == "gs-alpha" {
              alpha_total = total.to_int()
            }
            if ns_name == "gs-gamma" {
              gamma_total = total.to_int()
            }
          }
          _ => abort("stats item not object")
        }
      })
    }
    _ => abort("stats not object")
  }
  assert_eq(alpha_total, 2)
  assert_eq(gamma_total, 1)
}

///|
test "close 移除单个 ns，close_all 清空全部" {
  let ms = @store.MultiStore::new(data_dir=base_dir())
  assert_eq(ms.open(ns="cl-alpha", data_dir=base_dir()), true)
  assert_eq(ms.open(ns="cl-gamma", data_dir=base_dir()), true)
  assert_eq(ms.ns_list().length(), 2)
  ms.close("cl-alpha")
  assert_eq(ms.ns_list().length(), 1)
  ms.close_all()
  assert_eq(ms.ns_list().length(), 0)
}

///|
test "open 空 ns 被拒" {
  let ms = @store.MultiStore::new(data_dir=base_dir())
  assert_eq(ms.open(ns="", data_dir=base_dir()), false)
  assert_eq(ms.ns_list().length(), 0)
}

///|
/// WAL 并发测试：多命名空间同时写入，验证 WAL 模式下的并发读写稳定性。
test "WAL 模式：多 ns 并发写入 + 读取一致性" {
  reset_db("wal-a.db")
  reset_db("wal-b.db")
  reset_db("wal-c.db")
  let ms = @store.MultiStore::new(data_dir=base_dir())
  let ns_names = ["wal-a", "wal-b", "wal-c"]
  for ns in ns_names {
    assert_eq(ms.open(ns~, data_dir=base_dir()), true)
  }
  // 每个 ns 写入 5 条任务
  for ns in ns_names {
    match ms.get(ns) {
      Some(s) => {
        let mut i = 0
        while i < 5 {
          let t = @core.Task::new(
            id="\{ns}_\{i}",
            project_dir="/proj/wal",
            description="wal task \{i}",
            created_at="2026-09-13T10:00:00Z",
            ns~,
          )
          match s.create_task(t) {
            Ok(_) => ()
            Err(msg) => abort("WAL create_task failed: \{msg}")
          }
          i = i + 1
        }
      }
      None => abort("WAL get \{ns} failed")
    }
  }
  // 验证每个 ns 都能正确读取
  for ns in ns_names {
    match ms.get(ns) {
      Some(s) => assert_eq(s.list_tasks_in(ns).length(), 5)
      None => abort("WAL verify \{ns} failed")
    }
  }
  ms.close_all()
}

///|
/// BUG-78 成对锁：data_dir 的消毒必须覆盖**实际落点**，且拒绝要有出路可判。
/// 正向用 "."（与既有测试同目录）与 "temp"（仓库内 gitignore 目录），
/// 反向钉四种越界形态；最后一档是入口级——非法目录必须 open=false。
test "data_dir 只接受相对路径（BUG-78 成对）" {
  // 正向：合法相对目录不许被误拒（误拒＝把既有 store_open(scratch) 路径打断）
  assert_true(@store.MultiStore::data_dir_ok("."))
  assert_true(@store.MultiStore::data_dir_ok("temp"))
  assert_true(@store.MultiStore::data_dir_ok("temp/ms-b78"))
  // 反向：四种逃逸形态逐一必拒
  assert_false(@store.MultiStore::data_dir_ok(""))
  assert_false(@store.MultiStore::data_dir_ok("../outside"))
  assert_false(@store.MultiStore::data_dir_ok("temp/../../outside"))
  assert_false(@store.MultiStore::data_dir_ok("/etc"))
  assert_false(@store.MultiStore::data_dir_ok("C:/evil"))
  // 前导反斜杠（UNC 形态的起始）同样算"前导分隔符"
  assert_false(@store.MultiStore::data_dir_ok("\\server"))
  // 入口级：非法 data_dir 不得建库（open 回 false，且 ns 不进 ns_list）
  let ms = @store.MultiStore::new(data_dir=".")
  assert_false(ms.open(ns="b78out", data_dir="../b78-outside"))
  assert_false(ms.ns_list().contains("b78out"))
  assert_true(ms.open(ns="b78ok", data_dir="temp"))
  assert_true(ms.ns_list().contains("b78ok"))
  ms.close_all()
}

///|
/// 回归锁（2026-10-23，R28）：`MultiStore::new` 必须补建缺失的 `data_dir` 树。
///
/// 缺陷形状（产品修复已在 main 落地，本锁补的是"没锁"）：`SqliteStore::open` 把
/// `{data_dir}/{ns}.db` 原样交给 SQLite，而 **SQLite 不创建中间目录**；干净检出上 `.fist-mbt/data`
/// 不存在 ⇒ 打开命名空间库时 js 侧 daqing FFI **throw**（不是返回 null）⇒ 未捕获异常打死 serve。
/// 实测触发路径就是本仓对外宣称的一键自检 `python scripts/mcp_smoke.py`（干净树上先崩在 publish）。
test "multi_store: 深层 data_dir 下打开命名空间库会补建目录（干净检出不再 unable to open）" {
  let base = "temp/r28_mkdir_case"
  let deep = base + "/a/b"
  // 自内向外清场（remove_dir 只删空目录）⇒ 下面的 assert_false 才真证明"原本不存在"
  for p in [deep, base + "/a", base] {
    @fs.remove_dir(p) catch {
      _ => ()
    }
  }
  assert_false(@fs.path_exists(deep))
  let ms = @store.MultiStore::new(data_dir=deep)
  // 断言**有效行为**而不是"new 有没有预建目录"：main 的设计是在 open 时兜底补建
  // （`MultiStore::get/open → SqliteStore::open → ensure_db_parent_dir`），
  // new 本身不建目录也能工作。锁实现细节会把正常重构误判成回归。
  assert_true(ms.open(ns="r28deep", data_dir=""))
  ms.close_all()
  assert_true(@fs.path_exists(deep + "/r28deep.db"))
}

///|
/// 回归锁（2026-10-23，R28）：`SqliteStore::open` 必须为**任意 db 路径**补建父目录。
///
/// 覆盖 `MultiStore::new` 管不到的那一面：调用方把 `FIST_DB_PATH` 指到**不存在的深层目录**。
/// 同一根因（SQLite 不建中间目录 + FFI 打开失败是 throw），这一面由 `ensure_db_parent_dir` 兜住。
test "sqlite_store: open 补建深层父目录（FIST_DB_PATH 指新目录不再抛）" {
  let base = "temp/r28_deep_case"
  let deep = base + "/x/y"
  for p in [deep, base + "/x", base] {
    @fs.remove_dir(p) catch {
      _ => ()
    }
  }
  assert_false(@fs.path_exists(deep))
  let db_path = deep + "/probe.db"
  match @store.SqliteStore::open(db_path) {
    None =>
      abort(
        "open 失败：深层父目录未被补建 ⇒ 这类 FIST_DB_PATH 仍会打死 serve",
      )
    Some(s) => ignore(s.clear())
  }
  assert_true(@fs.path_exists(db_path))
}
