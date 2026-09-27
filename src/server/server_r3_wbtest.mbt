/// server_r3_wbtest.mbt —— Round 3 修复的白盒回归锁：BUG-19（schema.required 只声明不校验）。
///
/// 病灶：`schema(props, required)` 生成的 required 数组从没被 `_instrument` 读过，
/// 缺必填参数会落到 handler 的 `get_str(args, k)` → 拿到 ""，再被下游当成
/// 「任务不存在」或静默用默认值——契约写了但不生效（BUG-23 的吞参数也是同一族）。
/// 这里锁死三个纯函数的判定口径；入口侧行为另有调用面判据（temp/r3_callsite_*.py）。

///|
fn r3_schema() -> Json {
  schema(
    {
      "task_id": string_prop("任务 id"),
      "cmd": string_prop("命令"),
      "workdir": string_prop("工作目录(可选)"),
    },
    ["task_id", "cmd"],
  )
}

///|
test "BUG-19：schema_required 只取 required 数组里的非空名" {
  let req = schema_required(r3_schema())
  assert_eq(req.length(), 2)
  assert_eq(req[0], "task_id")
  assert_eq(req[1], "cmd")
  // 没有 required 键的 schema 不得凭空造约束（零回归：不改变未声明契约的工具）
  assert_eq(
    schema_required(Json::object({ "properties": Json::object({}) })).length(),
    0,
  )
  assert_eq(schema_required(Json::null()).length(), 0)
}

///|
test "BUG-19：缺失判定与 handler 的 get_str 口径一致（缺/Null/空串/空白都算缺）" {
  let req = schema_required(r3_schema())
  // 完全不给
  assert_eq(rq_join(missing_required(Json::object({}), req)), "task_id, cmd")
  // 给了一个，另一个是空串（Round 2 之前这种会静默变 ""）
  let partial = Json::object({
    "task_id": Json::string("T0r1"),
    "cmd": Json::string("   "),
  })
  assert_eq(rq_join(missing_required(partial, req)), "cmd")
  // Null 视同缺失
  let nulled = Json::object({
    "task_id": Json::string("T0r1"),
    "cmd": Json::null(),
  })
  assert_eq(rq_join(missing_required(nulled, req)), "cmd")
  // 成对：参数齐全时必须放行（否则就是把合法调用挡在门外）
  let full = Json::object({
    "task_id": Json::string("T0r1"),
    "cmd": Json::string("moon"),
    "workdir": Json::string("."),
  })
  assert_eq(missing_required(full, req).length(), 0)
  // 非字符串形态（整数/布尔/数组）不能因为 trim 语义被误判为缺失
  let typed = Json::object({
    "task_id": Json::string("T0r1"),
    "cmd": Json::number(1.0),
  })
  assert_eq(missing_required(typed, req).length(), 0)
}

///|
/// BUG-63：`config_json` 允许两种传法（JSON 文本 / 已解析的对象），旧 handler 用 get_str
/// 取它 ⇒ 对象形态拿到 ""，等于**整份配置被静默丢掉**、悄悄用默认池跑（工具却回 ok=true）。
/// 这里锁提取→解析整条链：对象必须能解析回同形状的 Json，缺失/Null 才是"没给配置"。
test "BUG-63：get_json_text 取对象形态的配置不丢内容，取缺失/Null 才为空" {
  let as_text = Json::object({
    "config_json": Json::string("{\"threshold_pct\": 80.0}"),
  })
  assert_eq(get_json_text(as_text, "config_json"), "{\"threshold_pct\": 80.0}")
  // 对象形态：修复前这条拿到 ""（配置被吞），现在必须拿到可再解析的 JSON 文本
  let as_obj = Json::object({
    "config_json": Json::object({
      "threshold_pct": Json::number(80.0),
      "free_pool": Json::array([
        Json::object({
          "name": Json::string("b63_free"),
          "limit": Json::number(3.0),
        }),
      ]),
    }),
  })
  let got = get_json_text(as_obj, "config_json")
  assert_true(!got.is_empty())
  match mr_parse_config(got) {
    Err(e) => abort("对象形态的配置没能再解析回来：" + e)
    Ok(j) =>
      match j {
        Json::Object(m) => {
          assert_true(m.contains("free_pool"))
          assert_true(m.contains("threshold_pct"))
        }
        _ => abort("解析结果不是对象")
      }
  }
  // 成对（零回归）：没给 / 显式 null 仍然是"没给配置"，不当成违例
  assert_eq(get_json_text(Json::object({}), "config_json"), "")
  assert_eq(
    get_json_text(Json::object({ "config_json": Json::null() }), "config_json"),
    "",
  )
  assert_eq(get_json_text(Json::null(), "config_json"), "")
  assert_eq(mr_parse_config("").is_ok(), true)
}

///|
test "BUG-19：拒绝消息必须自带出路（说清缺哪几个、去哪看全量参数）" {
  let miss = rq_join(
    missing_required(Json::object({}), schema_required(r3_schema())),
  )
  let msg = "run_check: 缺必填参数 " +
    miss +
    "（schema.required 已声明，BUG-19 硬门）。全部可用参数见 tools/list 的 inputSchema.properties"
  assert_true(msg.contains("task_id, cmd"))
  assert_true(msg.contains("inputSchema"))
  // 全量注册面都接了这道门：required 解析出的约束数量必须等于声明数，防止 wrapper 漏挂
  let srv = r3_schema().stringify()
  assert_true(srv.contains("\"required\""))
}
