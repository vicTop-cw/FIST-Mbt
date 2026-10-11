# Round 7 报告（12 轮六相流水线）

- **时间**：2026-10-11T09:00Z – 2026-10-11T09:07Z
- **本轮相位**：advance（性能：DAG 依赖判断消除逐条 DB 读）

## 一、advance（推进）

**根任务 T0r566**「DAG 依赖判断三处消除逐条 DB 读」。

### 病灶

`FistEngine::deps_satisfied` 内部对每个依赖调 `self.store.get_task(tid)`
（SqliteStore 下是 DB 读）。三个调用方都是"逐任务调 `deps_satisfied`"模式：

| 调用方 | 复杂度 |
|--------|--------|
| `ready_tasks`（engine.mbt:1397） | N×(1+D) 次 DB 读 |
| `parallelism`（engine_dag_ext.mbt:92） | N×(1+D) 次 DB 读 |
| `task_triage`（engine_triage.mbt:175） | N×(1+D) 次 DB 读 |

### 修复

**一次遍历建 `completed : Map[String, Bool]`（id → 是否已完成）**，
之后 `deps_ready_memo(dep_ids, completed)` 用 O(1) Map 查询判依赖满足。

新增 `pub fn deps_ready_memo`：
```moonbit
pub fn deps_ready_memo(
  dep_ids : Array[String],
  completed : Map[String, Bool],
) -> Bool {
  for tid in dep_ids {
    let done = match completed.get(tid) {
      Some(b) => b
      None => false
    }
    if not(done) { return false }
  }
  true
}
```

语义完全等价：依赖不存在 → Map 查不到 → false（与 `get_task` None → false 一致）。

### 提交

- `36710d6`：`ready_tasks` 复用 deps_ready_memo
- `149eea3`：`parallelism` 复用 deps_ready_memo（`deps_ready_memo` 加 pub 供跨文件复用）
- `935e5a5`：`task_triage` 复用 deps_ready_memo

## 二、bugfind（寻虫）

advance 阶段发现 **issue_scan 漏掉了 `* 86400` 家族**：
`possible-overflow` 规则只匹配 `* 10` / `to_int()*`，
而 BUG-217/218/219 的 `* 86400` 模式（一天 86400 秒是大系数，
超过 24855 天即溢出 Int32）从未被自动扫描捕获。
这是"寻虫工具自身漏虫"——`issue_scan` 是 bugfind 阶段的主工具，
它漏掉这个家族意味着后续轮次会反复踩同一坑。

## 三、fix_and_merge（修复）

新增第 11 条规则 `secs-overflow`（medium）：
- pattern: `["* 86400", "*86400"]`
- 说明：加天数上界守卫（如 `if days > 24855`），或改用 Int64

配套测试 `issue_scan_secs_overflow_test.mbt`（建 temp/lint_secs 夹具
注入 `days * 86400`，断言 by_rule 统计含 secs-overflow）。
全量 726/726 通过。

现有 3 处 `* 86400` 已全部守卫（ops_ts.mbt:57 由 BUG-217 修复、
ops_cleanup.mbt:25 由 BUG-219 修复、model_router.mbt:259 由 BUG-218 修复），
守卫感知过滤正确地不报它们——规则生效但不误报，正是我们要的。

三处 DAG 遍历统一为同款优化，代码收敛在 `deps_ready_memo` 单一来源。

## 四、polish（打磨）

- 本报告落盘。
- CHANGELOG 更新见下一节。

## 五、使用的 FIST 工具

publish / claim / execute / submit / verify / output_validate。

## 六、沉淀（本轮教训）

1. **同一性能模式在不同文件重复出现**——
   `deps_satisfied` 逐条 DB 读这个模式在 `ready_tasks` / `parallelism` /
   `task_triage` 三处独立出现。**找一次模式、修三处**比逐个文件发现更高效。
   本轮一次建 `deps_ready_memo` 就全部收口。
2. **`Map[String, Bool]` 一次遍历替代 N 次查询是 DAG 场景的万能药**——
   依赖满足判断本质是"所有依赖都 completed"，用一个布尔映射就够。
   R5 的 dag_mc deps 映射、R7 的 ready/parallelism/triage 都是这个模式。
3. **性能债往往藏在"看起来合理"的循环里**——
   `for t in tasks { if self.deps_satisfied(t.get_id()) }` 看起来是标准写法，
   但 `deps_satisfied` 内部又是个循环，于是 O(N×D) 悄悄变 O(N×D×DB_read)。
   **任何"循环里调用会查询的方法"都是疑点**。
4. **算子扩展方向可以收敛**——
   本轮不再新开功能，而是把既有性能主线（R3 难度解析缓存、R5 deps 映射、
   R6 board_ascii getter 去重、R7 DAG 依赖 memo）持续推进。
   "每个热点找一次 + 同款复用"是稳定节奏。