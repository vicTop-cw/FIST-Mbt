/// engine_challenge_level_wbtest.mbt —— 回归锁：`challenge`（更难变体）派生的新根**固定 level=6（连长级）**
///
/// 真源裁决：`docs/plans/decisions/2026-10-29-challenge-level.md`（2026-10-29 人类指挥官裁决，
/// 承接 2026-10-18 军衔接线报告的「待裁决」条目）。裁决三句话：
///   ① `challenge` 新根 **level == 6**，**不继承**源任务军衔（默认连长，与 `publish` 缺省一致）；
///   ② 溯源不变：新根**仍是新根**（`parent_id` 为空，不引入父子关系）；
///      源任务关系由 description 里的 `from <源 id>` 承担 —— 「同源更难」不是「上下级」；
///   ③ 源任务军衔 **!= 6** 时新根仍 **6** —— 这一格是变异对照的承重墙：
///      把实现改成 `level=src.level`（继承）时本文件**必红**（判例-29/30：改的是代码不是注释）。
///
/// ⚠️ 本文件只断言 **返回值 / Task 字段读数**，**不**断言「源码里存在某个字符串」——
///    那种断言会被注释喂绿（判例-30 自指假绿）。改坏实现后本锁必然变红，见任务回执里的红读数。

///|
/// 发布一条指定军衔的根任务（`created_by=human_steward` 过指挥官门）。
fn chl_publish(e : FistEngine, desc : String, level : Int32) -> String {
  match
    e.publish(
      project_dir="/proj/challenge-level",
      description=desc,
      created_by="human_steward",
      now="2026-10-29T10:00:00Z",
      level~,
    ) {
    Ok(id) => id
    Err(m) => abort("publish 失败: \{m}")
  }
}

///|
/// 把源任务按真实状态机推成「已完成」（challenge 只接受已完成/已归档）。
/// 认领人固定用 `human_steward`：claim 的军衔门对**非叶子**任务按任务自身 level 判
/// （`leaf_claim_level()` 只对 depth<=1 的叶子放宽），源任务 level=0/3/5 时
/// Executor 档会被 RANK_GATE 拒绝 —— 那不是本锁要考的东西。
fn chl_complete(e : FistEngine, id : String) -> Unit {
  match
    e.claim(task_id=id, assignee="human_steward", now="2026-10-29T10:01:00Z") {
    Ok(_) => ()
    Err(m) => abort("源任务 claim 失败: \{m}")
  }
  match
    e.execute(
      task_id=id,
      deliverable="完成挑战变体路径：新增 level 回归锁 + 3 条用例",
      now="2026-10-29T10:02:00Z",
    ) {
    Ok(_) => ()
    Err(m) => abort("源任务 execute 失败: \{m}")
  }
  match e.submit(task_id=id, now="2026-10-29T10:03:00Z") {
    Ok(_) => ()
    Err(m) => abort("源任务 submit 失败: \{m}")
  }
  match e.verify(task_id=id, verifier="ver_1", now="2026-10-29T10:04:00Z") {
    Ok(_) => ()
    Err(m) => abort("源任务 verify 失败: \{m}")
  }
}

///|
/// 主锁：源任务 level=3（旅长，比默认连长**更资深**）→ 新根必须回到连长级 6。
///
/// 为什么源任务要选非 6：若源任务本身就是 6，「默认 6」与「继承源」两种实现的读数**完全相同**
/// ⇒ 变异对照不可能变红，锁就是假绿。**这一格的前置自证（源 level==3）是锁的一部分。**
test "challenge 新根固定 level=6：源任务 level=3（旅长）不被继承，且溯源仍是新根" {
  let e = FistEngine::new()
  let src_id = chl_publish(e, "实现一个基础计算器", 3)
  chl_complete(e, src_id)
  // 前置自证：源任务军衔确实是 3（否则本格对「继承」变异不敏感）
  match e.get_task(src_id) {
    Some(t) => assert_eq(t.get_level(), 3)
    None => abort("源任务不存在: \{src_id}")
  }
  match e.challenge(task_id=src_id, by="auto", now="2026-10-29T10:05:00Z") {
    Err(m) => abort("对已完成任务 challenge 应成功: \{m}")
    Ok(j) => {
      let new_id = match jget(j, "new_id") {
        Some(String(s)) => s
        _ => abort("challenge 回执缺 new_id: " + j.stringify())
      }
      // 新根必须是一条**新**任务（id 不等于源）
      assert_eq(new_id == src_id, false)
      match e.get_task(new_id) {
        Some(t) => {
          // ① 裁决本体：新根恒连长级 6，与源任务 level=3 无关
          //    （等价于 assert_eq(t.get_level(), 6)，但带诊断文案：红的时候直接说出继承到了几级）
          if t.get_level() != 6 {
            abort(
              "新根 level 应为 6（连长级），实测 \{t.get_level()} —— 源任务 level=3 被继承了？",
            )
          }
          // ② 新根是真新根：parent_id 为空 ⇒ 不引入「父子」语义（军衔继承正是靠它表达的）
          assert_eq(t.parent_id, (None : String?))
          // ③ 溯源不变：源任务 id 仍写在 description 的 `from <源 id>` 里
          assert_eq(t.description.contains("from " + src_id), true)
          // ④ 从源的子树里读不到它 ⇒「同源更难」不是「上下级」
          assert_eq(e.children_of(src_id).length(), 0)
          // ⑤ 只有军衔**不**随源走，其它继承字段照旧（示例：重要度升一档）
          assert_eq(t.importance, "高")
        }
        None => abort("challenge 新根不存在: \{new_id}")
      }
    }
  }
}

///|
/// 表驱动锁：源任务军衔 0（司令）/ 3（旅长）/ 5（营长）/ 7（排长）**全部**产出新根 level=6。
///
/// 单点（只测 3）能被人用「恰好 3 被钳到 6」之类巧合解释；四个不同档位一起读，
/// 才把「恒默认连长」与「继承源」彻底分开 —— 也顺手锁住 `clamp_level` 没有在别处夹带源值。
test "challenge 新根恒 level=6：与源任务军衔 0/3/5/7 全部无关（表驱动）" {
  for lv in [0, 3, 5, 7] {
    let e = FistEngine::new()
    let src_id = chl_publish(e, "进阶源任务 level=\{lv}", lv)
    chl_complete(e, src_id)
    match e.get_task(src_id) {
      Some(t) => assert_eq(t.get_level(), lv)
      None => abort("源任务不存在: \{src_id}")
    }
    match e.challenge(task_id=src_id, by="auto", now="2026-10-29T10:05:00Z") {
      Err(m) => abort("源任务 level=\{lv} 时 challenge 应成功: \{m}")
      Ok(j) => {
        let new_id = match jget(j, "new_id") {
          Some(String(s)) => s
          _ => abort("challenge 回执缺 new_id: " + j.stringify())
        }
        match e.get_task(new_id) {
          Some(t) =>
            if t.get_level() != 6 {
              abort(
                "源任务 level=\{lv} 时新根 level 应为 6，实测 \{t.get_level()}（继承变异会读到 \{lv}）",
              )
            }
          None => abort("challenge 新根不存在: \{new_id}")
        }
      }
    }
  }
}
