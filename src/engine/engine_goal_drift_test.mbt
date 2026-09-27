/// engine_goal_drift_test.mbt —— BUG-25 回归锁：goal_drift_check 在中文语料上的判别力口径。
///
/// 锁的到底是什么（三件事，缺一就算没修）：
///   ① 判据**自述不是硬门**（hard_gate=false + 每条 check 带 advisory=true）——
///      BUG-25 的原始症状是 6/6 全误报，修法不是把阈值调到永远通过（那条形同虚设），
///      而是把"不能当打回依据"写进返回体，让下游误用变成可见违约；
///   ② **保序性**：真实改写子任务的 drift 必须严格低于跨域外来任务（标定用同一手法）；
///   ③ **低信息量不再恒阳性**：空根目标/模板桩子任务判 insufficient，而不是 drift_suspect。
/// 夹具文本取自本机 fist-mbt.db 的真实任务（T0r61/T0r61.2/T0r126.1），不是编的样例；
/// 数字口径可用 `python scripts/calibrate_goal_drift.py` 复跑（同一套 tokens/coverage）。

///|
/// BUG-25 夹具：真实根任务描述（T0r61，Cypy 26 项缺陷修复的拆解根）
let b25_root = "[gate:required] 按 2026-09-24 三方代码审查报告修复 Cypy 仍存在的 26 项 critical/high 缺陷（critical 4 项：依赖图恒空、#include 任意文件读取、Tab 缩进推断、pointer 所有权模型）。每个拆解单元走 Omega 强验证：建语料→验证者审语料→执行→复验成果；验收判据 python -m pytest tests -q 全绿 且 bash scripts/e2e_golden.sh PASS=22 FAIL=0。"

///|
/// 真实子任务（T0r61.2）：合法改写——换了一整套词，只保留少数共同术语
let b25_child_real = "[gate:required] 前端解析、预处理与类型判等修复：cypyc/parser/preprocessor.py 的 #include 文件名未校验未规范化（<../../etc/passwd> 任意文件读取）；macro_expander.py 嵌套宏不展开、字符串实参不转义、纯文本替换破坏字符串字面量与注释；cypyc/utils/indent_detector.py 把 Tab 按字符 //4 折算致缩进推断系统性错误；cypyc/analyzer/type_checker.py 的 Type.__eq__ 忽略 union_members 使 Optional[int]==int。单元1 固化失败测试，单元2 实施修复并回归。"

///|
/// 外来任务（T0r126.1，Actus 项目）：与根目标无关，应当排得更"漂"
let b25_child_foreign = "C1 workflow 入口链断裂（前缀 repro_wf_）：actuscore/workflow.py:518 读索引键 'file_path' 而实际键是 'path' → action_path='' → FileNotFoundError；②仓库相对 path 未对 ACTUS_REPO_ROOT 归一，绝对路径直穿测试机。"

///|
/// 前缀型切片（本仓 task_plan_deep 的常见形状：根描述原样 + 单元名）——coverage 应判 aligned
fn b25_prefix_slice(unit : String) -> String {
  b25_root + " - 子任务单元 " + unit + " [omega:required]"
}

///|
/// 建一棵挂在给定根描述下的树（不走 publish，直接写 store 以自由控制描述）
fn b25_tree(
  root_desc : String,
  children : Array[(String, String)],
) -> FistEngine {
  let e = FistEngine::new()
  ignore(
    e.store.create_task(
      @core.Task::new(
        id="R",
        project_dir="/proj/demo",
        description=root_desc,
        created_at="2026-09-27T00:00:00Z",
      ),
    ),
  )
  for c in children {
    let (id, desc) = c
    ignore(
      e.store.create_task(
        @core.Task::new(
          id~,
          project_dir="/proj/demo",
          description=desc,
          parent_id="R",
          created_at="2026-09-27T00:00:00Z",
        ),
      ),
    )
  }
  e
}

///|
/// 读出某子任务的数值字段（drift_score/redundancy_score）
fn b25_score(j : Json, id : String, key : String) -> Double {
  match j.value("checks") {
    Some(Array(a)) =>
      for x in a {
        match x.value("subtask_id") {
          Some(Json::String(s)) =>
            if s == id {
              match x.value(key) {
                Some(Json::Number(n, ..)) => return n
                _ => abort("\{key} 缺失: " + x.stringify())
              }
            }
          _ => ()
        }
      }
    _ => abort("checks 缺失: " + j.stringify())
  }
  abort("未找到子任务 " + id)
}

///|
/// 读出某子任务的布尔字段（advisory/re_anchor）
fn b25_flag(j : Json, id : String, key : String) -> Bool {
  match j.value("checks") {
    Some(Array(a)) =>
      for x in a {
        match x.value("subtask_id") {
          Some(Json::String(s)) =>
            if s == id {
              match x.value(key) {
                Some(v) =>
                  match v.as_bool() {
                    Some(b) => return b
                    None => abort(key + " 非布尔: " + x.stringify())
                  }
                _ => abort("\{key} 缺失或非布尔: " + x.stringify())
              }
            }
          _ => ()
        }
      }
    _ => abort("checks 缺失: " + j.stringify())
  }
  abort("未找到子任务 " + id)
}

///|
/// 读出顶层布尔字段
fn b25_top_flag(j : Json, key : String) -> Bool {
  match j.value(key) {
    Some(v) =>
      match v.as_bool() {
        Some(b) => b
        None => abort("顶层 \{key} 非布尔: " + j.stringify())
      }
    None => abort("顶层 \{key} 缺失: " + j.stringify())
  }
}

///|
test "BUG-25：中文改写型子任务——判据仍发红，但返回体自述不是硬门（advisory/hard_gate）" {
  let e = b25_tree(b25_root, [
    ("C1", b25_child_real),
    ("C2", b25_child_foreign),
    ("C3", b25_prefix_slice("1")),
  ])
  let j = e.goal_drift_check("R")
  // ① 前缀型真实切片 aligned（旧口径 char-jaccard 在这类样本上 16.9% 误报，新口径 1.9%）
  assert_eq(gdc_verdict(j, "C3"), "aligned")
  // 改写型子任务在纯词法口径下**仍**会被点名——这是 BUG-25 标定出来的事实，不假装修好了
  assert_eq(gdc_verdict(j, "C1"), "drift_suspect")
  // 但每一条都必须是 advisory，且顶层 hard_gate=false：下游拿它自动打回=违约使用
  assert_eq(b25_top_flag(j, "hard_gate"), false)
  assert_eq(b25_flag(j, "C1", "advisory"), true)
  assert_eq(b25_flag(j, "C2", "advisory"), true)
  assert_eq(b25_flag(j, "C3", "advisory"), true)
  // 返回体自带标定出处（调用方不必回忆 README 就能看到"这判据的假阳性是多少"）
  match j.value("calibration") {
    Some(Object(c)) => {
      match c.get("reworded_pairs_suspect") {
        Some(Json::Number(n, ..)) => assert_true(n > 0.5)
        _ =>
          abort("calibration.reworded_pairs_suspect 缺失: " + j.stringify())
      }
      match c.get("conclusion") {
        Some(Json::String(s)) => assert_true(s.contains("advisory"))
        _ => abort("calibration.conclusion 缺失: " + j.stringify())
      }
    }
    _ => abort("calibration 缺失: " + j.stringify())
  }
  // note 里必须写明"不可作打回硬门"——J10 口径：自述范围==实现
  match j.value("note") {
    Some(Json::String(s)) => assert_true(s.contains("非硬门"))
    _ => abort("note 缺失")
  }
}

///|
test "BUG-25：保序性——真实改写子任务的 drift 必须低于跨域外来任务" {
  // 判据无法把"合法改写"从硬门下游救回来（上一条锁的就是这个事实），
  // 但它必须**保序**：外来任务比自家切片更可疑。丢了这个性质，
  // drift_suspect 连排序信息都没有，就真成了恒阳性噪声。
  let e = b25_tree(b25_root, [("C1", b25_child_real), ("C2", b25_child_foreign)])
  let j = e.goal_drift_check("R")
  let d_real = b25_score(j, "C1", "drift_score")
  let d_foreign = b25_score(j, "C2", "drift_score")
  assert_true(d_real < d_foreign)
  assert_true(d_foreign > 0.7)
  // 口径自证：coverage 非对称 ⇒ 子任务多写模板不被长度惩罚（drift 只会持平或更低）
  let long_copy = b25_child_real +
    " " +
    b25_child_real +
    " 附加模板：目标/边界/回传格式/验收标准"
  let e2 = b25_tree(b25_root, [("C1", b25_child_real), ("C2", long_copy)])
  let j2 = e2.goal_drift_check("R")
  assert_true(b25_score(j2, "C2", "drift_score") <= d_real)
}

///|
test "BUG-25：低信息量判 insufficient，不再混进 drift_suspect" {
  // 真实形状：本库 default ns 的 T0r292 树——根任务描述为空串，子任务是模板桩。
  // 旧口径下空根 ⇒ jaccard 恒 0 ⇒ 全部判漂移（BUG-25 的 6/6 里就有这一类）。
  let e = b25_tree("", [("C1", "T0r66 的子任务 1"), ("C2", "子任务")])
  let j = e.goal_drift_check("R")
  assert_eq(gdc_verdict(j, "C1"), "insufficient")
  assert_eq(gdc_verdict(j, "C2"), "insufficient")
  assert_eq(gdc_count(j, "insufficient"), 2)
  assert_eq(gdc_count(j, "drift_suspect"), 0)
  // re_anchor 只对真漂移给出，insufficient 不许挂"把根目标重新注入"的建议
  assert_eq(b25_flag(j, "C1", "re_anchor"), false)
}

///|
test "BUG-25：兄弟冗余口径保留词序不敏感分量（换位重复仍要抓得住）" {
  let e = b25_tree("数据采集与清洗管线", [
    ("C", "数据采集模块实现"),
    ("D", "采集数据模块实现"),
  ])
  let j = e.goal_drift_check("R")
  // 二字组口径下这俩只有 0.556（会漏报），可见字符集口径是 1.0——取最大值才既不误伤又不漏
  assert_eq(gdc_verdict(j, "C"), "redundant_suspect")
  assert_eq(gdc_verdict(j, "D"), "redundant_suspect")
  assert_eq(b25_score(j, "C", "redundancy_score"), 1.0)
}
