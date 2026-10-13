///|
/// diff/diff.mbt —— 轻量文本 diff（LCS 最长公共子序列）。
///
/// 用于报告对比、测试输出 diff、AI 交付物变更审查等场景。
/// 纯函数零依赖（除 core/json 用于序列化），双后端通用。
///
/// 用法：
///   let ops = diff_lines("a\nb\nc", "a\nx\nc")
///   // ops = [Equal("a"), Delete("b"), Insert("x"), Equal("c")]
///   let patch = render_unified(ops)  // 类 unified diff 格式

///|
/// diff 操作类型。
pub enum DiffOp {
  Equal(String)
  Insert(String)
  Delete(String)
}

///|
/// DiffOp 的 kind 标签（equal/insert/delete），用于 JSON 序列化。
pub fn DiffOp::kind(self : DiffOp) -> String {
  match self {
    Equal(_) => "equal"
    Insert(_) => "insert"
    Delete(_) => "delete"
  }
}

///|
/// DiffOp 的文本内容。
pub fn DiffOp::text(self : DiffOp) -> String {
  match self {
    Equal(s) => s
    Insert(s) => s
    Delete(s) => s
  }
}

///|
/// 按行 diff（LCS）。输入 old/new 文本，返回操作序列（含空行）。
/// 算法：经典 LCS 动态规划，O(n*m) 时间/空间。
pub fn diff_lines(old : String, new : String) -> Array[DiffOp] {
  let old_lines = split_lines(old)
  let new_lines = split_lines(new)
  let n = old_lines.length()
  let m = new_lines.length()
  // LCS DP 表：dp[i][j] = old[0..i] 与 new[0..j] 的 LCS 长度
  let dp : Array[Array[Int]] = []
  for i in 0..=n {
    let row : Array[Int] = []
    for _j in 0..=m {
      row.push(0)
    }
    dp.push(row)
  }
  for i in 1..=n {
    for j in 1..=m {
      if old_lines[i - 1] == new_lines[j - 1] {
        dp[i][j] = dp[i - 1][j - 1] + 1
      } else {
        dp[i][j] = if dp[i - 1][j] >= dp[i][j - 1] {
          dp[i - 1][j]
        } else {
          dp[i][j - 1]
        }
      }
    }
  }
  // 回溯生成操作序列
  let ops : Array[DiffOp] = []
  let mut i = n
  let mut j = m
  while i > 0 || j > 0 {
    if i > 0 && j > 0 && old_lines[i - 1] == new_lines[j - 1] {
      ops.push(Equal(old_lines[i - 1]))
      i = i - 1
      j = j - 1
    } else if j > 0 && (i == 0 || dp[i][j - 1] >= dp[i - 1][j]) {
      ops.push(Insert(new_lines[j - 1]))
      j = j - 1
    } else {
      ops.push(Delete(old_lines[i - 1]))
      i = i - 1
    }
  }
  // Array 无 reverse 方法，手动反转
  let reversed : Array[DiffOp] = []
  for idx in 0..<ops.length() {
    reversed.push(ops[ops.length() - 1 - idx])
  }
  reversed
}

///|
/// 按行分割（保留行内容，不含换行符；末尾空行忽略）。
fn split_lines(s : String) -> Array[String] {
  let lines : Array[String] = []
  let mut start = 0
  for i in 0..<s.length() {
    if s[i] == '\n' {
      lines.push(s[start:i].to_owned())
      start = i + 1
    }
  }
  if start < s.length() {
    lines.push(s[start:].to_owned())
  }
  lines
}

///|
/// 渲染为类 unified diff 格式（+/-/ 前缀）。
pub fn render_unified(ops : Array[DiffOp]) -> String {
  let out : Array[String] = []
  for op in ops {
    match op {
      Equal(s) => out.push(" " + s)
      Insert(s) => out.push("+" + s)
      Delete(s) => out.push("-" + s)
    }
  }
  out.join("\n")
}

///|
/// 渲染为 JSON 数组：[{"kind":"equal|insert|delete","text":"..."}]
pub fn render_json(ops : Array[DiffOp]) -> String {
  let items : Array[String] = []
  for op in ops {
    let kind = op.kind()
    let text = json_escape(op.text())
    items.push("{\"kind\":\"" + kind + "\",\"text\":\"" + text + "\"}")
  }
  "[" + items.join(",") + "]"
}

///|
/// JSON 字符串转义（最小集：引号、反斜杠、换行、回车、制表符）。
fn json_escape(s : String) -> String {
  let out : Array[String] = []
  for ch in s {
    match ch {
      '"' => out.push("\\\"")
      '\\' => out.push("\\\\")
      '\n' => out.push("\\n")
      '\r' => out.push("\\r")
      '\t' => out.push("\\t")
      _ => out.push(ch.to_string())
    }
  }
  out.join("")
}

///|
/// 统计：equal/insert/delete 计数，返回 {equal, insert, delete}。
pub fn diff_stats(ops : Array[DiffOp]) -> (Int, Int, Int) {
  let mut eq = 0
  let mut ins = 0
  let mut del = 0
  for op in ops {
    match op {
      Equal(_) => eq = eq + 1
      Insert(_) => ins = ins + 1
      Delete(_) => del = del + 1
    }
  }
  (eq, ins, del)
}
