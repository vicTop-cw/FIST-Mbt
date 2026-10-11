/// children_index_test.mbt —— R12-R8 bugfind：验证 children_index 与 children_of 语义等价
/// （旧 children_of 每查一次全库 list_tasks；新 children_index 一次建索引 O(1) 查）。
test "children_index 与 children_of 语义等价" {
  let e = FistEngine::new()
  // 建一棵 3 层树：P -> A,B -> A1,A2
  let mk = fn(id : String, parent : String) {
    let t = @core.Task::new(
      id~,
      project_dir="/proj/demo",
      description="测试 \{id}",
      parent_id=parent,
      created_at="2026-01-01T00:00:00Z",
      depends_on=[],
    )
    ignore(e.store.create_task(t))
  }
  mk("P", "")
  mk("A", "P")
  mk("B", "P")
  mk("A1", "A")
  mk("A2", "A")
  // children_index 与 children_of 对同一 parent 应返回相同 id 集合
  let idx = e.children_index()
  let direct_a = idx.get("A").unwrap_or([]).sort()
  let ref_a = e.children_of("A").map(fn(t) { t.get_id() }).sort()
  assert_eq(direct_a, ref_a)
  let direct_p = idx.get("P").unwrap_or([]).sort()
  let ref_p = e.children_of("P").map(fn(t) { t.get_id() }).sort()
  assert_eq(direct_p, ref_p)
  // 叶节点应为空
  assert_eq(idx.get("A1").unwrap_or([]), [])
}