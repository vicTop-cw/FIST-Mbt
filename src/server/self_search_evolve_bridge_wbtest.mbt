/// self_search_evolve_bridge_wbtest.mbt —— 白盒锁：evolve_asset_register 的 IO 流程
/// 真的触达 src/evolve/self_search.mbt（接线后不再是孤代码）
///
/// 锁三件事：
///   1. `do_evolve_asset_register_with_search`（evolve_asset_register 的 IO 实现）在
///      注入 runner 时**确实**调用了 `@evolve.run_external_search`——用 mock runner
///      记录 (cmd, args) 并回喂候选文本，断言调用发生；
///   2. 候选文本经 `analyze_candidate`（内含 `assess_portability`）与
///      `distill_candidates` 蒸馏后，`portable_candidates` 只保留 portable=true 的
///      **去重后**集合——用**成员/计数断言**锁"去重 + 过滤不可移植"两个语义，
///      不断言 `distill_candidates` 内部排序方向（并发会话正在调整该排序，本锁不站队）；
///   3. 未注入 runner（默认 None）→ 跳过搜索，注册照常成功且 `portable_candidates` 为空
///      （零回归契约锁：外部搜索未配置时不给 IO 加负担）。
///
/// 全部走内存 Archive + 现有 evolve_store（本包模块级），不 spawn 任何子进程。

///|
fn wiring_mock_runner(
  hits : Array[String],
) -> (Array[String], (String, Array[String]) -> Result[String, String]) {
  let calls : Array[String] = []
  let r = fn(cmd : String, args : Array[String]) -> Result[String, String] {
    calls.push("cmd=" + cmd + ";args=" + args.join(","))
    if hits.is_empty() {
      Err("mock: no hits")
    } else {
      Ok(hits.join("\n"))
    }
  }
  (calls, r)
}

///|
fn json_field(j : Json, key : String) -> Json {
  match j {
    Object(m) =>
      match m.get(key) {
        Some(v) => v
        None => Json::null()
      }
    _ => Json::null()
  }
}

///|
/// 取字段的 Json::Array 视图（测试用；非数组字段回退空数组）。
fn json_field_array(j : Json, key : String) -> Array[Json] {
  match j {
    Object(m) =>
      match m.get(key) {
        Some(Json::Array(a)) => a
        _ => []
      }
    _ => []
  }
}

///|
test "evolve_asset_register 注入 runner 后确实触达 self_search 并蒸馏出可移植候选" {
  let hits = [
    "wrapper-lib\t可移植封装库\tcrate\texposes a reusable wrapper", "tiny\t短描述\tblogs\thi",
    "wrapper-lib\t重复同键\tcrate\tduplicate candidate", "alpha\t先出现\tcrate\tadapt the wrapper",
    "beta\t后出现\tgh\tporting a reusable mechanism",
  ]
  let (calls, runner) = wiring_mock_runner(hits)
  let j = do_evolve_asset_register_with_search(
    "wireup-test",
    "接线自检提示词",
    "https://example.invalid/wireup",
    0.6,
    "2026-10-13T16:00:00Z",
    runner=Some(runner),
  )
  match j {
    Err(e) => abort("wiring test Err: " + e)
    Ok(j) => {
      // 1) self_search 真被调用：mock runner 收到 "self-search" + [source, code]
      assert_eq(calls.length(), 1)
      assert_true(calls[0].contains("cmd=self-search"))
      assert_true(
        calls[0].contains("args=wireup-test,https://example.invalid/wireup"),
      )
      // 2) 注册本身照常发生（既有语义不回归）
      assert_true(
        json_field(j, "goal").stringify().contains("[asset]wireup-test"),
      )
      assert_true(
        json_field(j, "id").stringify().contains("asset-wireup-test-"),
      )
      // 3) 蒸馏结果（成员 + 计数断言，不依赖 distill 内部排序方向）：
      //    去重 → {wrapper-lib, alpha, beta}；过滤 → 去掉不可移植的 tiny（机制 "hi" 过短）。
      let arr = json_field_array(j, "portable_candidates")
      assert_eq(arr.length(), 3)
      let names = arr.map(fn(x) { json_field(x, "name").stringify() })
      assert_true(names.contains("\"alpha\""))
      assert_true(names.contains("\"beta\""))
      assert_true(names.contains("\"wrapper-lib\""))
      // 去重：wrapper-lib 只出现一次
      let wl_count = names.filter(fn(n) { n == "\"wrapper-lib\"" }).length()
      assert_eq(wl_count, 1)
      // 每条都确实是可移植的
      for x in arr {
        assert_true(json_field(x, "portable") == Json::boolean(true))
      }
      // 4) 蒸馏结果里"tiny"（不可移植）被过滤掉
      assert_true(!Json::array(arr).stringify().contains("tiny"))
    }
  }
}

///|
test "evolve_asset_register 未注入 runner 时跳过 self_search，注册零回归" {
  let j = do_evolve_asset_register_with_search(
    "wireup-none",
    "零回归提示词",
    "docs/code-review.md",
    0.5,
    "2026-10-13T16:01:00Z",
    runner=None,
  )
  match j {
    Err(e) => abort("wiring none Err: " + e)
    Ok(j) => {
      assert_true(
        json_field(j, "goal").stringify().contains("[asset]wireup-none"),
      )
      // 默认无 runner → 候选为空，注册成功，无外部 IO
      assert_eq(json_field_array(j, "portable_candidates").length(), 0)
    }
  }
}

///|
test "self_search_runner_default 未配置环境变量时返回 None（不硬编码、不默认 spawn）" {
  // 测试进程内不设置 FIST_SELF_SEARCH_PATH/CMD，默认路径必须 None（跳过搜索）
  let r = self_search_runner_default()
  assert_true(r is None)
}
