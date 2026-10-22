/// output_validate_ext_invariant_test.mbt —— R132：外部产物（check_key）的
/// invariant 不许被静默忽略。
///
/// 病灶两条（与 BUG-31/BUG-209 同族，都是「声明了检查却没人读它」= 假 pass）：
/// 1) `{check_key, min_chars}`：`artifact_spec_errors` 只验值型不拒组合，
///    `check_external_artifact` 又不读 min_chars ⇒ 硬门按更弱的 ok 判 pass。
/// 2) `{check_key, contains/not_contains}` 且 external_results 里是非对象
///    （bare true/"ok"）：`check_external_artifact` 的非对象分支直接按 ok 判 pass，
///    没有 stdout 可校验却当作校验通过（BUG-143 的同类漏口）。

///|
fn r132ov_json(r : Result[Json, String]) -> Json {
  match r {
    Ok(j) => j
    Err(e) => abort("output_validate 返回 Err: " + e)
  }
}

///|
fn r132ov_verdict(j : Json) -> String {
  match j.value("verdict") {
    Some(String(s)) => s
    _ => abort("缺 verdict: " + j.stringify())
  }
}

///|
fn r132ov_details(j : Json) -> String {
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
fn r132ov_ext_stdout(key : String, stdout : String) -> Json {
  let inner : Map[String, Json] = Map([])
  inner.set("ok", Json::boolean(true))
  inner.set("code", Json::number(0.0))
  inner.set("stdout", Json::string(stdout))
  let outer : Map[String, Json] = Map([])
  outer.set(key, Json::object(inner))
  Json::object(outer)
}

///|
fn r132ov_ext_bool(key : String, v : Bool) -> Json {
  let outer : Map[String, Json] = Map([])
  outer.set(key, Json::boolean(v))
  Json::object(outer)
}

///|
/// check_key 产物声明 min_chars 必须被判 spec 非法（fail），不得静默降级成只查 ok。
test "r132_1_check_key_min_chars_rejected" {
  let artifacts : Array[Json] = [
    Json::object({
      "check_key": Json::string("moon_test"),
      "min_chars": Json::number(1_000_000.0),
    }),
  ]
  // 外部结果本身完全合法（汇总行齐全）——失败只可能来自「min_chars 没人读」
  let ext = r132ov_ext_stdout(
    "moon_test", "Total tests: 645, passed: 645, failed: 0.",
  )
  let r = @server.output_validate(
    ".",
    artifacts,
    ext,
    "",
    require_evidence=false,
  )
  let j = r132ov_json(r)
  assert_eq(r132ov_verdict(j), "fail")
  assert_true(r132ov_details(j).contains("min_chars"))
}

///|
/// 非对象外部结果 + 声明 contains：没有 stdout 可校验，必须 fail-closed。
test "r132_2_check_key_contains_bare_bool_fails_closed" {
  let artifacts : Array[Json] = [
    Json::object({
      "check_key": Json::string("linter"),
      "contains": Json::string("READY"),
    }),
  ]
  let r = @server.output_validate(
    ".",
    artifacts,
    r132ov_ext_bool("linter", true),
    "",
    require_evidence=false,
  )
  let j = r132ov_json(r)
  assert_eq(r132ov_verdict(j), "fail")
  assert_true(r132ov_details(j).contains("stdout"))
}

///|
/// 反向对照：没声明 invariant 的 bare bool 外部结果保持原便利行为（pass），
/// 证明 r132 的收紧只作用于「声明了却校验不到」这一档。
test "r132_3_check_key_bare_bool_without_invariant_pass" {
  let artifacts : Array[Json] = [
    Json::object({ "check_key": Json::string("linter") }),
  ]
  let r = @server.output_validate(
    ".",
    artifacts,
    r132ov_ext_bool("linter", true),
    "",
    require_evidence=false,
  )
  let j = r132ov_json(r)
  assert_eq(r132ov_verdict(j), "pass")
}
