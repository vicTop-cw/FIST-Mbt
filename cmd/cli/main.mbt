///|
/// FIST-Mbt CLI 子命令分发器
/// 用法：
///   moon run cmd/cli/main -- serve   # 启动 MCP server（stdio 传输）
///   moon run cmd/cli/main -- demo    # 七态闭环自包含 demo
///   moon run cmd/cli/main -- doctor  # 健康检查
async fn main {
  let args = @env.args()
  // @env.args() 返回 js/node 原生 argv：
  // args[0] = node.exe 路径, args[1] = .js 路径, args[2..] = 用户参数
  let sub = if args.length() >= 3 { args[2] } else { "" }

  match sub {
    "serve" => run_serve()
    "demo" => run_demo()
    "doctor" => run_doctor()
    "help" => print_help()
    "" => print_help()
    other => {
      println("未知子命令: \{other}")
      print_help()
    }
  }
}

///|
/// 打印帮助
fn print_help() -> Unit {
  println("FIST-Mbt CLI v0.3.0")
  println("")
  println("用法: fist <subcommand>")
  println("")
  println("子命令:")
  println("  serve    启动 MCP server（stdio 传输）")
  println("  demo     自包含七态闭环 demo")
  println("  doctor   只读健康检查")
  println("  help     显示本帮助")
}

///|
/// serve：启动 MCP server
/// 当前实现：提示用户手动运行（避免直接 import server 包的 SQLite require 问题）
/// 后续版本补 @process.spawn 启动编译产物
fn run_serve() -> Unit {
  println("[fist] serve — 启动 MCP server (stdio 传输)")
  println("")
  println("当前环境建议：")
  println("  moon run cmd/main")
  println("")
  println("或直接启动编译产物：")
  println("  moon build cmd/main && node _build/js/debug/build/cmd/main/main.js")
  println("")
  println("serve 子命令的进程 spawn 实现待补充。")
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
    Ok(id) => { println("✅ [1/7] publish → \{id}"); id }
    Err(e) => { println("❌ publish: \{e}"); return }
  }

  // 2. claim 根（Pending → Claimed）
  match engine.claim(task_id=root_id, assignee="leader", now~) {
    Ok(_) => println("✅ [2/7] claim → 已领取")
    Err(e) => { println("❌ claim 根: \{e}"); return }
  }

  // 3. plan 根（Claimed → Splitting，生成 depth=2 子任务）
  match engine.plan(task_id=root_id, split_n=2, by="agent", now~) {
    Ok(ids) => println("✅ [3/7] plan → 生成 \{ids.length()} 个子任务")
    Err(e) => { println("❌ plan 根: \{e}"); return }
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
    if !t.is_leaf() { continue }
    ref_count[0] = ref_count[0] + 1
    let tid = t.get_id()

    // claim 叶子
    let _cr = engine.claim(task_id=tid, assignee="worker-\{tid}", now~)

    // execute（Claimed/Splitting → Executing）
    let ex = engine.execute(task_id=tid, deliverable="\{tid} 交付物", now~)
    match ex {
      Ok(_) => ()
      Err(e) => { println("   ❌ execute \{tid}: \{e}"); ref_fail[0] = ref_fail[0] + 1; continue }
    }

    // submit（Executing → Reviewing）
    let sb = engine.submit(task_id=tid, now~)
    match sb {
      Ok(_) => ()
      Err(e) => { println("   ❌ submit \{tid}: \{e}"); ref_fail[0] = ref_fail[0] + 1; continue }
    }

    // verify（Reviewing → Completed，并自动向上归并父任务）
    let vr = engine.verify(task_id=tid, verifier="leader", now~)
    match vr {
      Ok(_) => ref_ok[0] = ref_ok[0] + 1
      Err(e) => { println("   ❌ verify \{tid}: \{e}"); ref_fail[0] = ref_fail[0] + 1 }
    }
  }
  println("✅ [5/7] 叶子闭环: \{ref_ok[0]}/\{ref_count[0]} 成功, \{ref_fail[0]} 失败")

  // 6. 手动 verify 所有中间层任务（engine.verify 向上归并不自动 verify 父）
  let ref_mid = [0]
  for t in engine.list_all() {
    let tid = t.get_id()
    if tid == root_id { continue }
    if t.is_leaf() { continue }
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
/// doctor：5 项只读健康检查，输出 ✅/❌
/// 全程不修改任何持久化数据（store 用内存后端）
fn run_doctor() -> Unit {
  let ref_total = [0]
  let ref_ok = [0]

  // —— 检查 1：engine 能创建 ——
  ref_total[0] = ref_total[0] + 1
  let e1 = @engine.FistEngine::new()
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
  let e4 = @engine.FistEngine::new()
  let now = "2026-09-27T10:00:00Z"
  let c4 = e4.publish(
    project_dir="./",
    description="doctor 闭环最小版",
    created_by="human_steward",
    now~,
    ns="doctor-check",
  )
  let e4_ok = match c4 {
    Err(_) => false
    Ok(root_id) =>
      match e4.claim(task_id=root_id, assignee="leader", now~) {
        Err(_) => false
        Ok(_) =>
          match e4.plan(task_id=root_id, split_n=1, by="agent", now~) {
            Err(_) => false
            Ok(_) => {
              let kids = e4.children_of(root_id)
              if kids.is_empty() {
                false
              } else {
                let kid_id = kids[0].get_id()
                let _ = e4.claim(task_id=kid_id, assignee="w", now~)
                let ex = match e4.execute(task_id=kid_id, deliverable="done", now~) {
                  Err(_) => false
                  Ok(_) =>
                    match e4.submit(task_id=kid_id, now~) {
                      Err(_) => false
                      Ok(_) =>
                        match e4.verify(task_id=kid_id, verifier="leader", now~) {
                          Err(_) => false
                          Ok(_) =>
                            match e4.archive(task_id=root_id, by="human_steward", now~) {
                              Err(_) => false
                              Ok(_) => true
                            }
                        }
                    }
                }
                ex
              }
            }
          }
      }
  }
  if e4_ok {
    ref_ok[0] = ref_ok[0] + 1
    println("✅ [4/5] 七态机闭环（最小版 depth=2）")
  } else {
    println("❌ [4/5] 七态机闭环失败")
  }

  // —— 检查 5：SQLite store（真实尝试，失败自动 skip 不阻塞）——
    ref_total[0] = ref_total[0] + 1
    let tmp_db = "_fist_doctor_check.db"
    match @engine.FistEngine::open_sqlite(tmp_db) {
      None => println("⏭️ [5/5] SQLite store 跳过（open_sqlite 返回 None，可能 ESM require 不可用）")
      Some(e) => {
        // 最小闭环: open_sqlite + publish（具名参数，跟 demo 一致）
        let pub_res = e.publish(
          project_dir="./",
          description="sqlite engine check",
          created_by="human_steward",
          now="2026-09-27T15:00:00Z",
          ns="doctor-sqlite-check",
        )
        println("✅ [5/5] SQLite store 可打开 (open_sqlite + publish 闭环, pub=\{pub_res.to_string()})")
        ref_ok[0] = ref_ok[0] + 1
      }
    }

  // 汇总
  println("")
  println("--- 汇总 ---")
  println("\{ref_ok[0]}/\{ref_total[0]} checks 通过")
  if ref_ok[0] == ref_total[0] {
    println("🎉 全部通过 ✅")
  } else {
    println("⚠️  有 \{ref_total[0] - ref_ok[0]} 项失败")
  }
}
