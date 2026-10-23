/// core_task_desc_clip_wbtest.mbt —— Task::to_json desc_limit / desc_clip 白盒锁
/// 给 AI 编排用的 MCP 工具返回体积控闸：task_plan_deep 开满 gradient/reinject_context/
/// boundary_probe 后 description 会递归膨胀到数 KB，supervisor_status 默认截断到 200 字节，
/// 否则全量回传会把上下文/返回体积炸掉。锁：
///   dc_1  desc_limit<=0 原样返回（零回归锚）
///   dc_2  短字符串不截断
///   dc_3  长字符串截断且 UTF-8 字符边界安全（中文不被切半）
///   dc_4  to_json desc_limit 生效、description 被截断
///   dc_5  to_json 默认（desc_limit=-1）description 完整（零回归锚）

///|
/// 直构任务（同包字段可见）。
fn dc_task(description : String) -> Task {
  Task::new(id="T_dc", project_dir="/p", description~, created_at="t0")
}

///|
/// 从 task JSON 取 description 字符串。
fn dc_desc_of(j : Json) -> String {
  match j {
    Json::Object(m) =>
      match m.get("description") {
        Some(Json::String(s)) => s
        _ => ""
      }
    _ => ""
  }
}

///|
test "dc_1 desc_limit<=0 原样返回（零回归锚）" {
  let s = "some long enough description text here"
  assert_eq(desc_clip(s, 0), s)
  assert_eq(desc_clip(s, -1), s)
}

///|
test "dc_2 短字符串不截断" {
  let s = "短描述"
  assert_eq(desc_clip(s, 200), s)
}

///|
test "dc_3 长字符串截断且 UTF-8 字符边界安全" {
  // 中文 3 字节/字：limit=6 若按字节硬切会落在第 2 个中文字符中间
  let s = "一二三四五六七八九十"
  let out = desc_clip(s, 6)
  // 6 字节 = 2 个中文字符 + "…"
  assert_eq(out, "一二…")
  // 落点必须是合法 UTF-8（不 panic、长度符合预期）
  assert_eq(out.length() > 0, true)
}

///|
/// 拼接出长字符串（MoonBit 无字符串 `*` 操作符）。
fn dc_long_str(unit : String, times : Int32) -> String {
  let mut out = ""
  let mut i = 0
  while i < times {
    out = out + unit
    i = i + 1
  }
  out
}

///|
test "dc_4 to_json desc_limit 生效、description 被截断" {
  let long = dc_long_str("abcdefghij", 40)
  let j = dc_task(long).to_json(desc_limit=20)
  let d = dc_desc_of(j)
  assert_eq(d.contains(dc_long_str("abcdefghij", 40)), false)
  assert_eq(d.has_suffix("…"), true)
  // 截断后长度应 <= limit + 省略号
  assert_eq(d.length() <= 21, true)
}

///|
test "dc_5 to_json 默认 desc_limit=-1 description 完整（零回归锚）" {
  let long = dc_long_str("abcdefghij", 40)
  let j = dc_task(long).to_json()
  assert_eq(dc_desc_of(j), long)
}
