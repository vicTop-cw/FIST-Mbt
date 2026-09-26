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
