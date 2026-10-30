
///|
/// R226：`mcp_config_scaffold` 的 **4 个零直接覆盖 pub fn** 契约锁。
/// 既有 14 格通过顶层 `mcs_run_err` **间接**打了凭据扫描 —— 但这 4 个函数是
/// 脚手架的**可独立复用件**（name 校验 / env 过滤 / 凭据扫描 / pretty 打印），
/// 它们各自的边界没有被直接钉过。钉住它们 = 允许别人放心复用。

///|
/// 名字校验的三段边界：空拒 / >32 拒 / 字符集白名单（A-Z a-z 0-9 _ -）。
/// 拼错的 serverName 会变成进程 spawn 失败或 PATH 注入面，字符集是唯一防线。
test "mcs_valid_server_name 的三段边界" {
  assert_true(mcs_valid_server_name("fist-mbt"), msg="合法名被拒")
  assert_true(mcs_valid_server_name("FIST_MBT_01"), msg="大写下划线数字被拒")
  assert_false(mcs_valid_server_name(""), msg="空名应拒")
  assert_false(mcs_valid_server_name("a b"), msg="空格应拒")
  assert_false(mcs_valid_server_name("srv/path"), msg="斜杠应拒")
  assert_false(mcs_valid_server_name("srv;rm"), msg="分号应拒")
  assert_false(mcs_valid_server_name("../etc"), msg="点应拒（路径穿越形状）")
  let long31 = "abcdefghijklmnopqrstuvwxyz12345"
  let long32 = long31 + "6"
  assert_true(mcs_valid_server_name(long31) && mcs_valid_server_name(long32),
    msg="31/32 字符应放行")
  assert_false(mcs_valid_server_name(long32 + "7"), msg="33 字符应拒")
}

///|
/// env 白名单过滤的**双向**：白名单键进（值为字符串原样保留）、
/// 非白名单键收集进 unknown（不进结果）。这是 mcp_env_whitelist 单一真源的行为锁：
/// 白名单改动时，这里会先红。
test "mcs_filter_env 双向过滤" {
  let j : Json = Json::object({
    "FIST_PROJECT_DIR": Json::string("."),
    "FIST_DB_PATH": Json::string("data/x.db"),
    "MY_SECRET": Json::string("zzz"),
    "PATH_OVERRIDE": Json::string("/evil"),
  })
  let unknown : Array[String] = []
  match mcs_filter_env(j, unknown) {
    Ok(m) => {
      assert_eq(m.get("FIST_PROJECT_DIR"), Some("."), msg="白名单键应原样保留")
      assert_eq(m.get("FIST_DB_PATH"), Some("data/x.db"), msg="白名单键应原样保留")
      assert_true(m.get("MY_SECRET") is None, msg="非白名单键不得进结果")
      assert_true(m.get("PATH_OVERRIDE") is None, msg="非白名单键不得进结果")
      assert_true(unknown.contains("MY_SECRET"), msg="非白名单键应被收集")
      assert_true(unknown.contains("PATH_OVERRIDE"), msg="非白名单键应被收集")
    }
    Err(e) => assert_true(false, msg="过滤不应失败: \{e}")
  }
}

///|
/// 凭据扫描**直接调用**的形状锁（既有测试只经顶层间接覆盖）：
/// 键名族（api_key/token/secret/…）与值形状族（sk-/Bearer /ghp_/glpat-/aiza/ya29.）各验代表。
test "mcs_scan_credentials 的键名族与值形状族" {
  // 键名族：大小写变体也要中
  for kv in [
    ("{\"api_key\":\"x\"}", "api_key"),
    ("{\"ApiKey\":\"x\"}", "api_key 变体"),
    ("{\"auth_token\":\"x\"}", "token"),
    ("{\"password\":\"x\"}", "password"),
    ("{\"Authorization\":\"x\"}", "authorization"),
  ] {
    let (j, why) = kv
    let parsed : Json = @json.parse(j) catch { _ => Json::object({}) }
    assert_true(mcs_scan_credentials(parsed) is Err(_),
      msg="键名族应拒: \{why}")
  }
  // 值形状族
  for sv in [
    "{\"env\":{\"K\":\"sk-abc123\"}}",
    "{\"env\":{\"K\":\"Bearer xyz\"}}",
    "{\"env\":{\"K\":\"ghp_1234567890\"}}",
    "{\"env\":{\"K\":\"glpat-abc\"}}",
    "{\"env\":{\"K\":\"AIzaSyXXX\"}}",
    "{\"env\":{\"K\":\"ya29.a0ABC\"}}",
  ] {
    let parsed : Json = @json.parse(sv) catch { _ => Json::object({}) }
    assert_true(mcs_scan_credentials(parsed) is Err(_),
      msg="值形状族应拒")
  }
  // 干净面不得误伤
  let clean : Json = @json.parse(
    "{\"env\":{\"FIST_PROJECT_DIR\":\".\"}}") catch { _ => Json::object({}) }
  assert_true(mcs_scan_credentials(clean) is Ok(_), msg="干净 env 不应被拒")
}

///|
/// pretty 打印：输出必须是**合法 JSON 文本**（含引号与花括号），
/// 且嵌套结构有缩进层次（缩进是给"人读"的，丢了它 pretty 就名存实亡）。
test "mcs_pretty 的输出形状" {
  let j : Json = Json::object({
    "a": Json::number(1.0),
    "b": Json::array([Json::string("x")]),
  })
  let s = mcs_pretty(j)
  assert_true(s.contains("\"a\""), msg="pretty 丢键名")
  assert_true(s.contains("\"b\""), msg="pretty 丢键名")
  assert_true(s.contains("{") && s.contains("}"), msg="pretty 丢花括号")
  assert_true(s.contains("\n"), msg="pretty 没有换行 ⇒ 没有缩进 ⇒ 不是 pretty")
}
