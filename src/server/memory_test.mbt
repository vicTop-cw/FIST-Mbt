/// memory_test.mbt —— 自我记忆（Hermes 式）三工具 + 自进化蒸馏（evolve_distill）测试
///
/// 覆盖：
///   1) memory_gc_logic：上限软降权纯逻辑（未超限 / 超限切分 / 中文按字符截断）
///   2) memory_gc_one：文件不存在 → {gc:false, exists:false}
///   3) memory_consolidate：writing target.md + thinking append-only 前后缀
///   4) memory_link：links.md 创建与追加，`from -> to note` 格式
///   5) evolve_distill：distill_principle_goal 前缀；重复蒸馏触发查重但仍入库；
///      sqlite upsert 幂等（同 now 同 target → 同 id 覆盖）
///
/// 目录约定：每个用例使用独立目录 temp/mem_cN / temp/dist_cN，可重复运行。

// ---------------------------------------------------------------------------
// 测试辅助
// ---------------------------------------------------------------------------

///|
/// 清理用例目录（递归删除所涉文件，各自失败忽略使幂等）。
fn mem_clean(dir : String) -> Unit {
  for
    f in [
      "memory/links.md", "memory/target.md", "memory/thinking.md", "memory/archive/target.archive.md",
      "memory/archive",
    ] {
    @fs.remove_file(dir + "/" + f) catch {
      _ => ()
    }
  }
}

///|
/// 准备用例目录（含 memory/ 骨架）。
fn mem_dir(name : String) -> String {
  @fs.create_dir("temp") catch {
    _ => ()
  }
  let d = "temp/" + name
  @fs.create_dir(d) catch {
    _ => ()
  }
  @fs.create_dir(d + "/memory") catch {
    _ => ()
  }
  @fs.create_dir(d + "/memory/archive") catch {
    _ => ()
  }
  mem_clean(d)
  d
}

///|
/// 读 JSON 字符串字段（缺失返回 "<null>"）。
fn mem_str(j : Json, key : String) -> String {
  match j {
    Object(m) =>
      match m.get(key) {
        Some(String(s)) => s
        _ => "<null>"
      }
    _ => "<null>"
  }
}

///|
/// 读 JSON 布尔字段（缺失返回 false）。
fn mem_bool(j : Json, key : String) -> Bool {
  match j {
    Object(m) =>
      match m.get(key) {
        Some(True) => true
        _ => false
      }
    _ => false
  }
}

///|
/// 读 JSON 数字字段为 int（缺失返回 -1）。
fn mem_int(j : Json, key : String) -> Int {
  match j {
    Object(m) =>
      match m.get(key) {
        Some(Number(n, ..)) => n.to_int()
        _ => -1
      }
    _ => -1
  }
}

// ---------------------------------------------------------------------------
// 用例 1：memory_gc_logic 纯逻辑
// ---------------------------------------------------------------------------

///|
test "memory_1_gc_logic_no_trim" {
  let content = "abcdef"
  let (kept, archived) = memory_gc_logic(content, 10)
  assert_eq(kept, "abcdef")
  assert_eq(archived, "")
  // 恰好等于上限：不归档
  let (k2, a2) = memory_gc_logic(content, 6)
  assert_eq(k2, "abcdef")
  assert_eq(a2, "")
}

///|
test "memory_2_gc_logic_trim" {
  let content = "abcdefghij"
  let (kept, archived) = memory_gc_logic(content, 4)
  assert_eq(kept, "ghij")
  assert_eq(archived, "abcdef")
}

///|
test "memory_3_gc_logic_chinese" {
  // 中文按字符截断（UTF-16 字符），取最新 3 个字符
  let content = "第一阶段的老人条目最新目标"
  let (kept, archived) = memory_gc_logic(content, 3)
  assert_eq(kept, "新目标")
  assert_eq(archived, "第一阶段的老人条目最")
}

// ---------------------------------------------------------------------------
// 用例 4：memory_gc_one 文件不存在 → exists:false
// ---------------------------------------------------------------------------

///|
test "memory_4_gc_missing_file" {
  let dir = mem_dir("mem_c4_missing")
  let j = memory_gc_one(dir, "target", 2000)
  assert_true(not(mem_bool(j, "gc")))
  assert_true(not(mem_bool(j, "exists")))
  assert_eq(mem_str(j, "kind"), "target")
}

///|
test "memory_5_gc_one_archives" {
  let dir = mem_dir("mem_c5_arch")
  // 写 20 字符正文
  @fs.write_string_to_file(
    dir + "/memory/target.md",
    "0123456789abcdefghij",
    encoding="utf8",
  ) catch {
    _ => abort("写档失败")
  }
  let j = memory_gc_one(dir, "target", 5)
  assert_true(mem_bool(j, "gc"))
  assert_eq(mem_int(j, "before_chars"), 20)
  assert_eq(mem_int(j, "after_chars"), 5)
  assert_true(mem_str(j, "archived_to").contains("archive"))
  // 正文只保留最新 5 字符
  let body = @fs.read_file_to_string(dir + "/memory/target.md", encoding="utf8") catch {
    _ => abort("读正文失败")
  }
  assert_eq(body, "fghij")
  // 归档保留老人
  let arch = @fs.read_file_to_string(
    dir + "/memory/archive/target.archive.md",
    encoding="utf8",
  ) catch {
    _ => abort("读归档失败")
  }
  assert_true(arch.contains("0123456789abcde"))
}

// ---------------------------------------------------------------------------
// 用例 6：memory_gc_all 四件套
// ---------------------------------------------------------------------------

///|
test "memory_6_gc_all_kinds" {
  let dir = mem_dir("mem_c6_all")
  @fs.write_string_to_file(
    dir + "/memory/target.md",
    "abcdefghij",
    encoding="utf8",
  ) catch {
    _ => ()
  }
  @fs.write_string_to_file(dir + "/memory/product.md", "short", encoding="utf8") catch {
    _ => ()
  }
  let j = memory_gc_all(dir, 4)
  assert_true(mem_bool(j, "gc"))
  // 四件套均返回
  match j {
    Object(m) =>
      match m.get("kinds") {
        Some(Array(a)) => assert_eq(a.length(), 4)
        _ => abort("应返回四件套数组")
      }
    _ => abort("应返回 JSON 对象")
  }
  // target 已被裁剪，product 未超限保留
  let body = @fs.read_file_to_string(dir + "/memory/target.md", encoding="utf8") catch {
    _ => abort("读正文失败")
  }
  assert_eq(body, "ghij")
  assert_true(@fs.path_exists(dir + "/memory/archive/target.archive.md"))
}

// ---------------------------------------------------------------------------
// 用例 7：memory_consolidate
// ---------------------------------------------------------------------------

///|
test "memory_7_consolidate_target" {
  let dir = mem_dir("mem_c7_cons")
  let j = match
    memory_consolidate(
      dir, "T1", "target", "# 本轮目标：完成 X", "2026-09-05T00:00:00Z",
    ) {
    Ok(x) => x
    Err(m) => abort(m)
  }
  assert_true(mem_bool(j, "consolidated"))
  assert_eq(mem_str(j, "kind"), "target")
  // 覆盖写：正文即为写入内容
  let body = @fs.read_file_to_string(dir + "/memory/target.md", encoding="utf8") catch {
    _ => abort("读正文失败")
  }
  assert_eq(body, "# 本轮目标：完成 X")
}

///|
test "memory_8_consolidate_thinking_append" {
  let dir = mem_dir("mem_c8_think")
  ignore(
    memory_consolidate(
      dir, "T1", "thinking", "第一步思考", "2026-09-05T00:00:00Z",
    ),
  )
  ignore(
    memory_consolidate(
      dir, "T1", "thinking", "第二步思考", "2026-09-06T00:00:00Z",
    ),
  )
  let body = @fs.read_file_to_string(
    dir + "/memory/thinking.md",
    encoding="utf8",
  ) catch {
    _ => abort("读正文失败")
  }
  assert_true(body.contains("2026-09-05T00:00:00Z"))
  assert_true(body.contains("第一步思考"))
  assert_true(body.contains("2026-09-06T00:00:00Z"))
  assert_true(body.contains("第二步思考"))
}

// ---------------------------------------------------------------------------
// 用例 9：memory_link
// ---------------------------------------------------------------------------

///|
test "memory_9_link_create_append" {
  let dir = mem_dir("mem_c9_link")
  let j1 = match memory_link(dir, "taskA", "taskB", "关联说明") {
    Ok(x) => x
    Err(m) => abort(m)
  }
  assert_true(mem_bool(j1, "linked"))
  // 追加一条
  ignore(memory_link(dir, "taskB", "taskC", ""))
  let body = @fs.read_file_to_string(dir + "/memory/links.md", encoding="utf8") catch {
    _ => abort("读 links 失败")
  }
  assert_true(body.contains("taskA -> taskB  关联说明"))
  assert_true(body.contains("taskB -> taskC"))
}

// ---------------------------------------------------------------------------
// 用例 10：evolve_distill
// ---------------------------------------------------------------------------

///|
test "memory_10_distill_principle_goal" {
  assert_eq(
    distill_principle_goal("保持单一职责"),
    "[principle] 保持单一职责",
  )
  // 已带前缀则不重复叠加
  assert_eq(
    distill_principle_goal("  [principle] 旧原则  "),
    "[principle] 旧原则",
  )
}

///|
test "memory_11_distill_in_memory" {
  // 独立 Archive + 无 sqlite（仅进程内），验证 distilled + artifact_id
  let arc = @evolve.Archive::new("test-dist")
  let j1 = do_evolve_distill(
    arc,
    None,
    "单一职责原则",
    "说明",
    1.0,
    "2026-09-05T00:00:00Z",
  )
  assert_true(mem_bool(j1, "distilled"))
  assert_true(mem_str(j1, "artifact_id").contains("principle-"))
  // 同 now 同 goal 二次蒸馏：同一 id，upsert 幂等
  let j2 = do_evolve_distill(
    arc,
    None,
    "单一职责原则",
    "说明",
    1.0,
    "2026-09-05T00:00:00Z",
  )
  assert_eq(mem_str(j1, "artifact_id"), mem_str(j2, "artifact_id"))
  // 不同 now 蒸馏相同目标 → 触发查重（duplicate=true）但各称 id 独立成条原则（复用 upsert 语义）
  let j3 = do_evolve_distill(
    arc,
    None,
    "单一职责原则",
    "说明",
    1.0,
    "2026-09-06T00:00:00Z",
  )
  assert_true(mem_bool(j3, "duplicate"))
  assert_true(mem_str(j3, "artifact_id") != mem_str(j2, "artifact_id"))
  // 不同目标 → 独立成条（用与 j1 不同的 now 确保 id 唯一）
  let j4 = do_evolve_distill(
    arc,
    None,
    "另一原则",
    "说明2",
    1.0,
    "2026-09-07T00:00:00Z",
  )
  assert_true(mem_str(j4, "artifact_id") != mem_str(j2, "artifact_id"))
  // archive 内存库：j1/j2 同 id 计 1，j3/j4 各 1 → 共 3 条不同 id
  assert_eq(@evolve.Archive::len(arc), 3)
}

///|
test "memory_12_distill_persist_sqlite" {
  // 复用 store 层 sqlite（store 层原生支持 js），验证落库返回 id
  let s = match @store.SqliteStore::open("temp/distill_c12.db") {
    Some(x) => x
    None => abort("sqlite open failed")
  }
  ignore(s.clear())
  let arc = @evolve.Archive::new("test-dist-sql")
  let j = do_evolve_distill(
    arc,
    Some(s),
    "可计算评分原则",
    "说明",
    1.0,
    "2026-09-05T00:00:00Z",
  )
  assert_true(mem_bool(j, "distilled"))
  assert_true(mem_bool(j, "persisted"))
  let id = mem_str(j, "artifact_id")
  // store 层可查到（evolve_list 返回含该 id）
  let list = s.evolve_list()
  let mut found = false
  for item in list {
    if mem_str(item, "id") == id {
      found = true
      break
    }
  }
  assert_true(found)
  ignore(s.clear())
}
