///|
/// tz_minus_secs_wbtest.mbt —— BUG-196 白盒锁：iso_minus_secs / _iso_to_unix_ms。
/// 锁定两个修复：
/// ① iso_minus_secs 真正以 `iso` 参数为基准（此前完全忽略该参数、只读墙钟 @env.now()）；
/// ② secs 为负时钳到 0（负回退会算出未来 cutoff，让 assistant_claim 立即接管新鲜主助理 =
///    fail-open 授权绕过；assistant_sweep 会把刚心跳过的助理标 dead）。
test "BUG-196：iso_minus_secs 以 iso 为基准回退 60 秒" {
  assert_eq(iso_minus_secs("2026-10-15T00:00:00Z", 60), "2026-10-14T23:59:00Z")
}

///|
test "BUG-196：iso_minus_secs 回退 0 秒恒等（不产生未来 cutoff）" {
  assert_eq(iso_minus_secs("2026-10-15T00:00:00Z", 0), "2026-10-15T00:00:00Z")
}

///|
test "BUG-196：iso_minus_secs 负 secs 钳到 0——不产生未来 cutoff" {
  assert_eq(
    iso_minus_secs("2026-10-15T00:00:00Z", -100),
    "2026-10-15T00:00:00Z",
  )
  assert_eq(
    iso_minus_secs("2026-10-15T00:00:00Z", -86400),
    "2026-10-15T00:00:00Z",
  )
}

///|
test "BUG-196：iso_minus_secs 恰好回退一天（跨日边界）" {
  assert_eq(
    iso_minus_secs("2026-10-15T00:00:00Z", 86400),
    "2026-10-14T00:00:00Z",
  )
}

///|
test "BUG-196：iso_minus_secs 负回退不越过 1970 下界" {
  // secs 大过基准到 1970 之前 → 下界哨兵"0000-00-00T00:00:00Z"
  let r = iso_minus_secs("1970-01-01T00:00:00Z", 86400)
  assert_eq(r, "0000-00-00T00:00:00Z")
}

///|
test "BUG-196：_iso_to_unix_ms 解析 1970-01-01 得 0" {
  assert_eq(_iso_to_unix_ms("1970-01-01T00:00:00Z"), Some(0L))
}

///|
test "BUG-196：_iso_to_unix_ms 解析 2026-10-15 得预期毫秒" {
  // 2026-10-15 = 距 1970-01-01 的 20741 天（Hinnant days_from_civil）
  assert_eq(
    _iso_to_unix_ms("2026-10-15T00:00:00Z"),
    Some(20741L * 86400L * 1000L),
  )
}

///|
test "BUG-196：_iso_to_unix_ms 越界字段返回 None" {
  assert_eq(_iso_to_unix_ms("2026-10-15T24:00:00Z"), None) // hour=24 越界
  assert_eq(_iso_to_unix_ms("2026-10-15T00:60:00Z"), None) // min=60 越界
  assert_eq(_iso_to_unix_ms("2026-00-15T00:00:00Z"), None) // mon=0 越界
  assert_eq(_iso_to_unix_ms("2026-13-15T00:00:00Z"), None) // mon=13 越界
}

///|
test "BUG-196：_iso_to_unix_ms 短串 / 非数字返回 None" {
  assert_eq(_iso_to_unix_ms("garbage"), None)
  assert_eq(_iso_to_unix_ms("2026-10-15T00:00"), None) // 长度 16 < 19
  assert_eq(_iso_to_unix_ms(""), None)
}

///|
test "BUG-196：_iso_to_unix_ms 闰日边界（2024-02-29 合法）" {
  // 只验证可解析（不校验日历合法性），非 None 即通过
  if _iso_to_unix_ms("2024-02-29T12:34:56Z") is None {
    abort("2024-02-29 应可解析")
  }
}
