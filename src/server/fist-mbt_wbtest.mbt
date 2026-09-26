// Whitebox tests run within the package scope.
// Use them to validate internal helpers or invariants.
// Keep them focused; public behavior belongs in `_test.mbt`.

///|
test "sync_db_lessons 让 DB 中的 [lesson] 教训对 inject 与 dead_ends 进程内可见" {
  let db = "temp/sync_db_lessons_wbtest.db"
  match @store.SqliteStore::open(db) {
    None => abort("open sync db failed")
    Some(store) => {
      // 模拟一条 Omega 打回自动落库的 [lesson]（仅落 DB，不经内存 Archive）
      ignore(
        store.evolve_upsert(
          id="omega-lesson-synctest",
          parent_id="",
          goal="[lesson] omega.spec_rejected",
          note="验收标准不量化",
          code="按审核意见重写语料",
          score=0.5,
          parts_json="{}",
          created_at="2026-09-25T09:00:00Z",
        ),
      )
      let arc = @evolve.Archive::new("sync-test")
      // 同步 DB → 内存档案库
      let n1 = sync_db_lessons(arc, Some(store))
      assert_eq(n1, 1)
      assert_eq(@evolve.Archive::len(arc), 1)
      // inject：按类目命中教训（供 plan/claim 检索"踩过的坑"）
      let inj = lookup_injected_assets_in(arc, "omega.spec_rejected").stringify()
      assert_true(inj.contains("验收标准不量化"))
      // dead_ends："此路不通"地图应如实反映教训
      let dead = @evolve.Archive::dead_ends(arc, limit=8)
      assert_true(dead.length() >= 1)
      assert_true(dead[0].contains("[lesson]"))
      // 幂等：重复同步不重复计数
      assert_eq(sync_db_lessons(arc, Some(store)), 0)
    }
  }
}

///|
/// 取 moon.mod 里 `version = \"x.y.z\"` 的声明值（逐字符状态机；无关键字返回空串）。
/// 用 Array[Char] + 字面量比较（沿用 engine.mbt::extract_difficulty 的既有惯用法），
/// 而不是在测试里写嵌套转义——转义写错会让守卫自己变成假绿。
/// 状态机对分隔符不敏感：关键字后先跳过 `=`、空格、引号，再收集版本字元，
/// 遇到第一个不属于 [0-9A-Za-z.-] 的字符即收尾。
fn moon_mod_version_char_ok(c : Char) -> Bool {
  let digit = c >= '0' && c <= '9'
  let letter = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
  digit || letter || c == '.' || c == '-'
}

///|
fn moon_mod_declared_version(text : String) -> String {
  let cs = text.to_array()
  let key = "version".to_array()
  let mut at = -1
  let mut i = 0
  while at < 0 && i + key.length() <= cs.length() {
    let mut matched = true
    for k = 0; k < key.length(); k = k + 1 {
      if cs[i + k] != key[k] {
        matched = false
      }
    }
    if matched {
      at = i
    }
    i = i + 1
  }
  if at < 0 {
    return ""
  }
  let mut out = ""
  let mut started = false
  let mut j = at + key.length()
  while j < cs.length() {
    let c = cs[j]
    if moon_mod_version_char_ok(c) {
      out = out + c.to_string()
      started = true
    } else if started {
      return out
    }
    j = j + 1
  }
  out
}

///|
test "BUG-16：对外版本单一真源——project_version 逐字等于 moon.mod 声明版本" {
  // 前置哨兵①：moon.mod 读不到就 abort，防「解析不到 → 两边都空串 → 假绿」
  let raw = match mem_read("moon.mod") {
    None =>
      abort(
        "moon.mod 不可读（测试必须在项目根跑）——版本守卫无法自证",
      )
    Some(c) => c
  }
  let declared = moon_mod_declared_version(raw)
  assert_true(declared != "")
  assert_eq(project_version, declared)
  // 前置哨兵②：解析器本身要在合成文本上取对值，并能拒掉不含 version 关键字的输入
  // （否则「恒返回空串」的坏解析也能让上面的等式假绿）。
  // 状态机对分隔符不敏感，所以合成输入不必写引号——这正是它能穿过 `= \"...\"` 的原因。
  assert_eq(
    moon_mod_declared_version("name = foo" + " version = 9.9.9-beta"),
    "9.9.9-beta",
  )
  assert_eq(moon_mod_declared_version("nothing here at all"), "")
  // 三个对外面都得用同一个真源（此前各写一遍字面量，升版漏改即落后一整版）
  assert_true(overview_json().stringify().contains(declared))
  let e = @engine.FistEngine::new()
  assert_true(
    render_status_summary(e.list_all(), [], project_version)
    .stringify()
    .contains(declared),
  )
  assert_true(
    render_project_health(e.list_all(), project_version)
    .stringify()
    .contains(declared),
  )
  // 回归锁：server.mbt 不得再残留上一版对外字面量（三处硬编码正是这次漂移的成因）
  let src = match mem_read("src/server/server.mbt") {
    None => abort("src/server/server.mbt 不可读——回归锁无法自证")
    Some(c) => c
  }
  assert_true(not(src.contains("0.2.4")))
  assert_true(src.contains("let project_version"))
}
