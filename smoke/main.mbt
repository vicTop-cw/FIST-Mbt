/// FIST-Mbt sqlite smoke walker（M1 验收辅助，非交付代码）
/// 直接驱动 SqliteStore + Store trait，跨连接验证持久化。
/// 运行：moon build --target js 后 node 运行生成的 smoke.js。

fn check(cond : Bool, name : String) -> Unit {
  if cond {
    println("PASS  \{name}")
  } else {
    abort("check failed: \{name}")
  }
}

fn main {
  println("== FIST-Mbt sqlite smoke ==")
  let s = match @lib.SqliteStore::open("smoke_walker.db") {
    Some(x) => x
    None => abort("sqlite open failed")
  }
  ignore(s.clear())

  let t0 = @lib.Task::new(
    id="S0",
    project_dir="E:/proj/demo",
    description="smoke 根任务",
    priority="高",
    importance="高",
    depth=3,
    split_n=3,
    created_at="2026-09-05T10:00:00Z",
  )
  ignore(s.create_task(t0))
  match s.get_task("S0") {
    Some(x) => {
      check(x.get_id() == "S0", "create/get id")
      check(x.status_to_string() == "待领取", "status default")
      check(x.get_depth() == 3, "depth roundtrip")
      check(x.get_description() == "smoke 根任务", "description roundtrip (utf8)")
    }
    None => abort("S0 missing after create")
  }

  let claimed = match s.get_task("S0") {
    Some(x) => x
    None => abort("no S0")
  }
  let claimed = match claimed.claim(assignee="exec_1") {
    Ok(x) => x
    Err(m) => abort("claim: \{m}")
  }
  match s.update_task(claimed) {
    Ok(_) => ()
    Err(m) => abort("update err: \{m}")
  }
  match s.get_task("S0") {
    Some(x) => {
      check(x.status_to_string() == "已领取", "update status persisted")
      match x.get_assignee() {
        Some(a) => check(a == "exec_1", "assignee utf8 roundtrip")
        None => abort("assignee missing after update")
      }
    }
    None => abort("S0 missing after update")
  }
  check(s.list_tasks().length() == 1, "list size")

  // 跨连接持久化
  let s2 = match @lib.SqliteStore::open("smoke_walker.db") {
    Some(x) => x
    None => abort("reopen failed")
  }
  match s2.get_task("S0") {
    Some(x) => check(x.status_to_string() == "已领取", "persist across reopen")
    None => abort("S0 not persisted")
  }
  ignore(s2.delete_task("S0"))
  match s2.get_task("S0") {
    Some(_) => abort("S0 should be deleted")
    None => println("PASS  delete")
  }
  ignore(s2.clear())
  println("== smoke done ==")
}
