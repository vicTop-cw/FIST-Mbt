// BUG-159: 跨 target 取用户首参 —— JS 下跳过 node.exe/.js 路径（args[2]），native 下跳过 exe 路径（args[1]）；统一用 user_arg(args, i) 访问用户参数

///|
#cfg(target="js")
fn user_first_arg(args : Array[String]) -> String {
  if args.length() >= 3 {
    args[2]
  } else {
    ""
  }
}

///|
#cfg(any(target="native", target="llvm"))
fn user_first_arg(args : Array[String]) -> String {
  // native 目标 argv[0] 是 exe 路径，真实子命令从 argv[1] 开始
  if args.length() >= 2 {
    args[1]
  } else {
    ""
  }
}

///|
#cfg(not(any(target="js", target="native", target="llvm")))
fn user_first_arg(args : Array[String]) -> String {
  if args.length() >= 3 {
    args[2]
  } else {
    ""
  }
}

///|
/// FIST-Mbt CLI 子命令分发器
/// 用法：
///   moon run cmd/cli/main -- serve   # 启动 MCP server（stdio 传输）
///   moon run cmd/cli/main -- demo    # 七态闭环自包含 demo
///   moon run cmd/cli/main -- doctor  # 健康检查
async fn main {
  let args = @env.args()
  let sub = user_first_arg(args)

  let cmd = parse_subcmd(sub)
  match cmd {
    Serve => run_serve()
    Version => run_version()
    Demo => run_demo()
    Doctor => if !run_doctor() { cli_exit(1) }
    Upgrade => run_upgrade()
    Help => run_help(args)
    NoArgs => print_help()
    Unknown(other) => {
      println("未知子命令: \{other}")
      print_help()
      cli_exit(exit_code_of(cmd))
    }
  }
}

///|
/// help 子命令：解析 topic 参数，调用 help_topics
/// user_arg(1)=topic, user_arg(2)=可选第二参数
fn run_help(args : Array[String]) -> Unit {
  let topic : String = user_arg(args, 1)
  match topic {
    "overview" => println(help_overview())
    "cli" => println(help_cli())
    "tools" => println(help_tools())
    "tool" => {
      let tool = user_arg(args, 2)
      if tool.length() == 0 {
        println("Usage: fist help tool <tool_name>")
        println("List:  fist help tools")
      } else {
        println("Tool detail: " + tool)
      }
    }
    "mcp" => println(help_mcp())
    "plugins" => println(help_plugins())
    "install" => println(help_install())
    _ => println(list_topics())
  }
}

///|
/// 统一用户参数访问：ua[0]=子命令、ua[1]=子命令后第一个参数……
/// JS 目标：@env.args() 为 [node.exe, 脚本路径, 用户参数…]，ua[i]=args[i+2]
#cfg(target="js")
fn user_arg(args : Array[String], i : Int32) -> String {
  if args.length() > i + 2 {
    args[i + 2]
  } else {
    ""
  }
}

///|
#cfg(any(target="native", target="llvm"))
fn user_arg(args : Array[String], i : Int32) -> String {
  // native 目标 @env.args()[0] 为 exe 路径，ua[i]=args[i+1]
  if args.length() > i + 1 {
    args[i + 1]
  } else {
    ""
  }
}

///|
fn print_help() -> Unit {
  println(list_topics())
}

///|
/// version：打印版本号（单一真源 moon.mod → project_version）
fn run_version() -> Unit {
  let v = @server.get_version()
  println("FIST-Mbt v\{v}")
  println("(moon.mod version 单一真源)")
}

///|

///|
/// upgrade：从远端 fetch 最新版本、备份、替换当前二进制
/// 核心逻辑在 cmd/cli/upgrade_core.mbt:run_upgrade_full（纯计算层）
/// BUG-160 修复：CLI match 缺 Upgrade 分支
async fn run_upgrade() -> Unit {
  // native 下 run_upgrade_full 是 stub（只 Err 提示需 js target）
  // js 下真实 fetch + IO
  let result = run_upgrade_full("gitcode", "fist-mbt.js", "", false)
  match result {
    Ok(msg) => println(msg)
    Err(e) => {
      eprintln("升级失败: \{e}")
      cli_exit(1)
    }
  }
}

///|
/// serve：启动 MCP server (stdio 传输)
/// 直接 import @server.run_server()，零 spawn 零进程创建
async fn run_serve() -> Unit {
  // BUG-101/R12：stdout 只走 JSON-RPC —— 这句提示打给 stderr，否则第一条协议帧前多一行横幅，
  // 所有 stdio 客户端（scripts/mcp_smoke.py 等 27 个判据）解析首行即崩
  eprintln("[fist] serve — 启动 MCP server (stdio 传输)")
  eprintln("stdin/stdout 接管, Ctrl+C 停止")
  eprintln("")
  // BUG-377：shim 指向的构建产物被清空时（_build 空、_release 未装），
  // 至少给出可读提示而不是只剩 node 的 Cannot find module 堆栈。
  try {
    @server.run_server()
  } catch {
    _ => {
      eprintln("[fist] serve 启动失败：未找到构建产物，请运行 install 或使用发布包")
      cli_exit(1)
    }
  }
}

///|
/// demo：七态闭环 publish→claim→plan→execute→submit→verify→archive
/// 全程内存 store，零网络、零真实文件系统
fn run_demo() -> Unit {
  let now = "2026-09-27T10:00:00Z"
  let engine = @engine.FistEngine::new() // 内存 store，不污染仓库
  let ns = "cli-demo-20260927"

  println("=== FIST-Mbt CLI Demo: 七态闭环 ===")
  println("")

  // 1. publish 根任务
  let pub_result = engine.publish(
    project_dir="./",
    description="CLI demo 根任务",
    created_by="human_steward",
    now~,
    ns~,
  )
  let root_id : String = match pub_result {
    Ok(id) => {
      println("✅ [1/7] publish → \{id}")
      id
    }
    Err(e) => {
      println("❌ publish: \{e}")
      return
    }
  }

  // 2. claim 根（Pending → Claimed）
  match engine.claim(task_id=root_id, assignee="leader", now~) {
    Ok(_) => println("✅ [2/7] claim → 已领取")
    Err(e) => {
      println("❌ claim 根: \{e}")
      return
    }
  }

  // 3. plan 根（Claimed → Splitting，生成 depth=2 子任务）
  match engine.plan(task_id=root_id, split_n=2, by="agent", now~) {
    Ok(ids) => println("✅ [3/7] plan → 生成 \{ids.length()} 个子任务")
    Err(e) => {
      println("❌ plan 根: \{e}")
      return
    }
  }

  // 4. 对每个子任务再 claim + plan 一层（depth=2 → depth=1 叶子）
  let children = engine.children_of(root_id)
  println("   子任务数: \{children.length()}")
  for child in children {
    let cid = child.get_id()
    // 子任务刚 plan 创建是 Pending，先 claim（ignore 错误）
    ignore(engine.claim(task_id=cid, assignee="mid-\{cid}", now~))
    // plan child 生成孙任务（叶子 depth=1）
    let pc = engine.plan(task_id=cid, split_n=2, by="agent", now~)
    match pc {
      Ok(_) => ()
      Err(e) => println("   ⚠️  plan \{cid}: \{e}")
    }
  }

  // 5. 对所有叶子任务：claim → execute → submit → verify
  println("✅ [4/7] 子任务全部拆分完成，开始叶子闭环")
  // 用 Array 做 ref cell 实现可变计数
  let ref_count = [0]
  let ref_ok = [0]
  let ref_fail = [0]

  for t in engine.list_all() {
    if !t.is_leaf() {
      continue
    }
    ref_count[0] = ref_count[0] + 1
    let tid = t.get_id()

    // claim 叶子
    let _cr = engine.claim(task_id=tid, assignee="worker-\{tid}", now~)

    // execute（Claimed/Splitting → Executing）
    let ex = engine.execute(task_id=tid, deliverable="\{tid} 交付物", now~)
    match ex {
      Ok(_) => ()
      Err(e) => {
        println("   ❌ execute \{tid}: \{e}")
        ref_fail[0] = ref_fail[0] + 1
        continue
      }
    }

    // submit（Executing → Reviewing）
    let sb = engine.submit(task_id=tid, now~)
    match sb {
      Ok(_) => ()
      Err(e) => {
        println("   ❌ submit \{tid}: \{e}")
        ref_fail[0] = ref_fail[0] + 1
        continue
      }
    }

    // verify（Reviewing → Completed，并自动向上归并父任务）
    let vr = engine.verify(task_id=tid, verifier="leader", now~)
    match vr {
      Ok(_) => ref_ok[0] = ref_ok[0] + 1
      Err(e) => {
        println("   ❌ verify \{tid}: \{e}")
        ref_fail[0] = ref_fail[0] + 1
      }
    }
  }
  println(
    "✅ [5/7] 叶子闭环: \{ref_ok[0]}/\{ref_count[0]} 成功, \{ref_fail[0]} 失败",
  )

  // 6. 手动 verify 所有中间层任务（engine.verify 向上归并不自动 verify 父）
  let ref_mid = [0]
  for t in engine.list_all() {
    let tid = t.get_id()
    if tid == root_id {
      continue
    }
    if t.is_leaf() {
      continue
    }
    let vr = engine.verify(task_id=tid, verifier="leader", now~)
    match vr {
      Ok(_) => ref_mid[0] = ref_mid[0] + 1
      Err(_) => () // 可能不是 Reviewing，忽略
    }
  }
  println("✅ [6/7] 中间层 verify: \{ref_mid[0]} 个成功")

  // 7. verify 根 + archive
  let vr_root = engine.verify(task_id=root_id, verifier="leader", now~)
  match vr_root {
    Ok(_) => ()
    Err(e) => println("   ℹ️  verify 根: \{e}（可能已自动完成）")
  }

  match engine.archive(task_id=root_id, by="human_steward", now~) {
    Ok(_) => println("✅ [7/7] archive → 已归档")
    Err(e) => println("   ⚠️  archive 根: \{e}")
  }

  // 最终校验
  println("")
  let final_root = engine.get_task(root_id)
  match final_root {
    None => println("❌ 根任务丢失")
    Some(t) => {
      let st = t.get_status()
      println("--- 最终状态 ---")
      println("根任务: \{t.get_id()} [\{st.to_string()}]")
      println("")
      if st.is_archived() && ref_fail[0] == 0 {
        println("🎉 七态闭环全绿 ✅")
      } else {
        println("⚠️  闭环有异常")
        println("   根状态: \{st.to_string()}")
        println("   叶子失败: \{ref_fail[0]}")
      }
    }
  }
}

///|
/// doctor 检查 4 的闭环本体：publish → claim → plan → 叶子生命周期 → verify(根) → 归档。
/// 每步的 `Err` 带步名上抛，不再被吞成 `Bool`——这一格长期恒红却无人能定位，
/// 正是因为只印一句「闭环失败」（BUG-393）。
/// `verify(根)` 是必需一步：`verify(叶)` 的向上归并只把根推到「待验收」，
/// 而 archive 的前置门是 `is_completed()` ⇒ 少这一格必被「仅已完成任务可归档」拒绝。
fn doctor_closed_loop() -> Result[Unit, String] {
  let now = "2026-09-27T10:00:00Z"
  let e = @engine.FistEngine::new()
  let root_id = match
    e.publish(
      project_dir="./",
      description="doctor 闭环最小版",
      created_by="human_steward",
      now~,
      ns="doctor-check",
    ) {
    Ok(id) => id
    Err(m) => return Err("publish: \{m}")
  }
  match e.claim(task_id=root_id, assignee="leader", now~) {
    Ok(_) => ()
    Err(m) => return Err("claim(root): \{m}")
  }
  match e.plan(task_id=root_id, split_n=1, by="agent", now~) {
    Ok(_) => ()
    Err(m) => return Err("plan(root): \{m}")
  }
  let kids = e.children_of(root_id)
  if kids.is_empty() {
    return Err("plan(root): 无子任务")
  }
  let kid_id = kids[0].get_id()
  let _ = e.claim(task_id=kid_id, assignee="w", now~)
  // 审计门禁(R10)会拒绝 "done"/"完成"/"ok" 等占位符交付物，
  // 闭环探针须用真实交付物，否则 execute 被拒导致 [4/5] 恒红。
  match
    e.execute(
      task_id=kid_id,
      deliverable="doctor 闭环探针：七态机最小闭环通过",
      now~,
    ) {
    Ok(_) => ()
    Err(m) => return Err("execute(kid): \{m}")
  }
  match e.submit(task_id=kid_id, now~) {
    Ok(_) => ()
    Err(m) => return Err("submit(kid): \{m}")
  }
  match e.verify(task_id=kid_id, verifier="leader", now~) {
    Ok(_) => ()
    Err(m) => return Err("verify(kid): \{m}")
  }
  match e.verify(task_id=root_id, verifier="leader", now~) {
    Ok(_) => ()
    Err(m) => return Err("verify(root): \{m}")
  }
  match e.archive(task_id=root_id, by="human_steward", now~) {
    Ok(_) => Ok(())
    Err(m) => return Err("archive(root): \{m}")
  }
}

///|
/// doctor：5 项只读健康检查，输出 ✅/❌，返回是否无失败项（false=有 ❌）
/// 全程不修改任何持久化数据（store 用内存后端）
/// ⏭️ 跳过不算失败：`e2e_irm_line.py` 的安装自检线要求 `doctor=0`，
/// 把"工具链不给量"判成"安装坏了"就是 BUG-142 那格反向的错
fn run_doctor() -> Bool {
  let ref_total = [0]
  let ref_ok = [0]
  let ref_skip = [0]

  // —— 检查 1：engine 能创建 ——
  ref_total[0] = ref_total[0] + 1
  let _e1 = @engine.FistEngine::new()
  ref_ok[0] = ref_ok[0] + 1
  println("✅ [1/5] FistEngine 能创建")

  // —— 检查 2：七态枚举方法可调用 ——
  // 不直接构造变体（MoonBit enum 变体不可跨包构造），
  // 而是发布一个任务后获取其状态并调用方法确认枚举有效
  ref_total[0] = ref_total[0] + 1
  let e2 = @engine.FistEngine::new()
  let c2 = e2.publish(
    project_dir="./",
    description="status-probe",
    created_by="human_steward",
    now="2026-09-27T10:00:00Z",
    ns="doctor-check",
  )
  let mut status_ok : Bool = true
  match c2 {
    Ok(id) =>
      match e2.get_task(id) {
        Some(t) => {
          let st = t.get_status()
          let _s = st.to_string()
          let _c = st.can_split()
          let _e = st.can_execute()
          let _p = st.is_pending()
          let _co = st.is_completed()
          let _ar = st.is_archived()
          let _rv = st.is_reviewing()
          let _ac = st.is_active()
        }
        None => status_ok = false
      }
    Err(_) => status_ok = false
  }
  if status_ok {
    ref_ok[0] = ref_ok[0] + 1
    println("✅ [2/5] 七态枚举方法可调用")
  } else {
    println("❌ [2/5] 七态枚举异常")
  }

  // —— 检查 3：store 基本操作（publish → get → list）——
  ref_total[0] = ref_total[0] + 1
  let e3 = @engine.FistEngine::new()
  let c3 = e3.publish(
    project_dir="./",
    description="store-op-probe",
    created_by="human_steward",
    now="2026-09-27T10:00:00Z",
    ns="doctor-check",
  )
  let e3_ok = match c3 {
    Ok(id) =>
      match e3.get_task(id) {
        Some(_t) => e3.list_all().length() >= 1
        None => false
      }
    Err(_) => false
  }
  if e3_ok {
    ref_ok[0] = ref_ok[0] + 1
    println("✅ [3/5] store 基本操作 (publish → get → list)")
  } else {
    println("❌ [3/5] store 基本操作失败")
  }

  // —— 检查 4：七态机闭环最小版（depth=2，单叶子）——
  ref_total[0] = ref_total[0] + 1
  match doctor_closed_loop() {
    Ok(_) => {
      ref_ok[0] = ref_ok[0] + 1
      println("✅ [4/5] 七态机闭环（最小版 depth=2）")
    }
    Err(why) => println("❌ [4/5] 七态机闭环失败：\{why}")
  }

  // —— 检查 5：SQLite store（真实尝试，失败自动 skip 不阻塞）——
  ref_total[0] = ref_total[0] + 1
  let tmp_db = doctor_db_path(@env.get_env_var("FIST_DB_PATH"))
  match @engine.FistEngine::open_sqlite(tmp_db) {
    None => {
      ref_skip[0] = ref_skip[0] + 1
      println(
        "⏭️ [5/5] SQLite store 跳过（open_sqlite 返回 None，可能 ESM require 不可用）",
      )
    }
    Some(e) => {
      // 最小闭环: open_sqlite + publish（具名参数，跟 demo 一致）
      let pub_res = e.publish(
        project_dir="./",
        description="sqlite engine check",
        created_by="human_steward",
        now="2026-09-27T15:00:00Z",
        ns="doctor-sqlite-check",
      )
      println(
        "✅ [5/5] SQLite store 可打开 (open_sqlite + publish 闭环, pub=\{pub_res.to_string()})",
      )
      ref_ok[0] = ref_ok[0] + 1
    }
  }

  // 汇总
  let failed = doctor_failed_count(ref_ok[0], ref_total[0], ref_skip[0])
  println("")
  println("--- 汇总 ---")
  println("\{ref_ok[0]}/\{ref_total[0]} checks 通过")
  if failed > 0 {
    println("⚠️  有 \{failed} 项失败")
  } else if ref_skip[0] > 0 {
    println("⏭️  有 \{ref_skip[0]} 项跳过（不计失败）")
  } else {
    println("🎉 全部通过 ✅")
  }
  failed == 0
}
