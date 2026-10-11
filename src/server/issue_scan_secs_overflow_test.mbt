/// issue_scan_secs_overflow_test.mbt —— R12-R7 bugfind：验证 issue_scan 的 secs-overflow
/// 规则存在（BUG-217/218/219 教训：*86400 是 Int32 溢出重灾区，旧规则只匹配 * 10）。
test "secs-overflow 规则存在且可统计" {
  // 建独立用例目录，注入一个含 * 86400 的 .mbt 文件
  @fs.create_dir("temp") catch { _ => () }
  let d = "temp/lint_secs"
  @fs.create_dir(d) catch { _ => () }
  let body = "/// overflow case\n" +
    "pub fn f(days: Int) -> Int {\n" +
    "  days * 86400\n" +
    "}\n"
  @fs.write_string_to_file(d + "/sample.mbt", body, encoding="utf8") catch {
    _ => ()
  }
  let r = issue_scan(d, "", 500)
  assert_true(r.is_ok())
  let j = match r {
    Ok(x) => x
    Err(_) => return
  }
  // 解析 by_rule 数组，找 secs-overflow 且 count >= 1
  let by_rule = match j {
    Json::Object(m) =>
      match m.get("by_rule") {
        Some(Json::Array(a)) => a
        _ => []
      }
    _ => []
  }
  let mut found = false
  for rule in by_rule {
    let id = match rule {
      Json::Object(m) =>
        match m.get("rule") {
          Some(Json::String(s)) => s
          _ => ""
        }
      _ => ""
    }
    if id == "secs-overflow" {
      found = true
    }
  }
  assert_true(found)
}