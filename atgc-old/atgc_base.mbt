/// ATGC 双链虚拟机 · 基础编码模块（atgc/atgc_base.mbt）。
/// 依据设计文档 idea.md §2.1 / §2.3 / §4：A/T/G/C = 四进制 0/1/2/3，
/// 3 个碱基一组 = 64 密码子，反向互补 rc(seq) = reverse(complement(seq))（§4.2/§4.4）。
/// 单碱基以 `Char` 表示；整串以 `for c in str` 做 Unicode 安全的逐字符迭代。

///|
/// 碱基 → 四进制数值。仅接受 DNA 四字母；U 已在词法层归并为 T。未知返回 None。
pub fn base_to_int(c : Char) -> Int? {
  match c {
    'A' => Some(0)
    'T' => Some(1)
    'G' => Some(2)
    'C' => Some(3)
    _ => None
  }
}

///|
/// 四进制数值 → 碱基。v 越界 0..3 时按 mod 4 折叠（防御）。
pub fn int_to_base(v : Int) -> Char {
  let b = if v < 0 { v + 4 } else if v > 3 { v % 4 } else { v }
  match b {
    0 => 'A'
    1 => 'T'
    2 => 'G'
    _ => 'C'
  }
}

///|
/// 碱基互补配对（Watson-Crick）：A↔T、G↔C。未知返回 None。
pub fn complement(c : Char) -> Char? {
  match c {
    'A' => Some('T')
    'T' => Some('A')
    'G' => Some('C')
    'C' => Some('G')
    _ => None
  }
}

///|
/// 单个密码子（3 碱基）按四进制解析为 0..63（§2.3）。长度不足/非法返回 None。
pub fn quaternary_of(codon : String) -> Int? {
  if codon.length() != 3 {
    return None
  }
  let mut v = 0
  for c in codon {
    match base_to_int(c) {
      Some(x) => v = v * 4 + x
      None => return None
    }
  }
  Some(v)
}

///|
/// 四进制数值 0..63 渲染为 3 碱基密码子。
pub fn int_to_codon(v : Int) -> String {
  let sb = StringBuilder()
  sb.write_char(int_to_base(v / 16 % 4))
  sb.write_char(int_to_base(v / 4 % 4))
  sb.write_char(int_to_base(v % 4))
  sb.to_string()
}

///|
/// 反向互补：先逐碱基互补，再整串倒序（§4.2 rc = reverse(complement)）。
/// 非法碱基返回 None（纯函数，不抛异常）。
pub fn reverse_complement(seq : String) -> String? {
  let comps : Array[Char] = []
  for c in seq {
    match complement(c) {
      Some(x) => comps.push(x)
      None => return None
    }
  }
  let sb = StringBuilder()
  let n = comps.length()
  let mut i = n
  while i > 0 {
    i = i - 1
    sb.write_char(comps[i])
  }
  Some(sb.to_string())
}

///|
/// 判断一条序列是否为合法 DNA 程序（仅含 A/T/G/C）。
pub fn is_valid_dna(seq : String) -> Bool {
  for c in seq {
    match base_to_int(c) {
      Some(_) => ()
      None => return false
    }
  }
  true
}

///|
/// 按字符位置截取子串（Char 语义）：取出 [start, start+len) 的字符。
/// 越界自动截断。用于指令区解析（无 sub_string 依赖）。
pub fn slice_str(s : String, start : Int, len : Int) -> String {
  let sb = StringBuilder()
  let mut i = 0
  for c in s {
    if i >= start && i < start + len {
      sb.write_char(c)
    }
    i = i + 1
  }
  sb.to_string()
}

///|
/// 在 hay 中查找 needle 首次出现的起始下标；未找到返回 -1（避免依赖 sub_string 索引）。
pub fn find_substr(hay : String, needle : String) -> Int {
  let n = hay.length()
  let m = needle.length()
  if m > n {
    return -1
  }
  for i in 0..<(n - m + 1) {
    if slice_str(hay, i, m) == needle {
      return i
    }
  }
  -1
}
