///|
/// 档4：boundary_probe —— 按规则类型路由的边界输入建议生成器（纯计算，不跑测试）。
///
/// 输入一条 finding（rule / code / line / file），按规则类型返回该位置的边界输入建议数组。
/// 每条建议带 `confirmed=false`：调用方（bugfind 模式第四步）把 `input` 喂给 `run_check`，
/// 能触发 panic/崩溃的才回写 `confirmed=true`。本函数**不执行任何测试**，只产出建议。

///|

///|
/// 构造一条边界建议（kind / input / note），confirmed 恒为 false（纯计算不执行）
fn boundary_sug(
  kind : String,
  input : String,
  note : String,
) -> Map[String, Json] {
  let m : Map[String, Json] = Map([])
  m.set("kind", Json::string(kind))
  m.set("input", Json::string(input))
  m.set("note", Json::string(note))
  m.set("confirmed", Json::boolean(false))
  m
}

///|
/// 按规则类型路由，产出边界建议数组（纯计算）
fn boundary_suggestions(rule : String) -> Array[Json] {
  let arr : Array[Json] = []
  if rule.contains("divide") || rule.contains("div") {
    arr.push(
      Json::object(
        boundary_sug(
          "divisor-zero", "y = 0", "除数置 0，验证除零保护",
        ),
      ),
    )
    arr.push(
      Json::object(
        boundary_sug(
          "divisor-extreme", "y = 1e308", "除数取极大值，验证溢出/精度路径",
        ),
      ),
    )
    arr.push(
      Json::object(
        boundary_sug(
          "divisor-negative", "y = -1", "负除数，验证符号处理",
        ),
      ),
    )
  } else if rule.contains("substring") ||
    rule.contains("index") ||
    rule.contains("下标") {
    arr.push(
      Json::object(
        boundary_sug(
          "negative-index", "s[-1]", "负下标，验证越界保护",
        ),
      ),
    )
    arr.push(
      Json::object(
        boundary_sug(
          "boundary-index", "s[len]", "边界下标（等于长度），验证 off-by-one",
        ),
      ),
    )
    arr.push(
      Json::object(
        boundary_sug(
          "empty-input", "s = 空串 / 空数组", "空输入，验证空数组/越界",
        ),
      ),
    )
    arr.push(
      Json::object(
        boundary_sug(
          "huge-input", "s = 长度 1000000 的串", "超长输入，验证性能/溢出",
        ),
      ),
    )
  } else if rule.contains("unwrap") || rule.contains("unsafe_get") {
    arr.push(
      Json::object(
        boundary_sug(
          "none-input", "x = None", "None / 空 Optional，验证 unwrap 保护",
        ),
      ),
    )
    arr.push(
      Json::object(
        boundary_sug(
          "empty-collection", "xs = 空数组", "空集合，验证 unsafe_get 保护",
        ),
      ),
    )
    arr.push(
      Json::object(
        boundary_sug(
          "partial-construct", "只构造部分字段", "部分构造，验证结构完整性",
        ),
      ),
    )
  } else if rule.contains("empty") || rule.contains("match") {
    arr.push(
      Json::object(
        boundary_sug(
          "empty-input", "输入为空", "空输入 / 空 match，验证穷尽性",
        ),
      ),
    )
    arr.push(
      Json::object(
        boundary_sug(
          "unknown-tag", "未知枚举变体", "非法 / 未覆盖输入",
        ),
      ),
    )
    arr.push(
      Json::object(
        boundary_sug(
          "all-variants", "覆盖全部变体", "穷尽性对照：合法输入",
        ),
      ),
    )
  } else if rule.contains("overflow") || rule.contains("secs") {
    arr.push(
      Json::object(
        boundary_sug(
          "int-max", "x = Int 最大值", "整数上界，验证溢出",
        ),
      ),
    )
    arr.push(
      Json::object(
        boundary_sug(
          "int-min", "x = Int 最小值", "整数下界，验证溢出",
        ),
      ),
    )
    arr.push(
      Json::object(
        boundary_sug(
          "huge-duration", "secs = 1e15", "超大时长，验证 secs 溢出",
        ),
      ),
    )
  } else if rule.contains("race") ||
    rule.contains("concurrency") ||
    rule.contains("共享") ||
    rule.contains("竞态") {
    arr.push(
      Json::object(
        boundary_sug(
          "interleaving", "两个线程交替读写同一变量", "并发交错，验证竞态",
        ),
      ),
    )
    arr.push(
      Json::object(
        boundary_sug(
          "no-barrier", "无同步原语并发写", "缺失屏障，验证共享可变",
        ),
      ),
    )
    arr.push(
      Json::object(
        boundary_sug(
          "reentrant", "同一函数重入", "重入，验证共享状态",
        ),
      ),
    )
  } else if rule.contains("json") ||
    rule.contains("injection") ||
    rule.contains("escape") ||
    rule.contains("插值") ||
    rule.contains("泄漏") {
    arr.push(
      Json::object(
        boundary_sug(
          "meta-char", "含引号 / 反斜杠 / 换行的输入", "JSON / 插值元字符注入",
        ),
      ),
    )
    arr.push(
      Json::object(
        boundary_sug(
          "nested-quote", "含未转义引号", "引号 / 反斜杠未转义",
        ),
      ),
    )
    arr.push(
      Json::object(
        boundary_sug("unicode-trap", "含全角 / 控制字符", "编码边界"),
      ),
    )
  } else if rule.contains("path") || rule.contains("traversal") {
    arr.push(
      Json::object(
        boundary_sug("dotdot", "path = ../secret.txt", "路径穿越"),
      ),
    )
    arr.push(
      Json::object(
        boundary_sug(
          "abs-path", "path = 盘符绝对路径", "绝对路径 / 跨盘",
        ),
      ),
    )
    arr.push(
      Json::object(
        boundary_sug("symlink", "path = 符号链接", "符号链接逃逸"),
      ),
    )
  } else if rule.contains("float") || rule.contains("浮点") {
    arr.push(
      Json::object(
        boundary_sug("nan", "x = 0.0 除以 0.0", "NaN，验证浮点相等"),
      ),
    )
    arr.push(
      Json::object(boundary_sug("infinity", "x = 1.0 除以 0.0", "Infinity")),
    )
    arr.push(
      Json::object(
        boundary_sug("neg-zero", "x = -0.0", "负零，验证浮点相等"),
      ),
    )
  } else if rule.contains("resource") {
    arr.push(
      Json::object(
        boundary_sug("leak-loop", "循环内 open/close 缺失", "资源泄漏"),
      ),
    )
    arr.push(
      Json::object(
        boundary_sug("early-return", "中途 return 未释放", "早退泄漏"),
      ),
    )
  } else if rule.contains("async_main") {
    arr.push(
      Json::object(
        boundary_sug(
          "blocking-call", "async_main 内调阻塞函数", "阻塞调用",
        ),
      ),
    )
    arr.push(
      Json::object(
        boundary_sug("spawn-leak", "大量 spawn 未 join", "协程泄漏"),
      ),
    )
  } else if rule.contains("abort") {
    arr.push(
      Json::object(
        boundary_sug(
          "dead-branch", "abort 后续代码", "死代码分支可达性",
        ),
      ),
    )
  } else if rule.contains("discard") || rule.contains("result") {
    arr.push(
      Json::object(
        boundary_sug(
          "err-result", "返回 Err 的结果被丢弃", "错误丢弃验证",
        ),
      ),
    )
    arr.push(
      Json::object(
        boundary_sug(
          "ok-result", "返回 Ok 的结果被丢弃", "成功丢弃验证",
        ),
      ),
    )
  } else if rule.contains("noop") || rule.contains("assignment") {
    arr.push(
      Json::object(
        boundary_sug(
          "reassign-same", "对同一变量连续赋值", "无效赋值验证",
        ),
      ),
    )
  } else if rule.contains("long") || rule.contains("函数") {
    arr.push(
      Json::object(
        boundary_sug(
          "branch-trap", "长函数内部分支未覆盖", "长函数分支覆盖",
        ),
      ),
    )
  } else {
    arr.push(
      Json::object(
        boundary_sug("generic-empty", "空输入", "通用边界：空"),
      ),
    )
    arr.push(
      Json::object(
        boundary_sug("generic-extreme", "极值输入", "通用边界：极值"),
      ),
    )
    arr.push(
      Json::object(
        boundary_sug(
          "generic-illegal", "非法输入", "通用边界：非法/异常",
        ),
      ),
    )
  }
  arr
}

///| 档4 主入口：给定 finding 字段，返回 { rule, file, line, code, suggestions[], total, confirmed_count, note }

///|
/// 纯计算，不 spawn 不跑测试。suggestions 里的 `input` 供调用方喂给 run_check 验证。
pub fn boundary_probe(
  rule : String,
  code : String,
  line : String,
  file : String,
) -> Json {
  let arr = boundary_suggestions(rule)
  let m : Map[String, Json] = Map([])
  m.set("rule", Json::string(rule))
  m.set("file", Json::string(file))
  m.set("line", Json::string(line))
  m.set("code", Json::string(code))
  m.set("suggestions", Json::array(arr))
  m.set("total", Json::number(arr.length().to_double()))
  m.set("confirmed_count", Json::number(0.0))
  m.set(
    "note",
    Json::string(
      "纯计算建议，不执行。调用方（bugfind 第四步）把 input 喂给 run_check，触发 panic/崩溃的再回写 confirmed=true",
    ),
  )
  Json::object(m)
}

///|
/// 便捷入口：只给 rule 和 code，file/line 用占位（供测试/快速试用）
pub fn boundary_probe_by_code(rule : String, code : String) -> Json {
  boundary_probe(rule, code, "?", "?")
}
