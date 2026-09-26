/// output_validate_r3_test.mbt —— BUG-31 回归锁：交付物硬门不得被"空检查"自证为真。
///
/// 病灶：`parse_artifact` 过去只读它认识的键，拼错/臆造的键（`contans`、`must_contain`）
/// 被静默忽略，spec 退化成「文件存在 + 非空」——verdict 仍 pass，detail 还写
/// 「invariant 全部通过」。等于 L4 证据梯可以凭空造，验收面最不该有的一种假绿。

///|
fn r3ov_json(r : Result[Json, String]) -> Json {
  match r {
    Ok(j) => j
    Err(e) => abort("output_validate 返回 Err: " + e)
  }
}

///|
fn r3ov_verdict(j : Json) -> String {
  match j.value("verdict") {
    Some(String(s)) => s
    _ => abort("缺 verdict: " + j.stringify())
  }
}

///|
/// 把所有 check 的 detail 拼成一段文本，便于断言"错误信息点名了未知键"。
fn r3ov_details(j : Json) -> String {
  let mut out = ""
  match j.value("checks") {
    Some(Array(arr)) =>
      for c in arr {
        match c.value("detail") {
          Some(String(s)) => out = out + " | " + s
          _ => ()
        }
      }
    _ => ()
  }
  out
}

///|
test "BUG-31：拼错的 artifact 键必须让硬门变红，且点名未知键" {
  // 与下面那条"合法 contains 断言"只差一个字母——旧实现两者都回 pass，正是病灶
  let j = r3ov_json(
    output_validate(
      ".",
      [
        Json::object({
          "path": Json::string("README.md"),
          "contans": Json::string("FIST-Mbt"),
        }),
      ],
      Json::object({}),
      "ev",
    ),
  )
  if r3ov_verdict(j) != "fail" {
    abort(
      "未知键被静默降级成空检查，verdict 仍是 " + r3ov_verdict(j),
    )
  }
  let d = r3ov_details(j)
  if !d.contains("contans") {
    abort("拒绝原因未点出未知键，调用方只能猜: " + d)
  }
  if !d.contains("check_key") {
    abort("拒绝原因必须同时给出可用键清单: " + d)
  }
}

///|
test "BUG-31 成对：合法规格必须放行，冲突/空规格必须挡下" {
  let ok = r3ov_json(
    output_validate(
      ".",
      [
        Json::object({
          "path": Json::string("README.md"),
          "contains": Json::string("FIST-Mbt"),
        }),
      ],
      Json::object({}),
      "ev",
    ),
  )
  if r3ov_verdict(ok) != "pass" {
    abort("合法 contains 断言被误拒: " + r3ov_details(ok))
  }
  let both = r3ov_json(
    output_validate(
      ".",
      [
        Json::object({
          "path": Json::string("README.md"),
          "check_key": Json::string("moon_test"),
        }),
      ],
      Json::object({}),
      "ev",
    ),
  )
  if r3ov_verdict(both) != "fail" {
    abort(
      "path+check_key 同时给仍算通过，两条检查路径语义被混用",
    )
  }
  let empty_spec = r3ov_json(
    output_validate(
      ".",
      [Json::object({ "min_chars": Json::number(1.0) })],
      Json::object({}),
      "ev",
    ),
  )
  if r3ov_verdict(empty_spec) != "fail" {
    abort("既无 path 又无 check_key 的空规格算通过")
  }
}

///|
test "BUG-31 建议2：纯 {path} 的 pass 文案不得声称 invariant 通过" {
  let j = r3ov_json(
    output_validate(
      ".",
      [Json::object({ "path": Json::string("README.md") })],
      Json::object({}),
      "ev",
    ),
  )
  if r3ov_verdict(j) != "pass" {
    abort("纯存在性 artifact 本应 pass，实际 " + r3ov_verdict(j))
  }
  let d = r3ov_details(j)
  if d.contains("invariant 全部通过") {
    abort("pass 文案冒充评估过 invariant: " + d)
  }
  if !d.contains("仅存在性") {
    abort("pass 文案未声明只做了存在性/非空: " + d)
  }
}
