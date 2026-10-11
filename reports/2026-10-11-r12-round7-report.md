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

本轮 advance 阶段顺带确认了无新 bug（`deps_ready_memo` 语义等价，
不存在新的边界条件）。上一轮 R6 已把 BUG-217/218/219/220 全部收口，
本轮无 OPEN bug。

## 三、fix_and_merge（修复）

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