# Round 8 报告（R12 十二轮六相流水线 · 第 8 轮）

日期：2026-10-11
阶段：推进 → 寻虫 → 修复 → 打磨 → 验证

## 一、advance（推进）

延续 R7 的 `deps_satisfied` N×(1+D) 主线，**系统排查所有「循环内调查询方法」模式**。

- 全量 grep `get_task` / `list_tasks` / `children_of` 覆盖 src 全部引擎方法。
- `list_tasks()` 调用点收敛为 4 处（`children_of` / `children_index` / `list_all` / `list_in_ns`）；
- `topo_sort` 每任务调一次 `get_task`（O(N)，非 N×D）；
- `dag_slack_analysis` / `dag_schedule` / `dag_cost_route` 均为 O(N) 级（单次遍历）；
- `omega_strong` / `omega_gate` / `docs_gate` 均为单任务查询；
- `bug_list_with_links` 的 N 次 `task_status_of` 是 N 个不同 task_id（无法去重，非同款）。

### 关键发现

**BUG-222（子树遍历 O(N×M)）**：`children_of(task_id)` 每查一个父任务
都 `store.list_tasks()`（全库遍历）。在 `subtree_ids`（`progress_gate` /
`cost_budget_split` / `plan_revise` 等都要走）和 `plan_exec_order` 这类
"按子树递归遍历"里是 O(N×M)。与 R7 已修的 `deps_satisfied` N×(1+D) 同款病灶，
只是维度从"依赖"换成了"父→子"。

## 二、bugfind（寻虫）

**BUG-221（同型函数漏守卫）**：`output_validate.mbt` 的 `ov_parse_int` 与
`ops_selfdrive.mbt` 的 `sd_parse_int` 是同型函数（十进制字符串 → Int），
但 `ov_parse_int` **缺 `sd_parse_int` 的 `int_safe` 上界守卫**（200_000_000）。
长数字串（如 `max_findings=99999999999`）在 `v = v * 10 + d` 上溢出 Int32
而不报错（绕回/精度丢失）。这是"同一代码模式复制了两份，只给一份加防护"的经典疏漏。

## 三、fix_and_merge（修复）

### BUG-221（commit `1142b17`）
- `ov_parse_int` 加 `if v >= int_safe { return None }` 守卫；
- 函数改 `pub fn`（供测试直接调用）；
- 新增 `output_validate_overflow_test.mbt`：11 位 9 触发 None、3 位正常数字仍可解析。

### BUG-222（commit `ed82f5d`）
- `engine.mbt` 新增 `pub fn children_index() -> Map[String, Array[String]]`，
  一次 `list_tasks()` 建 parent→children 索引，之后每次查 O(1) Map；
- `engine_dag_ext.mbt` 的 `subtree_ids` 改用索引遍历（O(N+M)）；
- `engine.mbt` 的 `plan_exec_order` BFS 改用索引；
- 新增 `children_index_test.mbt`：建 3 层树（P→A,B→A1,A2），断言索引与
  `children_of` 对同 parent 返回同 id 集、叶节点索引为空。

## 四、polish（打磨）

- `CHANGELOG.md` 新增 R12-P8 段（BUG-221/222 双收口记录）；
- 本报告落盘 `reports/2026-10-11-r12-round8-report.md`。

## 五、verify（验证）

- `moon test --target js --no-render`：**728/728 通过**（Round 7 末 726 → 本轮 +2）。
- `output_validate` L4：7 条产物检查全过，证据层 `l4-pass`。
- 三面守卫：`check_plugin_sync` / `check_tools_sync` / `check_doc_surface` 均 PASS。
- `git log` 本轮 commits：`1142b17`（BUG-221）、`ed82f5d`（BUG-222）。

## 六、沉淀（lessons）

1. **同型函数只给一份加防护 = 另一份是隐患**。`sd_parse_int` 有 `int_safe`
   守卫，`ov_parse_int` 没有——复制代码不复制防护是最常见的疏漏。
   教训：新增同型函数时先 grep 同型前身，把防护清单抄一遍。

2. **「循环内调查询方法」是通用病灶形态**，但维度不一：
   `deps_satisfied` 是 N×(1+D)、`children_of` 是 N×M、`bug_list_with_links`
   是 N×1（不可去重）。同一类"一次建索引、循环里走 Map"的解药，
   在维度可去重时才适用；不可去重要诚实标注不修。

3. **`list_tasks()` 是全库读，任何循环内调用都值得审计**。全仓库 `list_tasks`
   只剩 4 处（2 处是索引构建，2 处是 `list_all`/`list_in_ns` 单次返回），
   说明清理后模式收敛——这本身就是可测量的进展。

## 七、遗留

- R5 lesson #6（进程重启丢 LoopRegistry）仍未解决——建议 R10 或 R11 作为算子扩展方向。
- 12 轮 pipeline 进度：Round 1–8 已完成，Round 9–12 待续。