/// executor_register_wbtest.mbt —— BUG-232 回归锁。
///
/// 修复前：`executor_register` 把 `engine.executor_save` 的 Result 用 `ignore()` 吞掉，
/// 且回执 `persisted` 硬编码为 true——写盘失败时仍谎报落库，进程内注册表看似成功、
/// store 里却没有，重启后 `executor_route` 读不到（静默吞错家族，与 BUG-230 同族）。
///
/// 锁两件事：(1) 纯函数 `executor_persist_note` 的 Ok/Err 双分支语义；
/// (2) server.mbt 源码文本——调用点已接线、硬编码 `persisted:true` 已消除、`persist_error` 留痕。

///|
/// 纯函数语义：Ok→(true, "") 无错不留痕；Err→(false, 错误原文)。
test "BUG-232：executor_persist_note Ok/Err 双分支" {
  let (ok_p, ok_e) = executor_persist_note(Ok("executor-A"))
  assert_eq(ok_p, true)
  assert_eq(ok_e, "")
  let (bad_p, bad_e) = executor_persist_note(
    Err("sqlite 写入 executors 失败"),
  )
  assert_eq(bad_p, false)
  assert_eq(bad_e, "sqlite 写入 executors 失败")
  // 空原因也照样成型（不 panic、不吞成空串之外的东西）
  let (e2_p, e2_e) = executor_persist_note(Err(""))
  assert_eq(e2_p, false)
  assert_eq(e2_e, "")
}

///|
/// 源码文本锁：接线点存在 + 硬编码 persisted:true 已消除 + persist_error 透出。
test "BUG-232：executor_register 不再硬编码 persisted:true（源码文本锁）" {
  let src = r2_read_or_abort("src/server/server.mbt")
  assert_true(r2_count(src, "= executor_persist_note(") >= 1)
  assert_eq(r2_count(src, "\"persisted\": Json::boolean(true),"), 0)
  assert_true(
    src.contains("m.set(\"persist_error\", Json::string(persist_error))"),
  )
}

///|
/// 空白归一：连续空白折成单个空格，使源码文本锁对 moon fmt 折行免疫。
fn normalize_ws(s : String) -> String {
  let buf = StringBuilder::new()
  let mut prev_ws = false
  for ch in s {
    let is_ws = ch == ' ' || ch == '\n' || ch == '\t' || ch == '\r'
    if is_ws {
      if !prev_ws {
        buf.write_char(' ')
      }
      prev_ws = true
    } else {
      buf.write_char(ch)
      prev_ws = false
    }
  }
  buf.to_string()
}

///|
/// Tier2 PR3 机器注册表（真源 docs/2026-10-21-fist-governance-tier2-plan.md PR3 节）：
/// 纯函数 executor_machine_merge 的三格语义。
test "PR3：machine_id 缺省=原样返回（零回归变异对照格）" {
  // 变异对照：若有人把「空=原样」的短路守卫改成无条件追加标签，
  // 本格立刻红——缺 machine_id 的行为必须与旧版逐字一致。
  let abs = ["编排", "json"]
  let out = executor_machine_merge(abs, "")
  assert_eq(out.length(), 2)
  assert_eq(out[0], "编排")
  assert_eq(out[1], "json")
  // 空数组同样原样（不凭空长出标签）
  let empty = executor_machine_merge([], "")
  assert_eq(empty.length(), 0)
}

///|
test "PR3：machine_id 非空=追加 machine_id:<id> 标签（幂等）" {
  let abs = ["编排"]
  let out = executor_machine_merge(abs, "worker-1")
  assert_eq(out.length(), 2)
  assert_eq(out[0], "编排")
  assert_eq(out[1], "machine_id:worker-1")
  // 幂等：标签已在则不重复追加
  let again = executor_machine_merge(out, "worker-1")
  assert_eq(again.length(), 2)
  assert_eq(again[1], "machine_id:worker-1")
  // 同名前缀不误判：machine_id:worker-10 不会挡住 machine_id:worker-1
  let distinct = executor_machine_merge(["machine_id:worker-10"], "worker-1")
  assert_eq(distinct.length(), 2)
  assert_eq(distinct[1], "machine_id:worker-1")
}

///|
/// 源码文本锁（判例-29：机制格 ≠ 实现路径格）：server.mbt 真的把 machine_id
/// 接进了 executor_register 的 schema 与回执，而不是只留一个没人调用的纯函数。
/// 匹配前先做空白归一（moon fmt 会把长调用折行，逐字 contains 会被折行喂空）。
test "PR3：executor_register 参数面与回执已接线（源码文本锁）" {
  let src = r2_read_or_abort("src/server/server.mbt")
  let norm = normalize_ws(src)
  // schema 面有 machine_id 参数
  assert_true(
    norm.contains("\"machine_id\": string_prop( \"可选：机器标识"),
  )
  // handler 真读取并把合并结果喂给注册表（接线点，非死代码）
  assert_true(norm.contains("let mid = get_str(args, \"machine_id\")"))
  assert_true(
    norm.contains(
      "let abs = executor_machine_merge( strlist(get_array(args, \"abilities\")), mid, )",
    ),
  )
  // 回执守卫：仅显式登记机器时才带 machine_id 字段（缺省路径逐字零回归）
  assert_true(norm.contains("m.set(\"machine_id\", Json::string(mid))"))
}
