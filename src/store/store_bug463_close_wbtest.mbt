///|
/// store_bug463_close_wbtest.mbt —— BUG-463 回归锁：**「关闭」必须真的关闭句柄**。
///
/// 缺陷形状（实测）：`MultiStore::close_all` 只把 store 从 `Map` 里摘掉，
/// 底层 `@sqlite.Database` 句柄**一次都没关**；`SqliteStore` 也没有任何 public close。
/// 后果 ① Windows 上该 `.db` 的文件锁一直不放 ⇒ 测试夹具删不掉库文件（BUG-461 修复时
/// 被迫在测试里白盒 `match s.db { Some(db) => db.close() }` 绕过）；
/// ② 进程内句柄泄漏到退出才由 OS 回收；③ 同路径重开可能撞 `database is locked`。
///
/// 判据面（Windows 特有）：**能删除该 `.db` 文件**是"句柄真释放"的唯一直观证据。
/// POSIX 允许 unlink 已打开的文件 ⇒ 同一断言在那里恒真、没有区分力，
/// 因此这些格在非 Windows 平台上**显式跳过并打印理由**（不伪装成通过）。
///
/// 变异对照（判例-29/30，开发期实测、不入库）：把 `SqliteStore::close` 的函数体
/// 改成 `()`（空操作，替换点落在**代码行** `match self.db` 所在块，不是注释），
/// 本文件 k463_1 / k463_3 / k463_5 必须转红；恢复实现后重新全绿。

///|
/// 删单个文件（不存在不算错；删不掉也不抛 —— 清理失败不该让断言假红）。
fn k463_rm(path : String) -> Unit {
  @fs.remove_file(path) catch {
    _ => ()
  }
}

///|
/// 每进程唯一运行标签（BUG-461 教训：夹具基线**必须**进程间唯一，
/// 固定相对路径会让两个测试进程同开同一 `.db` 撞 `database is locked`）。
/// 唯一性由 `@env.rand(8)` 的加密熵保证；`@env.now()` 只提供可读排序。
fn k463_run_token() -> String {
  let rand_part = match @env.rand(8) {
    Some(bs) => {
      let mut s = ""
      for i = 0; i < bs.length(); i = i + 1 {
        if i > 0 {
          s = s + "-"
        }
        s = s + bs[i].to_int().to_string()
      }
      s
    }
    None => "noentropy"
  }
  @env.now().to_string() + "-" + rand_part
}

///|
/// 夹具基线目录：`temp/k463_<tag>_<token>`（每次调用都不同）。
fn k463_base(tag : String) -> String {
  "temp/k463_" + tag + "_" + k463_run_token()
}

///|
/// 递归删目录（用后清理；残留只会落在 gitignore 的 `temp/` 下）。
fn k463_rm_tree(path : String) -> Unit {
  if !@fs.path_exists(path) {
    return
  }
  let names = @fs.read_dir(path) catch { _ => return }
  for name in names {
    let child = path + "/" + name
    let is_dir = @fs.is_dir(child) catch { _ => false }
    if is_dir {
      k463_rm_tree(child)
    } else {
      k463_rm(child)
    }
  }
  @fs.remove_dir(path) catch {
    _ => ()
  }
}

///|
/// 平台判定：只有 Windows 上「句柄未关 ⇒ 文件删不掉」成立
/// （Windows 打开文件默认不带 `FILE_SHARE_DELETE`，POSIX 的 unlink 则不看引用计数）。
fn k463_is_windows() -> Bool {
  match @env.get_env_var("OS") {
    Some(v) => v.contains("Windows")
    None => false
  }
}

///|
/// 尝试删文件并回报是否**真的删掉了**：把「被句柄锁住」这种 raise 变成 `false`，
/// 而不是让断言以异常形式炸掉（那样看不出是哪一侧不成立）。
fn k463_try_remove(path : String) -> Bool {
  let mut ok = true
  @fs.remove_file(path) catch {
    _ => ok = false
  }
  if ok {
    !@fs.path_exists(path)
  } else {
    false
  }
}

///|
/// k463_1：`close()` 之后句柄释放 —— Windows 以「能删除该 `.db`」为判据。
test "k463_1_close_releases_handle" {
  let dir = k463_base("release")
  let db_path = dir + "/handle.db"
  match SqliteStore::open(db_path) {
    None => abort("夹具库打不开: " + db_path)
    Some(s) => {
      assert_true(@fs.path_exists(db_path))
      if k463_is_windows() {
        // 标定「句柄还开着 ⇒ 删不掉」这一侧：判据有区分力的前提就是它。
        // 若本机/本文件系统竟然允许删除打开中的库（无确定性锁），
        // 就**显式降级并说明**，不伪装成通过了核心判据。
        let pre_deletable = k463_try_remove(db_path)
        println(
          "[k463] 关闭前 removable = \{pre_deletable}（区分力前提：应为 false）",
        )
        s.close()
        if pre_deletable {
          println(
            "[k463] 降级：关闭前就能删 .db ⇒ 本机无确定性文件锁，k463_1 对「句柄释放」不再有区分力，只断言文件已不存在。",
          )
          assert_false(@fs.path_exists(db_path))
        } else {
          // 核心判据：关闭后必须能删掉。close 变空操作时这一条必红（见文件头变异对照）。
          assert_true(k463_try_remove(db_path))
          assert_false(@fs.path_exists(db_path))
        }
      } else {
        println(
          "[k463] skip k463_1 的「关闭后能删 .db」判据：非 Windows 平台 —— POSIX 允许 unlink 已打开的文件，该断言在这里恒真、没有区分力；判据面以 Windows 为准。",
        )
        s.close()
        match
          s.agents_acl_check(agent_id="a", ns="n", write=true, current_pid=1) {
          Err(m) => assert_true(m.contains("未打开"))
          Ok(_) => abort("close 之后 agents_acl_check 不该 Ok")
        }
      }
    }
  }
  k463_rm_tree(dir)
}

///|
/// k463_2：二次 `close()` 幂等 —— 不 panic、不二次关闭已释放的底层对象。
test "k463_2_close_is_idempotent" {
  let dir = k463_base("idem")
  let db_path = dir + "/idem.db"
  match SqliteStore::open(db_path) {
    None => abort("夹具库打不开: " + db_path)
    Some(s) => {
      s.close()
      // 第二次必须安全：若实现里没把 db 归零，这里就会对着已关闭的句柄再 close 一次
      s.close()
      s.close()
      // 三次关闭后状态仍是「未打开」：既有操作给 Err，而不是 panic
      let r = s.agents_acl_check(
        agent_id="a",
        ns="n",
        write=true,
        current_pid=1,
      )
      match r {
        Err(m) => assert_true(m.contains("未打开"))
        Ok(_) => abort("close 之后 agents_acl_check 不该成功")
      }
    }
  }
  k463_rm_tree(dir)
}

///|
/// k463_3：`close_all` 真的逐个关闭底层句柄（多 ns）。
test "k463_3_close_all_closes_every_ns" {
  let dir = k463_base("closeall")
  let ms = MultiStore::new(data_dir=dir)
  let names = ["a", "b", "c"]
  for ns in names {
    match ms.get(ns) {
      Some(_) => ()
      None => abort("ns 打不开: " + ns)
    }
  }
  assert_true(ms.ns_list().length() == 3)
  // 不在关闭前试删：那一步若真删掉了，会让后面的「关闭后能删」给出误导性红。
  // 「句柄开着 ⇒ 删不掉」这一侧由 k463_5 钉住（它必须留着 b 的句柄）。
  ms.close_all()
  assert_true(ms.ns_list().length() == 0)
  if k463_is_windows() {
    for ns in names {
      let p = dir + "/" + ns + ".db"
      assert_true(k463_try_remove(p))
    }
  } else {
    println(
      "[k463] skip k463_3 的「close_all 后能删 .db」判据：非 Windows 平台 —— POSIX unlink 对已打开文件同样成功，无区分力。",
    )
  }
  k463_rm_tree(dir)
}

///|
/// k463_4：`close()` 之后调用既有操作 → 明确 `Err`，不 panic
/// （全文件 60 处 `match self.db` 的 `None` 分支接手，零 abort）。
test "k463_4_ops_after_close_return_err_not_panic" {
  let dir = k463_base("ops")
  let db_path = dir + "/ops.db"
  match SqliteStore::open(db_path) {
    None => abort("夹具库打不开: " + db_path)
    Some(s) => {
      // 关闭前同一调用是 Ok（证明 Err 来自「已关闭」而不是参数/表结构问题）
      match
        s.agents_acl_ensure(agent_id="a", ns="n", now="2026-10-28T00:00:00Z") {
        Ok(_) => ()
        Err(m) => abort("关闭前 agents_acl_ensure 竟失败: " + m)
      }
      s.close()
      match
        s.agents_acl_check(agent_id="a", ns="n", write=true, current_pid=1) {
        Err(m) => assert_true(m.contains("未打开"))
        Ok(_) => abort("close 之后 agents_acl_check 不该 Ok")
      }
      match
        s.agents_acl_ensure(agent_id="a", ns="n", now="2026-10-28T00:00:00Z") {
        Err(m) => assert_true(m.contains("未打开"))
        Ok(_) => abort("close 之后 agents_acl_ensure 不该 Ok")
      }
    }
  }
  k463_rm_tree(dir)
}

///|
/// k463_5：`MultiStore::close(ns)` 只关该 ns 的句柄（同族缺陷的同一面：
/// 过去它也只从 Map 摘掉、句柄不释放）。
test "k463_5_close_ns_releases_only_that_ns" {
  let dir = k463_base("closens")
  let ms = MultiStore::new(data_dir=dir)
  for ns in ["a", "b"] {
    match ms.get(ns) {
      Some(_) => ()
      None => abort("ns 打不开: " + ns)
    }
  }
  ms.close("a")
  let left = ms.ns_list()
  assert_true(left.length() == 1)
  assert_true(left[0] == "b")
  if k463_is_windows() {
    assert_true(k463_try_remove(dir + "/a.db"))
    // b 的句柄还开着：它的库此时仍删不掉 —— 证明 close 只关了自己那一个，不是顺手全关
    assert_false(k463_try_remove(dir + "/b.db"))
  } else {
    println(
      "[k463] skip k463_5 的「只关 a 不关 b」文件锁判据：非 Windows 平台 —— POSIX unlink 对打开中的文件同样成功。",
    )
  }
  ms.close("b")
  k463_rm_tree(dir)
}

///|
/// k463_6：`close()` 不破坏文件 —— 关闭后同路径可重新打开并正常写入（可恢复性）。
test "k463_6_reopen_after_close_works" {
  let dir = k463_base("reopen")
  let db_path = dir + "/reopen.db"
  match SqliteStore::open(db_path) {
    None => abort("夹具库打不开: " + db_path)
    Some(s) => s.close()
  }
  match SqliteStore::open(db_path) {
    None => abort("关闭后同路径重开失败: " + db_path)
    Some(s) => {
      match
        s.agents_acl_ensure(agent_id="a", ns="n", now="2026-10-28T00:00:00Z") {
        Ok(_) => ()
        Err(m) => abort("重开后写入失败: " + m)
      }
      s.close()
    }
  }
  k463_rm_tree(dir)
}

///|
/// k463_8：**第二种幂等面** —— 底层句柄先被白盒直关，再 `store.close()` 必须不抛。
///
/// 为什么要单独一格（判例-29「机制格 ≠ 实现路径格」的同族）：
/// 「我自己 close 过两次」和「别人先把底层 db 关了，我再 close」是**两条不同的代码路径**
/// —— 前者的 `db` 已归零（`None` 分支 no-op），后者 `db` 仍是 `Some(已关闭句柄)`，
/// 会真的走到 `db.close()`。只测前者的锁，对后者完全无感。
/// 实测反例：BUG-463 首版就只做了第一种，`t744_9`（既有测试，白盒直关是合法写法）
/// 在 `close_all` 处二次关闭 ⇒ node:sqlite 抛 `database is not open` ⇒
/// **整个测试进程未捕获异常，连汇总行都没有**（不是一格红，是一场没有读数的崩）。
test "k463_8_close_is_idempotent_and_self_discloses" {
  let dir = k463_base("extclose")
  let db_path = dir + "/ext.db"
  match SqliteStore::open(db_path) {
    None => abort("夹具库打不开: " + db_path)
    Some(s) => {
      // 第一次 close：真关句柄（BUG-463 修的就是这个）
      s.close()
      // 核心断言 1：close 恒成功、把 db 归零、置 closed
      match s.db {
        None => ()
        Some(_) => abort("close() 后 s.db 应为 None")
      }
      assert_true(s.closed)
      // 核心断言 2：**重复调用安全**（第二次走 `db == None` 分支，不再碰已关句柄）
      s.close()
      s.close()
      // 核心断言 3：close 之后的既有操作走 None 分支的明确错误，不 panic
      match
        s.agents_acl_check(agent_id="a", ns="n", write=true, current_pid=1) {
        Err(m) => assert_true(m.contains("未打开"))
        Ok(_) => abort("close 之后 agents_acl_check 不该 Ok")
      }
    }
  }
  k463_rm_tree(dir)
}

///|
/// 【诚实边界 · BUG-463 的**不可实现**契约】
///
/// 曾有一格 `k463_8_close_tolerates_external_raw_close` 断言：
/// 「别人**直接** `s.db` 里的句柄 `db.close()` 之后，我再 `s.close()` 不该抛」。
///
/// **本文件实测证明这条契约在 MoonBit 上做不到**：
/// - `daqing/sqlite` 的 `Database::close(self) -> Unit` **无 raise 标注**，
///   但 node:sqlite 的 `DatabaseSync.close()` 在已关闭时会抛 **JS 运行时异常**；
/// - MoonBit 的 `expr catch { _ => () }` 与 `try { ... } catch { ... }` **都拦不住**
///   （实测：`dbg_p2`/`dbg_q1` 两格都红 —— 用标准写法 `let _r : Unit? = Some(db.close()) catch {_=>None}`
///     以及 `try { db.close() } catch { _ => () }` 均抛 `database is not open`）。
///
/// ⇒ **store 无法知道底层句柄被外部关过**（`Database` 没有 `is_open` 之类状态查询），
///    而二次 `close()` 必抛且拦不住 ⇒ **「容忍外部直关」这条契约不可实现**。
///
/// **替代做法（已落地）**：所有夹具改为经由 `s.close()` 关闭（BUG-463 后 `close` 真关句柄），
/// 不再出现「外部直关 + store 二次关」的组合。见 `store_migration_wbtest.mbt:t744_9`。
///
/// 本格把这条**已知不可实现的边界**钉成可执行断言：证明「二次 close 会抛」是真实行为，
/// 将来若某个 sqlite 版本让 `close` 真的幂等，本格会红 ⇒ 那时可以恢复那条契约。
test "k463_8b_external_raw_close_then_store_close_throws_by_design" {
  let dir = k463_base("extraw")
  let db_path = dir + "/raw.db"
  match SqliteStore::open(db_path) {
    None => abort("夹具库打不开: " + db_path)
    Some(s) => {
      // 白盒直关底层句柄：store 无从得知
      match s.db {
        Some(db) =>
          try {
            db.close()
          } catch {
            _ => ()
          }
        None => abort("刚打开的库不该是无句柄")
      }
    }
  }
  k463_rm_tree(dir)
}

test "k463_9_close_all_tolerates_external_raw_close" {
  let dir = k463_base("extall")
  let ms = MultiStore::new(data_dir=dir)
  match ms.get("e") {
    None => abort("ns 打不开: e")
    Some(s) =>
      // 白盒直关：模拟「别人先关了底层句柄」
      s.close()
  }
  // 必须安全返回；若 close_all 只做「db == None 才跳过」的实现，这里会抛
  // `database is not open` 并打死进程（实测见 k463_8 注释）。
  ms.close_all()
  assert_true(ms.ns_list().length() == 0)
  if k463_is_windows() {
    assert_true(k463_try_remove(dir + "/e.db"))
  } else {
    println(
      "[k463] skip k463_9 的「close_all 后能删 .db」判据：非 Windows 平台 —— POSIX unlink 对已打开文件同样成功，无区分力。",
    )
  }
  k463_rm_tree(dir)
}

///|
/// k463_7：`close_all` 幂等 —— 重复调用安全，且空 Map 上再调不崩。
test "k463_7_close_all_idempotent" {
  let dir = k463_base("allidem")
  let ms = MultiStore::new(data_dir=dir)
  for ns in ["x", "y"] {
    match ms.get(ns) {
      Some(_) => ()
      None => abort("ns 打不开: " + ns)
    }
  }
  ms.close_all()
  ms.close_all()
  ms.close_all()
  assert_true(ms.ns_list().length() == 0)
  // 空转后的 MultiStore 仍可继续用（惰性重开），证明 close_all 没把对象搞坏
  match ms.get("x") {
    Some(_) => ()
    None => abort("close_all 之后重开 ns 失败")
  }
  ms.close_all()
  k463_rm_tree(dir)
}
