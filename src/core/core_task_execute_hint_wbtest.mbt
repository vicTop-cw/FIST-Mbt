///|
/// core_task_execute_hint_wbtest.mbt —— `execute` 失败时的**出路文案**白盒锁（R145）。
///
/// 为什么补：`Task::execute_exit_hint` 是 `engine.execute` 拒绝时拼进用户回执的**唯一指引**
/// （`engine.mbt`：「非法执行: 任务处于 [...]。出路：{execute_exit_hint(...)}」）。
/// 它此前**零直接引用**（差集扫出来的），也就是没人钉过：
///   · 每个状态都返回**非空**文案（空串 = 用户只看到"非法执行"却不知道怎么办）；
///   · 不可执行的状态必须给出**具体动作**（claim / retry / reject / resume / reopen_task），
///     而不是一句无用的"当前状态不支持"。
///
/// 穷尽性由编译器保证（`match` 无 `_` 分支、9 态全列），本文件钉的是**内容质量**。

///|
/// 造一个状态（用 `from_db` 走存储字面量，避免直接构造枚举变体——与真实反序列化同路）。
fn st_of(s : String) -> TaskStatus {
  Task::from_db(
    "hint-" + s,
    None,
    ".",
    "default",
    "中",
    "中",
    1,
    3,
    6,
    s,
    None,
    "描述",
    "",
    "2026-01-01T00:00:00Z",
    "2026-01-01T00:00:01Z",
    None,
    "deferred",
    [],
    false,
  ).get_status()
}

///|
/// 锁 1：**9 个状态全部返回非空文案**（空串等于没有指引）。
test "execute_exit_hint_all_nine_non_empty" {
  let keys : Array[String] = [
    "待领取", "已领取", "拆分中", "执行中", "待验收", "已完成", "已归档", "已打回", "已暂停",
  ]
  for k in keys {
    let hint = Task::execute_exit_hint(st_of(k))
    assert_true(!hint.is_empty())
  }
}

///|
/// 锁 2：**不可执行的状态必须给出具体动作**，且动作名是真实存在的工具/方法名。
///
/// 这些是用户唯一的自救线索：写错动词（比如让已归档的去 `retry`）比不写更糟——
/// 用户会照着做然后再次失败。
test "execute_exit_hint_actions_are_real_and_correct" {
  // 待领取 ⇒ claim
  assert_true(Task::execute_exit_hint(st_of("待领取")).contains("claim"))
  // 已打回 ⇒ retry
  assert_true(Task::execute_exit_hint(st_of("已打回")).contains("retry"))
  // 待验收 ⇒ reject（改交付物前必须先打回）
  assert_true(Task::execute_exit_hint(st_of("待验收")).contains("reject"))
  // 已暂停 ⇒ resume
  assert_true(Task::execute_exit_hint(st_of("已暂停")).contains("resume"))
  // 已完成 / 已归档 ⇒ reopen_task（不是 retry —— 终态没有 retry 出路）
  assert_true(Task::execute_exit_hint(st_of("已完成")).contains("reopen_task"))
  assert_true(Task::execute_exit_hint(st_of("已归档")).contains("reopen_task"))
  assert_true(!Task::execute_exit_hint(st_of("已归档")).contains("retry"))
}

///|
/// 锁 3：**可执行三态共享同一句**「已是可执行状态，直接 execute」——
/// 它们本来就该 execute 成功，走到这里只可能是调用方多余地先问了文案；
/// 若有人把这句改成"先做点什么"，说明可执行集合被动过了，必须重新审视。
test "execute_exit_hint_executable_trio_is_uniform" {
  let a = Task::execute_exit_hint(st_of("已领取"))
  let b = Task::execute_exit_hint(st_of("拆分中"))
  let c = Task::execute_exit_hint(st_of("执行中"))
  assert_eq(a, b)
  assert_eq(b, c)
  assert_true(a.contains("直接 execute"))
}
