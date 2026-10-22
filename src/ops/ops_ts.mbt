///|
/// ops_ts.mbt —— ISO 时间戳工具（M4 运维模块共用）
///
/// 解析固定格式 `YYYY-MM-DDTHH:MM:SS(Z)`（T/空格 分隔）为"自某参考点的累计秒"，
/// 供心跳超时与归档保留期的比较。**非精确 UTC 绝对时间**（忽略时区/闰秒，但含闰年），
/// 仅保证同一体系内的时间先后可比较（FIST 内部时间戳均为该格式，满足需求）。
fn char_int(c : Char) -> Int32 {
  c.to_int() - '0'.to_int()
}

///|
fn parse_digits(chars : Array[Char], start : Int32, len~ : Int32) -> Int32 {
  let mut v = 0
  for i = 0; i < len; i = i + 1 {
    let c = chars[start + i]
    if c < '0' || c > '9' {
      return -1
    }
    v = v * 10 + char_int(c)
  }
  v
}

///|
fn is_leap_year(year : Int32) -> Bool {
  (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
}

///|
fn days_in_month(year : Int32, mon : Int32) -> Int32 {
  if mon == 2 {
    if is_leap_year(year) {
      29
    } else {
      28
    }
  } else if mon == 4 || mon == 6 || mon == 9 || mon == 11 {
    30
  } else {
    31
  }
}

///|
/// 把 `YYYY-MM-DDTHH:MM:SS...` 起始的时间戳解析为累计秒。解析失败返回 -1。
/// 以 2024-01-01 为参考基准（仅用于同体系先后比较，非绝对 UTC）：
/// 避免 year*365*86400 在 32 位 Int 下溢出。
pub fn iso_to_secs(s : String) -> Int32 {
  let chars = s.to_array()
  if chars.length() < 16 {
    return -1
  }
  // R129：分隔符位固定为 `-` `-` (T/t/空格) `:` `:`——字段数字合法但分隔符错位
  //（如 `2024:01-01T...`）此前会静默算出值；秒段只在 length ≥ 19 时解析，
  // 故第 17 个字符只在 length ≥ 17 时要求是 `:`（兼容 16/18 字符截断输入）。
  if chars[4] != '-' ||
    chars[7] != '-' ||
    (chars[10] != 'T' && chars[10] != 't' && chars[10] != ' ') ||
    chars[13] != ':' {
    return -1
  }
  if chars.length() >= 17 && chars[16] != ':' {
    return -1
  }
  let year = parse_digits(chars, 0, len=4)
  let mon = parse_digits(chars, 5, len=2)
  let day = parse_digits(chars, 8, len=2)
  let hour = parse_digits(chars, 11, len=2)
  let min = parse_digits(chars, 14, len=2)
  // R13-R1 bugfind（BUG-175）：秒段 parse_digits(chars,17,len=2) 会访问 chars[17] 与 chars[18]，
  // 守卫 `length >= 17` 只保证 chars[17] 安全（length==17 时 chars[17] 已越界，length==18 时 chars[18] 越界）。
  // 收紧到 `>= 19`：完整 "YYYY-MM-DDTHH:MM:SS" 恰好 19 字符；length<19 一律按无秒段处理（sec=0）。
  let sec = if chars.length() >= 19 {
    parse_digits(chars, 17, len=2)
  } else {
    0
  }
  if year < 2024 {
    return -1
  }
  // R12-R5 bugfind（BUG-217）：下界有检查但无上界——year=9999 时
  // (9999-2024)*365*86400 = 2.5e11 远超 Int32（2^31-1 ≈ 2.1e9），
  // 静默绕回乱数进而让心跳/归档/比较产生错误行为。
  // 上界取 2091（保守留余量）：含闰日后 2091-12-31 为 24837 天，
  // 24837*86400+86399 = 2,146,003,199 < 2^31-1（2,147,483,647）；
  // 2092 起 25203*86400 ≈ 2.18e9 已越过 Int32 上界。
  if year > 2091 {
    return -1
  }
  // R128：字段范围校验。`parse_digits` 不做范围检查——`2091-12-99T...` 的 day=99
  // 会让 days=24888，`days * 86400` 越过 Int32（issue_scan secs-overflow 实测命中）。
  // 非数字字符由 parse_digits 返回 -1，同样落到下面的范围检查。
  // 非法字段一律按解析失败返回 -1；hour/min/sec 同样要挡，否则 day 合法时仍可能越界。
  if mon < 1 || mon > 12 {
    return -1
  }
  // R129：按真实日历校验当月天数——只挡 day>31 会放过 2/30、4/31 这类
  // 不存在的日期，跨解析器顺序锁实测 2024-02-29 与 2024-03-01 同值。
  if day < 1 || day > days_in_month(year, mon) {
    return -1
  }
  if hour < 0 || hour > 23 {
    return -1
  }
  if min < 0 || min > 59 {
    return -1
  }
  if sec < 0 || sec > 59 {
    return -1
  }
  // 月起点累计天数（非闰年表；闰年 3 月起的 +1 由 leap_fix 补；索引 = 真实月份-1）
  let accum : Array[Int32] = [
    0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334,
  ]
  // R129：真闰年口径。原「365 天年 + 非闰月表」让 2024-02-29 与 2024-03-01
  // 算出同一个值，跨解析器顺序锁当场抓到；数值只用于同体系时间差，不持久化。
  let leaps = (year - 2024 + 3) / 4
  let leap_fix = if is_leap_year(year) && mon > 2 { 1 } else { 0 }
  let month_days = accum[mon - 1]
  // 字段已校验且 2024 ≤ year ≤ 2091 ⇒ days ≤ 24837；乘法走 Int64（同 server.mbt 口径），
  // 再窄化回 Int32：即使未来放宽 year 上界，这里也不会静默绕回。
  let days = (year - 2024) * 365 + leaps + month_days + leap_fix + day
  let total_secs : Int64 = days.to_int64() * 86400L +
    hour.to_int64() * 3600L +
    min.to_int64() * 60L +
    sec.to_int64()
  total_secs.to_int()
}
