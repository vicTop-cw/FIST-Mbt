// R129：ops 与 router 各有一份 iso_to_secs（参考系不同：2024 起算 365 天 vs
// 1970 起算真闰年），两者只承诺"同体系内可比"。本锁钉跨解析器的一致性：
// 任取两枚都合法的时间戳，两边给出的先后关系必须相同——参考系不同也不许翻转。

///|
fn cross_sign(v : Int32) -> Int32 {
  if v > 0 {
    1
  } else if v < 0 {
    -1
  } else {
    0
  }
}

///|
test "iso_to_secs: ops 与 router 对同一对时间戳的先后判断一致" {
  let stamps : Array[String] = [
    "2024-01-01T00:00:00", "2024-02-28T23:59:59", "2024-02-29T00:00:00", "2024-03-01T00:00:00",
    "2024-12-31T23:59:59", "2025-01-01T00:00:00", "2026-10-22T12:00:00", "2028-02-29T00:00:00",
    "2037-12-31T23:59:59",
  ]
  for i = 0; i < stamps.length(); i = i + 1 {
    for j = i + 1; j < stamps.length(); j = j + 1 {
      let a = stamps[i]
      let b = stamps[j]
      let oa = @ops.iso_to_secs(a)
      let ob = @ops.iso_to_secs(b)
      let ra = @router.iso_to_secs(a)
      let rb = @router.iso_to_secs(b)
      assert_true(oa >= 0)
      assert_true(ra >= 0)
      assert_eq(cross_sign(oa - ob), cross_sign(ra - rb))
    }
  }
}
