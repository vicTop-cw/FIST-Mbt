// github_client 白盒测试（L43，供 self_search 使用）

///|
test "repo_search_url 默认参数" {
  let url = repo_search_url("moonbit parser")
  assert_true(url.contains("search/repositories"))
  assert_true(url.contains("q=moonbit parser"))
  assert_true(url.contains("per_page=30"))
}

///|
test "repo_search_url 自定义 per_page 和 sort" {
  let url = repo_search_url("ltl", per_page=50, sort="stars")
  assert_true(url.contains("per_page=50"))
  assert_true(url.contains("sort=stars"))
}

///|
test "repo_search_url per_page 越界钳制" {
  let url = repo_search_url("x", per_page=999)
  assert_true(url.contains("per_page=100"))
  let url2 = repo_search_url("x", per_page=0)
  assert_true(url2.contains("per_page=1"))
}

///|
test "code_search_url 结构" {
  let url = code_search_url("moonbit lang:moonbit")
  assert_true(url.contains("search/code"))
  assert_true(url.contains("q=moonbit lang:moonbit"))
}

///|
test "topic_search_url 结构" {
  let url = topic_search_url("moonbit")
  assert_true(url.contains("q=topic:moonbit"))
}

///|
test "parse_repo_search 解析正常响应" {
  let json = "{\"items\":[{\"full_name\":\"owner/repo\",\"description\":\"a parser\",\"stargazers_count\":100,\"language\":\"MoonBit\",\"html_url\":\"https://github.com/owner/repo\",\"topics\":[\"parser\",\"ltl\"]}]}"
  let repos = parse_repo_search(json)
  assert_eq(repos.length(), 1)
  assert_eq(repos[0].full_name, "owner/repo")
  assert_eq(repos[0].stargazers_count, 100)
  assert_eq(repos[0].language, "MoonBit")
  assert_eq(repos[0].topics.length(), 2)
}

///|
test "parse_repo_search 空响应返回空数组" {
  let repos = parse_repo_search("")
  assert_eq(repos.length(), 0)
}

///|
test "parse_repo_search 非法 JSON 返回空数组" {
  let repos = parse_repo_search("not json")
  assert_eq(repos.length(), 0)
}

///|
test "parse_repo_search 缺字段容错" {
  let json = "{\"items\":[{\"full_name\":\"a/b\"}]}"
  let repos = parse_repo_search(json)
  assert_eq(repos.length(), 1)
  assert_eq(repos[0].description, "")
  assert_eq(repos[0].stargazers_count, 0)
}

///|
test "parse_code_search 解析正常响应" {
  let json = "{\"items\":[{\"repository\":{\"full_name\":\"owner/repo\"},\"path\":\"src/main.mbt\",\"html_url\":\"https://github.com/owner/repo/blob/main/src/main.mbt\",\"score\":1.5}]}"
  let codes = parse_code_search(json)
  assert_eq(codes.length(), 1)
  assert_eq(codes[0].repository, "owner/repo")
  assert_eq(codes[0].path, "src/main.mbt")
}

///|
test "repos_to_candidates 生成候选" {
  let repos = [
    {
      full_name: "o/r",
      description: "extract reusable parser",
      stargazers_count: 10,
      language: "MoonBit",
      html_url: "u",
      topics: ["parser"],
    },
  ]
  let cands = repos_to_candidates(repos)
  assert_eq(cands.length(), 1)
  assert_eq(cands[0].name, "o/r")
  assert_eq(cands[0].source, "gh")
}

///|
test "code_to_candidates 生成候选" {
  let codes = [
    { repository: "o/r", path: "src/x.mbt", html_url: "u", score: 1.0, },
  ]
  let cands = code_to_candidates(codes)
  assert_eq(cands.length(), 1)
  assert_eq(cands[0].source, "gh-code")
  assert_true(cands[0].name.contains("o/r:src/x.mbt"))
}

///|
test "distill_repo_search 过滤不可移植" {
  // description 含 "extract" → 可移植
  let json = "{\"items\":[{\"full_name\":\"a/b\",\"description\":\"extract reusable module\",\"stargazers_count\":0,\"language\":\"\",\"html_url\":\"\",\"topics\":[]},{\"full_name\":\"c/d\",\"description\":\"xyz\",\"stargazers_count\":0,\"language\":\"\",\"html_url\":\"\",\"topics\":[]}]}"
  let cands = distill_repo_search(json)
  // c/d 描述过短且无移植词 → 被过滤
  assert_true(cands.length() <= 1)
}

///|
test "distill_code_search 去重" {
  let json = "{\"items\":[{\"repository\":{\"full_name\":\"a/b\"},\"path\":\"p.mbt\",\"html_url\":\"\",\"score\":1.0},{\"repository\":{\"full_name\":\"a/b\"},\"path\":\"p.mbt\",\"html_url\":\"\",\"score\":1.0}]}"
  let cands = distill_code_search(json)
  // 两个相同 (name, source) → 去重后剩 1
  assert_eq(cands.length(), 1)
}

///|
test "curl_repo_search 匿名不带 token" {
  let cmd = curl_repo_search("moonbit")
  assert_true(cmd.contains("curl"))
  assert_false(cmd.contains("Authorization"))
}

///|
test "curl_repo_search 带 token 不回显" {
  let cmd = curl_repo_search("moonbit", token="secret123")
  assert_true(cmd.contains("Authorization"))
  assert_false(cmd.contains("secret123"))
}

///|
test "candidates_to_tsv_lines 输出 TSV 格式" {
  let cands = [
    analyze_candidate("o/r", "o/r", "gh", "extract reusable"),
    analyze_candidate("a/b", "a/b", "gh-code", "extract p.mbt"),
  ]
  let tsv = candidates_to_tsv_lines(cands)
  let lines = tsv.split("\n").to_array()
  assert_eq(lines.length(), 2)
  let parts = lines[0].split("\t").to_array()
  assert_eq(parts.length(), 4)
  assert_eq(parts[0], "o/r")
  assert_eq(parts[2], "gh")
}

///|
test "candidates_to_tsv_lines 替换 Tab 防破坏" {
  let cands = [analyze_candidate("a\tb", "t", "gh", "mech")]
  let tsv = candidates_to_tsv_lines(cands)
  let lines = tsv.split("\n").to_array()
  let parts = lines[0].split("\t").to_array()
  // name 里的 Tab 被替换成空格，所以 parts 仍是 4 个
  assert_eq(parts.length(), 4)
}

///|
test "repo_search_to_tsv 端到端" {
  let json = "{\"items\":[{\"full_name\":\"o/r\",\"description\":\"extract parser\",\"stargazers_count\":10,\"language\":\"MoonBit\",\"html_url\":\"\",\"topics\":[]}]}"
  let tsv = repo_search_to_tsv(json)
  let lines = tsv.split("\n").to_array()
  assert_eq(lines.length(), 1)
  assert_true(lines[0].contains("o/r"))
  assert_true(lines[0].contains("gh"))
}

///|
test "code_search_to_tsv 端到端" {
  let json = "{\"items\":[{\"repository\":{\"full_name\":\"o/r\"},\"path\":\"p.mbt\",\"html_url\":\"\",\"score\":1.0}]}"
  let tsv = code_search_to_tsv(json)
  let lines = tsv.split("\n").to_array()
  assert_eq(lines.length(), 1)
  assert_true(lines[0].contains("gh-code"))
}
