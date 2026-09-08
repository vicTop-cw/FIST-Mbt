/// ops_ts.mbt —— ISO 时间戳工具（M4 运维模块共用）
///
/// 解析固定格式 `YYYY-MM-DDTHH:MM:SS(Z)`（T/空格 分隔）为"自某参考点的累计秒"，
/// 供心跳超时与归档保留期的比较。**非精确 UTC 绝对时间**（忽略闰年/时区），
/// 仅保证同一体系内的时间先后可比较（FIST 内部时间戳均为该格式，满足需求）。

fn char_int(c : Char) -> Int {
  c.to_int() - '0'.to_int()
}

fn parse_digits(chars : Array[Char], start : Int, len~ : Int) -> Int {
  var v = 0
  for i = 0; i < len; i = i + 1 {
    v = v * 10 + char_int(chars[start + i])
  }
  v
}

/// 把 `YYYY-MM-DDTHH:MM:SS...` 起始的时间戳解析为累计秒。解析失败返回 -1。
/// 以 2024-01-01 为参考基准（仅用于同体系先后比较，非绝对 UTC）：
/// 避免 year*365*86400 在 32 位 Int 下溢出。
pub fn iso_to_secs(s : String) -> Int {
  let chars = s.to_array()
  if chars.length() < 16 {
    return -1
  }
  let year = parse_digits(chars, 0, len=4)
  let mon = parse_digits(chars, 5, len=2)
  let day = parse_digits(chars, 8, len=2)
  let hour = parse_digits(chars, 11, len=2)
  let min = parse_digits(chars, 14, len=2)
  let sec = if chars.length() >= 17 { parse_digits(chars, 17, len=2) } else { 0 }
  if year < 2024 {
    return -1
  }
  // 月起点累计天数（非闰年近似，同体系比较足够）
  let accum : Array[Int] = [0, 0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334]
  let month_days = if mon >= 1 && mon <= 12 { accum[mon - 1] } else { 0 }
  let days = (year - 2024) * 365 + month_days + day
  days * 86400 + hour * 3600 + min * 60 + sec
}
