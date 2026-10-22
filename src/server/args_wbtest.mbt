/// args_wbtest.mbt —— BUG-23「参数名静默忽略」的白盒锁
///
/// 真源：src/server/server.mbt 的 schema_properties / misnamed_args（_instrument 在
/// 每次调用前用它们把「与本工具已声明参数互为前缀的错名」挡在入口）。
///
/// 成对：① 错名必被抓（ns↔namespace、task↔task_id）；② 正名不得误抓（恒红判据不可信）；
/// ③ 与任何声明都不相干的陌生键**不在本条射程内**（实测 5890 行 call_log 里 4310 行带
/// 这类键，一律拒绝会打断 73% 调用面 —— 这条反向对照把边界钉住，防止下一个人"顺手加严"）。

///|
fn b23_props() -> Array[String] {
  schema_properties(
    schema(
      {
        "project_dir": string_prop("项目目录"),
        "description": string_prop("任务描述"),
        "namespace": string_prop("命名空间"),
        "created_by": string_prop("创建者"),
      },
      ["project_dir", "description"],
    ),
  )
}

///|
test "BUG-23：schema_properties 读得到声明的参数名（读不到就恒绿）" {
  let p = b23_props()
  assert_eq(p.length(), 4)
  assert_true(p.contains("namespace"))
  // 解析器饿死对照：空 schema 必须解析出 0 个（misnamed_args 对空 props 直接放行）
  assert_eq(
    schema_properties(schema({}, ["something_not_declared"])).length(),
    0,
  )
}

///|
test "BUG-23：与已声明参数互为前缀的错名必被抓" {
  let p = b23_props()
  // 本会话真实踩过的形状：CLI 把 --ns 逐字发成 {"ns": ...}，publish 静默落进 default
  let j = Json::object({
    "ns": Json::string("r1"),
    "project_dir": Json::string("."),
    "description": Json::string("x"),
  })
  let bad = misnamed_args(j, p)
  // 前提自证（不是可选装饰）：这条锁依赖"能读到 args 的键"和"子串判定可用"两件事，
  // 任一前提塌了，下面的 misnamed_args 断言就变成恒绿的装饰。
  let keys : Array[String] = []
  match j {
    Object(m) =>
      for (k, _) in m {
        keys.push(k)
      }
    _ => ()
  }
  assert_true(keys.contains("ns"))
  // 前提 ②：**缩写不是子串**——"ns" 在 "namespace" 里不连续。
  // 这条断言钉住"为什么必须有 known_arg_aliases"：只靠子串规则，ns 永远抓不到。
  assert_false("namespace".contains("ns"))
  assert_eq(known_arg_aliases("ns"), "namespace")
  assert_true("description".contains("desc"))
  assert_eq(bad.length(), 1)
  let (k1, v1) = bad[0]
  assert_eq(k1, "ns")
  assert_eq(v1, "namespace")
  // desc→description 同形
  let j2 = Json::object({
    "desc": Json::string("x"),
    "project_dir": Json::string("."),
  })
  let bad2 = misnamed_args(j2, p)
  assert_eq(bad2.length(), 1)
  let (k2, v2) = bad2[0]
  assert_eq(k2, "desc")
  assert_eq(v2, "description")
}

///|
test "BUG-23：正名与不相干陌生键都不得误判（否则本条守卫变恒红）" {
  let p = b23_props()
  // 全部用正名 ⇒ 一条都不能报
  let good = Json::object({
    "project_dir": Json::string("."),
    "description": Json::string("x"),
    "namespace": Json::string("r1"),
    "created_by": Json::string("cmd"),
  })
  assert_eq(misnamed_args(good, p).length(), 0)
  let unknown_key = Json::object({
    "project_dir": Json::string("."),
    "description": Json::string("x"),
    "now": Json::string("2026-09-27T00:00:00Z"),
  })
  assert_eq(misnamed_args(unknown_key, p).length(), 0)
  // props 解析不到（空）时一律放行：判据不能因为读不到 schema 就误伤
  assert_eq(
    misnamed_args(Json::object({ "ns": Json::string("a") }), []).length(),
    0,
  )
}

///|
/// 判定口径的边界（BUG-23）：后缀形态算同根（dir↔project_dir），单字符不算（噪声）。
/// 缺这两条对照时，"互为子串"可以悄悄退化成"任何键都拒绝"。
test "BUG-23：同根判定的边界——后缀算、单字符不算" {
  let props = ["project_dir", "namespace"]
  let b1 = misnamed_args(
    Json::object({ "dir": Json::string("x"), "namespace": Json::string("a") }),
    props,
  )
  assert_eq(b1.length(), 1)
  let (k1, v1) = b1[0]
  assert_eq(k1, "dir")
  assert_eq(v1, "project_dir")
  // 单字符键：不得判成同根（否则任何调用都红）
  assert_eq(
    misnamed_args(
      Json::object({ "n": Json::string("x"), "project_dir": Json::string(".") }),
      props,
    ).length(),
    0,
  )
}
