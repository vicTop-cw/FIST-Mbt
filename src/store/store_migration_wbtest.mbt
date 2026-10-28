///|
/// store_migration_wbtest.mbt —— T0r744 回归锁（BUG-78 的迁移缺口）。
///
/// 缺陷形状：BUG-78 把 `store_open` 默认落点从 cwd 根 `<ns>.db` 改成
/// `.fist-mbt/data/<ns>.db`，但**没迁存量库**。BUG-389 只补了「检测到旧库就永远复用
/// 旧位置」，于是 ① 存量库永远搬不进新默认位置；② 「新位置空壳 + 旧位置有真库」
/// 这种最常见的升级形态没有裁定；③ 做了没做、做了多少在回执里看不到 ⇒
/// 跨进程/升级后同 ns 任务「凭空不存在」。
///
/// 这里钉的是**真迁移**（判定 → 复制 → 内容级校验 → 回执）的四档矩阵，
/// 以及迁移后任务真的可见（不是"文件在、数据没了"）。
/// 全部用例先删后建（可重复执行），夹具库显式 checkpoint 让主库自包含。

///|
/// 删单个文件（不存在不算错）。
fn t744_rm(path : String) -> Unit {
  @fs.remove_file(path) catch {
    _ => ()
  }
}

///|
/// 每进程唯一基线目录（BUG-461）。
///
/// 旧夹具基线是**进程间共享的固定相对路径**（`temp/t744_legacy_only` 等）：
/// 两个测试进程同时打开同一个 `.db` ⇒ sqlite 报 `database is locked`
/// （实测后台全量 6 格假红、同一份代码单包 97/97 全绿）。
/// 因此基线必须**每次取用都不同**。三个来源**组合**用，不是择一：
///   · `@env.rand(8)`：跨进程加密熵（node crypto / native BCryptGenRandom），
///     **唯一性由它保证**——时间戳只降低碰撞概率，不构成保证；
///   · `@env.now()`：可读时间戳，便于事后在 `temp/` 里认出是哪一轮的残留；
///   · `FIST_T744_RUN_ID`：可选人工标签，只做**附加**可检索性，不替换唯一性来源。
fn t744_run_token() -> String {
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
    // 熵源拿不到：明确标出来，不伪装成"唯一"
    None => "noentropy"
  }
  let label = match @env.get_env_var("FIST_T744_RUN_ID") {
    Some(v) if v != "" => "_" + v
    _ => ""
  }
  @env.now().to_string() + "-" + rand_part + label
}

///|
/// 取一个**每次调用都不同**的夹具基线目录：`temp/t744_<tag>_<token>`。
fn t744_base(tag : String) -> String {
  "temp/t744_" + tag + "_" + t744_run_token()
}

///|
/// 递归删目录（用后清理）。不存在不算错；删不掉也不抛——清理失败不该让断言假红，
/// 残留只落在 gitignore 的 `temp/` 下，不会往仓库根泄漏。
fn t744_rm_tree(path : String) -> Unit {
  if !@fs.path_exists(path) {
    return
  }
  let names = @fs.read_dir(path) catch { _ => return }
  for name in names {
    let child = path + "/" + name
    let is_dir = @fs.is_dir(child) catch { _ => false }
    if is_dir {
      t744_rm_tree(child)
    } else {
      t744_rm(child)
    }
  }
  @fs.remove_dir(path) catch {
    _ => ()
  }
}

///|
/// 清场：主库 + WAL 侧车 + 覆盖留档，避免上一次运行的残留让"应当为空"的断言假红。
fn t744_reset(dir : String, ns : String) -> Unit {
  let p = dir + "/" + ns + ".db"
  for suffix in ["", "-wal", "-shm", ".replaced-bak", ".replaced-bak-wal"] {
    t744_rm(p + suffix)
  }
}

///|
/// 造夹具库：`n` 条任务 + 显式 `wal_checkpoint(TRUNCATE)`。
///
/// 为什么要 checkpoint：`SqliteStore::open` 会开 WAL，写完的任务可能还躺在 `<db>-wal`
/// 里而主库文件尚未包含——不 checkpoint 就直接复制主库，测出来的是"搬了个空壳"，
/// 会让迁移实现的判据看起来时红时绿（不可复现的锁 = 不可信）。
fn t744_make_db(dir : String, ns : String, n : Int32) -> Unit {
  ensure_dir_tree(dir)
  let path = dir + "/" + ns + ".db"
  match SqliteStore::open(path) {
    None => abort("T0r744 夹具库打开失败: " + path)
    Some(s) => {
      let mut i = 0
      while i < n {
        let t = @core.Task::new(
          id="T\{i}",
          project_dir="/proj/t744",
          description="t744 fixture \{i}",
          created_at="2026-10-26T00:00:00Z",
          ns~,
        )
        match s.create_task(t) {
          Ok(_) => ()
          Err(msg) => abort("T0r744 夹具 create_task 失败: " + msg)
        }
        i = i + 1
      }
      // 夹具自持的 sqlite 句柄必须显式关掉：Windows 上未关闭的句柄会把 `.db` 钉住，
      // 用例末尾的 t744_rm_tree 就删不掉（表现为"清理跑了但目录还在"）。
      // 产品侧 `MultiStore::close_all` 同样只从 map 里摘掉、不关底层句柄（BUG-461 附带发现，已上报）。
      s.close()
    }
  }
  match @sqlite.Database::open(path) {
    None => ()
    Some(db) => {
      ignore(db.exec("PRAGMA wal_checkpoint(TRUNCATE)"))
      db.close()
    }
  }
}

///|
/// 锁 1：判定表（纯函数、零 IO）——九档闭集 + 「只有三档真搬」。
///
/// 这张表是迁移行为的**唯一真源**：IO 层只按它执行，因此这里每格都必须有断言，
/// 否则改判定就会从没有断言的那一格漏过去。
test "t744_1_migration_reason_table" {
  // 旧位置没有库：全新项目/已升级完的项目，正常落新位置
  assert_eq(store_migration_reason(false, 0, false, 0, false), "no-legacy")
  assert_eq(store_migration_reason(false, 0, true, 5, false), "no-legacy")
  // 只有旧库：BUG-78 的正常升级路径，必须搬
  assert_eq(store_migration_reason(true, 7, false, 0, false), "legacy-only")
  // 新位置空壳 + 旧库有数据：本次要治的形状（用户先跑出新空库，旧库才是真历史）
  assert_eq(store_migration_reason(true, 7, true, 0, false), "empty-target")
  // 两边都空：没有内容可搬
  assert_eq(store_migration_reason(true, 0, true, 0, false), "both-empty")
  // 旧库空壳、新位置有数据：新位置才是正文，不动
  assert_eq(store_migration_reason(true, 0, true, 9, false), "target-has-data")
  // 新位置行数已覆盖旧库：判为上次迁移的产物 ⇒ 幂等重入不重复搬
  assert_eq(store_migration_reason(true, 7, true, 7, false), "already-migrated")
  assert_eq(store_migration_reason(true, 7, true, 9, false), "already-migrated")
  // 两边都有数据且新位置不覆盖旧库：不自动覆盖（会丢数据），亮红灯要显式 migrate=true
  assert_eq(store_migration_reason(true, 9, true, 3, false), "conflict")
  // 显式 force：旧库有数据才搬；旧库空壳则没东西可搬
  assert_eq(store_migration_reason(true, 9, true, 3, true), "forced")
  assert_eq(store_migration_reason(true, 0, true, 3, true), "legacy-empty")
  // 「真搬」的闭集只有三档——多放一档进来就是"未经裁定就覆盖用户数据"
  assert_true(store_migration_applies("legacy-only"))
  assert_true(store_migration_applies("empty-target"))
  assert_true(store_migration_applies("forced"))
  for
    r in [
      "no-legacy", "both-empty", "target-has-data", "already-migrated", "conflict",
      "legacy-empty", "invalid-ns", "same-dir", "explicit-data-dir",
    ] {
    assert_false(store_migration_applies(r))
  }
}

///|
/// 锁 2：只有旧库（新位置什么都没有）→ 自动迁移，**任务数搬到位**，旧库原件保留。
///
/// 判据不是"新文件存在"（建空库也能过），而是新库 `tasks` 行数 == 旧库行数。
test "t744_2_legacy_only_migrates" {
  let base = t744_base("legacy_only")
  let ns = "ns-t744-only"
  let legacy_dir = base
  let new_dir = base + "/.fist-mbt/data"
  t744_reset(legacy_dir, ns)
  t744_reset(new_dir, ns)
  t744_make_db(legacy_dir, ns, 3)
  assert_eq(db_file_task_count(legacy_dir + "/" + ns + ".db"), 3)
  assert_false(db_file_exists(new_dir + "/" + ns + ".db"))
  let m = migrate_legacy_store(legacy_dir, new_dir, ns)
  assert_eq(m.reason, "legacy-only")
  assert_true(m.applied)
  assert_eq(m.legacy_tasks, 3)
  assert_eq(m.moved_tasks, 3)
  assert_eq(m.from, legacy_dir + "/" + ns + ".db")
  assert_eq(m.to, new_dir + "/" + ns + ".db")
  // 内容到位
  assert_true(db_file_exists(m.to))
  assert_eq(db_file_task_count(m.to), 3)
  // 旧库是备份，不删除
  assert_true(db_file_exists(m.from))
  assert_eq(db_file_task_count(m.from), 3)
  // 回执 note 点名两边路径（"做了多少"要自证）
  assert_true(m.note.contains("3 条"))
  assert_true(m.note.contains(m.to))
  t744_rm_tree(base)
}

///|
/// 锁 3：新位置空壳 + 旧位置有数据（最常见升级形态）→ 覆盖空壳迁移。
///
/// 这是 BUG-389 那版修复**没有**覆盖的档：旧代码逻辑是"旧库存在就复用旧位置"，
/// 于是新空壳永远不会被填上，用户按 BUG-78 默认路径去看就是"0 条任务"。
test "t744_3_empty_target_migrates" {
  let base = t744_base("empty_target")
  let ns = "ns-t744-empty"
  let legacy_dir = base
  let new_dir = base + "/.fist-mbt/data"
  t744_reset(legacy_dir, ns)
  t744_reset(new_dir, ns)
  t744_make_db(legacy_dir, ns, 4)
  // 新位置：真实存在的空库（0 条），不是"文件不存在"
  t744_make_db(new_dir, ns, 0)
  assert_eq(db_file_task_count(new_dir + "/" + ns + ".db"), 0)
  let m = migrate_legacy_store(legacy_dir, new_dir, ns)
  assert_eq(m.reason, "empty-target")
  assert_true(m.applied)
  assert_eq(m.new_tasks, 0)
  assert_eq(m.moved_tasks, 4)
  assert_eq(db_file_task_count(m.to), 4)
  // 空壳没有留档价值：这次不该产生 .replaced-bak
  assert_false(db_file_exists(m.to + ".replaced-bak"))
  t744_rm_tree(base)
}

///|
/// 锁 4：两边都有数据（新位置不覆盖旧库）→ **不自动迁移**，两边都原样。
///
/// 自动覆盖在这里等于静默丢新库的数据；判定必须停在 conflict 并给出两条出路，
/// 由人用 `migrate=true` 或 `data_dir="."` 显式选择。
test "t744_4_conflict_does_not_touch_either_side" {
  let base = t744_base("conflict")
  let ns = "ns-t744-conflict"
  let legacy_dir = base
  let new_dir = base + "/.fist-mbt/data"
  t744_reset(legacy_dir, ns)
  t744_reset(new_dir, ns)
  t744_make_db(legacy_dir, ns, 5)
  t744_make_db(new_dir, ns, 2)
  let m = migrate_legacy_store(legacy_dir, new_dir, ns)
  assert_eq(m.reason, "conflict")
  assert_false(m.applied)
  assert_eq(m.moved_tasks, 0)
  assert_eq(m.legacy_tasks, 5)
  assert_eq(m.new_tasks, 2)
  // 两边都不许被动：新库仍是 2 条，旧库仍是 5 条
  assert_eq(db_file_task_count(new_dir + "/" + ns + ".db"), 2)
  assert_eq(db_file_task_count(legacy_dir + "/" + ns + ".db"), 5)
  assert_false(db_file_exists(new_dir + "/" + ns + ".db.replaced-bak"))
  // 出路必须写在回执里（拒绝要自带出路）
  assert_true(m.note.contains("conflict"))
  assert_true(m.note.contains("migrate=true"))
  assert_true(m.note.contains("data_dir=\".\""))
  t744_rm_tree(base)
}

///|
/// 锁 5：两边都没有库 → no-legacy，不建任何文件（不能"迁移"出一个空库）。
test "t744_5_no_legacy_creates_nothing" {
  let base = t744_base("none")
  let ns = "ns-t744-none"
  let legacy_dir = base
  let new_dir = base + "/.fist-mbt/data"
  t744_reset(legacy_dir, ns)
  t744_reset(new_dir, ns)
  let m = migrate_legacy_store(legacy_dir, new_dir, ns)
  assert_eq(m.reason, "no-legacy")
  assert_false(m.applied)
  assert_false(db_file_exists(legacy_dir + "/" + ns + ".db"))
  assert_false(db_file_exists(new_dir + "/" + ns + ".db"))
  // 纯判定，不算行数（也不该把"打不开"误算成"有 0 条"）
  assert_eq(m.legacy_tasks, 0)
  assert_eq(m.new_tasks, 0)
  t744_rm_tree(base)
}

///|
/// 锁 6：幂等重入——迁移完再 open 一次，判为 already-migrated 且**不动**数据。
///
/// 没有这一格，第二次 store_open 会怎么走全靠猜：重复复制会白白改写新库，
/// 而错误地判成 conflict 会让"升级完成后每次 open 都亮红灯"。
test "t744_6_second_open_is_already_migrated" {
  let base = t744_base("idem")
  let ns = "ns-t744-idem"
  let legacy_dir = base
  let new_dir = base + "/.fist-mbt/data"
  t744_reset(legacy_dir, ns)
  t744_reset(new_dir, ns)
  t744_make_db(legacy_dir, ns, 3)
  let first = migrate_legacy_store(legacy_dir, new_dir, ns)
  assert_true(first.applied)
  let second = migrate_legacy_store(legacy_dir, new_dir, ns)
  assert_eq(second.reason, "already-migrated")
  assert_false(second.applied)
  assert_eq(second.moved_tasks, 0)
  assert_eq(second.legacy_tasks, 3)
  assert_eq(second.new_tasks, 3)
  assert_eq(db_file_task_count(new_dir + "/" + ns + ".db"), 3)
  t744_rm_tree(base)
}

///|
/// 锁 7：`migrate=true` 强制覆盖 conflict 档 → 旧库内容赢，新库先留档。
///
/// 强制档是唯一**会覆盖已有数据**的路径，因此"覆盖前留档"必须锁住：
/// 留档文件里要能数出新库原来的 2 条任务。
test "t744_7_forced_overwrites_with_backup" {
  let base = t744_base("forced")
  let ns = "ns-t744-forced"
  let legacy_dir = base
  let new_dir = base + "/.fist-mbt/data"
  t744_reset(legacy_dir, ns)
  t744_reset(new_dir, ns)
  t744_make_db(legacy_dir, ns, 6)
  t744_make_db(new_dir, ns, 2)
  let m = migrate_legacy_store(legacy_dir, new_dir, ns, force=true)
  assert_eq(m.reason, "forced")
  assert_true(m.applied)
  assert_eq(m.moved_tasks, 6)
  assert_eq(db_file_task_count(new_dir + "/" + ns + ".db"), 6)
  assert_true(m.backup != "")
  assert_eq(m.backup, new_dir + "/" + ns + ".db.replaced-bak")
  assert_true(db_file_exists(m.backup))
  // 留档里是**被覆盖掉的新库**内容，不是迁移后的内容
  assert_eq(db_file_task_count(m.backup), 2)
  t744_rm_tree(base)
}

///|
/// 锁 8：回执 JSON 把"哪个位置/有没有迁移/迁移多少条"三件事都说清楚。
///
/// 这是验收要求 4 的直接对应面：不含这三个字段的回执等于"迁移做得再对也没人知道"。
test "t744_8_receipt_json_is_self_evident" {
  let base = t744_base("receipt")
  let ns = "ns-t744-receipt"
  let legacy_dir = base
  let new_dir = base + "/.fist-mbt/data"
  t744_reset(legacy_dir, ns)
  t744_reset(new_dir, ns)
  t744_make_db(legacy_dir, ns, 2)
  let m = migrate_legacy_store(legacy_dir, new_dir, ns)
  let j = m.to_json()
  let s = j.stringify()
  assert_true(s.contains("\"applied\":true"))
  assert_true(s.contains("\"migrated_tasks\":2"))
  assert_true(s.contains("\"reason\":\"legacy-only\""))
  assert_true(s.contains(ns + ".db"))
  // 跳过档也走同一形状（调用方不用在两个结构之间分支）
  let skipped = StoreMigration::skipped("explicit-data-dir")
  let sj = skipped.to_json().stringify()
  assert_true(sj.contains("\"applied\":false"))
  assert_true(sj.contains("\"migrated_tasks\":0"))
  assert_true(sj.contains("explicit-data-dir"))
  t744_rm_tree(base)
}

///|
/// 锁 9：迁移后**任务真的可见**（端到端：不再"凭空不存在"）。
///
/// 前八格都是文件/计数层面；这一格才回答用户真正的问题——
/// 按 BUG-78 新默认位置 `MultiStore::new(data_dir=new_dir)` 打开后，
/// 旧库里的任务能不能被列出来。
test "t744_9_tasks_visible_after_migration" {
  let base = t744_base("visible")
  let ns = "ns-t744-visible"
  let legacy_dir = base
  let new_dir = base + "/.fist-mbt/data"
  t744_reset(legacy_dir, ns)
  t744_reset(new_dir, ns)
  t744_make_db(legacy_dir, ns, 3)
  let m = migrate_legacy_store(legacy_dir, new_dir, ns)
  assert_true(m.applied)
  let ms = MultiStore::new(data_dir=new_dir)
  match ms.get(ns) {
    None => abort("迁移后按新默认位置仍打不开 ns: " + ns)
    Some(s) => {
      let tasks = s.list_tasks_in(ns)
      assert_eq(tasks.length(), 3)
      // 同 t744_make_db：显式关掉夹具句柄，清理才删得掉（close_all 不关句柄）
      s.close()
    }
  }
  ms.close_all()
  t744_rm_tree(base)
}

///|
/// 锁 11：旧位置存在但文件头不是 SQLite（脏文件/半截文件）→ **不迁移**并点名路径。
///
/// 为什么单独一格：把脏文件搬进新默认位置等于"把问题搬到更难发现的地方"——
/// 迁移完 store_open 打开它照样炸，而审计面看到的是"迁移成功"。
test "t744_11_invalid_legacy_is_refused" {
  let base = t744_base("invalid_legacy")
  let ns = "ns-t744-invalid"
  let legacy_dir = base
  let new_dir = base + "/.fist-mbt/data"
  t744_reset(legacy_dir, ns)
  t744_reset(new_dir, ns)
  ensure_dir_tree(legacy_dir)
  let junk : Unit? = Some(
    @fs.write_string_to_file(
      legacy_dir + "/" + ns + ".db",
      "garbage-not-a-sqlite-file",
      encoding="utf8",
    ),
  ) catch {
    _ => None
  }
  assert_true(junk is Some(_))
  let m = migrate_legacy_store(legacy_dir, new_dir, ns)
  assert_eq(m.reason, "invalid-legacy")
  assert_false(m.applied)
  assert_eq(m.moved_tasks, 0)
  // 目标位置不许被创建/覆盖，脏文件也不许被搬走
  assert_false(db_file_exists(new_dir + "/" + ns + ".db"))
  assert_true(db_file_exists(legacy_dir + "/" + ns + ".db"))
  assert_true(m.note.contains(legacy_dir + "/" + ns + ".db"))
  t744_rm_tree(base)
}

///|
/// 锁 10：`db_file_task_count` 的边界——缺失文件/非库文件都归 0，
/// 且**探测本身不改物证**（空壳判据依赖这一点：探一下就把空壳变成"有表的新库"，
/// 后续所有判定都会失去依据）。
test "t744_10_task_count_probe_boundaries" {
  let base = t744_base("probe")
  ensure_dir_tree(base)
  // 缺失文件 → 0
  let missing = base + "/ns-nope.db"
  t744_rm(missing)
  assert_eq(db_file_task_count(missing), 0)
  assert_false(db_file_exists(missing))
  // 非 SQLite 文件 → 0（不许抛，否则 store_open 会被一次脏文件打死）
  let junk = base + "/ns-junk.db"
  let wrote : Unit? = Some(
    @fs.write_string_to_file(junk, "not-a-sqlite-db", encoding="utf8"),
  ) catch {
    _ => None
  }
  assert_true(wrote is Some(_))
  assert_eq(db_file_task_count(junk), 0)
  // 空壳库（真实 sqlite 文件 + 无 tasks 表）→ 0，且不因探测而长出 tasks 表
  let shell = base + "/ns-shell.db"
  t744_rm(shell)
  match @sqlite.Database::open(shell) {
    None => abort("空壳库建不出来")
    Some(db) => db.close()
  }
  assert_eq(db_file_task_count(shell), 0)
  match @sqlite.Database::open(shell) {
    None => abort("空壳库二次打开失败")
    Some(db) => {
      // 探测后仍然没有 tasks 表：prepare 拿不到 → 0
      let has_table : Bool = match
        db.prepare(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='tasks'",
        ) {
        None => false
        Some(stmt) => {
          let hit = stmt.step()
          stmt.finalize()
          hit
        }
      }
      assert_false(has_table)
      db.close()
    }
  }
  t744_rm_tree(base)
}

///|
/// 锁 12：基线自检——**两次取到的基线必须互不相等**（BUG-461 的防回退锁）。
///
/// 为什么这格必须存在：夹具路径一旦被改回固定常量，并发跑测就重新变成
/// `database is locked`，而那几格假红只在**两个进程同时跑**时出现——
/// 单进程全绿会把它伪装成"已经修好"。这一格把"基线唯一"变成可断言的属性。
test "t744_12_unique_base_selftest" {
  let a = t744_base("selftest")
  let b = t744_base("selftest")
  // 核心断言：同一 tag 两次取到不同基线（改回固定路径 ⇒ 这里立刻红）
  assert_true(a != b)
  // 基线必须落在 temp/ 下：不往仓库根/产品数据目录泄漏
  assert_true(a.has_prefix("temp/t744_selftest_"))
  assert_true(b.has_prefix("temp/t744_selftest_"))
  // 确实带了唯一后缀，而不是把 tag 直接当路径用
  let prefix_len = "temp/t744_selftest_".length()
  assert_true(a.length() > prefix_len)
  // 两个基线可以同时存在（并发跑测的形态），各自独立落盘、互不覆盖
  ensure_dir_tree(a)
  ensure_dir_tree(b)
  let wa : Unit? = Some(
    @fs.write_string_to_file(a + "/marker.txt", "a", encoding="utf8"),
  ) catch {
    _ => None
  }
  let wb : Unit? = Some(
    @fs.write_string_to_file(b + "/marker.txt", "b", encoding="utf8"),
  ) catch {
    _ => None
  }
  assert_true(wa is Some(_))
  assert_true(wb is Some(_))
  assert_true(@fs.path_exists(a + "/marker.txt"))
  assert_true(@fs.path_exists(b + "/marker.txt"))
  // 环境变量注入只做**附加**标签，不替换唯一性来源（取完立刻还原，不污染进程）
  @env.set_env_var("FIST_T744_RUN_ID", "lane-h-store")
  let c = t744_base("selftest")
  let d = t744_base("selftest")
  @env.unset_env_var("FIST_T744_RUN_ID")
  assert_true(c != d)
  assert_true(c.has_suffix("_lane-h-store"))
  // 用后清理：删干净，不留在 temp/ 里
  t744_rm_tree(a)
  t744_rm_tree(b)
  t744_rm_tree(c)
  t744_rm_tree(d)
  assert_false(@fs.path_exists(a))
  assert_false(@fs.path_exists(b))
  assert_false(@fs.path_exists(c))
  assert_false(@fs.path_exists(d))
}
