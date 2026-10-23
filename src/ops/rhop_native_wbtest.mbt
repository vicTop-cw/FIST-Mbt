/// rhop_native 白盒：force_polling 轮询核心（异机 / 网络 FS / native 兜底）
/// 造 .rhop 夹具，验证解码 / 去重 / 坏文件跳过 / 版本门禁。
///
/// 夹具为什么不用 `@rhop.rhop_send`（BUG-389，2026-10-22 暴露）：
/// 该函数在依赖侧是**目标分片**——`rhop_js.mbt` 是真实现，`rhop_native.mbt` 只
/// `println("native 目标暂不可用…")` 后返回，**不落盘也不报错**。native 上用它造夹具，
/// 目录里永远是 0 个 `.rhop`，三个用例会稳定假红 `0 != 1`。本文件测的是**本仓的
/// `rhop_poll_once`**，与依赖侧写盘能力无关，故夹具改走等价纯函数 + `@fs` 直写（见 rn_send）。
/// 此前该文件在 js 上全绿而 native 从未跑过（被崩溃挡住），所以这处缺陷长期不可见。
///
/// BUG-343 根因：测试共享 temp/rhop_poll_<name>/ 目录，连续跑残留 .rhop
/// 文件污染断言（got1.length 期望 1 实际 2）。修复：rn_dir 开头先清理
/// 目标目录内所有 .rhop / .rhop.tmp 文件，保证每次 run 独立。

///|
fn rn_ensure(d : String) -> Unit {
  @fs.create_dir(d) catch {
    _ => ()
  }
}

///|
/// tear-down：列出 dir 下所有文件名，逐个删除。
/// MoonBit x/fs 没有 remove_dir_all，故用"列 + 逐个删"清理。
fn rn_clean(dir : String) -> Unit {
  let names = @fs.read_dir(dir) catch { _ => [] }
  for name in names {
    let full = dir + "/" + name
    let _ = @fs.remove_file(full) catch { _ => () }
  }
}

///|
fn rn_dir(name : String) -> String {
  rn_ensure("temp")
  let d = "temp/rhop_poll_" + name
  rn_clean(d) // BUG-343 tear-down：先清后建
  rn_ensure(d)
  d
}

///|
/// 造夹具：与 `@rhop.rhop_send` 的 js 实现**逐句同构**，但只走公开纯函数 + `@fs` 直写。
///   ct   = cipher.encrypt(packet.to_json_string())
///   text = RhopEnvelope::encode(1, cipher.alg_name(), ct)
/// 唯一差别是最后一步：js 版走 `ffi_write_atomic`（裸文件名写入），这里走
/// `@fs.write_string_to_file`（同一目标路径）。这样 native 与 js 两个目标都能造夹具。
fn rn_send(d : String, name : String, pkt : @rhop.RhopPacket) -> Unit {
  let c = @rhop.RhopCipherNone::new()
  let ct = c.encrypt(pkt.to_json_string())
  let text = @rhop.RhopEnvelope::encode(1, c.alg_name(), ct)
  @fs.write_string_to_file(d + "/" + name + ".rhop", text, encoding="utf8") catch {
    _ => ()
  }
}

///|
test "rhop_poll_once 解码新增 .rhop 且按完整路径去重" {
  let d = rn_dir("dedup")
  let seen : @ref.Ref[@hashset.HashSet[String]] = @ref.Ref(@hashset.HashSet([]))
  rn_send(
    d,
    "m1",
    @rhop.RhopPacket::new(
      "id1",
      "commissar-send",
      "guidance",
      Json::object({ "x": Json::string("1") }),
      1000L,
    ),
  )
  let got1 = rhop_poll_once(d, @rhop.RhopCipherNone::new(), seen)
  assert_eq(got1.length(), 1)
  if got1.length() >= 1 {
    assert_eq(got1[0].id, "id1")
  }
  // 同 seen 二拍：无新增 → 0
  let got2 = rhop_poll_once(d, @rhop.RhopCipherNone::new(), seen)
  assert_eq(got2.length(), 0)
  // 新增一条 → +1
  rn_send(
    d,
    "m2",
    @rhop.RhopPacket::new(
      "id2",
      "commissar-send",
      "heartbeat",
      Json::object({ "x": Json::string("2") }),
      2000L,
    ),
  )
  let got3 = rhop_poll_once(d, @rhop.RhopCipherNone::new(), seen)
  assert_eq(got3.length(), 1)
  if got3.length() >= 1 {
    assert_eq(got3[0].id, "id2")
  }
}

///|
test "rhop_poll_once 跳过 .rhop.tmp 与非 .rhop 文件" {
  let d = rn_dir("ext")
  let seen : @ref.Ref[@hashset.HashSet[String]] = @ref.Ref(@hashset.HashSet([]))
  rn_send(
    d,
    "m1",
    @rhop.RhopPacket::new(
      "id1",
      "s",
      "k",
      Json::object({ "x": Json::string("1") }),
      1L,
    ),
  )
  @fs.write_string_to_file(d + "/m1.rhop.tmp", "tmp", encoding="utf8") catch {
    _ => ()
  }
  @fs.write_string_to_file(d + "/readme.txt", "x", encoding="utf8") catch {
    _ => ()
  }
  let got = rhop_poll_once(d, @rhop.RhopCipherNone::new(), seen)
  assert_eq(got.length(), 1)
  if got.length() >= 1 {
    assert_eq(got[0].id, "id1")
  }
}

///|
test "rhop_poll_once 坏信封 / 坏密文静默跳过" {
  let d = rn_dir("bad")
  let seen : @ref.Ref[@hashset.HashSet[String]] = @ref.Ref(@hashset.HashSet([]))
  rn_send(
    d,
    "good",
    @rhop.RhopPacket::new(
      "good",
      "s",
      "k",
      Json::object({ "x": Json::string("1") }),
      1L,
    ),
  )
  @fs.write_string_to_file(d + "/badjson.rhop", "not-a-json", encoding="utf8") catch {
    _ => ()
  }
  let badct = @rhop.RhopEnvelope::encode(1, "none", "@@@not-base64@@@")
  @fs.write_string_to_file(d + "/badct.rhop", badct, encoding="utf8") catch {
    _ => ()
  }
  let got = rhop_poll_once(d, @rhop.RhopCipherNone::new(), seen)
  assert_eq(got.length(), 1)
  if got.length() >= 1 {
    assert_eq(got[0].id, "good")
  }
}

///|
test "rhop_poll_once 版本 != 1 的信封跳过" {
  let d = rn_dir("v2")
  let seen : @ref.Ref[@hashset.HashSet[String]] = @ref.Ref(@hashset.HashSet([]))
  let env = @rhop.RhopEnvelope::encode(2, "none", "whatever")
  @fs.write_string_to_file(d + "/v2.rhop", env, encoding="utf8") catch {
    _ => ()
  }
  let got = rhop_poll_once(d, @rhop.RhopCipherNone::new(), seen)
  assert_eq(got.length(), 0)
}
