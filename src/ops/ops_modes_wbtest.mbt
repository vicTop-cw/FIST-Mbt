///|
/// ops_modes_wbtest.mbt —— 自驱编程 6 种开发模式注册表白盒测试（≥ 20 条）

// ---------------------------------------------------------------------------
// default_mode
// ---------------------------------------------------------------------------

test "modes: default_mode 是 Advance" {
  match default_mode() {
    Advance => assert_true(true)
    _ => assert_true(false)
  }
}

// ---------------------------------------------------------------------------
// parse_mode：6 种合法值
// ---------------------------------------------------------------------------

///|
test "modes: parse_mode advance" {
  match parse_mode("advance") {
    Ok(Advance) => assert_true(true)
    _ => assert_true(false)
  }
}

///|
test "modes: parse_mode polish" {
  match parse_mode("polish") {
    Ok(Polish) => assert_true(true)
    _ => assert_true(false)
  }
}

///|
test "modes: parse_mode verify" {
  match parse_mode("verify") {
    Ok(Verify) => assert_true(true)
    _ => assert_true(false)
  }
}

///|
test "modes: parse_mode bugfind" {
  match parse_mode("bugfind") {
    Ok(BugFind) => assert_true(true)
    _ => assert_true(false)
  }
}

///|
test "modes: parse_mode fix_and_merge" {
  match parse_mode("fix_and_merge") {
    Ok(FixAndMerge) => assert_true(true)
    _ => assert_true(false)
  }
}

///|
test "modes: parse_mode tidy" {
  match parse_mode("tidy") {
    Ok(Tidy) => assert_true(true)
    _ => assert_true(false)
  }
}

// ---------------------------------------------------------------------------
// parse_mode：非法值
// ---------------------------------------------------------------------------

///|
test "modes: parse_mode 非法值返回 Err" {
  match parse_mode("ADVANCE") {
    Err(_) => assert_true(true)
    Ok(_) => assert_true(false)
  }
  match parse_mode("bogus") {
    Err(_) => assert_true(true)
    Ok(_) => assert_true(false)
  }
  match parse_mode("") {
    Err(_) => assert_true(true)
    Ok(_) => assert_true(false)
  }
}

///|
test "modes: parse_mode 自动 trim 空白" {
  match parse_mode("  polish  ") {
    Ok(Polish) => assert_true(true)
    _ => assert_true(false)
  }
}

// ---------------------------------------------------------------------------
// mode_short
// ---------------------------------------------------------------------------

///|
test "modes: mode_short Advance" {
  assert_eq(mode_short(Advance), "advance")
}

///|
test "modes: mode_short Polish" {
  assert_eq(mode_short(Polish), "polish")
}

///|
test "modes: mode_short 覆盖 6 种" {
  assert_eq(mode_short(Advance), "advance")
  assert_eq(mode_short(Polish), "polish")
  assert_eq(mode_short(Verify), "verify")
  assert_eq(mode_short(BugFind), "bugfind")
  assert_eq(mode_short(FixAndMerge), "fix_and_merge")
  assert_eq(mode_short(Tidy), "tidy")
}

// ---------------------------------------------------------------------------
// mode_template_path
// ---------------------------------------------------------------------------

///|
test "modes: mode_template_path advance" {
  assert_eq(mode_template_path("advance"), "templates/pipeline_mode_advance.md")
}

///|
test "modes: mode_template_path polish" {
  assert_eq(mode_template_path("polish"), "templates/pipeline_mode_polish.md")
}

///|
test "modes: mode_template_path 非法值也返回拼接字符串" {
  assert_eq(mode_template_path("bogus"), "templates/pipeline_mode_bogus.md")
}

// ---------------------------------------------------------------------------
// mode_constraints（用 Json::boolean 构造函数 + assert_eq 比对）
// ---------------------------------------------------------------------------

///|
test "modes: mode_constraints polish forbid_new_features=true" {
  let j = mode_constraints("polish")
  match j {
    Object(m) =>
      assert_eq(m.get("forbid_new_features"), Some(Json::boolean(true)))
    _ => assert_true(false)
  }
}

///|
test "modes: mode_constraints tidy forbid_new_code=true" {
  let j = mode_constraints("tidy")
  match j {
    Object(m) => assert_eq(m.get("forbid_new_code"), Some(Json::boolean(true)))
    _ => assert_true(false)
  }
}

///|
test "modes: mode_constraints bugfind require_issue_scan=true" {
  let j = mode_constraints("bugfind")
  match j {
    Object(m) =>
      assert_eq(m.get("require_issue_scan"), Some(Json::boolean(true)))
    _ => assert_true(false)
  }
}

///|
test "modes: mode_constraints fix_and_merge require_github_token=true" {
  let j = mode_constraints("fix_and_merge")
  match j {
    Object(m) =>
      assert_eq(m.get("require_github_token"), Some(Json::boolean(true)))
    _ => assert_true(false)
  }
}

///|
test "modes: mode_constraints verify API 枚举与文档检查" {
  let j = mode_constraints("verify")
  match j {
    Object(m) => {
      assert_eq(m.get("require_api_enum"), Some(Json::boolean(true)))
      assert_eq(m.get("require_doc_check"), Some(Json::boolean(true)))
    }
    _ => assert_true(false)
  }
}

///|
test "modes: mode_constraints advance 无特殊约束" {
  let j = mode_constraints("advance")
  match j {
    Object(m) => {
      assert_eq(m.get("forbid_new_features"), Some(Json::boolean(false)))
      assert_eq(m.get("require_issue_scan"), Some(Json::boolean(false)))
    }
    _ => assert_true(false)
  }
}

// ---------------------------------------------------------------------------
// all_modes
// ---------------------------------------------------------------------------

///|
test "modes: all_modes 长度 6" {
  assert_eq(all_modes().length(), 6)
}

///|
test "modes: all_modes 每个元素字段完备" {
  let all = all_modes()
  for item in all {
    match item {
      Object(m) => {
        // mode 字段
        match m.get("mode") {
          Some(Json::String(s)) => assert_true(s != "")
          _ => assert_true(false)
        }
        // name 字段
        match m.get("name") {
          Some(Json::String(s)) => assert_true(s != "")
          _ => assert_true(false)
        }
        // description 字段
        match m.get("description") {
          Some(Json::String(s)) => assert_true(s != "")
          _ => assert_true(false)
        }
        // constraints 字段（必须是 Json 对象）
        match m.get("constraints") {
          Some(Json::Object(_)) => assert_true(true)
          _ => assert_true(false)
        }
        // template_path 字段
        match m.get("template_path") {
          Some(Json::String(s)) => assert_true(s != "")
          _ => assert_true(false)
        }
        // forbidden_tools 字段（必须是数组）
        match m.get("forbidden_tools") {
          Some(Json::Array(_)) => assert_true(true)
          _ => assert_true(false)
        }
      }
      _ => assert_true(false)
    }
  }
}

///|
test "modes: all_modes mode 值互逆" {
  let all = all_modes()
  let expected = [
    "advance", "polish", "verify", "bugfind", "fix_and_merge", "tidy",
  ]
  for i = 0; i < all.length(); i = i + 1 {
    match all[i] {
      Object(m) =>
        match m.get("mode") {
          Some(Json::String(s)) => assert_eq(s, expected[i])
          _ => assert_true(false)
        }
      _ => assert_true(false)
    }
  }
}

// ---------------------------------------------------------------------------
// 额外：非法 parse_mode 错误消息包含提示
// ---------------------------------------------------------------------------

///|
test "modes: parse_mode 错误消息含可选值" {
  match parse_mode("bogus") {
    Err(msg) => assert_true(msg.contains("advance"))
    Ok(_) => assert_true(false)
  }
}
