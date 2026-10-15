# Goal-2 Round 36 报告：CAF 记忆逐条持久化层（caf_memory_dump / load）

- **日期**：2026-10-15
- **提交**：R36 code（2 文件 +267：`src/router/router_caf_persist.mbt` + `_test.mbt`）
- **状态**：§2.3 server 接线仍阻塞（并发 agent 占用），本轮完成接线的**持久化前置**

## 结果摘要

### 发现缺口

§2.3 接线要求 `executor_run` 走 CAF 路由后，记忆要跨 server 重启存活。但审查 `CafMemory` 发现：

- **`CafMemory::to_json` 是聚合快照**（total/count/by_model，`src/router/router_caf.mbt` L211），
  **不含原始 records** → 只能展示，**无法恢复记忆**。
- **`from_json` 根本不存在**（grep 全库 0 匹配）。

即 §2.3 接线完成后，server 重启会**丢光 CAF 记忆**。这是接线的持久化缺口。

### 新增逐条持久化层（独立文件，不碰并发域）

新增 `src/router/router_caf_persist.mbt`：

| 函数 | 作用 | 关键契约 |
|---|---|---|
| `caf_memory_dump(mem) : Json` | 逐条导出（时间序），含 `max_size` | 保留原始记录可完整往返 |
| `caf_memory_load(json) : (CafMemory, Array[String])` | 从逐条 JSON 恢复记忆 | 坏类型降级 + warning，绝不 panic |

**格式**（与 `model-router-{ns}.json` 同形态，落盘 `memory/model-router-caf-{ns}.json`）：
```json
{ "max_size": Int,
  "records": [ { "feature_hash": Int, "model": Str, "ok": Bool,
                 "cost": Double, "ts": Str }, ... ] }
```

**恢复顺序守恒**：`load` 用 `new(max_size)` + 逐条 `push` 重建。因 `push` 后 `all()` 从 index 0 起遍历，
只要 `dump` 按 `all()` 顺序导出、`load` 按序 `push`，恢复后 `all()` 顺序与原记忆一致。

**坏类型降级**（与 `RouterConfig::from_json` 同口径）：顶层非对象→空+warning；`max_size` 非整数→10000+warning；
`records` 非数组→空+warning；单条缺任一字段→跳过该条+warning（不污染记忆）。

### 新增 4 条往返契约锁

`src/router/router_caf_persist_test.mbt`（blackbox，只用 pub API）：

| 锁 | 钉死的契约 | 区分度 |
|---|---|---|
| `caf_persist_1_空记忆往返` | 空 → dump → load → all() 空、warns 空 | 断言 all 空 + warns=0 |
| `caf_persist_2_多条记录往返` | 3 条 → dump → load → all() **逐字段一致** | 逐字段比对（feature_hash/model/ok/cost/ts） |
| `caf_persist_3_坏类型records降级` | records 给 String → 空 + 1 warning | 断言 all 空 + warns≥1 |
| `caf_persist_4_坏字段单条跳过` | 缺 feature_hash 的条被跳过，正常条保留 | 断言保留 1 条 free-a + warns≥1 |

**意义**：锁 `caf_persist_2` 是核心——证明**往返可恢复**（顺序 + 字段），不是只「不 panic」的弱断言。

## 资源消耗

`moon fmt` / `moon check`（3 次修复迭代）/ `moon test --target js src/router` / 全仓回归 / `git commit`

## 任务分配记录

本轮**无任务分配**（未拆子任务）。本人在 router 域独立推进，新文件独占（不修改并发域 `router_caf.mbt`，
只读引用 `CafMemory`/`CafRecord` 的 pub API）。

## 遗留风险

- **§2.3 server 接线仍未做**。持久化层是接线时的 `caf_memory.push` + 重启恢复前置，
  但接线本体（`executor_run` 回写 + status 展示 + 落盘）仍待并发 agent 释放 `model_router_ops.mbt`。
- **落盘未接**：本层是**纯计算序列化**（dump/load），**不碰文件 IO**（避免与并发 agent 的 server IO 冲突）。
  接线时由 server 层做 read/write `memory/model-router-caf-{ns}.json`。
- **并发 agent WIP 面极大**：工作树 89+ 文件未提交（整个 src/ 在同步开发），
  本轮 `memory/bugs.md` 已被并发 agent staged（R35 已实际踩过 commit 污染，本轮用 `git commit -- <paths>` 正确避开）。

## 后续建议

1. **接线方案（R37 首选）**：§2.3 的 CAF 逻辑放**独立文件** `src/server/model_router_caf_ops.mbt`，
   `model_router_ops.mbt` 只加最少调用点（如 `executor_run` 成功后一行 `caf_memory.push(...)`）。
   调用持久化层的顺序：
   - `executor_run` 前：`caf_memory_load` 从 `memory/model-router-caf-{ns}.json` 恢复
   - `executor_run` 后：`caf_memory_dump` 落盘
   - status 工具：`caf_memory_status_text`（已有）+ dump 的 records 数
2. **R37 备选**：CAF 记忆的**容量上限与淘汰策略**审查（`max_size` 默认 10000，无软淘汰；纯计算域）
3. **R37 备选 2**：`caf_memory_dump` 的 `max_size` 读取依赖 `to_json()["capacity"]`（间接），
   若 `to_json` 未来改动会静默退回默认 10000——建议接线时在 server 层显式传 max_size。

## 超额内容

**Json API 修正记录**（R35/R36 连续踩到，值得钉死）：
1. `Json::Number/Array/String/Bool`（大写构造子）**不存在**——用 `Json::number/array/string/boolean`（小写函数）
2. `json["key"]` **语法无效**（`Type Json has no method op_get`）——Json 对象须先解构 `Json::Object(m)`
   再 `m.get("key")`（返回 `Option[Json]`）
3. Bool 匹配用 `Json::True` / `Json::False`（不是 `Json::Bool(b)`）
4. `Json::object({ "key": v })` 字面量构造有效，`Json::array([...])` 有效

## 来源

- 代码（只读审查）：`src/router/router_caf.mbt`（CafRecord L14、CafMemory L40、to_json L211）
- 新增：`src/router/router_caf_persist.mbt`、`src/router/router_caf_persist_test.mbt`
- 设计：`docs/2026-10-15-fist-mbt-caf-p2c-wiring-design.md`、`docs/2026-10-15-fist-mbt-caf-p2d-cold-start-design.md`
