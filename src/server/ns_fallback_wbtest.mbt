/// ns_fallback_wbtest.mbt —— BUG-433 的成对锁。
///
/// **病灶**：`engine_for_ns` 过去是 `None => engine` —— 把「请求的 ns 不存在/非法」
/// 与「就用主库」在**类型上**做成不可分，谁也看不见自己在动主库。
/// 而 `ns` 既是任务标签又是**物理库路由** ⇒ 非法 ns 静默回落会让 `delete`/`archive`/
/// `execute`/`claim` 这些写工具打到**主库任务**上（同 id 存在即误删，不可逆）。
///
/// **修法**：收口为 `Result` + `engine_route_in`（可注入 getter 的纯路由判据）。
/// 三条出口**没有一条是"静默换库"**：
/// ① 主库（""/"default"）→ `Ok(main_eng)`
/// ② 非法 ns → `Err`，**getter 一次都不调**（连库句柄都不碰）
/// ③ 合法 ns → getter；拿到库 → `Ok(该库引擎)`，**拿不到 → `Err`**（不是 `Ok(main_eng)`！）

///|
/// 计数用的可变盒子（MoonBit 闭包捕获 `mut` 局部变量受限，用 Array 兜住）。
fn _ns_probe_counter() -> Array[Int] {
  [0]
}

///|
/// 锁 1：**非法 ns ⇒ Err 且 getter 一次都不调**。
///
/// 这一格是 BUG-433 的**机制格本尊**：它同时钉住两件事 ——
/// ① 非法 ns 必须被拒（不能回落主库）；② **连库句柄都不碰**（getter 调用计数 = 0）。
/// 若把 `ns_reject_reason` 那一段删掉（退回旧的 `None => engine` 语义），本格必红。
test "bug433_illegal_ns_never_touches_store" {
  let main = @engine.FistEngine::new()
  let cnt = _ns_probe_counter()
  let getter = fn(_ns : String) -> @store.SqliteStore? {
    cnt[0] = cnt[0] + 1
    None
  }
  let bad_ns : Array[String] = [
    "has.dot", "has space", "中文命名", "a/b", "a:b", "with\backslash",
  ]
  for bad in bad_ns {
    match engine_route_in(main, getter, bad) {
      Err(_) => ()
      Ok(_) => fail("BUG-433：非法 ns 必须 Err，实得 Ok：" + bad)
    }
  }
  // ★ 关键：六个非法 ns 试过，getter 一次都不该被调用
  assert_eq(cnt[0], 0)
}

///|
/// 锁 2：**合法但库打不开 ⇒ Err，绝不 Ok(main)**。
///
/// 这是最容易被"顺手修回去"的一格：`getter` 返回 `None` 时最省事的写法是
/// `None => Ok(main_eng)` —— 那正是 BUG-433 的病灶形状（静默换库）。本格钉住「拿不到库就 Err」。
test "bug433_unopenable_valid_ns_is_err_not_main" {
  let main = @engine.FistEngine::new()
  let getter = fn(_ns : String) -> @store.SqliteStore? { None }
  match engine_route_in(main, getter, "valid-ns") {
    Err(_) => ()
    Ok(_) => fail("BUG-433：合法但库打不开必须 Err —— Ok 意味着静默回落主库")
  }
}

///|
/// 锁 3：`""` / `"default"` 走主库 ⇒ `Ok(main)`，且**不该去查 mstore**。
///
/// 防「修过头」：把默认路径也做成"必须 store_open 过"会让所有既有单库用法断掉。
test "bug433_default_paths_ok_main_without_lookup" {
  let main = @engine.FistEngine::new()
  let cnt = _ns_probe_counter()
  let getter = fn(_ns : String) -> @store.SqliteStore? {
    cnt[0] = cnt[0] + 1
    None
  }
  let ok_ns : Array[String] = ["", "default"]
  for ok in ok_ns {
    match engine_route_in(main, getter, ok) {
      Ok(_) => ()
      Err(_) => fail("BUG-433：非法判定过宽 —— \"" + ok + "\" 必须走主库 Ok")
    }
  }
  assert_eq(cnt[0], 0) // 默认路径不查 mstore
}

///|
/// 锁 4：纯判定的**拒绝文案三要件**（可行动性 —— 光拒绝不给路等于把调用方卡死）。
///
/// 判据：文案里必须同时有 ①「非法」二字 ② 允许的字符集 ③「静默回落主库」这句
/// —— 第三条是把**修法的语义**写进回执，让调用方知道这不是"库坏了"而是"你 ns 写错了"。
test "bug433_reject_message_is_actionable" {
  match ns_reject_reason("has.dot") {
    None => fail("BUG-433：非法 ns 必须给拒绝文案")
    Some(msg) => {
      assert_true(msg.contains("非法"))
      assert_true(msg.contains("0-9A-Za-z_-"))
      assert_true(msg.contains("静默回落主库"))
    }
  }
  // 合法形态不拒（含默认两档与常见合法字符）
  let ok_ns : Array[String] = ["", "default", "valid-ns", "valid_ns_123", "A1-b2_c3"]
  for ok in ok_ns {
    match ns_reject_reason(ok) {
      None => ()
      Some(_) => fail("BUG-433：合法 ns 不该被拒：" + ok)
    }
  }
}
