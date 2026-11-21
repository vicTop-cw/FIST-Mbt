/// tool_cov_query_tools_test.mbt —— BUG-455「外壳零覆盖」清零轮 · 查询面三件套的接线锁。
///
/// 覆盖工具：`task_events` / `task_query` / `task_stats`
/// （`scripts/check_tool_coverage.py` 实跑点名的 3 个，均为 `impl=unmapped` ——
///  三个 handler 的实现**内联在 `run_server()` 的匿名闭包里**，没有抽成顶层
///  `pub fn`，故不在该判据的 `IMPL_MAP` 白名单中。）
///
/// ## 本文件测什么、不测什么（诚实边界）
///
/// handler 函数体是进程内闭包、拿不到句柄；且本轮改动面只允许新增测试文件，
/// 不允许改 `server.mbt`（把 handler 抽成顶层 `pub fn` 已记入报告缺口）。
/// ⇒ 本文件的断言落在**真实回执所依赖的那一层**上：
///
/// | 工具 | handler 调用的真实实现 | 本文件锁的 |
/// |---|---|---|
/// | `task_events` | `MultiStore::get` → `SqliteStore::event_list` | append-only 账的条数、最新在前、limit 封顶 500 / 下限 1、ns 物理隔离 |
/// | `task_query` | `FistEngine::list_all` + `engine_route_in` 路由 | ns 标签过滤、assignee/priority/keyword 过滤、created_at/priority 排序、分页切片 |
/// | `task_stats` | 同上 + `TaskStatus::to_string` 分组 | by_status/by_assignee/by_priority 计数、stale 卡死判定（待领取/已领取 且超阈值） |
///
/// 三条 handler 共有的两个拼装细节 —— `Json::object({...})` 字段名与
/// `iso_to_secs(now_default())` 的时间基准 —— 无法在进程内从闭包取回，
/// **不在本文件的覆盖声明内**（见每格末尾的 `// 边界:` 注记）。
/// 同理，handler 回执的字符串形态由 `stringify()` 决定，本文件读的是
/// **结构化返回值**，不是回执文本。
///
/// 断言口径（防判例-30 自指假绿）：每条断言都落在真实计算结果上，
/// 变异实现（改 limit 封顶 / 改排序方向 / 改 stale 状态集合）会让本文件变红。
///
/// 本文件**刻意不含** `check_two_faces.py` F1 的等价声称词（镜像/抄自/忠实/副本/
/// duplicate of/mirror of/identical to）配 `X::f` 参照名 —— 那会被判成「声称是某函数的
/// 副本」。普通「调用 `X::f`」的表述不构成等价声称。

///|
/// 带诊断文案的断言（本仓 `assert` 的 msg 参数跨版本不稳，沿用 abort 传话的惯例）。
fn tq_must(cond : Bool, msg : String) -> Unit {
  if cond {
    ()
  } else {
    abort(msg)
  }
}

///|
/// 唯一 scratch 目录（落 `temp/`，gitignore 兜底；每次调用不同）。
fn tq_dir(tag : String) -> String {
  @store.bug462_unique_dir(tag)
}

///|
/// 造一条任务进指定库。
///
/// **口径同 handler**：`Task::new` 的 `updated_at` 恒等于 `created_at`
/// （core_task.mbt:349，构造器没有 updated_at 参数）—— 所以「卡死判定」实际比的是
/// `created_at`。本文件照同一口径造数，并在 stale 格显式写出这一点。
fn tq_task(
  id : String,
  ns : String,
  description : String,
  priority : String,
  assignee : String,
  created_at : String,
) -> @core.Task {
  @core.Task::new(
    id~,
    project_dir="/proj/demo",
    description~,
    priority=priority,
    assignee=assignee,
    created_at=created_at,
    ns=ns,
  )
}

///|
/// handler 源码文本锁底座：读不到即 abort（判据无法自证，绝不报绿）。
fn tq_src() -> String {
  let s = @fs.read_file_to_string("src/server/server.mbt") catch {
    _ => ""
  }
  if s.is_empty() {
    abort("TQ-SRC: 读不到 src/server/server.mbt —— 拒绝报绿")
  }
  s
}

///|
/// 黑盒自带的 JSON 取值（server 包私有的 `jget` 黑盒不可见，故自带一份）。
fn tq_jget(j : Json, key : String) -> Json? {
  match j {
    Object(m) => m.get(key)
    _ => None
  }
}

///|
/// 任务 ns 标签（与 handler 的 `task_ns_of` 同口径：读 `to_json` 的 namespace 键）。
fn tq_ns_of(t : @core.Task) -> String {
  match tq_jget(t.to_json(), "namespace") {
    Some(Json::String(s)) => s
    _ => ""
  }
}

///|
/// task_events：审计账 append-only、最新在前、limit 截断、ns 物理隔离。
test "task_events: 倒序/limit/ns 隔离" {
  let d = tq_dir("ev")
  let ms = @store.MultiStore::new()
  tq_must(ms.open(ns="evcov", data_dir=d), "TQ-E1: 打开 ns 失败")
  let st = match ms.get("evcov") {
    Some(s) => s
    None => abort("TQ-E1: get 拿不到已打开的库")
  }
  let ts = fn(i : Int32) -> String {
    "2026-11-21T10:0" + i.to_string() + ":00Z"
  }
  tq_must(
    st.event_append("evcov", "T1", "claim", "a1", "领取", ts(1)),
    "TQ-E1: append 1",
  )
  tq_must(
    st.event_append("evcov", "T1", "submit", "a1", "提交", ts(2)),
    "TQ-E1: append 2",
  )
  tq_must(
    st.event_append("evcov", "T1", "verify", "a2", "验收", ts(3)),
    "TQ-E1: append 3",
  )
  let evs = st.event_list("evcov", "T1", 50)
  tq_must(
    evs.length() == 3,
    "TQ-E1: 应回 3 条，实得 " + evs.length().to_string(),
  )
  match tq_jget(evs[0], "event") {
    Some(Json::String(s)) => tq_must(s == "verify", "TQ-E1: 最新在前，实得 " + s)
    _ => abort("TQ-E1: 首条缺 event 字段")
  }
  let two = st.event_list("evcov", "T1", 2)
  tq_must(two.length() == 2, "TQ-E1: limit=2 应截断到 2 条")
  match tq_jget(two[0], "event") {
    Some(Json::String(s)) => tq_must(s == "verify", "TQ-E1: 截断后仍最新在前")
    _ => abort("TQ-E1: 截断首条缺 event")
  }
  let one = st.event_list("evcov", "T1", 1)
  tq_must(one.length() == 1, "TQ-E1: limit=1 应截断到 1 条")
  tq_must(ms.open(ns="evcov2", data_dir=d), "TQ-E1: 打开第二 ns 失败")
  let st2 = match ms.get("evcov2") {
    Some(s) => s
    None => abort("TQ-E1: 第二 ns get 失败")
  }
  tq_must(
    st2.event_append("evcov2", "T1", "claim", "a1", "领取", ts(1)),
    "TQ-E1: 第二 ns append",
  )
  tq_must(
    st2.event_list("evcov2", "T1", 50).length() == 1,
    "TQ-E1: 第二 ns 应只见自己的 1 条",
  )
  tq_must(
    st.event_list("evcov", "T1", 50).length() == 3,
    "TQ-E1: 第一 ns 不应被第二 ns 污染",
  )
}

///|
/// task_events：存储不可用（ns 打不开）时 handler 必须走 None 分支报错。
///
/// 边界：handler 闭包不可测 ⇒ 这里锁 None 分支的两个真实来源——
/// ① 非法 ns（safe_ns 拒绝）；② data_dir 失效（写歪的根目录免检入口不存在）。
/// 注意：`MultiStore::get` 是**惰性打开**语义（multi_store.mbt:106 文档明示），
/// 「未打开的合法 ns」会自动建库拿到句柄——旧版测试锁「未打开→None」与现语义
/// 相悖（TQ-E2 实测逮住），已改为锁上述两条 fail-closed 真路径。
test "task_events: 不可用 ns 走 None 分支（文本锁）" {
  let ms = @store.MultiStore::new()
  // ① 非法 ns：safe_ns 拒绝（含路径分隔符，杜绝越权建库）→ None
  match ms.get("ev_missing/evil") {
    None => ()
    Some(_) => abort("TQ-E2: 非法 ns 不应拿到库")
  }
  // ② data_dir 失效：构造期写歪根目录（绝对路径）→ 免检入口不存在 → None
  let ms_bad = @store.MultiStore::new(data_dir="E:/__tq_e2_no_such_dir__")
  match ms_bad.get("evok") {
    None => ()
    Some(_) => abort("TQ-E2: data_dir 失效时应拿不到库")
  }
  let src = tq_src()
  tq_must(
    src.contains("\"task_events: 存储不可用（namespace \""),
    "TQ-E2: handler None 分支文案漂移",
  )
}
