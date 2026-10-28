///|
/// evolve/github_client.mbt —— GitHub 搜索 API 客户端（L43，供 self_search 使用）
///
/// 原则：纯计算，零网络、零 token。HTTP 执行由调用方通过 `fetch` 注入；
/// 本模块只负责：构造请求 URL/参数 + 把 GitHub API JSON 响应解析为 self_search
/// 的 `SearchCandidate` 数组。这样 self_search 模块可以直接消费结果，
/// 走 distill_candidates 去重+可移植性过滤。

///|
/// GitHub 仓库搜索结果项
pub struct GhRepo {
  full_name : String // owner/repo
  description : String
  stargazers_count : Int32
  language : String
  html_url : String
  topics : Array[String]
}

///|
/// GitHub 代码搜索结果项
pub struct GhCode {
  repository : String // owner/repo
  path : String
  html_url : String
  score : Double
}

///|
/// 构造 GitHub 仓库搜索 API URL
///   query: 搜索关键词（如 "moonbit ltl parser"）
///   per_page: 每页条数（1~100，默认 30）
///   sort: 排序字段（"stars"/"updated"/""，空=默认 best match）
fn clamp_pp(n : Int32) -> Int32 {
  if n < 1 {
    1
  } else if n > 100 {
    100
  } else {
    n
  }
}

///|
/// 构造 GitHub 仓库搜索 API URL
///   query: 搜索关键词（如 "moonbit ltl parser"）
///   per_page: 每页条数（1~100，默认 30）
///   sort: 排序字段（"stars"/"updated"/""，空=默认 best match）
pub fn repo_search_url(
  query : String,
  per_page~ : Int32 = 30,
  sort~ : String = "",
) -> String {
  let q = query.trim().to_owned()
  let pp = clamp_pp(per_page)
  let sort_param = if sort.length() > 0 { "&sort=" + sort } else { "" }
  "https://api.github.com/search/repositories?q=" +
  q +
  "&per_page=" +
  pp.to_string() +
  sort_param
}

///|
/// 构造 GitHub 代码搜索 API URL
pub fn code_search_url(query : String, per_page~ : Int32 = 30) -> String {
  let q = query.trim().to_owned()
  let pp = clamp_pp(per_page)
  "https://api.github.com/search/code?q=" + q + "&per_page=" + pp.to_string()
}

///|
/// 构造 GitHub topic 搜索 API URL
pub fn topic_search_url(topic : String, per_page~ : Int32 = 30) -> String {
  let t = topic.trim().to_owned()
  let pp = clamp_pp(per_page)
  "https://api.github.com/search/repositories?q=topic:" +
  t +
  "&per_page=" +
  pp.to_string()
}

///|
/// 解析 GitHub 仓库搜索 API 的 JSON 响应为 GhRepo 数组
/// 容错：任何解析失败都跳过该项，不崩溃
pub fn parse_repo_search(json_text : String) -> Array[GhRepo] {
  let out : Array[GhRepo] = []
  let j = @json.parse(json_text) catch { _ => Json::null() }
  let items = match j {
    Object(m) =>
      match m.get("items") {
        Some(Array(a)) => a
        _ => []
      }
    _ => []
  }
  for item in items {
    match item {
      Object(im) => {
        let full_name = match im.get("full_name") {
          Some(String(s)) => s
          _ => ""
        }
        let description = match im.get("description") {
          Some(String(s)) => s
          _ => ""
        }
        let stars = match im.get("stargazers_count") {
          Some(Number(n, ..)) => n.to_int()
          _ => 0
        }
        let language = match im.get("language") {
          Some(String(s)) => s
          _ => ""
        }
        let html_url = match im.get("html_url") {
          Some(String(s)) => s
          _ => ""
        }
        let topics = match im.get("topics") {
          Some(Array(a)) =>
            a.filter_map(fn(t) {
              match t {
                String(s) => Some(s)
                _ => None
              }
            })
          _ => []
        }
        if full_name.length() > 0 {
          out.push({
            full_name,
            description,
            stargazers_count: stars,
            language,
            html_url,
            topics,
          })
        }
      }
      _ => ()
    }
  }
  out
}

///|
/// 解析 GitHub 代码搜索 API 的 JSON 响应为 GhCode 数组
pub fn parse_code_search(json_text : String) -> Array[GhCode] {
  let out : Array[GhCode] = []
  let j = @json.parse(json_text) catch { _ => Json::null() }
  let items = match j {
    Object(m) =>
      match m.get("items") {
        Some(Array(a)) => a
        _ => []
      }
    _ => []
  }
  for item in items {
    match item {
      Object(im) => {
        let repo = match im.get("repository") {
          Some(Object(rm)) =>
            match rm.get("full_name") {
              Some(String(s)) => s
              _ => ""
            }
          _ => ""
        }
        let path = match im.get("path") {
          Some(String(s)) => s
          _ => ""
        }
        let html_url = match im.get("html_url") {
          Some(String(s)) => s
          _ => ""
        }
        let score = match im.get("score") {
          Some(Number(n, ..)) => n
          _ => 0.0
        }
        if repo.length() > 0 {
          out.push({ repository: repo, path, html_url, score, })
        }
      }
      _ => ()
    }
  }
  out
}

///|
/// 把 GhRepo 数组转成 self_search 的 SearchCandidate 数组
///   - name = full_name
///   - title = full_name (description 可附在 mechanism)
///   - source = "gh"
///   - mechanism = description + language + topics（供可移植性评估）
pub fn repos_to_candidates(repos : Array[GhRepo]) -> Array[SearchCandidate] {
  repos.map(fn(r) {
    let mech = r.description +
      " | lang:" +
      r.language +
      " | topics:" +
      r.topics.join(",")
    analyze_candidate(r.full_name, r.full_name, "gh", mech)
  })
}

///|
/// 把 GhCode 数组转成 self_search 的 SearchCandidate 数组
///   - name = repository:path
///   - source = "gh-code"
///   - mechanism = path（供可移植性评估，含 "extract" 等词时可判可移植）
pub fn code_to_candidates(codes : Array[GhCode]) -> Array[SearchCandidate] {
  codes.map(fn(c) {
    let name = c.repository + ":" + c.path
    let mech = "extract " + c.path + " from " + c.repository
    analyze_candidate(name, name, "gh-code", mech)
  })
}

///|
/// 一站式：把仓库搜索 JSON 响应直接蒸馏为可移植候选
/// （parse → to_candidates → distill）
pub fn distill_repo_search(json_text : String) -> Array[SearchCandidate] {
  let repos = parse_repo_search(json_text)
  let cands = repos_to_candidates(repos)
  distill_candidates(cands)
}

///|
/// 一站式：把代码搜索 JSON 响应直接蒸馏为可移植候选
pub fn distill_code_search(json_text : String) -> Array[SearchCandidate] {
  let codes = parse_code_search(json_text)
  let cands = code_to_candidates(codes)
  distill_candidates(cands)
}

///|
/// 把 SearchCandidate 数组转成 TSV 行文本（name\ttitle\tsource\tmechanism），
/// 供 run_external_search 的行解析器消费。纯计算，不碰 IO。
///   - portable=false 的候选也输出（让下游 distill 决定过滤，不在这里硬编码门槛）
///   - 字段内含 Tab 替换为空格，防止破坏行解析
pub fn candidates_to_tsv_lines(cands : Array[SearchCandidate]) -> String {
  let lines : Array[String] = []
  for c in cands {
    let name = c.name.replace_all(old="\t", new=" ")
    let title = c.title.replace_all(old="\t", new=" ")
    let source = c.source.replace_all(old="\t", new=" ")
    let mech = c.mechanism.replace_all(old="\t", new=" ")
    lines.push(name + "\t" + title + "\t" + source + "\t" + mech)
  }
  lines.join("\n")
}

///|
/// 端到端：GitHub 仓库搜索 JSON → TSV 行（可直接喂 run_external_search 的行解析器）
pub fn repo_search_to_tsv(json_text : String) -> String {
  let repos = parse_repo_search(json_text)
  let cands = repos_to_candidates(repos)
  candidates_to_tsv_lines(cands)
}

///|
/// 端到端：GitHub 代码搜索 JSON → TSV 行
pub fn code_search_to_tsv(json_text : String) -> String {
  let codes = parse_code_search(json_text)
  let cands = code_to_candidates(codes)
  candidates_to_tsv_lines(cands)
}

///|
/// 把 run_external_search 的原始输出（curl 返回的 GitHub JSON 文本）
/// 直接转成 self_search 可消费的 TSV 行。
///   - 自动判断是仓库搜索还是代码搜索 JSON（看 items[0] 是否含 full_name 顶层字段）
///   - 解析失败或空 items → 返回空串（下游 distill 得到空数组，零回归）
pub fn github_json_to_tsv(json_text : String) -> String {
  let repos = parse_repo_search(json_text)
  if repos.length() > 0 {
    return repo_search_to_tsv(json_text)
  }
  let codes = parse_code_search(json_text)
  if codes.length() > 0 {
    return code_search_to_tsv(json_text)
  }
  ""
}

///|
/// 生成 curl 命令（供外部执行，不内置网络）
///   - token 留空则不带 Authorization header（匿名，限流 60/h）
///   - 不回显 token 本体
pub fn curl_repo_search(query : String, token~ : String = "") -> String {
  let url = repo_search_url(query)
  let auth = if token.length() > 0 {
    " -H \"Authorization: Bearer ***\""
  } else {
    ""
  }
  "curl -s -H \"Accept: application/vnd.github+json\"" +
  auth +
  " \"" +
  url +
  "\""
}
