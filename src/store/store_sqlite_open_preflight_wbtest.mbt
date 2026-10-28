///|
/// store_sqlite_open_preflight_wbtest.mbt —— BUG-390「后一半」的白盒锁（`open_preflight_ok`）。
///
/// 上游只补了「能建目录」那一半（`ensure_db_parent_dir` 尽力 mkdir、失败被 `catch { _ => () }`
/// 吞掉），目录建不出来时仍会把路径交给 `@sqlite.Database::open`。js 侧那个函数是
/// `Some(new DatabaseSync(path))` 无条件、**失败只会 throw** ⇒ 服务面被一个畸形参数打死。
/// native 侧同函数诚实返回 None ⇒ 同一条契约在两端语义不同（BUG-78「不许两套规则」）。
///
/// 本文件锁三件事：
///   P1 纯判定：不涉文件系统的名字放行；既存目录 / 父段是既存文件 / 建不出目录 ⇒ false；
///   P2 接线：`SqliteStore::open` 真的消费这个判定（返回 None 而不是抛出去）——
///      这是「机制 ≠ 实现路径」那一格（判例-29）：只测纯函数绿，不证明 open 接住了；
///   P3 不误伤：干净可写路径预检放行且 open 真能建库（判据不许把能用面当缺陷报）。
///
/// 变异对照（判例-29/30）：把 `open` 里那两行预检短路删掉，P2 的两格必红（js 侧 throw 穿透 ⇒
/// 测试驱动 catch 成失败）；只留 P1 的话会误报「已修」——这正是本文件要防的假绿。

///|
/// 造一个既存普通文件当"墙"：任何 `<墙>/<x>.db` 的父目录都建不出来。
fn pf_make_blocker(name : String) -> Unit {
  @fs.write_string_to_file(name, "blocker") catch {
    _ => ()
  }
}

///|
fn pf_remove(name : String) -> Unit {
  @fs.remove_file(name) catch {
    _ => ()
  }
}

///|
/// P1a：不涉文件系统的两个名字直接放行。
test "P1a open_preflight_ok: :memory: 与空串放行" {
  assert_eq(SqliteStore::open_preflight_ok(":memory:"), true)
  assert_eq(SqliteStore::open_preflight_ok(""), true)
}

///|
/// P1b + P2a：父段是既存文件 ⇒ 预检 false，且 open 返回 None 而不是把 throw 漏出去。
test "P1b/P2a 父段是既存文件：预检 false，open 返回 None" {
  let blocker = "pf-blocker.db"
  pf_make_blocker(blocker)
  let path = "\{blocker}/ghost.db"
  assert_eq(SqliteStore::open_preflight_ok(path), false)
  match SqliteStore::open(path) {
    None => ()
    Some(_) => abort("父段是既存文件时 open 竟然成功：预检没接住 js 侧 throw 那一面")
  }
  pf_remove(blocker)
}

///|
/// P1c + P2b：目标名撞既存目录 ⇒ 预检 false，open 返回 None。
test "P1c/P2b 目标名撞既存目录：预检 false，open 返回 None" {
  let dir_db = "pf-dir.db"
  @fs.create_dir(dir_db) catch {
    _ => ()
  }
  assert_eq(SqliteStore::open_preflight_ok(dir_db), false)
  match SqliteStore::open(dir_db) {
    None => ()
    Some(_) => abort("目标是既存目录时 open 竟然成功：『既存路径必须是普通文件』这一半没判掉")
  }
  @fs.remove_dir(dir_db) catch {
    _ => ()
  }
}

///|
/// P2c：`MultiStore::open` 是 `store_open` 工具真正走的那条路，同一条预检必须在这里也成立。
test "P2c MultiStore::open 对建不出目录的 data_dir 返回 false 且不装进 ns 表" {
  let blocker = "pf-ms-blocker.db"
  pf_make_blocker(blocker)
  let ms = MultiStore::new(data_dir=".")
  assert_eq(ms.open(ns="pf-ms", data_dir="\{blocker}/sub"), false)
  assert_eq(ms.ns_list().length(), 0)
  pf_remove(blocker)
}

///|
/// P3：正向对照——干净可写路径预检放行，且 open 真能建库（预检不误拒）。
test "P3 正向对照：干净路径放行且 open 真能建库" {
  let path = "pf-ok.db"
  pf_remove(path)
  assert_eq(SqliteStore::open_preflight_ok(path), true)
  match SqliteStore::open(path) {
    Some(s) => ignore(s)
    None => abort("干净可写路径被预检误拒：判据会把能用面当缺陷报")
  }
  pf_remove(path)
  pf_remove("\{path}-wal")
  pf_remove("\{path}-shm")
}
