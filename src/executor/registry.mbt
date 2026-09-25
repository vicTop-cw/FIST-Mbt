/// registry.mbt — 执行器注册表 + 能力路由（Marketplace/Dynamic 范式雏形）。
///
/// 管理执行器实例的注册与查找。默认注册 McpDelegateExecutor。
/// 支持自定义执行器（通过 register / add_ability 动态添加）。
/// R30 增强：为每个执行器登记「能力标签 abilities」（如 ["编排","json"]），并提供
/// 纯计算的能力路由 route_pick——给定任务所需能力 need 与各执行器当前负载 load，
/// 返回按「是否覆盖所需能力(全命中优先) → 负载最小 → 名称」排序的执行器候补。
/// 负载由调用方注入（引擎按 assignee 统计活跃任务），本层保持纯函数、不碰存储。

///|
/// 注册表结构体：名称 -> 名称（既有），加 名称 -> 能力标签集合。
pub struct ExecutorRegistry {
  executors : Map[String, String]
  abilities : Map[String, Array[String]]
}

///|
/// 全局注册表（使用 Once 懒初始化）。默认注册 McpDelegateExecutor 与 manual。
pub fn ExecutorRegistry::new() -> ExecutorRegistry {
  let m : Map[String, String] = Map([])
  let ab : Map[String, Array[String]] = Map([])
  // 默认注册 McpDelegateExecutor 与 manual（无能力标签）
  m.set("McpDelegateExecutor", "McpDelegateExecutor")
  m.set("manual", "manual")
  ab.set("McpDelegateExecutor", [])
  ab.set("manual", [])
  { executors: m, abilities: ab, }
}

///|
/// 注册执行器（保留既有能力标签，无则置空）。
pub fn ExecutorRegistry::register(
  self : ExecutorRegistry,
  name : String,
) -> ExecutorRegistry {
  let m = self.executors
  m.set(name, name)
  if self.abilities.get(name).is_none() {
    ignore(self.abilities.set(name, []))
  }
  { executors: m, abilities: self.abilities, }
}

///|
/// 为已注册执行器登记（或覆盖）能力标签集合。
pub fn ExecutorRegistry::add_ability(
  self : ExecutorRegistry,
  name : String,
  a : Array[String],
) -> ExecutorRegistry {
  let m = self.executors
  m.set(name, name)
  ignore(self.abilities.set(name, a))
  { executors: m, abilities: self.abilities, }
}

///|
/// 查询执行器的能力标签（未注册/无标签返回空数组）。
pub fn ExecutorRegistry::abilities_of(
  self : ExecutorRegistry,
  name : String,
) -> Array[String] {
  match self.abilities.get(name) {
    Some(a) => a
    None => []
  }
}

///|
/// 检查执行器是否已注册
pub fn ExecutorRegistry::has(self : ExecutorRegistry, name : String) -> Bool {
  self.executors.get(name) is Some(_)
}

///|
/// 列出所有已注册执行器
pub fn ExecutorRegistry::list(self : ExecutorRegistry) -> Array[String] {
  let names : Array[String] = []
  for k in self.executors.keys() {
    names.push(k)
  }
  names
}

///|
/// 获取执行器（返回名称，实际构造由调用方完成）
pub fn ExecutorRegistry::get(self : ExecutorRegistry, name : String) -> String? {
  self.executors.get(name)
}

///|
/// 便捷函数：判断是否为合法执行器名称
pub fn is_valid_executor(name : String) -> Bool {
  name == "McpDelegateExecutor" || name == "manual"
}

///|
/// 把 `need` 打散成能力标签数组：按 `,`、`，`、空格、`、` 分隔，去掉空串。
pub fn split_need_tags(need : String) -> Array[String] {
  let out : Array[String] = []
  let mut cur = ""
  for c in need {
    let ch = c.to_string()
    if ch == "," || ch == "，" || ch == " " || ch == "、" {
      if cur != "" {
        out.push(cur)
        cur = ""
      }
    } else {
      cur = cur + ch
    }
  }
  if cur != "" {
    out.push(cur)
  }
  out
}

///|
/// 该执行器对 need 的能力覆盖率 0..1：命中所需标签数 / 所需标签总数。
/// need 为空（无可比性）返回 _load-only_ 语义，score 记为 0（由调用方按负载兜底）。
pub fn ability_coverage(ab : Array[String], need : Array[String]) -> Double {
  if need.is_empty() {
    return 0.0
  }
  let mut hit = 0
  for t in need {
    for a in ab {
      if a == t {
        hit = hit + 1
        break
      }
    }
  }
  hit.to_double() / need.length().to_double()
}

///|
/// 纯计算能力路由：按 { 覆盖率 desc, 负载 asc, 名称 asc } 排序注册的执行器，
/// 返回候选列表（每个带 name/coverage/load/abilities）。load 由调用方从 store 注入
/// （assignee 名下的活跃任务数），本层不读存储。
pub fn ExecutorRegistry::route_pick(
  self : ExecutorRegistry,
  need : String,
  load : Map[String, Int],
) -> Json {
  let tags = split_need_tags(need)
  // 汇总每条候选：覆盖率 + 负载
  let rows : Array[Json] = []
  for name in self.list() {
    let cov = ability_coverage(self.abilities_of(name), tags)
    let ld = match load.get(name) {
      Some(n) => n
      None => 0
    }
    rows.push(
      Json::object({
        "name": Json::string(name),
        "coverage": Json::number(cov),
        "load": Json::number(ld.to_double()),
        "abilities": Json::array(
          self.abilities_of(name).map(fn(s) { Json::string(s) }),
        ),
      }),
    )
  }
  // 稳定排序：coverage desc → load asc → name asc
  rows.sort_by(fn(a : Json, b : Json) -> Int {
    let ac = num(a, "coverage")
    let bc = num(b, "coverage")
    if ac != bc {
      if ac > bc {
        -1
      } else {
        1
      }
    } else {
      let al = num(a, "load")
      let bl = num(b, "load")
      if al != bl {
        if al < bl {
          -1
        } else {
          1
        }
      } else {
        let an = str(a, "name")
        let bn = str(b, "name")
        if an < bn {
          -1
        } else {
          1
        }
      }
    }
  })
  let best : Json = if rows.is_empty() { Json::null() } else { rows[0] }
  Json::object({
    "need": Json::string(need),
    "parsed": Json::array(tags.map(fn(s) { Json::string(s) })),
    "count": Json::number(rows.length().to_double()),
    "candidates": Json::array(rows),
    "best": best,
  })
}

///|
/// 读 Json 对象的数值字段。
fn num(j : Json, key : String) -> Double {
  match j.value(key) {
    Some(Json::Number(n, ..)) => n
    _ => 0.0
  }
}

///|
/// 读 Json 对象的字符串字段。
fn str(j : Json, key : String) -> String {
  match j.value(key) {
    Some(Json::String(s)) => s
    _ => ""
  }
}
