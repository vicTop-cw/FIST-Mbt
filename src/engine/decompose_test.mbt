// M3: AO 式递归拆解（plan_deep）测试（原 decompose 包，随 plan_deep 迁入 engine 包）。
// 覆盖：带 spec.laws 的递归拆解、无 spec 默认拆分、原子任务拒绝、SQLite 持久化恢复。

///|
fn dp_new_engine() -> @engine.FistEngine {
  @engine.FistEngine::new()
}

///|
fn dp_publish(
  e : @engine.FistEngine,
  desc? : String = "M3 根任务",
) -> String {
  match
    e.publish(
      project_dir="/proj/demo",
      description=desc,
      created_by="human_steward",
      now="2026-09-05T10:00:00Z",
    ) {
    Ok(id) => id
    Err(m) => abort("publish failed: \{m}")
  }
}

///|
fn dp_spec(laws : Array[String]) -> Json {
  let m : Map[String, Json] = Map([
    ("op", Json::string("task_decompose")),
    ("version", Json::string("1.0")),
    ("laws", Json::array(laws.map(fn(s) { Json::string(s) }))),
    ("fingerprint", Json::string("fnv1a64:test-spec-hash")),
  ])
  Json::object(m)
}

///|
test "plan_deep 无 spec 时按 split_n 递归拆整棵子树并落库" {
  let e = dp_new_engine()
  let id = dp_publish(e)
  ignore(e.claim(task_id=id, assignee="leader_a", now="2026-09-05T10:01:00Z"))
  match
    e.plan_deep(
      task_id=id,
      split_n=3,
      by="leader_a",
      now="2026-09-05T10:02:00Z",
    ) {
    Ok(res) => {
      // 根 T0(depth3) -> 3 个 depth2 -> 每层再拆 2(其 split_n=2) -> depth1 叶
      // 总任务数 = 1 + 3 + 6 = 10
      assert_eq(e.list_all().length(), 10)
      // T0.1 存在且 depth=2、非叶；其 2 个孩子 depth=1、叶
      match e.get_task("T0.1") {
        Some(t) => {
          assert_eq(t.get_depth(), 2)
          assert_eq(t.is_leaf(), false)
        }
        None => abort("T0.1 missing")
      }
      let ch = e.children_of("T0.1")
      assert_eq(ch.length(), 2)
      for c in ch {
        assert_eq(c.get_depth(), 1)
        assert_eq(c.is_leaf(), true)
        // 验收基准挂在描述（无 spec 时空串）
        assert_eq(c.get_status().to_string(), "待领取")
      }
      // 叶子不可再拆：取 T0.1 的任一叶 id 验证
      let leaf = e.children_of("T0.1")
      let leaf_id = leaf[0].get_id()
      assert_eq(leaf[0].is_leaf(), true)
      match
        e.plan_deep(
          task_id=leaf_id,
          split_n=3,
          by="leader_a",
          now="2026-09-05T10:03:00Z",
        ) {
        Err(_) => ()
        Ok(_) => abort("leaf should not be further split")
      }
    }
    Err(m) => abort("plan_deep failed: \{m}")
  }
}

///|
test "plan_deep 以 spec.laws 为切割依据递归拆解" {
  let e = dp_new_engine()
  let id = dp_publish(e)
  ignore(e.claim(task_id=id, assignee="leader_a", now="2026-09-05T10:01:00Z"))
  let spec = dp_spec(["L1: 满足能力A", "L2: 满足能力B"])
  match
    e.plan_deep(
      task_id=id,
      split_n=3,
      by="leader_a",
      spec=Some(spec),
      now="2026-09-05T10:02:00Z",
    ) {
    Err(m) => abort("plan_deep with spec failed: \{m}")
    Ok(res) => {
      // laws 2 条 -> T0.1/T0.2（depth2，split_n=2）-> 各有 2 个 depth1 叶
      assert_eq(e.list_all().length(), 1 + 2 + 4)
      match e.get_task("T0.1") {
        Some(t) => {
          // 描述应以 law 为切片并挂 spec 指纹
          assert_eq(t.description.contains("L1: 满足能力A"), true)
          assert_eq(t.description.contains("fnv1a64:test-spec-hash"), true)
        }
        None => abort("T0.1 missing")
      }
      // 树结构可经 children_of 恢复；T0.1 的子节点为 depth1 叶
      let leaf = e.children_of("T0.1")
      assert_eq(leaf.length(), 2)
      assert_eq(leaf[0].is_leaf(), true)
      assert_eq(leaf[1].is_leaf(), true)
    }
  }
}

///|
test "plan_deep 状态机校验：已完成/已归档任务拒绝拆分，不存在任务被拒" {
  let e = dp_new_engine()
  let id = dp_publish(e)
  // 不存在的任务
  match
    e.plan_deep(
      task_id="NOPE",
      split_n=3,
      by="leader_a",
      now="2026-09-05T10:01:00Z",
    ) {
    Err(m) => assert_eq(m.contains("task not found"), true)
    Ok(_) => abort("missing task should reject plan_deep")
  }
  // 推到已完成后再拆
  ignore(e.claim(task_id=id, assignee="exec_1", now="2026-09-05T10:02:00Z"))
  ignore(e.execute(task_id=id, deliverable="x", now="2026-09-05T10:03:00Z"))
  ignore(e.submit(task_id=id, now="2026-09-05T10:04:00Z"))
  ignore(e.verify(task_id=id, verifier="ver_1", now="2026-09-05T10:05:00Z"))
  match
    e.plan_deep(
      task_id=id,
      split_n=2,
      by="leader_a",
      now="2026-09-05T10:06:00Z",
    ) {
    Err(m) => assert_eq(m.contains("非法拆解"), true)
    Ok(_) => abort("completed task should reject plan_deep")
  }
  // 归档后同样拒绝
  ignore(e.archive(task_id=id, by="human_steward", now="2026-09-05T10:07:00Z"))
  match
    e.plan_deep(
      task_id=id,
      split_n=2,
      by="leader_a",
      now="2026-09-05T10:08:00Z",
    ) {
    Err(m) => assert_eq(m.contains("非法拆解"), true)
    Ok(_) => abort("archived task should reject plan_deep")
  }
}

///|
test "plan_deep 未认领任务（待领取）也允许拆解（拳长可直接 plan 叠加）" {
  let e = dp_new_engine()
  let id = dp_publish(e)
  match
    e.plan_deep(
      task_id=id,
      split_n=2,
      by="leader_a",
      now="2026-09-05T10:01:00Z",
    ) {
    Ok(_) => ()
    Err(m) => abort("plan_deep on pending root should succeed: \{m}")
  }
}

///|
test "plan_deep 开启 gradient 时子任务描述带难度梯度与更简单变体；默认关闭零回归" {
  let e = dp_new_engine()
  let id = dp_publish(e)
  // 默认不传 gradient：描述不含梯度标记（零回归）
  match
    e.plan_deep(
      task_id=id,
      split_n=3,
      by="leader_a",
      now="2026-09-05T10:01:00Z",
    ) {
    Err(m) => abort("default plan_deep failed: \{m}")
    Ok(_) =>
      match e.get_task("T0.1") {
        Some(t) => assert_eq(t.description.contains("难度梯度"), false)
        None => abort("T0.1 missing")
      }
  }
  // 开启 gradient：T0.1/T0.2/T0.3 各带难度梯度标注 + 更简单变体提示
  let id2 = dp_publish(e, desc="M3 挑战根任务")
  match
    e.plan_deep(
      task_id=id2,
      split_n=3,
      by="leader_a",
      gradient=true,
      now="2026-09-05T10:02:00Z",
    ) {
    Err(m) => abort("gradient plan_deep failed: \{m}")
    Ok(_) => {
      // id2 由 first_free_root_id 顺延得到（如 T0r2.children 即本轮梯度根的子节点
      let kids = e.children_of(id2)
      assert_eq(kids.length() >= 3, true)
      // 梯度：第 1 片 -> 易（含更简单变体提示）；最后 1 片 -> 难
      let c_first = kids[0]
      assert_eq(
        c_first.description.contains("[难度梯度 1/\{kids.length()}:易]"),
        true,
      )
      assert_eq(c_first.description.contains("更简单变体"), true)
      // R35 深化：提示须含"由易到难——先完成更简单变体，再推广/逆推到本任务"的 LADDER 先易后逆推语
      assert_eq(c_first.description.contains("先易后逆推"), true)
      assert_eq(c_first.description.contains("推广/逆推"), true)
      let c_last = kids[kids.length() - 1]
      assert_eq(
        true,
        c_last.description.contains(
          "[难度梯度 \{kids.length()}/\{kids.length()}:难]",
        ),
      )
    }
  }
}

///|
test "plan_deep reinject_context 把父计划+剩余兄弟回注子任务描述；默认关闭零回归" {
  let e = dp_new_engine()
  // 默认不传 reinject_context：描述不含父计划标记（零回归）
  let id = dp_publish(e, desc="M3 回注根任务")
  match
    e.plan_deep(
      task_id=id,
      split_n=3,
      by="leader_a",
      now="2026-09-05T10:01:00Z",
    ) {
    Err(m) => abort("default plan_deep failed: \{m}")
    Ok(_) =>
      match e.get_task("T0.1") {
        Some(t) => assert_eq(t.description.contains("[父计划:"), false)
        None => abort("T0.1 missing")
      }
  }
  // 开启 reinject_context：子任务描述携带父计划 + 剩余兄弟，且下钻孙代也能继承父计划
  let id2 = dp_publish(e, desc="M3 回注启用根")
  match
    e.plan_deep(
      task_id=id2,
      split_n=3,
      by="leader_a",
      reinject_context=true,
      now="2026-09-05T10:02:00Z",
    ) {
    Err(m) => abort("reinject plan_deep failed: \{m}")
    Ok(_) => {
      let kids = e.children_of(id2)
      assert_eq(kids.length() >= 3, true)
      // 首切片含「父计划」= 根任务描述 + 剩余兄弟计数
      let c_first = kids[0]
      assert_eq(c_first.description.contains("[父计划:"), true)
      assert_eq(c_first.description.contains("M3 回注启用根"), true)
      assert_eq(c_first.description.contains("剩余兄弟:"), true)
      // 剩余兄弟数 = n-1（首片之后还有 n-1 个兄弟）
      assert_eq(c_first.description.contains("剩余兄弟: \{kids.length() - 1}"), true)
      // 下钻孙代同样继承父计划（知其所以然贯穿整棵树）
      let ch = e.children_of(c_first.get_id())
      if ch.length() > 0 {
        assert_eq(ch[0].description.contains("[父计划:"), true)
      }
    }
  }
}

///|
test "plan_deep gradient_dag 把更简单变体落成真实 DAG 前驱链；默认关闭零回归" {
  let e = dp_new_engine()
  // 控制组：仅 gradient=true 不传 gradient_dag，兄弟切片 depends_on 全空（零回归）
  let cid = dp_publish(e, desc="gradient-only 根")
  match
    e.plan_deep(
      task_id=cid,
      split_n=3,
      by="leader_a",
      gradient=true,
      now="2026-09-05T10:03:00Z",
    ) {
    Err(m) => abort("gradient-only plan_deep failed: \{m}")
    Ok(_) => {
      let kids = e.children_of(cid)
      for k in kids {
        assert_eq(k.depends_on.is_empty(), true)
      }
    }
  }
  // 实验组：gradient_dag=true → 兄弟切片由易到难连成前驱链
  let did = dp_publish(e, desc="gradient-dag 根")
  match
    e.plan_deep(
      task_id=did,
      split_n=3,
      by="leader_a",
      gradient=true,
      gradient_dag=true,
      now="2026-09-05T10:04:00Z",
    ) {
    Err(m) => abort("gradient_dag plan_deep failed: \{m}")
    Ok(tree) => {
      // 返回树顶层三兄弟：首个无依赖，后续各依赖前一兄弟
      match tree.value("tree") {
        None => abort("tree missing")
        Some(root_tree) =>
          match root_tree.value("children") {
            None => abort("children missing")
            Some(Array(cs)) => {
              for j = 0; j < cs.length(); j = j + 1 {
                let dep = match cs[j].value("depends_on") {
                  Some(Array(a)) => a
                  _ => []
                }
                if j == 0 {
                  assert_eq(dep.is_empty(), true)
                } else {
                  let prev_id = match cs[j - 1].value("id") {
                    Some(Json::String(s)) => s
                    _ => ""
                  }
                  // 依赖恰为前一兄弟 id
                  let has_prev = match dep[0] {
                    Json::String(s) => s == prev_id
                    _ => false
                  }
                  assert_eq(has_prev, true)
                  assert_eq(dep.length(), 1)
                }
              }
            }
            _ => abort("children not array")
          }
      }
      // 落库后 children_of 也能读到真实 depends_on
      let kids = e.children_of(did)
      for j = 0; j < kids.length(); j = j + 1 {
        if j == 0 {
          assert_eq(kids[j].depends_on.is_empty(), true)
        } else {
          assert_eq(
            kids[j].depends_on.length() == 1 &&
            kids[j].depends_on[0] == kids[j - 1].id,
            true,
          )
        }
      }
    }
  }
}

///|
test "plan_exec_order 输出 DAG 序执行计划：依赖先于被依赖，携带难度档" {
  let e = dp_new_engine()
  let id = dp_publish(e, desc="exec-order 根")
  // 拆解两层、gradient+gradient_dag（深度 2 → 顶层 3 兄弟 + 二三层再派生）
  match
    e.plan_deep(
      task_id=id,
      split_n=3,
      by="leader_a",
      gradient=true,
      gradient_dag=true,
      now="2026-09-05T10:05:00Z",
    ) {
    Err(m) => abort("gradient_dag plan_deep failed: \{m}")
    Ok(_) => {
      // 返回树顶层 3 兄弟均由易到难连链；exec_order 全后代扁平拓扑序
      let ej = e.plan_exec_order(id)
      match ej.value("order") {
        None => abort("order missing")
        Some(Array(seq)) => {
          let idx : Map[String, Int] = Map([])
          for k = 0; k < seq.length(); k = k + 1 {
            let oid = match seq[k].value("id") {
              Some(Json::String(s)) => s
              _ => abort("id missing")
            }
            idx.set(oid, k)
            // 每个后代都应有难度档（gradient 开启）
            let d = match seq[k].value("difficulty") {
              Some(Json::String(s)) => s
              _ => ""
            }
            assert_eq(d != "", true)
          }
          // DAG 序不变量：任一任务其 depends_on 中的前驱在序中下标必须更小
          for k = 0; k < seq.length(); k = k + 1 {
            let deps = match seq[k].value("depends_on") {
              Some(Array(a)) => a
              _ => []
            }
            let oid = match seq[k].value("id") {
              Some(Json::String(s)) => s
              _ => ""
            }
            for dep in deps {
              match dep {
                Json::String(did) =>
                  assert_eq(
                    // 在集合内才校验顺序（跨子树依赖归因到根内已含）
                    idx.get(did).is_none() ||
                    idx.get(did).unwrap_or(-1) < idx.get(oid).unwrap_or(-1),
                    true,
                  )
                _ => ()
              }
            }
          }
        }
        _ => abort("order not array")
      }
    }
  }
}

///|
test "plan_deep 难度校准：gradient+calibrate 用真实难度覆盖位置档，长度不匹配时回退" {
  let e = dp_new_engine()
  let id = dp_publish(e)
  // calibrate 长度与切片一致：T0.1 d=1.0(易)、T0.2 d=3.0(中)、T0.3 d=5.0(难)
  match
    e.plan_deep(
      task_id=id,
      split_n=3,
      by="leader_a",
      gradient=true,
      calibrate=Some([1.0, 3.0, 5.0]),
      now="2026-09-05T10:01:00Z",
    ) {
    Err(m) => abort("calibrated plan_deep failed: \{m}")
    Ok(_) => {
      let a = match e.get_task("T0.1") {
        Some(t) => t
        None => abort("T0.1 missing")
      }
      assert_eq(a.description.contains("[难度梯度 1/3:易"), true)
      // 校准难度数值（JS 端 1.0 渲染为 "1"，此处只断言 "d=1" 前缀命中）
      assert_eq(a.description.contains("d=1"), true)
      let b = match e.get_task("T0.2") {
        Some(t) => t
        None => abort("T0.2 missing")
      }
      assert_eq(b.description.contains("[难度梯度 2/3:中"), true)
      assert_eq(b.description.contains("d=3"), true)
      let c = match e.get_task("T0.3") {
        Some(t) => t
        None => abort("T0.3 missing")
      }
      assert_eq(c.description.contains("[难度梯度 3/3:难"), true)
      assert_eq(c.description.contains("d=5"), true)
    }
  }
  // calibrate 长度不匹配：回退位置档（不崩塌）
  let id2 = dp_publish(e, desc="M3 校准回退根")
  match
    e.plan_deep(
      task_id=id2,
      split_n=3,
      by="leader_a",
      gradient=true,
      calibrate=Some([2.0]),
      now="2026-09-05T10:02:00Z",
    ) {
    Err(m) => abort("calibrate mismatch should still succeed: \{m}")
    Ok(_) => {
      // id2 由 first_free_root_id 顺延（如 T0r2），取它的首个子节点
      let kids = e.children_of(id2)
      let a = kids[0]
      // 位置 1/3 → 易，且不附加校准 d 记号
      assert_eq(a.description.contains("[难度梯度 1/3:易]"), true)
      assert_eq(a.description.contains(" d="), false)
    }
  }
}

///|
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
      ignore(
        e.claim(task_id=id, assignee="leader_a", now="2026-09-05T10:01:00Z"),
      )
      let spec = dp_spec(["L1", "L2"])
      match
        e.plan_deep(
          task_id=id,
          split_n=2,
          by="leader_a",
          spec=Some(spec),
          now="2026-09-05T10:02:00Z",
        ) {
        Err(m) => abort("plan_deep sqlite failed: \{m}")
        Ok(_) => ()
      }
    }
  }
  // 模拟进程重建：重新打开同库，子树应完整可恢复
  match @engine.FistEngine::open_sqlite(db_path) {
    None => abort("sqlite reopen failed")
    Some(e2) => {
      assert_eq(e2.get_task("T0") is Some(_), true)
      // laws 2 条 -> T0.1/T0.2；再各拆 2 个 depth1 叶
      assert_eq(e2.get_task("T0.1") is Some(_), true)
      assert_eq(e2.get_task("T0.2") is Some(_), true)
      assert_eq(e2.children_of("T0.1").length(), 2)
      let c1 = match e2.get_task("T0.1") {
        Some(t) => t
        None => abort("T0.1 missing after reopen")
      }
      // 验收基准描述随库恢复
      assert_eq(c1.description.contains("fnv1a64:test-spec-hash"), true)
    }
  }
}
