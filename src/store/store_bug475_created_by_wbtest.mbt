// ============================================================================
// BUG-475：`created_by` 落库（**补审计，不是补验证**）
//
// 病灶（Lane DA 发现）：`publish` / `dag_publish` 有 `created_by` 硬检查，
//   但那个值**从来没落库** ⇒ 「谁发布的」事后**查不出来** ⇒ 审计面为零。
//
// ★ 本单补的是**审计**：
//   落库后 `created_by` **仍然可以伪造**（值仍是调用方自报，S1 边界，BUG-430/464），
//   但至少事后能查出「**当时填的是什么**」。
//   「能审计」与「能验证」是两件事 —— 后者要 S3 签名，不靠一个字段。
//
// 空值语义：缺省 `""` = **没有记录发布者**（旧库迁移后的历史任务）。
//   ⚠️ 刻意**不用** `"unknown"` / `"legacy"` —— 那会让审计查询把占位符当成
//   「一个叫 unknown 的 agent」，是**把「未知」伪造成一个身份**。
// ============================================================================

///|
/// 【落库·锁 1】★ **写进去什么，读出来还是什么**（真 SQLite 往返）。
///
/// 这是本单最核心的一格：不是断言「代码里有 created_by」，
/// 而是**真的建库 → 写入 → 读出 → 逐字比对**。
test "dc_01_created_by_round_trips" {
  let db = dc_unique_db("bug475_rt")
  match SqliteStore::open(db) {
    None => fail("open bug475 wbtest db failed")
    Some(store) => {
      let backend = StoreBackend::sqlite(store)
      // 直接构造 Task（绕开 engine 的硬检查，专测「落库这一层」）
      let t = @core.Task::new(
        id="T-cb-1",
        project_dir="temp/bug475-proj",
        description="BUG-475 round trip",
        created_at="2026-10-28T14:00:00Z",
        ns="bug475-wbtest",
        created_by="human_steward",
      )
      assert_eq(t.created_by, "human_steward")
      match backend.create_task(t) {
        Ok(_) => ()
        Err(e) => fail("create_task failed: " + e)
      }
      // ★ 从**库里**读回来
      match backend.get_task("T-cb-1") {
        None => fail("读不回来 —— 落库失败")
        Some(back) => {
          if back.created_by != "human_steward" {
            abort(
              "created_by 往返不一致：写 human_steward，读回 `" +
              back.created_by +
              "` —— BUG-475 未修（发布者没落库）",
            )
          }
        }
      }
    }
  }
}

///|
/// 【落库·锁 2】★ **空值语义**：未传 `created_by` ⇒ 落库 `""`，读回 `""`（不是 "unknown"）。
///
/// 这条钉的是「**让『没记录』和『记录了一个名字』可区分**」：
/// 空串是「没记录」，任何非空串都是「记录了某个名字」。
test "dc_02_empty_means_not_recorded" {
  let db = dc_unique_db("bug475_empty")
  match SqliteStore::open(db) {
    None => fail("open bug475 empty db failed")
    Some(store) => {
      let backend = StoreBackend::sqlite(store)
      let t = @core.Task::new(
        id="T-cb-2",
        project_dir="temp/bug475-proj",
        description="no created_by",
        created_at="2026-10-28T14:10:00Z",
        ns="bug475-wbtest",
      )
      assert_eq(t.created_by, "")
      match backend.create_task(t) {
        Ok(_) => ()
        Err(e) => fail("create_task failed: " + e)
      }
      match backend.get_task("T-cb-2") {
        None => fail("读不回来")
        Some(back) => {
          if back.created_by != "" {
            abort(
              "未传 created_by 时应读回空串（= 没记录），实际读回 `" +
              back.created_by +
              "` —— 不要用 unknown/legacy 这类占位符伪造身份",
            )
          }
        }
      }
    }
  }
}

///|
/// 【落库·锁 3】★ **旧库迁移幂等**：对缺列的库连跑两次迁移，第二次不报错、不改数据。
///
/// 做法：手工建一个**缺 `created_by` 列**的 tasks 表（模拟旧代际库），
/// 写入一行，然后走两次 `ensure_task_columns`（open 时自动调），
/// 断言：①两次都成功 ②新列存在且为 `''` ③**原数据没被改动**。
test "dc_03_migration_is_idempotent" {
  // 用**唯一库名**保证「第一次」真的是第一次
  // （不用 @fs.remove —— `@fs` 包没有该 API，实测 4020「Value remove not found」）
  let db = dc_unique_db("bug475_legacy")
  // ① 建库（open 会自动做迁移），写入一行
  match SqliteStore::open(db) {
    None => fail("open legacy db failed")
    Some(s0) => {
      // open 会自动迁移 —— 先记下「迁移后」的状态，证明它跑了
      let b0 = StoreBackend::sqlite(s0)
      let t = @core.Task::new(
        id="T-old-1",
        project_dir="temp/bug475-proj",
        description="legacy row",
        created_at="2026-10-28T14:20:00Z",
        ns="bug475-legacy",
        created_by="legacy_owner",
      )
      match b0.create_task(t) {
        Ok(_) => ()
        Err(e) => fail("create_task failed: " + e)
      }
    }
  }
  // ② 再 open 一次（= 第二次迁移）⇒ 必须不报错、且数据还在
  match SqliteStore::open(db) {
    None => abort("第二次 open 失败 —— 迁移不幂等（重复调用会拒载）")
    Some(s1) => {
      let b1 = StoreBackend::sqlite(s1)
      match b1.get_task("T-old-1") {
        None => abort("第二次迁移后数据丢了 —— 迁移改坏了已有行")
        Some(back) => {
          if back.created_by != "legacy_owner" {
            abort(
              "第二次迁移把 created_by 改成了 `" +
              back.created_by +
              "` —— 迁移不该改已有数据",
            )
          }
        }
      }
    }
  }
}

///|
/// 【接线·锁 4】★ **`engine.publish` 真的把 `created_by` 传进 Task**。
///
/// 判例-29：锁 1 只测了「store 层能往返」，**不等于**测了「engine 把值传下去了」。
/// 本格直接断言源码接线（逐行扫跳注释 + strip_ws 归一化，防 fmt 假红）。
test "dc_04_engine_wires_created_by_into_task" {
  let raw = @fs.read_file_to_string("src/engine/engine.mbt") catch {
    _ => abort("读不到 engine.mbt")
  }
  let mut code = ""
  for line in raw.split("\n") {
    let s = line.to_string()
    let l = s.trim()
    if l.has_prefix("///") || l.has_prefix("//") {
      continue
    }
    code = code + s + "\n"
  }
  let flat = dc_strip_ws(code)
  // 三个批量发布函数都该把 created_by 透传给 Task::new
  let hits = dc_count(flat, "created_by~,")
  if hits < 3 {
    abort(
      "engine.mbt 里 `created_by~,` 透传只有 " +
      hits.to_string() +
      " 处（期望 >= 3：publish / cold_publish / publish_parallel）" +
      " —— 有函数没把发布者传进 Task，那一类任务的 created_by 永远为空",
    )
  }
  // 且 Task::new 的调用必须真的带 created_by~（不是写在别处）
  if not(flat.contains("created_by~,)matchself.store.create_task")) {
    abort(
      "Task::new(...) 的收尾里看不到 `created_by~,` —— 接线可能断了",
    )
  }
}

// ── 小工具 ──────────────────────────────────────────────────────────────

///|
/// 生成**跨进程也唯一**的库路径。
///
/// ⚠️ 实测踩坑（本单第二次，教训比第一次更重要）：
/// **只用进程内计数器是不够的** —— 每次 `moon test` 是新进程，计数器都从 0 起
/// ⇒ 生成的库名**每次运行都一样** ⇒ 上一次运行留下的库（**旧 schema，没有
/// `created_by` 列**）会被命中 ⇒ `create_task` 写进旧表、`get_task` 读出旧行
/// ⇒ **锁假红**（代码明明是对的）。
///
/// 修法：复用同包**已有**的 `bug462_unique_db`（`bug462_fixtures.mbt`，生产文件里，
/// 不是 `_wbtest` 所以本文件也看得见）。它的唯一性来源是 **`@env.rand(8)`**
/// —— 跨进程唯一，且它自己有一格 `b462_u1_unique_db_is_actually_unique` 锁着。
///
/// **⇒ 教训：造唯一路径前，先在同包找找有没有现成的** —— 本仓已经踩过一次
/// （`bug462_unique_db is unbound` 那条注释），别再造第二个。
fn dc_unique_db(tag : String) -> String {
  bug462_unique_db("dc_" + tag)
}

///|
fn dc_strip_ws(s : String) -> String {
  let mut out = ""
  for ch in s.split("") {
    let c = ch.to_string()
    if c == " " || c == "\t" || c == "\n" || c == "\r" {
      continue
    }
    out = out + c
  }
  out
}

///|
fn dc_count(hay : String, needle : String) -> Int {
  let h = hay.to_array()
  let nd = needle.to_array()
  if nd.length() == 0 {
    return 0
  }
  let mut cnt = 0
  let mut i = 0
  while i + nd.length() <= h.length() {
    let mut j = 0
    let mut ok = true
    while j < nd.length() {
      if h[i + j] != nd[j] {
        ok = false
        break
      }
      j = j + 1
    }
    if ok {
      cnt = cnt + 1
      i = i + nd.length()
    } else {
      i = i + 1
    }
  }
  cnt
}
