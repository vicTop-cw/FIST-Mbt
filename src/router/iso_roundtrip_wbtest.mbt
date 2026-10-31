///|
/// iso_roundtrip_wbtest.mbt —— `iso_to_secs` ∘ `secs_to_iso` 的**往返不变量**（R189）。
///
/// 为什么补：这两个函数在**生产路径**上被用来算配额窗口的重置时刻
/// （`secs_to_iso(iso_to_secs(now) + window_seconds)`，见 model_router.mbt:904/950），
/// 而此前**没有任何一条测试**验证「解析再格式化能还原原串」——
/// 一个静默的差一天/差一秒会让所有模型的 5h 窗口在错误时刻重置。

///|
/// 往返：`secs_to_iso(iso_to_secs(s)) == s`（覆盖闰日 / 年界 / epoch / 支持上界）。
test "iso↔secs 往返：8 个代表日期逐字还原" {
  let samples : Array[String] = [
    "1970-01-01T00:00:00Z", // epoch 零点
     "1970-01-02T00:00:00Z", // +正好一天
     "2000-02-29T12:34:56Z", // 世纪闰日（400 年规则）
     "2023-12-31T23:59:59Z", // 年末最后一秒
     "2024-02-29T00:00:00Z", // 普通闰日
     "2026-10-29T12:00:00Z", // 本项目当前年
     "2037-12-31T23:59:59Z", // 支持上界（iso_to_secs 对 y>2037 返回 -1）
     "2021-03-01T05:06:07Z", // 任意样本
  ]
  for s in samples {
    let secs = iso_to_secs(s)
    assert_true(secs >= 0, msg="解析失败: " + s)
    assert_eq(secs_to_iso(secs), s, msg="往返不一致: " + s)
  }
}

///|
/// 边界契约：负数 / 非法输入的处理形状（**这些是调用方依赖的**，不是实现细节）。
test "iso↔secs 边界：非法 iso 归 -1、负秒数归空串" {
  assert_eq(iso_to_secs("1970-01-01T00:00:00Z"), 0) // epoch 零点 = 0 秒
  assert_eq(secs_to_iso(0), "1970-01-01T00:00:00Z")
  assert_eq(
    secs_to_iso(-1),
    "",
    msg="负秒数必须归空串（调用方据此判'不可用'）",
  )
  assert_eq(iso_to_secs(""), -1)
  assert_eq(iso_to_secs("not-a-date"), -1)
  assert_eq(
    iso_to_secs("2038-01-01T00:00:00Z"),
    -1,
    msg="y>2037 不支持，必须 -1 而非溢出",
  )
}
