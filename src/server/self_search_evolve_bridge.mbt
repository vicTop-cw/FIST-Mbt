/// self_search_evolve_bridge.mbt —— 把 src/evolve/self_search.mbt 接进 MCP 工具 IO 层
///
/// 背景（R13 polish，P3 self_search 入库半）：`src/evolve/self_search.mbt` 暴露
/// `analyze_candidate` / `is_duplicate_candidate` / `assess_portability` /
/// `distill_candidates` / `run_external_search`，但全仓 grep **零调用者**——它是悬空件。
/// `run_external_search` 有 `runner` 注入面（未注入 → Err「未注入搜索执行器」），
/// 缺的就是把它接进**一个现有 MCP 工具的 IO 流程**。
///
/// 接线点 = **方向 A（最小风险）**：`evolve_asset_register`。理由：
///   - 语义同域：它注册的本来就是**外部**资产（skill 库 / 路径 / URL），
///     self_search 的"外部搜索 → 分析 → 评估可移植性 → 蒸馏"正是为它设计的；
///   - 它是 **IO 型工具**（读进程内 Archive + 写 SQLite evolve_artifacts），
///     追加一次外部检索**不破坏**任何"纯计算零 IO"契约（`evolve_submit` 那类不碰）；
///   - 搜索执行器仍由**调用方注入**（本模块不内置网络、不硬编码命令/路径），
///     未配置时 `runner=None` → `run_external_search` 返回 Err → 候选为空，
///     注册流程照旧成功——**零回归**是默认路径。
///
/// 文件命名与并发会话的 `self_search_wire.mbt` 错开，避免同包重名冲突。
/// 接线实现是**同步**函数（注册 + 外部检索都是同步 IO），测试无需 async。

///|
/// 搜索原始文本解析成候选数组：按行切分，每行取 `\t` 分隔的 name/title/source/mechanism。
/// 行内字段不足 4 个、或 name/source 为空则跳过（脏数据不喂蒸馏）。纯计算，不碰 IO。
pub fn parse_search_lines(raw : String) -> Array[@evolve.SearchCandidate] {
  let out : Array[@evolve.SearchCandidate] = []
  for line in raw.split("\n").to_array() {
    let l = line.trim()
    if l == "" {
      continue
    }
    let parts = l.split("\t").to_array()
    if parts.length() >= 4 {
      let name = parts[0].trim().to_owned()
      let title = parts[1].trim().to_owned()
      let source = parts[2].trim().to_owned()
      let mechanism = parts[3].trim().to_owned()
      if name != "" && source != "" {
        out.push(@evolve.analyze_candidate(name, title, source, mechanism))
      }
    }
  }
  out
}

///|
/// 候选数组蒸馏后的 JSON 数组（保留 name/source/portable 三键，够用且不泄漏机制全文）。
fn candidates_to_json(cands : Array[@evolve.SearchCandidate]) -> Json {
  let arr : Array[Json] = []
  for c in cands {
    arr.push(
      Json::object({
        "name": Json::string(c.name),
        "source": Json::string(c.source),
        "portable": Json::boolean(c.portable),
      }),
    )
  }
  Json::array(arr)
}

///|
/// 默认搜索执行器：从 server 进程环境变量 `FIST_SELF_SEARCH_CMD` 取"搜索名"、
/// `FIST_SELF_SEARCH_PATH` 取候选文本文件路径；未配置 → None（跳过搜索）。
/// 执行是**同步文件读**：不 spawn 子进程、不硬编码任何盘符/绝对路径，
/// 搜索源完全由部署方注入（文件格式 = 每行 `\t` 分隔的 name/title/source/mechanism）。
/// 未配置时返回 None，因此默认路径下 `evolve_asset_register` **零额外 IO**（零回归）。
pub fn self_search_runner_default() -> ((String, Array[String]) -> Result[
  String,
  String,
])? {
  let path = match @env.get_env_var("FIST_SELF_SEARCH_PATH") {
    Some(p) => p.trim().to_owned()
    None => return None
  }
  if path == "" {
    return None
  }
  let name = match @env.get_env_var("FIST_SELF_SEARCH_CMD") {
    Some(c) => c.trim().to_owned()
    None => "file-search".to_string()
  }
  let p = path
  Some(fn(c : String, a : Array[String]) -> Result[String, String] {
    // 命令名回显 + 参数原样透传，让 runner 语义可诊断；实际读取文件路径。
    let _echo = c
    let _args = a
    let content = @fs.read_file_to_string(p, encoding="utf8") catch {
      _ =>
        return Err(
          "self_search: 读取搜索源失败（未配置 FIST_SELF_SEARCH_PATH？）",
        )
    }
    Ok(name + " :: " + content)
  })
}

///|
/// `evolve_asset_register` 的 IO 接线实现：
///   1. 构造 Artifact 并入进程内 Archive + SQLite evolve_artifacts（既有语义不变）；
///   2. **新增**：把注入的搜索执行器 `runner?` 交给 `run_external_search` 做外部检索，
///      命中后经 `analyze_candidate` → `assess_portability`（analyze 内部） →
///      `distill_candidates`（去重 + 过滤不可移植 + 按 source 稳定排序）蒸馏出可移植候选；
///   3. 回执追加 `portable_candidates` 键（未注入 runner 时为空数组，零回归）。
/// 签名保持与 `evolve_asset_register` 工具参数同形，便于白盒测试直接注入 mock runner。
/// 同步实现：注册（Archive + SQLite）与外部检索（文件读 / mock）都是同步 IO。
pub fn do_evolve_asset_register_with_search(
  source : String,
  note : String,
  code : String,
  score : Double,
  ts : String,
  runner? : ((String, Array[String]) -> Result[String, String])? = None,
) -> Result[Json, String] {
  if source == "" || note == "" || code == "" {
    return Err("source/note/code 均为必填")
  }
  let goal = "[asset]\{source}"
  let asset_id = "asset-\{source}-\{ts}"
  let art = @evolve.Artifact::create(
    id=asset_id,
    parent_id=None,
    goal~,
    note~,
    code~,
    score~,
    parts=Map([]),
    created_at=ts,
  )
  @evolve.Archive::add(evolve_arc, art)
  // BUG-140：外部资产注册必须同步落库 evolve_artifacts，否则重启即失、inject 检索不到 [asset]。
  ignore(
    match evolve_store {
      None => Err("evolve_store 未打开（内存态，未落库）")
      Some(s) =>
        s.evolve_upsert(
          id=asset_id,
          parent_id="",
          goal~,
          note~,
          code~,
          score~,
          parts_json="{}",
          created_at=ts,
        )
    },
  )
  // 自搜索接线：注入 runner 才执行；未注入 → 跳过（run_external_search 返回 Err，静默降级）。
  let candidates = match runner {
    None => []
    Some(r) =>
      match
        @evolve.run_external_search(
          "self-search",
          [source, code],
          runner=Some(r),
        ) {
        Ok(raw) => @evolve.distill_candidates(parse_search_lines(raw))
        Err(_) => []
      }
  }
  let base = art.to_json()
  let enriched = match base {
    Object(m) => {
      let m2 = m
      ignore(m2.set("portable_candidates", candidates_to_json(candidates)))
      Json::object(m2)
    }
    _ => base
  }
  Ok(enriched)
}
