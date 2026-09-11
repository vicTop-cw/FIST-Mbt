// M3: AO 式递归拆解（plan_deep）测试（原 decompose 包，随 plan_deep 迁入 engine 包）。
// 覆盖：带 spec.laws 的递归拆解、无 spec 默认拆分、原子任务拒绝、SQLite 持久化恢复。

fn dp_new_engine() -> @engine.FistEngine {
  @engine.FistEngine::new()
}

fn dp_publish(e : @engine.FistEngine, desc~ : String = "M3 根任务") -> String {
  match e.publish(
    project_dir="E:/proj/demo",
    description=desc,
    created_by="human_steward",
    now="2026-09-05T10:00:00Z",
  ) {
    Ok(id) => id
    Err(m) => abort("publish failed: \{m}")
  }
}

fn dp_spec(laws : Array[String]) -> Json {
  let m : Map[String, Json] = Map([
    ("op", Json::string("task_decompose")),
    ("version", Json::string("1.0")),
    ("laws", Json::array(laws.map(fn(s) { Json::string(s) }))),
    ("fingerprint", Json::string("fnv1a64:test-spec-hash")),
  ])
  Json::object(m)
}

test "plan_deep 无 spec 时按 split_n 递归拆整棵子树并落库" {
  let e = dp_new_engine()
  let id = dp_publish(e)
  ignore(e.claim(task_id=id, assignee="leader_a", now="2026-09-05T10:01:00Z"))
  match e.plan_deep(task_id=id, split_n=3, by="leader_a", now="2026-09-05T10:02:00Z") {
    Ok(res) => {
      // 根 T0(depth3) -> 3 个 depth2 -> 每层再拆 2(其 split_n=2) -> depth1 叶
      // 总任务数 = 1 + 3 + 6 = 10
      assert_eq!(e.list_all().length(), 10)
      // T0.1 存在且 depth=2、非叶；其 2 个孩子 depth=1、叶
      match e.get_task("T0.1") {
        Some(t) => {
          assert_eq!(t.get_depth(), 2)
          assert_eq!(t.is_leaf(), false)
        }
        None => abort("T0.1 missing")
      }
      let ch = e.children_of("T0.1")
      assert_eq!(ch.length(), 2)
      for c in ch {
        assert_eq!(c.get_depth(), 1)
        assert_eq!(c.is_leaf(), true)
        // 验收基准挂在描述（无 spec 时空串）
        assert_eq!(c.get_status().to_string(), "待领取")
      }
      // 叶子不可再拆：取 T0.1 的任一叶 id 验证
      let leaf = e.children_of("T0.1")
      let leaf_id = leaf[0].get_id()
      assert_eq!(leaf[0].is_leaf(), true)
      match e.plan_deep(task_id=leaf_id, split_n=3, by="leader_a", now="2026-09-05T10:03:00Z") {
        Err(_) => ()
        Ok(_) => abort("leaf should not be further split")
      }
    }
    Err(m) => abort("plan_deep failed: \{m}")
  }
}

test "plan_deep 以 spec.laws 为切割依据递归拆解" {
  let e = dp_new_engine()
  let id = dp_publish(e)
  ignore(e.claim(task_id=id, assignee="leader_a", now="2026-09-05T10:01:00Z"))
  let spec = dp_spec(["L1: 满足能力A", "L2: 满足能力B"])
  match e.plan_deep(task_id=id, split_n=3, by="leader_a", spec=Some(spec), now="2026-09-05T10:02:00Z") {
    Err(m) => abort("plan_deep with spec failed: \{m}")
    Ok(res) => {
      // laws 2 条 -> T0.1/T0.2（depth2，split_n=2）-> 各有 2 个 depth1 叶
      assert_eq!(e.list_all().length(), 1 + 2 + 4)
      match e.get_task("T0.1") {
        Some(t) => {
          // 描述应以 law 为切片并挂 spec 指纹
          assert_eq!(t.description.contains("L1: 满足能力A"), true)
          assert_eq!(t.description.contains("fnv1a64:test-spec-hash"), true)
        }
        None => abort("T0.1 missing")
      }
      // 树结构可经 children_of 恢复；T0.1 的子节点为 depth1 叶
      let leaf = e.children_of("T0.1")
      assert_eq!(leaf.length(), 2)
      assert_eq!(leaf[0].is_leaf(), true)
      assert_eq!(leaf[1].is_leaf(), true)
    }
  }
}

test "plan_deep 状态机校验：已完成/已归档任务拒绝拆分，不存在任务被拒" {
  let e = dp_new_engine()
  let id = dp_publish(e)
  // 不存在的任务
  match e.plan_deep(task_id="NOPE", split_n=3, by="leader_a", now="2026-09-05T10:01:00Z") {
    Err(m) => assert_eq!(m.contains("task not found"), true)
    Ok(_) => abort("missing task should reject plan_deep")
  }
  // 推到已完成后再拆
  ignore(e.claim(task_id=id, assignee="exec_1", now="2026-09-05T10:02:00Z"))
  ignore(e.execute(task_id=id, deliverable="x", now="2026-09-05T10:03:00Z"))
  ignore(e.submit(task_id=id, now="2026-09-05T10:04:00Z"))
  ignore(e.verify(task_id=id, verifier="ver_1", now="2026-09-05T10:05:00Z"))
  match e.plan_deep(task_id=id, split_n=2, by="leader_a", now="2026-09-05T10:06:00Z") {
    Err(m) => assert_eq!(m.contains("非法拆解"), true)
    Ok(_) => abort("completed task should reject plan_deep")
  }
  // 归档后同样拒绝
  ignore(e.archive(task_id=id, by="human_steward", now="2026-09-05T10:07:00Z"))
  match e.plan_deep(task_id=id, split_n=2, by="leader_a", now="2026-09-05T10:08:00Z") {
    Err(m) => assert_eq!(m.contains("非法拆解"), true)
    Ok(_) => abort("archived task should reject plan_deep")
  }
}

test "plan_deep 未认领任务（待领取）也允许拆解（拳长可直接 plan 叠加）" {
  let e = dp_new_engine()
  let id = dp_publish(e)
  match e.plan_deep(task_id=id, split_n=2, by="leader_a", now="2026-09-05T10:01:00Z") {
    Ok(_) => ()
    Err(m) => abort("plan_deep on pending root should succeed: \{m}")
  }
}

test "plan_deep SQLite 持久化：重启后子树可经 get_task 恢复" {
  let db_path = "decompose_persist.db"
  // 幂等：先经 SqliteStore 公共 API 清空上次残留，再构建引擎
  match @store.SqliteStore::open(db_path) {
    Some(s) => ignore(s.clear())
    None => abort("sqlite open failed")
  }
  match @engine.FistEngine::open_sqlite(db_path) {
    None => abort("sqlite open failed")
    Some(e) => {
      let id = dp_publish(e, desc="持久化根任务")
      ignore(e.claim(task_id=id, assignee="leader_a", now="2026-09-05T10:01:00Z"))
      let spec = dp_spec(["L1", "L2"])
      match e.plan_deep(task_id=id, split_n=2, by="leader_a", spec=Some(spec), now="2026-09-05T10:02:00Z") {
        Err(m) => abort("plan_deep sqlite failed: \{m}")
        Ok(_) => ()
      }
    }
  }
  // 模拟进程重建：重新打开同库，子树应完整可恢复
  match @engine.FistEngine::open_sqlite(db_path) {
    None => abort("sqlite reopen failed")
    Some(e2) => {
      assert_eq!(e2.get_task("T0") is Some(_), true)
      // laws 2 条 -> T0.1/T0.2；再各拆 2 个 depth1 叶
      assert_eq!(e2.get_task("T0.1") is Some(_), true)
      assert_eq!(e2.get_task("T0.2") is Some(_), true)
      assert_eq!(e2.children_of("T0.1").length(), 2)
      let c1 = match e2.get_task("T0.1") {
        Some(t) => t
        None => abort("T0.1 missing after reopen")
      }
      // 验收基准描述随库恢复
      assert_eq!(c1.description.contains("fnv1a64:test-spec-hash"), true)
    }
  }
}