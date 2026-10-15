/// router_caf.mbt —— C-A-F 轻量反馈记忆层（ACRouter 启发）
///
/// 设计决策（文档见 docs/2026-10-14-fist-mbt-router-caf-learning-plan.md）：
///   - 纯计算、零 IO、不依赖任何外部存储
///   - FIFO 环形表上限 10000 条，进程重启即清空（轻量第一，不做持久化）
///   - 特征哈希：基于任务语言/难度/动作类型组合的简单哈希，不做向量库
///   - 默认关闭（use_caf_memory=false），关闭时行为零回归
///   - 只在候选集内做软性排序微调，不破配额硬约束
///
/// 本文件仅包含 schema 与检索逻辑；旁路回写点在 src/server/model_router_ops.mbt。

///|
/// 一条 C-A-F 反馈记录
pub struct CafRecord {
  /// 特征哈希：由 task_lang/difficulty/action_type 组合成的标识符
  feature_hash : Int
  /// 被选的模型名
  model : String
  /// 是否成功
  ok : Bool
  /// 成本（美元，近似值；0 = 未知/免费）
  cost : Double
  /// 时间戳 ISO
  ts : String
} derive(Debug)

///|
pub fn CafRecord::new(
  feature_hash~ : Int,
  model~ : String,
  ok~ : Bool,
  cost~ : Double,
  ts~ : String,
) -> CafRecord {
  { feature_hash, model, ok, cost, ts, }
}

///|
/// C-A-F 反馈记忆表：FIFO 环形缓冲区，上限 max_size 条
pub struct CafMemory {
  records : Array[CafRecord?]
  max_size : Int
  mut head : Int
  mut count : Int
} derive(Debug)

///|
pub fn CafMemory::new(max_size? : Int = 10000) -> CafMemory {
  // BUG-188：max_size<=0 会让 records 成为空数组，push 时 records[0] 越界 panic。
  // 收敛到至少 1，使环形缓冲在任何输入下都可用。
  let m = if max_size <= 0 { 1 } else { max_size }
  { records: Array::make(m, None), max_size: m, head: 0, count: 0, }
}

///|
/// 追加一条记录（FIFO，超出 max_size 自动淘汰最旧）
pub fn CafMemory::push(self : CafMemory, rec : CafRecord) -> Unit {
  self.records[self.head] = Some(rec)
  self.head = (self.head + 1) % self.max_size
  if self.count < self.max_size {
    self.count = self.count + 1
  }
}

///|
/// 遍历所有有效记录
pub fn CafMemory::all(self : CafMemory) -> Array[CafRecord] {
  let mut out : Array[CafRecord] = []
  let mut i = 0
  while i < self.max_size {
    let r = self.records[(self.head + i) % self.max_size]
    match r {
      Some(rec) => out = out + [rec]
      None => ()
    }
    i = i + 1
  }
  out
}

///|
/// 按特征哈希检索：返回所有匹配记录
pub fn CafMemory::find(
  self : CafMemory,
  feature_hash~ : Int,
) -> Array[CafRecord] {
  let mut out : Array[CafRecord] = []
  let mut i = 0
  while i < self.max_size {
    match self.records[(self.head + i) % self.max_size] {
      Some(rec) if rec.feature_hash == feature_hash => out = out + [rec]
      _ => ()
    }
    i = i + 1
  }
  out
}

///|
/// 模型维度的成功率与成本统计
pub struct CafModelStats {
  model : String
  total : Int
  success : Int
  avg_cost : Double
} derive(Debug)

///|
/// 对检索结果做按模型的成功率统计
/// 返回按成功率降序、成本升序排列的数组
pub fn caf_stats(records : Array[CafRecord]) -> Array[CafModelStats] {
  let mut model_names : Array[String] = []
  let mut model_totals : Array[Int] = []
  let mut model_success : Array[Int] = []
  let mut model_cost_sum : Array[Double] = []

  for rec in records {
    let mut found = false
    for i in 0..<model_names.length() {
      if model_names[i] == rec.model {
        model_totals[i] = model_totals[i] + 1
        if rec.ok {
          model_success[i] = model_success[i] + 1
        }
        model_cost_sum[i] = model_cost_sum[i] + rec.cost
        found = true
        break
      }
    }
    if !found {
      model_names = model_names + [rec.model]
      model_totals = model_totals + [1]
      model_success = model_success + [if rec.ok { 1 } else { 0 }]
      model_cost_sum = model_cost_sum + [rec.cost]
    }
  }

  let mut out : Array[CafModelStats] = []
  for i in 0..<model_names.length() {
    out = out +
      [
        {
          model: model_names[i],
          total: model_totals[i],
          success: model_success[i],
          avg_cost: model_cost_sum[i] / model_totals[i].to_double(),
        },
      ]
  }
  // 按成功率降序、成本升序排列（sort_by 返回 Int：负=前者在前）
  // BUG-173：原实现在 rate_a==rate_b && avg_cost_a==avg_cost_b 时恒返回 1（非 0），
  // 违反严格弱序（自反性 cmp(a,a)!=0 / 反对称性），可致 sort_by 未定义行为。
  // 修复：三档比较（< / > / 0），完全相等时按 model 字典序做确定性 tiebreak。
  out.sort_by(fn(a, b) -> Int {
    let rate_a = if a.total > 0 {
      a.success.to_double() / a.total.to_double()
    } else {
      0.0
    }
    let rate_b = if b.total > 0 {
      b.success.to_double() / b.total.to_double()
    } else {
      0.0
    }
    if rate_a > rate_b {
      -1
    } else if rate_a < rate_b {
      1
    } else if a.avg_cost < b.avg_cost {
      -1
    } else if a.avg_cost > b.avg_cost {
      1
    } else if a.model < b.model {
      -1
    } else if a.model > b.model {
      1
    } else {
      0
    }
  })
  out
}

///|
/// 计算简单特征哈希
///
/// BUG-174：原实现 `h = h * 31 + c` 在 Int64 上无检查，约 14 字符以上的 context
/// 必然溢出到极端负值；`h.abs()` 在 `h == Int64.min_value()` 时 MoonBit 未定义（panic）。
/// 修复：每步用 `and 0xFFFFFFFF` 截断到 32 位无符号范围（0..2^32-1），
/// 使 h 恒为非负且不会溢出到极端负值，从而无需 `abs()`。
pub fn caf_feature_hash(context : String) -> Int {
  let mut h : Int = 0
  let mut i = 0
  while i < context.length() {
    let c = context[i].to_int()
    h = (h * 31 + c).land(0xFFFFFFFF)
    i = i + 1
  }
  h
}

///|
/// 取 CafMemory 快照的 JSON（供 model_router_status/usage_report 展示）
pub fn CafMemory::to_json(self : CafMemory) -> Json {
  let all_records = self.all()
  let total = all_records.length()
  let with_model = caf_stats(all_records)
  Json::object({
    "total_records": Json::number(total.to_double()),
    "capacity": Json::number(self.max_size.to_double()),
    "count": Json::number(self.count.to_double()),
    "by_model": Json::array(
      with_model.map(fn(s) {
        Json::object({
          "model": Json::string(s.model),
          "total": Json::number(s.total.to_double()),
          "success": Json::number(s.success.to_double()),
          "avg_cost": Json::number(s.avg_cost),
        })
      }),
    ),
  })
}
