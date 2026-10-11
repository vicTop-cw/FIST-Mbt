# Round 9 报告（R12 十二轮六相流水线 · 第 9 轮）

日期：2026-10-11
阶段：推进 → 寻虫 → 修复 → 打磨 → 验证

## 一、advance（推进）

延续 R8 `list_tasks()` 全库读收敛主线，**系统排查 DAG 调度底座的所有重复读**。

`engine_dag_ext.mbt` 中 `list_all()` 的 11 处调用点逐一核对函数体内出现次数：

| 函数 | list_all() 次数 | 修复 |
|---|---|---|
| `parallelism` | 1（R7 已修） | ✓ |
| `dag_topo_order` | 2 → 1 | ✓（BUG-223） |
| `dag_slack_analysis` | 2 → 1 | ✓（BUG-224） |
| `dag_schedule` | 2 → 1 | ✓（BUG-225） |
| `dag_cost_route` | 1（但间接再调 `dag_slack_analysis`） | 遗留（见 §七） |
| `dag_mc` | 1（R5 已 memo） | ✓ |

## 二、bugfind（寻虫）

**BUG-223（`dag_topo_order` 双 `list_all()`）**：Kahn 拓扑排序的构建阶段把
`self.list_all()` 调了两次——第一次取 ids，第二次建边。SqliteStore 下每次
都是全库读，N=2079 时多 2079 次 DB 读。

**BUG-224（`dag_slack_analysis` 双 `list_all()`）**：PERT/CPM 瓶颈分析取 ids
一次、建 reverse 边又一次。

**BUG-225（`dag_schedule` 双 `list_all()`）**：排程视图取 ids 一次、统计执行者
负载又一次。

这三处都是"DAG 底座"——被 `dag_cost_route` / `dag_mc` / `dag_schedule` /
`dag_sort` 等 N 个下游调用，一次调用内多读一次 = 全库多扫一遍。

## 三、fix_and_merge（修复）

- **BUG-223 commit `1301c1d`**：`dag_topo_order` 加 `let tasks_all = self.list_all()`，
  两个循环共用。
- **BUG-224 + BUG-225 commit `2243408`**：`dag_slack_analysis` 和 `dag_schedule`
  各加 `let tasks_all = self.list_all()`，各自的取 ids 与建边/统计负载两循环共用。
- **commit `9261583`**：`dag_mc` criticality top-10 从完整选择排序改为部分选择
  （O(N²) → O(10N)）。

## 四、polish（打磨）

- `CHANGELOG.md` 新增 R12-P9 段（BUG-223/224/225 三处 list_all 消除 + criticality
  top-k 部分选择 + issue_scan 假阳性排查）。
- 本报告落盘 `reports/2026-10-11-r12-round9-report.md`。

## 五、verify（验证）

- `moon test --target js --no-render src/engine`：**149/149 通过**（每次修复后复跑）。
- `moon test --target js --no-render src/server`：**199/199 通过**。
- 全量 moon test 在并发会话新增 `cmd/cli/upgrade_*.mbt` 语法错误前 728/728 通过，
  本次改动未改变该基线（改动仅在 `src/engine/engine_dag_ext.mbt` 与
  `src/engine/engine_dag_mc.mbt`，两文件均通过）。
- `output_validate` L4：本轮新增产物 + 既有 CHANGELOG/报告 均通过。
- 三面守卫：`check_tools_sync` PASS / `check_doc_surface` PASS。
  `check_plugin_sync` 因**并发会话**修改 `src/server/server.mbt` 等而未重生成
  插件而 FAIL——与本轮改动无关（本轮未改任何工具 schema）。

## 六、沉淀（lessons）

1. **「函数体内 `list_all()` 出现 N 次 = N-1 次可省」** 是 R8 结论的
   直接推广：R8 查的是跨函数（`children_of` 每查调一次），R9 查的是**同一函数
   体内多次调用**。一次 `let tasks_all = self.list_all()` 放函数顶，所有循环共用，
   是最通用且零回归的写法。

2. **「下游只用 top-k 却全量排序」是常见的 O(N²) 藏身处**：`dag_mc` criticality
   只 push 前 10 名，却对 N 个任务做完整选择排序。改成部分选择后 N=10000
   从 50M 比较降到 100K——差 500 倍。

3. **`issue_scan` 的 23 条 medium 隐患多为假阳性**：规则用「行级子串匹配」，
   不识别 `total > 0` / `max <= s.length()` / `int_safe` 前置守卫。这不是工具的
   bug（保守误报优于漏报），但**复核成本值得诚实记录**：23 条中 0 条真隐患。
   `secs-overflow` 规则 0 命中则**证明 R7 的 `* 86400` 守卫覆盖到位**。

## 七、遗留

- `dag_cost_route` 内部 `dag_slack_analysis()` 已调 `dag_topo_order()`，
  随后又调一次 `dag_topo_order()`——重复 1 次拓扑序。彻底修需
  `dag_slack_analysis` 的返回值带上 order（返回结构变更，风险中等）。
  建议 R10 或 R11 作为更大重构的候选。
- 12 轮 pipeline 进度：Round 1–9 已完成，Round 10–12 待续。