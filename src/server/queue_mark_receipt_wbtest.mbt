/// queue_mark_receipt_wbtest.mbt —— BUG-228 回归锁
///
/// report_bug auto_push 两处队列标记调用点曾 `let _ =` 丢弃 Result：本地队列写入失败时
/// 回执仍报 github.ok:true / gitcode.ok:true，下轮 sync 重复建号。回执必须可见。
///
/// 覆盖：
///   1) Ok 路径：ok=true / channel / marked / total 原样带回
///   2) Err 路径：ok=false / channel / queue_mark_error 含原始错误串（如「队列写入失败」）
///
///|

fn qmr_str(j : Json, key : String) -> String {
  match j {
    Object(m) =>
      match m.get(key) {
        Some(String(s)) => s
        _ => ""
      }
    _ => ""
  }
}

fn qmr_bool(j : Json, key : String) -> Bool {
  match j {
    Object(m) =>
      match m.get(key) {
        Some(True) => true
        _ => false
      }
    _ => false
  }
}

fn qmr_num(j : Json, key : String) -> Double {
  match j {
    Object(m) =>
      match m.get(key) {
        Some(Number(n, ..)) => n
        _ => 0.0
      }
    _ => 0.0
  }
}

test "bug228_queue_mark_receipt_ok" {
  let ok_json = Json::object(
    Map([("marked", Json::number(1.0)), ("total", Json::number(3.0))]),
  )
  let r = queue_mark_receipt("github", Ok(ok_json))
  assert_eq(qmr_bool(r, "ok"), true)
  assert_eq(qmr_str(r, "channel"), "github")
  assert_true(qmr_num(r, "marked") == 1.0)
  assert_true(qmr_num(r, "total") == 3.0)
}

test "bug228_queue_mark_receipt_err" {
  let r = queue_mark_receipt(
    "gitcode",
    Err("gitcode_queue_mark_sent_batch: 队列写入失败"),
  )
  assert_eq(qmr_bool(r, "ok"), false)
  assert_eq(qmr_str(r, "channel"), "gitcode")
  assert_true(qmr_str(r, "queue_mark_error").contains("队列写入失败"))
}
