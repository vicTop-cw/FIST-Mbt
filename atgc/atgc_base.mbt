/// atgc_base.mbt —— ATGC 极简库：碱基 <-> 四进制、互补、反向互补、MODE_B 转录。
/// 交付物：fist-mbt 自驱 + Omega 强验证管线「base」叶。
/// 验证语料(Omega spec content)：valid_input 仅接受 [ATGCU]/空白/`;;`；base_to_int 按
/// A=0,T=1,G=2,C=3；complement 为 A<->T、G<->C；reverse_complement 是 sequence 的对合
/// (rc(rc(s))==s, 且长度不变)；transcribe 把 T 换 U、其余碱基不动、非法输入返回 Err。

///|
/// 归一化：大写、去掉空白与 `;;` 注释，仅保留 [A-Z] 中的碱基。
pub fn normalize(seq : String) -> String {
  let sb = StringBuilder()
  let mut in_comment = false
  for c in seq {
    if in_comment {
      if c == '\n' {
        in_comment = false
      }
      continue
    }
    if c == ';' {
      in_comment = true
      continue
    }
    if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
      continue
    }
    sb.write_char(c.to_ascii_uppercase())
  }
  sb.to_string()
}

///|
/// 碱基 -> 四进制(A=0 T=1 G=2 C=3)；U 视为 T。
pub fn base_to_int(c : Char) -> Int? {
  let up = c.to_ascii_uppercase()
  if up == 'A' || up == 'U' {
    Some(0)
  } else if up == 'T' {
    Some(1)
  } else if up == 'G' {
    Some(2)
  } else if up == 'C' {
    Some(3)
  } else {
    None
  }
}

///|
/// 四进制 -> 碱基。
pub fn int_to_base(n : Int) -> Char {
  if n == 0 {
    'A'
  } else if n == 1 {
    'T'
  } else if n == 2 {
    'G'
  } else {
    'C'
  }
}

///|
/// 互补碱基（A<->T, G<->C）。
pub fn complement(c : Char) -> Char? {
  let up = c.to_ascii_uppercase()
  if up == 'A' || up == 'U' {
    Some('T')
  } else if up == 'T' {
    Some('A')
  } else if up == 'G' {
    Some('C')
  } else if up == 'C' {
    Some('G')
  } else {
    None
  }
}

///|
/// 反向互补：rc(s) = reverse(complement(each base))。非法字符返回 None。
/// 对合性质：rc(rc(s)) == s（DNA 无自反碱基）。
pub fn reverse_complement(seq : String) -> String? {
  let n = normalize(seq)
  let chars = n.to_array()
  let out = StringBuilder()
  for i = chars.length() - 1; i >= 0; i = i - 1 {
    match complement(chars[i]) {
      None => return None
      Some(c) => out.write_char(c)
    }
  }
  Some(out.to_string())
}

///|
/// MODE_B 转录：有义链的 T 换成 U（mRNA），其余碱基不变。非法输入返回 None。
pub fn transcribe(seq : String) -> String? {
  let n = normalize(seq)
  let sb = StringBuilder()
  for c in n {
    match base_to_int(c) {
      None => return None
      Some(_) =>
        sb.write_char(
          if c.to_ascii_uppercase() == 'T' {
            'U'
          } else {
            c.to_ascii_uppercase()
          },
        )
    }
  }
  Some(sb.to_string())
}

///|
/// 是否全为合法碱基/空白/注释（归一化后非空且均合法）。
pub fn valid_input(seq : String) -> Bool {
  let n = normalize(seq)
  if n.length() == 0 {
    return false
  }
  for c in n {
    if base_to_int(c) is None {
      return false
    }
  }
  true
}
