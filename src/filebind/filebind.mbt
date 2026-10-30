/// src/filebind/filebind.mbt —— F094 多管家并行的**文件绑定协调层**（纯逻辑，零 IO）
///
/// **它要解决的问题**（docs/features/F094-multi-butler-file-binds.md §一）：两个 agent 同时改
/// 同一文件 = last-write-wins 丢失。物理锁（`lock_acquire`）防的是「同一物理路径的并发写」，
/// 但它回答不了「**谁打算改哪个文件、打算改到什么时候**」——那层是**意图登记**，不是互斥。
///
/// **三层分工（互补，不是重复）**：
///   - `reserve_scope`：命名空间内 scope 字符串的软预订（进程内语义）；
///   - `lock_acquire`：scope + TTL + 违例留痕的**硬互斥**（谁先拿到谁写）；
///   - `file_bind`（本包）：**跨 agent 的意图账**——绑定键 `(ns, project_dir, 相对路径)`，
///     带 holder / 绑定时刻 / TTL / 意图备注。冲突时**点名现持有者**，让调用方自己决定
///     等待 / 换单 / 协商，而不是被一把无法协商的锁直接挡死。
///
/// **为什么纯逻辑**：TTL 过期必须是**可注入的**（判例-31：造竞态不许 `sleep` 抢时序）。
/// 本包所有判定都吃 `now : Int32` 参数 ⇒ 过期/有效可以在同一毫秒内用两个不同 now 断言，
/// 确定性可复现；IO（读账/写账/盖章）留在 `src/server/filebind_tools.mbt`。

///|
/// 一条文件绑定。字段与 F094 §3.1 的 `file_binds` 提案对齐，另加 `ns`（多租户隔离档）与
/// `project_dir`（同一 ns 下多个目标项目各自一本账）—— 这两维是**绑定键**的组成部分。
pub struct FileBind {
  ns : String
  project_dir : String
  path : String
  holder : String
  task_id : String
  kind : String // file | dir
  scope : String // edit | build
  intent : String
  bound_at : Int32 // 服务端盖章（秒）
  ttl_secs : Int32 // <=0 表示不自动过期（调用方显式要「长期持有」）
}

///|
/// 绑定裁决（payload-free，现持有者由调用方从条目/行上取——判例：回执不许由请求反推身份）。
pub enum BindVerdict {
  BndNew // 键空闲 ⇒ 新绑定
  BndRenewed // 同一 holder 重复绑定 ⇒ 幂等续期（重算 TTL，不产生第二条）
  BndReclaimed // 他 holder 但**已过期** ⇒ 接管（过期 ≠ 仍被持有）
  BndConflict // 他 holder 且**仍有效** ⇒ 拒绝，并点名 holder
  BndInvalidPath // 路径不合法（绝对路径 / 含 `..` / 空）⇒ 拒绝，不写账
}

///|
/// 释放裁决。
pub enum ReleaseVerdict {
  RelReleased // 持有者本人释放
  RelForced // 非持有者 + force（必须带理由）
  RelNotHolder // 非持有者且未 force ⇒ 拒绝
  RelNotFound // 该键没有绑定
}

///|
/// 单个路径的绑定计划行（逐条结果 = 调用方要看的那个「逐条」）。
pub struct BindPlanRow {
  path : String
  verdict : BindVerdict
  holder : String // 冲突时 = 现持有者（点名对象）；否则 = 本次请求者
  bound_at : Int32 // 冲突时 = 现持有者的绑定时刻
  ttl_secs : Int32 // 冲突时 = 现持有者的 TTL
}

///|
/// 单个路径的释放计划行。
pub struct ReleaseRow {
  path : String
  verdict : ReleaseVerdict
  holder : String // 冲突时 = 现持有者
}

///|
/// 默认 TTL（秒）：30 分钟。够一次正常的编辑-验证循环，又不至于让中断的 agent 锁一整天。
pub fn fb_default_ttl() -> Int32 {
  1800
}

///|
/// 路径归一（**仅用于键与比较**）：`\\` → `/`，丢掉空段与 `.` 段，剥掉尾部 `/`。
/// **不做**小写化（POSIX 大小写敏感；Windows 上同目录两种大小写极罕见 —— 宁可漏认、不可误认）。
/// **不解析 `..`**：`..` 段原样保留，交给 `fb_path_ok` 拒绝（归一阶段悄悄折叠会把越界洗白）。
pub fn fb_norm(p : String) -> String {
  let s = p.replace_all(old="\\", new="/")
  let mut out = ""
  for seg in s.split("/") {
    let t = seg.trim().to_owned()
    if t != "" && t != "." {
      if out == "" {
        out = t
      } else {
        out = out + "/" + t
      }
    }
  }
  out
}

///|
/// 相对路径白名单（形状判据，不判存在性）：非空、非绝对（无前导 `/`、无 `X:` 盘符）、
/// 归一后仍非空、不含 `..` 段。目录绑定（kind=dir）用同一判据，末尾斜杠由 `fb_norm` 剥掉。
pub fn fb_path_ok(p : String) -> Bool {
  let raw = p.replace_all(old="\\", new="/").trim().to_owned()
  if raw.is_empty() {
    return false
  }
  if raw.has_prefix("/") {
    return false
  }
  if raw.length() >= 2 && raw[1] == ':' {
    return false
  }
  let norm = fb_norm(raw)
  if norm.is_empty() {
    return false
  }
  for seg in norm.split("/") {
    if seg.to_owned() == ".." {
      return false
    }
  }
  true
}

///|
/// 绑定键：`ns|归一 project_dir|归一 path`。三元组而非裸路径——同一物理路径在不同 ns /
/// 不同目标项目下是**不同的绑定位**（ns 是协作的隔离档：不想协调就用不同 ns）。
pub fn fb_key(ns : String, project_dir : String, path : String) -> String {
  ns.trim().to_owned() + "|" + fb_norm(project_dir) + "|" + fb_norm(path)
}

///|
/// 是否过期。`ttl_secs <= 0` ⇒ 永不过期（调用方显式要长期持有）。
/// 判据写成 `now - bound_at` 而不是 `bound_at + ttl`，避免 Int32 相加溢出。
pub fn fb_expired(b : FileBind, now : Int32) -> Bool {
  if b.ttl_secs <= 0 {
    return false
  }
  now - b.bound_at >= b.ttl_secs
}

///|
/// 剩余秒数：`-1` = 永不过期，`0` = 已过期（不返回负数，免得调用方把负数当"负剩余"读）。
pub fn fb_remaining(b : FileBind, now : Int32) -> Int32 {
  if b.ttl_secs <= 0 {
    return -1
  }
  let left = b.bound_at + b.ttl_secs - now
  if left < 0 {
    0
  } else {
    left
  }
}

///|
/// 绑定裁决的**单一真源**（顺序承重）：
///   1. 键空闲 ⇒ `BndNew`；
///   2. **同一 holder 先判续期**（即便已过期也是"本人续期"而不是"接管自己的坟"）；
///   3. 他 holder 且已过期 ⇒ `BndReclaimed`（过期 ≠ 仍被持有，绝不能永远挡路）；
///   4. 他 holder 仍有效 ⇒ `BndConflict`。
pub fn fb_decide(
  existing : FileBind?,
  holder : String,
  now : Int32,
) -> BindVerdict {
  match existing {
    None => BndNew
    Some(b) =>
      if b.holder == holder {
        BndRenewed
      } else if fb_expired(b, now) {
        BndReclaimed
      } else {
        BndConflict
      }
  }
}

///|
/// 释放裁决的**单一真源**：找不到 ⇒ `RelNotFound`；`force` 优先于身份（但仍要理由，由 IO 层
/// 强制非空）：持有者本人 ⇒ `RelReleased`；其他人未 force ⇒ `RelNotHolder`。
pub fn fb_decide_release(
  existing : FileBind?,
  holder : String,
  force : Bool,
) -> ReleaseVerdict {
  match existing {
    None => RelNotFound
    Some(b) =>
      if force {
        RelForced
      } else if b.holder == holder {
        RelReleased
      } else {
        RelNotHolder
      }
  }
}

///|
/// 在**给定账本**里按键找条目（返回下标，纯函数；找不到 = `None`）。
pub fn fb_find_index(
  bs : Array[FileBind],
  ns : String,
  project_dir : String,
  path : String,
) -> Int32? {
  let key = fb_key(ns, project_dir, path)
  let mut i = 0
  while i < bs.length() {
    if fb_key(bs[i].ns, bs[i].project_dir, bs[i].path) == key {
      return Some(i)
    }
    i = i + 1
  }
  None
}

///|
/// 批量绑定计划（**逐条成行**，不在这里改账）。同一批里重复给同一个路径时按顺序叠加：
/// 第一行 `BndNew`，第二行 `BndRenewed`（用一份影子副本模拟"已落账"），不产生两条重复绑定。
pub fn fb_plan_bind(
  existing : Array[FileBind],
  ns : String,
  project_dir : String,
  paths : Array[String],
  holder : String,
  now : Int32,
  ttl_secs : Int32,
) -> Array[BindPlanRow] {
  let rows : Array[BindPlanRow] = []
  // 影子副本：本批次里"已成功绑定"的路径要让后续同路径行看见（否则重复路径会重复 New）。
  let shadow : Array[FileBind] = []
  for b in existing {
    shadow.push(b)
  }
  for p in paths {
    let norm = fb_norm(p)
    if !fb_path_ok(p) {
      rows.push(BindPlanRow::{
        path: p,
        verdict: BndInvalidPath,
        holder,
        bound_at: now,
        ttl_secs,
      })
      continue
    }
    let idx = fb_find_index(shadow, ns, project_dir, norm)
    let existing_one = match idx {
      Some(i) => Some(shadow[i])
      None => None
    }
    let v = fb_decide(existing_one, holder, now)
    let (h, at, ttl) = match existing_one {
      Some(b) =>
        match v {
          BndConflict => (b.holder, b.bound_at, b.ttl_secs)
          _ => (holder, now, ttl_secs)
        }
      None => (holder, now, ttl_secs)
    }
    rows.push(BindPlanRow::{
      path: norm,
      verdict: v,
      holder: h,
      bound_at: at,
      ttl_secs: ttl,
    })
    // 影子推进：非冲突行在"本批次内"已算落账
    match v {
      BndNew | BndRenewed | BndReclaimed => {
        let nb = FileBind::{
          ns,
          project_dir,
          path: norm,
          holder,
          task_id: "",
          kind: "file",
          scope: "edit",
          intent: "",
          bound_at: now,
          ttl_secs,
        }
        match idx {
          Some(i) => shadow[i] = nb
          None => shadow.push(nb)
        }
      }
      _ => ()
    }
  }
  rows
}

///|
/// 把绑定计划落成**新的账本**（纯函数：入参不动，返回新数组；IO 层负责写盘）。
/// 只落 `BndNew` / `BndRenewed` / `BndReclaimed` 三种行；冲突行与非法路径行**一个字节都不写**。
pub fn fb_apply_bind(
  bs : Array[FileBind],
  ns : String,
  project_dir : String,
  rows : Array[BindPlanRow],
  holder : String,
  task_id : String,
  kind : String,
  scope : String,
  intent : String,
  now : Int32,
  ttl_secs : Int32,
) -> Array[FileBind] {
  let out : Array[FileBind] = []
  for b in bs {
    out.push(b)
  }
  for r in rows {
    let keep = match r.verdict {
      BndNew | BndRenewed | BndReclaimed => true
      _ => false
    }
    if keep {
      let nb = FileBind::{
        ns,
        project_dir,
        path: r.path,
        holder,
        task_id,
        kind,
        scope,
        intent,
        bound_at: now,
        ttl_secs,
      }
      let key = fb_key(ns, project_dir, r.path)
      let mut found = false
      let mut i = 0
      while i < out.length() {
        if fb_key(out[i].ns, out[i].project_dir, out[i].path) == key {
          out[i] = nb
          found = true
        }
        i = i + 1
      }
      if !found {
        out.push(nb)
      }
    }
  }
  out
}

///|
/// 释放的筛选面（纯函数）：空串 = 该维不过滤。`paths` 非空时按路径集合收窄，
/// `task_id` 非空时按任务收窄 —— 两个都给就是**交集**（调用方要"这个任务在这些文件上的绑定"）。
pub fn fb_match(
  b : FileBind,
  ns : String,
  project_dir : String,
  paths : Array[String],
  task_id : String,
  scope : String,
) -> Bool {
  if ns != "" && b.ns != ns {
    return false
  }
  if project_dir != "" && fb_norm(b.project_dir) != fb_norm(project_dir) {
    return false
  }
  if scope != "" && b.scope != scope {
    return false
  }
  if task_id != "" && b.task_id != task_id {
    return false
  }
  if paths.length() > 0 {
    let mut hit = false
    for p in paths {
      if fb_norm(b.path) == fb_norm(p) {
        hit = true
      }
    }
    if !hit {
      return false
    }
  }
  true
}

///|
/// 释放计划：对筛选命中项逐条裁决。**未命中**的项不出行（不是"拒了"，是"不归这次管"）。
pub fn fb_plan_release(
  bs : Array[FileBind],
  ns : String,
  project_dir : String,
  paths : Array[String],
  task_id : String,
  scope : String,
  holder : String,
  force : Bool,
) -> Array[ReleaseRow] {
  let rows : Array[ReleaseRow] = []
  for b in bs {
    if fb_match(b, ns, project_dir, paths, task_id, scope) {
      let v = fb_decide_release(Some(b), holder, force)
      rows.push(ReleaseRow::{ path: b.path, verdict: v, holder: b.holder, })
    }
  }
  rows
}

///|
/// 把释放计划落成新账本：只有 `RelReleased` / `RelForced` 行会被移除，`RelNotHolder` 原样保留
/// （拒绝释放 ≠ 悄悄删掉，账必须还在）。
pub fn fb_apply_release(
  bs : Array[FileBind],
  ns : String,
  project_dir : String,
  rows : Array[ReleaseRow],
  task_id : String,
  scope : String,
) -> Array[FileBind] {
  let out : Array[FileBind] = []
  for b in bs {
    let mut drop = false
    for r in rows {
      let remove = match r.verdict {
        RelReleased | RelForced => true
        _ => false
      }
      if remove &&
        fb_norm(b.path) == fb_norm(r.path) &&
        fb_match(b, ns, project_dir, [], task_id, scope) {
        drop = true
      }
    }
    if !drop {
      out.push(b)
    }
  }
  out
}

///|
/// **过期与仍有效分开计数**（BUG-74 同族：两栏不许混读——`total` 大不等于"这么多人在改"，
/// 其中可能有没人释放的过期残留）。返回 `(valid, expired)`。
pub fn fb_counts(bs : Array[FileBind], now : Int32) -> (Int32, Int32) {
  let mut valid = 0
  let mut expired = 0
  for b in bs {
    if fb_expired(b, now) {
      expired = expired + 1
    } else {
      valid = valid + 1
    }
  }
  (valid, expired)
}

///|
/// 裁决 → 稳定的机器可读字符串（回执字段用它，别让调用方去 match 枚举名）。
pub fn fb_verdict_name(v : BindVerdict) -> String {
  match v {
    BndNew => "bound"
    BndRenewed => "renewed"
    BndReclaimed => "reclaimed"
    BndConflict => "conflict"
    BndInvalidPath => "invalid_path"
  }
}

///|
/// 释放裁决 → 字符串。
pub fn fb_release_name(v : ReleaseVerdict) -> String {
  match v {
    RelReleased => "released"
    RelForced => "forced"
    RelNotHolder => "not_holder"
    RelNotFound => "not_found"
  }
}

///|
/// 绑定行 → JSON（回执的单条结果；`ok` 只对成功三态为 true）。
pub fn fb_row_json(r : BindPlanRow, now : Int32) -> Json {
  let ok = match r.verdict {
    BndNew | BndRenewed | BndReclaimed => true
    _ => false
  }
  let m : Map[String, Json] = Map([])
  m.set("path", Json::string(r.path))
  m.set("verdict", Json::string(fb_verdict_name(r.verdict)))
  m.set("ok", Json::boolean(ok))
  m.set("holder", Json::string(r.holder))
  m.set("bound_at", Json::number(r.bound_at.to_double()))
  m.set("ttl_secs", Json::number(r.ttl_secs.to_double()))
  let left = if r.ttl_secs <= 0 {
    -1
  } else {
    let x = r.bound_at + r.ttl_secs - now
    if x < 0 {
      0
    } else {
      x
    }
  }
  m.set("remaining_secs", Json::number(left.to_double()))
  Json::object(m)
}

///|
/// 账本条目的 JSON 形状（写盘与回执共用同一个构造点）。
pub fn fb_entry_json(b : FileBind) -> Json {
  let m : Map[String, Json] = Map([])
  m.set("ns", Json::string(b.ns))
  m.set("project_dir", Json::string(b.project_dir))
  m.set("path", Json::string(b.path))
  m.set("holder", Json::string(b.holder))
  m.set("task_id", Json::string(b.task_id))
  m.set("kind", Json::string(b.kind))
  m.set("scope", Json::string(b.scope))
  m.set("intent", Json::string(b.intent))
  m.set("bound_at", Json::number(b.bound_at.to_double()))
  m.set("ttl_secs", Json::number(b.ttl_secs.to_double()))
  Json::object(m)
}

///|
/// 状态行：条目 + 派生读数（`expired` / `remaining_secs`）。**过期项不隐藏**——
/// 隐藏了就没人知道"这个文件还被一个死掉的 agent 占着"。
pub fn fb_status_json(b : FileBind, now : Int32) -> Json {
  let m : Map[String, Json] = Map([])
  m.set("ns", Json::string(b.ns))
  m.set("project_dir", Json::string(b.project_dir))
  m.set("path", Json::string(b.path))
  m.set("holder", Json::string(b.holder))
  m.set("task_id", Json::string(b.task_id))
  m.set("kind", Json::string(b.kind))
  m.set("scope", Json::string(b.scope))
  m.set("intent", Json::string(b.intent))
  m.set("bound_at", Json::number(b.bound_at.to_double()))
  m.set("ttl_secs", Json::number(b.ttl_secs.to_double()))
  m.set("expired", Json::boolean(fb_expired(b, now)))
  m.set("remaining_secs", Json::number(fb_remaining(b, now).to_double()))
  Json::object(m)
}

///|
/// JSON → 条目。缺字段给安全默认值；`path` 或 `holder` 为空的条目视为坏条目（返回 None）。
pub fn fb_of_json(j : Json) -> FileBind? {
  let path = fb_js(j, "path")
  let holder = fb_js(j, "holder")
  if path == "" || holder == "" {
    return None
  }
  Some(FileBind::{
    ns: fb_js(j, "ns"),
    project_dir: fb_js(j, "project_dir"),
    path,
    holder,
    task_id: fb_js(j, "task_id"),
    kind: fb_js(j, "kind"),
    scope: fb_js(j, "scope"),
    intent: fb_js(j, "intent"),
    bound_at: fb_ji(j, "bound_at"),
    ttl_secs: fb_ji(j, "ttl_secs"),
  })
}

///|
/// 取字符串字段（非对象/非字符串一律空串）。
fn fb_js(j : Json, key : String) -> String {
  match j {
    Object(m) =>
      match m.get(key) {
        Some(String(s)) => s
        _ => ""
      }
    _ => ""
  }
}

///|
/// 取整数字段（缺省 0）。
fn fb_ji(j : Json, key : String) -> Int32 {
  match j {
    Object(m) =>
      match m.get(key) {
        Some(Number(n, ..)) => n.to_int()
        _ => 0
      }
    _ => 0
  }
}

///|
/// 解析账本正文。**坏 JSON / 形状不对一律返回空**（由 IO 层决定如何报告——绝不"顺手清账"：
/// 坏账是证据，不是垃圾）。兼容两种形状：`{"version":1,"entries":[…]}` 与裸数组。
pub fn fb_ledger_parse(raw : String) -> Array[FileBind] {
  let out : Array[FileBind] = []
  if raw.trim() == "" {
    return out
  }
  let v = @json.parse(raw) catch { _ => return out }
  let arr = match v {
    Object(m) =>
      match m.get("entries") {
        Some(Array(a)) => a
        _ => []
      }
    Array(a) => a
    _ => []
  }
  for j in arr {
    match fb_of_json(j) {
      Some(b) => out.push(b)
      None => ()
    }
  }
  out
}

///|
/// 序列化账本（唯一构造点；`version` 给未来迁移留位）。
pub fn fb_ledger_serialize(bs : Array[FileBind]) -> String {
  let arr : Array[Json] = []
  for b in bs {
    arr.push(fb_entry_json(b))
  }
  let m : Map[String, Json] = Map([])
  m.set("version", Json::number(1.0))
  m.set("entries", Json::array(arr))
  Json::object(m).stringify()
}
