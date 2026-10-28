///|
/// core_task_from_db_wbtest.mbt —— **反序列化落位与 fallback 行为**白盒锁（R144）。
///
/// 为什么要有这个文件：`Task::from_db` / `Task::from_db_with_created_by` 是
/// **store 行 → 域对象**的唯一入口，此前只有 9 处**间接**调用（引擎测试拿它造特定状态的种子任务），
/// 对两条**静默行为**没有任何断言：
///
///   ① `status_s` 认不出时 **fallback 到 `Pending`**（`None => Pending`，且**原本无注释**）；
///   ② `level` 越界时被 `clamp_level` 夹到 0..7。
///
/// ①是**数据路径上的 fail-open**：`Pending` 是最宽松的可操作态（可 claim / 可 split），
/// 若存储里出现一个没被 `TaskStatus::from_string` 覆盖的状态串（改名 / 新增态 / 脏数据），
/// 该任务会**静默复活成"待领取"**而不是报错。本文件先把现状钉住并写明风险，
/// **是否改成 fail-closed（拒读 / 落到惰性态）属语义变更，留 owner 裁决**。

///|
/// 造一个 `from_db` 行（19 个**位置**参数，故用辅助函数收口，避免用例里写 19 行重复）。
fn fd(status_s : String, level : Int32, id : String) -> Task {
  Task::from_db(
    id,
    None,
    ".",
    "default",
    "中",
    "中",
    1,
    3,
    level,
    status_s,
    None,
    "描述",
    "",
    "2026-01-01T00:00:00Z",
    "2026-01-01T00:00:01Z",
    None,
    "deferred",
    [],
    false,
  )
}

///|
/// 锁 1：**9 个状态字面量逐字往返**（存储面用的就是这些中文串）。
/// 变异对照：把 `from_string` 任一分支的中文改一个字，本格立刻红。
test "from_db_status_literals_roundtrip_all_nine" {
  let keys : Array[String] = [
    "待领取", "已领取", "拆分中", "执行中", "待验收", "已完成", "已归档", "已打回", "已暂停",
  ]
  for k in keys {
    let t = fd(k, 6, "rt")
    assert_eq(t.status_to_string(), k)
  }
}

///|
/// 锁 2：**未知状态串 ⇒ `Pending`（fail-open）** —— 钉住现状并标注风险。
///
/// ⚠️ 这不是"正确行为"的背书：`Pending` 是最宽松态，脏状态串会让任务复活成可领取。
/// 本格的作用是「谁改了这条 fallback（改成报错 / 改成惰性态）都会立刻红」，
/// 迫使改动者先读到这段说明再决定。
test "from_db_unknown_status_falls_back_to_pending_failopen" {
  let t = fd("这不是任何一个状态", 6, "unknown")
  assert_eq(t.status_to_string(), "待领取")
  assert_true(t.get_status().is_pending())
}

///|
/// 锁 3：`level` 越界被 `clamp_level` 夹到 0..7（>7 ⇒ 7，<0 ⇒ 0）。
/// 为什么钉：`level` 参与军衔展示与 `plan_deep` 的子任务层级推导（父级 + 1 封顶 7），
/// 脏数据不夹会让展示层出现越界军衔。
test "from_db_level_is_clamped" {
  assert_eq(fd("待领取", 99, "lv-high").get_level(), 7)
  assert_eq(fd("待领取", -5, "lv-low").get_level(), 0)
  // 界内不动
  assert_eq(fd("待领取", 6, "lv-mid").get_level(), 6)
  assert_eq(fd("待领取", 0, "lv-zero").get_level(), 0)
}
