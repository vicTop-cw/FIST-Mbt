/// MultiStore 黑盒/白盒测试：open / 惰性打开 / ns 统计 / 关闭。
/// 内部可变性模式：open/close 直接修改 self.stores，无需返回新实例。

fn base_dir() -> String {
  "test-data"
}

test "open 创建并注册命名空间，get 幂等复用" {
  let ms = MultiStore::new(data_dir=base_dir())
  assert_eq!(ms.open(ns="alpha", data_dir=base_dir()), true)
  let list = ms.ns_list()
  assert_eq!(list.length(), 1)
  assert_eq!(list[0], "alpha")
  // 重复 open 同一 ns：幂等，不新增条目
  assert_eq!(ms.open(ns="alpha", data_dir=base_dir()), true)
  assert_eq!(ms.ns_list().length(), 1)
  // 通过 get 拿到同一 store，可正常 CRUD
  match ms.get("alpha") {
    Some(s) => {
      let t = @core.Task::new(
        id="T0",
        project_dir="E:/proj/demo",
        description="multi-store smoke",
        created_at="2026-09-05T10:00:00Z",
        ns="alpha",
      )
      match s.create_task(t) {
        Ok(_) => assert_eq!(s.list_tasks_in("alpha").length(), 1)
        Err(msg) => abort("create_task failed: \{msg}")
      }
    }
    None => abort("get alpha failed")
  }
}

test "惰性打开：未显式 open 时 get 可直接打开物理库" {
  let ms = MultiStore::new(data_dir=base_dir())
  assert_eq!(ms.ns_list().length(), 0)
  // 先 open 一次，确保物理库文件存在
  assert_eq!(ms.open(ns="beta", data_dir=base_dir()), true)
  assert_eq!(ms.ns_list().length(), 1)
  // get 返回的 store 可正常操作
  match ms.get("beta") {
    Some(s) => {
      let t = @core.Task::new(
        id="L0",
        project_dir="E:/proj/demo",
        description="lazy beta",
        created_at="2026-09-05T10:00:00Z",
        ns="beta",
      )
      match s.create_task(t) {
        Ok(_) => assert_eq!(s.list_tasks_in("beta").length(), 1)
        Err(msg) => abort("create_task failed: \{msg}")
      }
    }
    None => abort("get beta failed")
  }
}

test "ns_stats 反映各 ns 任务数" {
  let ms = MultiStore::new(data_dir=base_dir())
  assert_eq!(ms.open(ns="gs-alpha", data_dir=base_dir()), true)
  assert_eq!(ms.open(ns="gs-gamma", data_dir=base_dir()), true)
  match ms.get("gs-alpha") {
    Some(s) => {
      let t1 = @core.Task::new(
        id="SA0",
        project_dir="E:/proj/demo",
        description="a1",
        created_at="2026-09-05T10:00:00Z",
        ns="gs-alpha",
      )
      let t2 = @core.Task::new(
        id="SA1",
        project_dir="E:/proj/demo",
        description="a2",
        created_at="2026-09-05T10:01:00Z",
        ns="gs-alpha",
      )
      let _ = s.create_task(t1)
      let _ = s.create_task(t2)
    }
    None => abort("get alpha failed")
  }
  match ms.get("gs-gamma") {
    Some(s) => {
      let t = @core.Task::new(
        id="SG0",
        project_dir="E:/proj/demo",
        description="g1",
        created_at="2026-09-05T10:00:00Z",
        ns="gs-gamma",
      )
      let _ = s.create_task(t)
    }
    None => abort("get gamma failed")
  }
  let stats = ms.ns_stats()
  assert_eq!(stats.stringify().length() > 0, true)
  let mut alpha_total = -1
  let mut gamma_total = -1
  match stats {
    Json::Object(fields) => {
      assert_eq!(fields.size(), 2)
      fields.each(fn(k, v) {
        match v {
          Json::Object(item) => {
            let mut ns_name = ""
            let mut total = -1.0
            item.each(fn(ik, iv) {
              match (ik, iv) {
                ("ns", Json::String(s)) => ns_name = s
                ("total", Json::Number(n)) => total = n
                _ => ()
              }
            })
            if ns_name == "gs-alpha" { alpha_total = total.to_int() }
            if ns_name == "gs-gamma" { gamma_total = total.to_int() }
          }
          _ => abort("stats item not object")
        }
      })
    }
    _ => abort("stats not object")
  }
  assert_eq!(alpha_total, 2)
  assert_eq!(gamma_total, 1)
}

test "close 移除单个 ns，close_all 清空全部" {
  let ms = MultiStore::new(data_dir=base_dir())
  assert_eq!(ms.open(ns="cl-alpha", data_dir=base_dir()), true)
  assert_eq!(ms.open(ns="cl-gamma", data_dir=base_dir()), true)
  assert_eq!(ms.ns_list().length(), 2)
  ms.close("cl-alpha")
  assert_eq!(ms.ns_list().length(), 1)
  ms.close_all()
  assert_eq!(ms.ns_list().length(), 0)
}

test "open 空 ns 被拒" {
  let ms = MultiStore::new(data_dir=base_dir())
  assert_eq!(ms.open(ns="", data_dir=base_dir()), false)
  assert_eq!(ms.ns_list().length(), 0)
}
