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

///|
/// R158：**两份 `iso_to_secs` 的语义完全不同，不可互换** —— 上格只锁了**顺序**
/// （`cross_sign` 相等），若有人把两个实现统一成同一基准，上格**照样绿**，
/// 而"把一处算出的秒数喂给另一处的比较"就再也拦不住。本格把**实际口径**写死。
///
/// 从实现读出的事实（两边都**显式拒绝**越界年份，不是静默溢出）：
///
/// | 实现 | 基准 | 当年零点 | 年界 | 越界行为 |
/// |---|---|---|---|---|
/// | `@ops.iso_to_secs` | **2024-01-01**，且是 **1-based 天数**（`... + day`） | 该日 = **86400**（不是 0） | **2024..2091** | 返回 `-1` |
/// | `@router.iso_to_secs` | **1970 绝对 epoch 秒** | 2024-01-01 = **1704067200** | **1970..2037**（`y > 2037 ⇒ -1`，Y2038 规避） | 返回 `-1` |
///
/// ⇒ **共同可表示窗口只有 2024..2037**，且在该窗口内恒有
/// `router(s) - ops(s) == 1704067200 - 86400`（= 1703980800）。
/// 本格把常量差与**各自年界**一起钉住：谁改基准、谁放宽/收窄年界，都会立刻红。
test "iso_to_secs: 两份实现基准不同 + 年界不同（共同窗口 2024..2037）" {
  let off = 1703980800
  assert_eq(@ops.iso_to_secs("2024-01-01T00:00:00Z"), 86400)
  assert_eq(@router.iso_to_secs("2024-01-01T00:00:00Z"), 1704067200)
  for s in [
      "2024-01-01T00:00:00Z", "2026-09-26T13:37:55Z", "2037-12-31T23:59:59Z",
    ] {
    let o = @ops.iso_to_secs(s)
    let r = @router.iso_to_secs(s)
    assert_true(o >= 0 && r >= 0, msg="样本必须落在共同窗口：" + s)
    assert_eq(r - o, off)
  }
  // 各自年界（**口径不同**，谁"顺手统一"就会在这四行红）
  assert_eq(@ops.iso_to_secs("2023-12-31T23:59:59Z"), -1) // ops 下界 2024
  assert_true(@router.iso_to_secs("2023-12-31T23:59:59Z") > 0) // router 下界 1970
  assert_eq(@router.iso_to_secs("2038-01-01T00:00:00Z"), -1) // router 上界 2037
  assert_true(@ops.iso_to_secs("2038-01-01T00:00:00Z") > 0) // ops 到 2091
  assert_eq(@ops.iso_to_secs("2092-01-01T00:00:00Z"), -1) // ops 上界 2091
}
