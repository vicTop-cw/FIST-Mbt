/// engine/evolve_auto_wire.mbt —— Omega 打回自动回流（automatically learn on reject）
///
/// 目标：让 fist-mbt 的强验证流程「会犯错」自动沉淀成可演绎的教训——
/// 每次 Omega 语料审核 / 成果复验被打回（reject）时，无需人工额外调 `evolve_lesson`，
/// 引擎即自动把失败原因归档成一条 `[lesson]<类目>` 资产入 DGM。
///
/// 设计约束：engine 不能反向依赖 server（会成环），故此处只复用
/// `@evolve.evolve_lesson_persist`（evolve 包仅依赖 store），直接把教训落库到
/// evolve_artifacts，不再经过内存 Archive。落库后 plan/claim 的 inject 与
/// dead_ends 均可直接检索到该教训。

///|
/// /// Omega 打回自动落一条教训。cat 为类目 tag，reason 为失败原因，fix 为纠偏提示。
/// seq 用于同一类目、同一时刻多次打回的 id 趋唯一；id 纳入 cat，
/// 保证 spec 打回 / 复验打回 / 超限升级在同一时间戳下互不覆盖（upsert 语义防丢史）。
pub fn FistEngine::omega_auto_lesson(
  self : FistEngine,
  seq : Int,
  cat : String,
  reason : String,
  fix : String,
  now : String,
) -> Bool {
  let id = "omega-lesson-" +
    @evolve.lesson_ts_part(now) +
    "-" +
    cat +
    "-r" +
    seq.to_string()
  // 仅 SQLite 后端支持 evolve_artifacts 持久化；内存后端返回 false（不产生副作用）
  @evolve.evolve_lesson_persist(
    self.store.sqlite_store(),
    id~,
    cat,
    reason,
    fix,
    now,
  )
}
