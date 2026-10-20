///|
/// ops_heal_wbtest.mbt —— BUG-240 白盒回归锁：ops_heal.mbt 三个看护函数
/// （heal_stale_tasks / heal_stale_tasks_from_store / heal_stale_tasks_by_phi）
/// 清理持久化心跳失败时不再被 `ignore(...)` 静默吞掉，回执不得只报 healed 成功。
///
/// 病根：reopen 成功后 `ignore(engine.store_delete_heartbeat(...))` 吞掉 SQLite 删除失败，
/// 残留过期心跳行会让下一轮 `heal_stale_tasks_from_store`（以持久化心跳表为判活依据）
/// 把已回滚任务误判为「仍在执行」，错过下一次回滚窗口。
/// 修法：捕获 Result，失败 push 进 `delete_failed_ids` 旁路输出，由调用面点名披露。
///
/// 注：源码文本锁匹配字面量，新代码注释不得包含被锁模式本身。
/// src/ops 无 r2_* helper（那套在 src/server 同包），故本地定义 count / read。

///|
/// 统计子串出现次数（文本锁用）。不用 `hay.split(needle).length()`：
/// 本版本 `String::split` 返回消费式 Iter，第二次读到 0 会假红灯。
fn ops_heal_count(hay : String, needle : String) -> Int32 {
  let cs = hay.to_array()
  let ps = needle.to_array()
  if ps.length() == 0 {
    return 0
  }
  let mut n = 0
  let mut i = 0
  while i + ps.length() <= cs.length() {
    let mut matched = true
    for k = 0; k < ps.length(); k = k + 1 {
      if cs[i + k] != ps[k] {
        matched = false
      }
    }
    if matched {
      n = n + 1
      i = i + ps.length()
    } else {
      i = i + 1
    }
  }
  n
}

///|
/// 读项目根下的文件，读不到就 abort（防「路径不对→空串→假绿」）。
fn ops_heal_read_or_abort(path : String) -> String {
  let content : String? = Some(@fs.read_file_to_string(path, encoding="utf8")) catch {
    _ => None
  }
  match content {
    Some(c) => c
    None =>
      abort(
        "不可读 \{path}（测试必须在项目根跑）——该守卫无法自证",
      )
  }
}

///|
test "BUG-240：store_delete_heartbeat 不再被 ignore 静默吞掉（源码文本锁）" {
  let src = ops_heal_read_or_abort("src/ops/ops_heal.mbt")
  assert_eq(ops_heal_count(src, "ignore(engine.store_delete_heartbeat"), 0)
}

///|
test "BUG-240：三处清理心跳失败均点名进 delete_failed_ids（源码文本锁）" {
  let src = ops_heal_read_or_abort("src/ops/ops_heal.mbt")
  assert_eq(
    ops_heal_count(src, "Err(_) => delete_failed_ids.push(t.get_id())"),
    3,
  )
}

///|
/// BUG-342：并发 agent 把可选参数签名 `?` 批量改成 borrow `~`（MoonBit 0.1.20261016）。
/// 文本锁必须同时接受两种形态，否则同一语义不同签名会假红。
test "BUG-240：三个看护函数均暴露 delete_failed_ids 参数（源码文本锁）" {
  let src = ops_heal_read_or_abort("src/ops/ops_heal.mbt")
  let count_q = ops_heal_count(src, "delete_failed_ids? : Array[String] = []")
  let count_t = ops_heal_count(src, "delete_failed_ids~ : Array[String] = []")
  assert_eq(count_q + count_t, 3)
}
