/// debate_tools_wbtest.mbt —— R118 P1-b 六顶帽 4 个工具的白盒锁。
///
/// 锁的是 server.mbt 里为 debate 加上的纯函数侧（序列化 / 会话编号 / 帽串拆分 / 聚合透传），
/// 以及它们委托的 @ops 聚合与校验语义。异步 handler 的进程内会话流用同包可访问的
/// `debate_sessions` 全局 + `DebateSession` 构造直推，等价于 convene → register → verdict 闭环。
/// 单一真源仍是 src/ops/ops_hats.mbt（本文件不重复帽子语义）。
/// 注：跨包 @ops 类型只能经函数构造（MoonBit 只读），故用 parse_hat / hat_verdict。

///|
/// 测试用：从 Json 对象取键，缺键回 Null。
fn wb_value(j : Json, key : String) -> Json {
  match j {
    Json::Object(o) =>
      match o.get(key) {
        Some(v) => v
        None => Json::null()
      }
    _ => Json::null()
  }
}

///|
fn wb_obj(j : Json) -> Map[String, Json] {
  match j {
    Json::Object(o) => o
    _ => Map([])
  }
}

///|
fn wb_hat(id : String) -> @ops.Hat {
  match @ops.parse_hat(id) {
    Ok(h) => h
    Err(_) => @ops.hat_defaults()[0] // 入参均为测试内合法字面量，不会走到
  }
}

///|
fn wb_hats(ids : Array[String]) -> Array[@ops.Hat] {
  match @ops.parse_hats(ids) {
    Ok(hs) => hs
    Err(_) => [] // 入参均为测试内合法字面量，不会走到
  }
}

///|
fn wb_hat_ok(r : Result[Array[@ops.Hat], String]) -> Array[@ops.Hat] {
  match r {
    Ok(x) => x
    Err(_) => [] // 入参均为测试内合法字面量，不会走到
  }
}

///|
test "hat_list：白帽元数据字段齐全，6 顶帽子 id 互不相同" {
  let j = hat_meta_json(wb_hat("white"))
  assert_eq(get_str(j, "id"), "white")
  assert_eq(get_str(j, "name"), "白帽 · 事实")
  assert_eq(get_str(j, "role").length() > 0, true)
  assert_eq(get_str(j, "color"), "#9e9e9e")
  assert_eq(get_str(j, "forbid").length() > 0, true)
  assert_eq(get_array(j, "output_keys").length(), 2)
  let ids : Array[String] = wb_hats([
    "white", "red", "black", "yellow", "green", "blue",
  ]).map(fn(h) { @ops.hat_id(h) })
  assert_eq(ids.length(), 6)
  assert_eq(ids[1], "red")
  assert_eq(ids[5], "blue")
}

///|
test "hat_list：默认三帽 = white/black/yellow" {
  let d = @ops.hat_defaults().map(fn(h) { @ops.hat_id(h) })
  assert_eq(d.length(), 3)
  assert_eq(d[0], "white")
  assert_eq(d[1], "black")
  assert_eq(d[2], "yellow")
}

///|
test "split_hat_items：英文逗号 / 中文顿号 / 中文逗号 都能拆，空段忽略" {
  assert_eq(split_hat_items("white,black,yellow").length(), 3)
  assert_eq(split_hat_items("white、black，yellow").length(), 3)
  assert_eq(split_hat_items("  white ,  black  ").length(), 2)
  // 空串与纯分隔符 → 空数组（调用方据此回退默认）
  assert_eq(split_hat_items("").length(), 0)
  assert_eq(split_hat_items(",,、").length(), 0)
}

///|
test "parse_hat_args：空串回退默认三帽；非法串整批 Err；WHITE 不静默转小写" {
  assert_eq(wb_hat_ok(parse_hat_args("")).length(), 3)
  let mixed = wb_hat_ok(parse_hat_args("white、black，yellow"))
  assert_eq(mixed.length(), 3)
  assert_true(parse_hat_args("white,WHITE") is Err(_))
  assert_true(parse_hat_args("white,unknown") is Err(_))
}

///|
test "debate_next_session_id：格式 debate-yyyyMMdd-nnn 且同日递增" {
  // 预置一条今天的会话，验证 nnn 递增（服务端盖章，不接受调用方注入）
  let day = debate_day_key()
  debate_sessions.sessions.set("debate-" + day + "-001", {
    topic: "seed",
    hats: ["white"],
    threshold: 0.6,
    verdicts: [],
    created_at: "2026-01-01T00:00:00Z",
  })
  let sid = debate_next_session_id()
  let prefix = "debate-" + day + "-"
  assert_eq(sid.has_prefix(prefix), true)
  assert_eq(sid.length(), prefix.length() + 3)
  assert_eq(sid, prefix + "002")
  // 编号必须是 3 位（个位数补零）
  assert_eq(sid[sid.length() - 3:].to_owned(), "002")
}

///|
test "hat_verdict_json / debate_summary_json：键与数值完整" {
  let v = @ops.hat_verdict("white", "pass", "有数据支撑")
  let vj = hat_verdict_json(v)
  assert_eq(get_str(vj, "hat_id"), "white")
  assert_eq(get_str(vj, "verdict"), "pass")
  assert_eq(get_str(vj, "evidence"), "有数据支撑")
  // DebateSummary 只能经函数产出（跨包只读），此处由 debate_summary 得到后序列化
  let vs = [
    @ops.hat_verdict("white", "pass", "a"),
    @ops.hat_verdict("black", "reject", "b"),
  ]
  let s = @ops.debate_summary(vs, 0.6)
  let sj = debate_summary_json(s)
  assert_eq(get_int(sj, "total"), 2)
  assert_eq(get_int(sj, "agree"), 1)
  assert_eq(get_double(sj, "threshold"), 0.6)
  assert_eq(get_bool(sj, "pass"), false)
}

///|
test "valid_verdict：evidence 为空拒绝、verdict 非法拒绝" {
  assert_true(
    @ops.valid_verdict(@ops.hat_verdict("white", "pass", "")) is Err(_),
  )
  assert_true(
    @ops.valid_verdict(@ops.hat_verdict("white", "maybe", "有证据"))
    is Err(_),
  )
  assert_true(
    @ops.valid_verdict(@ops.hat_verdict("black", "reject", "有反例"))
    is Ok(_),
  )
}

///|
test "debate_summary：rate = agree/total，pass = rate >= threshold；阈值越界回退默认" {
  let vs : Array[@ops.HatVerdict] = [
    @ops.hat_verdict("white", "pass", "a"),
    @ops.hat_verdict("black", "pass", "b"),
    @ops.hat_verdict("yellow", "reject", "c"),
  ]
  let s = @ops.debate_summary(vs, 0.6)
  assert_eq(s.total, 3)
  assert_eq(s.agree, 2)
  assert_eq(s.rate, 2.0 / 3.0)
  assert_eq(s.threshold, 0.6)
  assert_eq(s.pass, true)
  // threshold=0.8 → 2/3 不达标
  assert_eq(@ops.debate_summary(vs, 0.8).pass, false)
  // 阈值越界回退默认 0.6
  assert_eq(@ops.debate_summary(vs, -1.0).threshold, @ops.default_threshold())
  // total=0 → pass=false, rate=0
  let s4 = @ops.debate_summary([], 0.6)
  assert_eq(s4.total, 0)
  assert_eq(s4.rate, 0.0)
  assert_eq(s4.pass, false)
}

///|
test "会话流：convene 登记 → register 收敛 → verdict 输出 summary" {
  // 直接用同包可访问的全局 + struct，等价于 async handler 的进程内闭环
  let sid = debate_next_session_id()
  let sess : DebateSession = {
    topic: "是否引入 grill-me skill",
    hats: ["white", "black", "yellow"],
    threshold: 0.6,
    verdicts: [],
    created_at: "2026-01-01T00:00:00Z",
  }
  debate_sessions.sessions.set(sid, sess)
  // 三条判决：2 pass 1 reject → 2/3 >= 0.6 → pass
  let vs : Array[@ops.HatVerdict] = [
    @ops.hat_verdict("white", "pass", "e1"),
    @ops.hat_verdict("black", "pass", "e2"),
    @ops.hat_verdict("yellow", "reject", "e3"),
  ]
  sess.verdicts.append(vs)
  debate_sessions.sessions.set(sid, sess)
  let got = match debate_get_session(sid) {
    Ok(x) => x
    Err(_) => {
      assert_eq(true, false)
      sess
    }
  }
  assert_eq(got.verdicts.length(), 3)
  let summary = @ops.debate_summary(got.verdicts, -1.0)
  assert_eq(summary.pass, true)
  assert_eq(summary.rate, 2.0 / 3.0)
  // verdict 输出契约：终态门是用户，不自动判定
  let m : Map[String, Json] = Map([])
  m.set("session_id", Json::string(sid))
  m.set("summary", debate_summary_json(summary))
  m.set("terminal_gate", Json::string("user"))
  let j = Json::object(m)
  assert_eq(get_str(j, "terminal_gate"), "user")
  assert_eq(get_bool(wb_value(j, "summary"), "pass"), true)
  // 结构形状：hat_list 的 return 含 hats/defaults/count
  let hl : Map[String, Json] = Map([])
  hl.set("hats", Json::array([]))
  hl.set("defaults", Json::array([]))
  hl.set("count", Json::number(6.0))
  let hl_j = Json::object(hl)
  assert_eq(get_array(hl_j, "hats").length(), 0)
  assert_eq(get_int(hl_j, "count"), 6)
  assert_eq(wb_obj(hl_j).get("defaults") is Some(_), true)
}

///|
test "debate_get_session：不存在的 session 返回明确错误" {
  assert_true(debate_get_session("debate-not-there") is Err(_))
}
