/// FIST-Mbt core: 七条金条（不可动摇原则）。
/// 迁移自 FIST(Python) 的 FIST-SKILL，作为可解释性（赛事验收标准之一）的
/// 机器可读呈现，并通过 resources/prompts 暴露给 MCP 客户端。

/// 单条原则
pub struct Principle {
  index : Int
  title : String
  body : String
} derive(Eq, Debug)

pub fn Principle::get_index(self : Principle) -> Int { self.index }
pub fn Principle::get_title(self : Principle) -> String { self.title }
pub fn Principle::get_body(self : Principle) -> String { self.body }

/// 七条金条的权威定义（与 FIST-SKILL/Python 版保持同源）
pub fn principles() -> Array[Principle] {
  [
    {
      index: 1,
      title: "一切行动听指挥",
      body: "任务由唯一指挥官（人类）发布，其他角色不得自作主张改变任务目标；AI 若需偏离，必须先向人类请示。",
    },
    {
      index: 2,
      title: "指挥官是一切的最终责任人",
      body: "人类对项目/任务负最终责任；任何导致资源占用、系统变更、删除覆盖的操作，都必须有明确授权。",
    },
    {
      index: 3,
      title: "任何输出都必须有负责人",
      body: "任何产物（文档、代码、配置、数据）都必须有明确的负责人（assignee），杜绝无主产物。",
    },
    {
      index: 4,
      title: "唯一指挥官",
      body: "一次只有一个'拳长'负责最高层扇区；任务的层次与所有权唯一，避免多头指挥。",
    },
    {
      index: 5,
      title: "权利与责任对等",
      body: "高难度任务必须拆分并下放执行（拆解 gcd=split_n，depth-1）；权限与责任必须对等，禁止越权。",
    },
    {
      index: 6,
      title: "安全与离开",
      body: "涉及系统/网络/存储的操作必须人类授权；任何人离开/任务交接必须留下安全边界（cleanup_mode）。",
    },
    {
      index: 7,
      title: "观察与记录",
      body: "任务执行必须有观察与记录（logs、进度、审计），任何东西都要可追溯、可验证。",
    },
  ]
}

/// 单条原则转 JSON（供 resource 输出）
pub fn Principle::to_json(self : Principle) -> Json {
  let m : Map[String, Json] = Map([])
  m.set("index", Json::number(self.index.to_double()))
  m.set("title", Json::string(self.title))
  m.set("body", Json::string(self.body))
  Json::object(m)
}

/// 全部原则转 JSON 数组
pub fn principles_json() -> Json {
  Json::array(principles().map(fn(p) { p.to_json() }))
}
