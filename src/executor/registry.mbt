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
/// 历史信任轴路由（R80，SwarmHarness 蒸馏）：在 route_pick 排序里加 trust 轴——
/// 排序键 coverage desc → trust desc → load asc → name asc。trust 由调用方注入
/// （执行者历史验收通过率，无历史取 0.5 中性）。原 route_pick 签名保留零回归。
pub fn ExecutorRegistry::route_pick_with_trust(
  self : ExecutorRegistry,
  need : String,
  load : Map[String, Int],
  trust : Map[String, Double],
) -> Json {
  let tags = split_need_tags(need)
  let rows : Array[Json] = []
  for name in self.list() {
    let cov = ability_coverage(self.abilities_of(name), tags)
    let ld = match load.get(name) {
      Some(n) => n
      None => 0
    }
    let tr = match trust.get(name) {
      Some(d) => d
      None => 0.5
    }
    rows.push(
      Json::object({
        "name": Json::string(name),
        "coverage": Json::number(cov),
        "trust": Json::number(tr),
        "load": Json::number(ld.to_double()),
        "abilities": Json::array(
          self.abilities_of(name).map(fn(s) { Json::string(s) }),
        ),
      }),
    )
  }
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
      let at = num(a, "trust")
      let bt = num(b, "trust")
      if at != bt {
        if at > bt {
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
    }
  })
  let best : Json = if rows.is_empty() { Json::null() } else { rows[0] }
  Json::object({
    "need": Json::string(need),
    "parsed": Json::array(tags.map(fn(s) { Json::string(s) })),
    "count": Json::number(rows.length().to_double()),
    "candidates": Json::array(rows),
    "best": best,
    "basis": Json::string(
      "能力覆盖 → 历史信任(验收通过率) → 负载 → 名称（R80）",
    ),
  })
}

///|
/// Agora 置信度校准拍卖（R87，Agora arXiv 2607.09600 蒸馏）：把执行者分派从"排序推荐"
/// 升级为"按出价竞拍"。每个已注册执行者对任务所需能力 need 出价（显式 bid，缺省按
/// 能力覆盖率自动出价），经校准系数 `1 - |出价 - 历史验收通过率|` 折扣——防"胜者诅咒"：
/// 过度自信（出价高而兑现差）的执行者被惩罚；再乘负载折扣 `1/(1+负载)` 得拍卖分。
/// 能力覆盖 > 0 方可竞拍（能力不匹配不进入拍卖）。纯计算：need/load/trust/bid 均由
/// 调用方注入，本层不读存储。排序：拍卖分 desc → 名称 asc。
pub fn ExecutorRegistry::auction_pick(
  self : ExecutorRegistry,
  need : String,
  load : Map[String, Int],
  trust : Map[String, Double],
  bid : Map[String, Double],
) -> Json {
  let tags = split_need_tags(need)
  let rows : Array[Json] = []
  for name in self.list() {
    let cov = ability_coverage(self.abilities_of(name), tags)
    if cov > 0.0 {
      let bd0 = match bid.get(name) {
        Some(d) => d
        None => cov
      }
      // 出价夹到 0..1（防止调用方传入越界置信度）
      let bd = if bd0 < 0.0 { 0.0 } else if bd0 > 1.0 { 1.0 } else { bd0 }
      let tr = match trust.get(name) {
        Some(d) => d
        None => 0.5
      }
      // 校准 = 1 - |出价 - 历史验收通过率|（Agora：按校准能力而非原始置信度拍卖）
      let diff = if bd > tr { bd - tr } else { tr - bd }
      let cal = 1.0 - diff
      let ld = match load.get(name) {
        Some(n) => n
        None => 0
      }
      // 负载折扣：活跃任务越多拍卖分越低（负载均衡）
      let lf = 1.0 / (ld + 1).to_double()
      let score = bd * cal * lf
      rows.push(
        Json::object({
          "name": Json::string(name),
          "coverage": Json::number(cov),
          "bid": Json::number(bd),
          "trust": Json::number(tr),
          "calibration": Json::number(cal),
          "load": Json::number(ld.to_double()),
          "overconfident": Json::boolean(bd > tr),
          "score": Json::number(score),
        }),
      )
    }
  }
  rows.sort_by(fn(a : Json, b : Json) -> Int {
    let as_ = num(a, "score")
    let bs = num(b, "score")
    if as_ != bs {
      if as_ > bs {
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
  })
  let winner : Json = if rows.is_empty() { Json::null() } else { rows[0] }
  let note = if rows.is_empty() {
    "无能力覆盖>0 的执行者可竞拍（need 无匹配或注册表为空）"
  } else {
    let wname = str(winner, "name")
    let wbid = num(winner, "bid")
    let wtr = num(winner, "trust")
    if wbid > wtr {
      "胜者 " +
      wname +
      " 出价高于其历史兑现率，已按校准折扣计入（仍胜出说明其余竞拍者更弱）"
    } else {
      "胜者 " +
      wname +
      " 出价与历史兑现率一致（校准=1），无胜者诅咒风险"
    }
  }
  Json::object({
    "need": Json::string(need),
    "parsed": Json::array(tags.map(fn(s) { Json::string(s) })),
    "count": Json::number(rows.length().to_double()),
    "bids": Json::array(rows),
    "winner": winner,
    "basis": Json::string(
      "置信度校准拍卖（Agora arXiv2607.09600 蒸馏）：能力覆盖>0 方可竞拍；出价=显式 bid 或默认按覆盖率；校准=1-|出价-历史验收通过率| 防胜者诅咒；拍卖分=出价×校准×负载折扣 1/(1+负载)；score desc → 名称 asc（R87）",
    ),
    "note": Json::string(note),
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
