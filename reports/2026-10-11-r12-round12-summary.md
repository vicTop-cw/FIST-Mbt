# R12 十二轮六相流水线 · 收敛总结（Round 12 · 收官）

日期：2026-10-11
轮次：12/12（[推进 → 寻虫 → 修复 → 打磨 → 验证 → 推进] × 12）

## 〇、本轮交付物

1. **本收敛总结**：R1–R12 全部改动汇总 + 四类性能/正确性模式清单。
2. **bug 账本清零确认**：`memory/bugs.md` 226 条，0 OPEN（BUG-227 已 FIXED）。
3. **回归测试**：engine 149 / evolve 32 / server 199 / ops / store / core
   合计 **600/600 通过**（并发会话的 `cmd/cli/upgrade_*.mbt` 语法错误
   未触碰，全量 `moon test` 在并发修复前停在 728/728）。

## 一、四类性能 / 正确性模式（R3–R12 沉淀的口诀）

### 模式 A：`* 86400` 溢出（Int32 溢出族，BUG-217/218/219/220）

- **根因**：`days * 86400` 在 days > 24855（约 68 年）时溢出 Int32。
  Y2038：`days_from_civil(2038,12,31) = 25201`，`* 86400 ≈ 2.18e9 > 2^31-1`。
  最大安全年份 2037。
- **修法**：`days > 24855` 前置守卫；`iso_to_secs` / `retention_days` /
  `heartbeat` / `cleanup` 全部加。
- **新增 issue_scan 规则**：`secs-overflow`（R7），pattern `["* 86400", "*86400"]`。
  本轮实测 0 命中——覆盖到位。

### 模式 B：`* 10 + d` 解析溢出（BUG-214/215/216/221）

- **根因**：逐位 `v = v * 10 + d` 无上界守卫，`Int` 越界静默饱和或溢出。
- **修法**：`v > (Int32Max - d) / 10` 前置守卫，超限 `return None`。
- **覆盖**：`bug_parse_int` / `sd_parse_int` / `ov_parse_int` /
  `parse_simple_double` / `parse_digits`（ops_ts.mbt，4 位数字安全）。
  测试：`output_validate_overflow_test.mbt` 11 位 `"99999999999"` → None。

### 模式 C：N×D 全库读（list_all / list_tasks 重复调用，BUG-223/224/225/226/227）

| 藏身处 | 修法 | 轮次 |
|---|---|---|
| 同一函数体内多次调用 | `let tasks_all = self.list_all()` 一次缓存 | R9 |
| 内部函数已算外层又算 | 让内部函数返回计算结果（`order` 字段回传） | R10 |
| 初始化值也走一次 O(N) | 取 `[0]` 也用缓存变量 | R11 |
| N×(每次查一次 DB) | 一次遍历建 Map 索引 → O(1) 查询 | R8 |
| 完整排序只为 top-k | 部分选择 O(kN) | R9 |

已收敛函数：`dag_topo_order` / `dag_slack_analysis` / `dag_schedule` /
`dag_cost_route` / `Archive::best` / `children_of` / `children_index` /
`parallelism` / `plan_exec_order` / `board_ascii` / `dag_mc` /
`health_check` / `executor_loads`。

### 模式 D：`issue_scan` 假阳性（保守误报优于漏报）

- R9 实测 23 条 medium 隐患，**0 条真隐患**：`unprotected-division`
  （`total > 0` 三元守卫）、`substring-overrun`（`max <= s.length()`）、
  `string-index`（`length() > 0`）全是已守卫代码。
- 结论：`issue_scan` 是**候选**扫描器，需调用方读上下文复核；
  `secs-overflow` 规则 0 命中即证明 R7 守卫覆盖到位。

## 二、DAG 调度底座性能演进轨迹

```
R3   dag_mc difficulty 缓存            O(N²) → O(N)
R5   dag_mc deps memo                  O(N×M) → O(N)
R6   board_ascii 双 getter 消除        O(2N) → O(N)
R7   DAG deps memo（3 处）             N×D → 1D
R8   children_index（1 处 + 2 消费）   N×D → 1D + O(1)
R9   dag_mc criticality 部分选择       O(N²) → O(10N)
R9   dag_topo_order 双 list_all        O(2N) → O(N)
R9   dag_slack_analysis 双 list_all    O(2N) → O(N)
R9   dag_schedule 双 list_all          O(2N) → O(N)
R10  dag_cost_route 重复 Kahn          O(2N) → O(N)
R11  Archive::best 双 all              O(2N) → O(N)
```

N=2079（当前任务库规模）时，`dag_mc` criticality 一处 2.1M → 20K 比较；
`dag_cost_route` 一处省 2079 次 DB read。

## 三、测试演进轨迹

| 轮次 | 测试数 | 说明 |
|---|---|---|
| R3 末 | 500 | 起步 |
| R5 末 | 650 | +150（decompose 等） |
| R7 末 | 726 | +76 |
| R8 末 | 728 | +2（BUG-221/222） |
| R11 末 | 728（全量）/ 600（并发受限后 6 包） | engine 149 / evolve 32 / server 199 / ops / store / core |

## 四、本轮 12 轮完成度

- **12/12 轮完成**（advance → bugfind → fix_and_merge → polish → verify → advance）。
- **226 条 bug 账本：0 OPEN**。
- **累计改动**：src/engine/engine_dag_{mc,ext}.mbt、src/engine/engine.mbt、
  src/engine/children_index_test.mbt、src/server/issue_scan.mbt、
  src/server/output_validate.mbt、src/server/output_validate_overflow_test.mbt、
  src/evolve/evolve.mbt、CHANGELOG.md（R12-P7 ~ R12-P11 五段）、
  reports/2026-10-11-r12-round{7,8,9,10,11}-report.md。

## 五、遗留（供后续接手）

1. **loop registry 持久化**（R5 lesson #6）：`ops_loop.mbt` 的
   `PipelineLoop` 是内存态，服务重启丢失；`loop_tick`/`loop_status`
   需重新 `loop_create`。修法：给 `PipelineLoop` 加 `to_json/from_json`、
   `LoopRegistry` 加 `save_to_file/load_from_file`，`server.mbt` 注册时
   先 load。**server.mbt 被并发会话占用，本轮未改**。
2. **并发会话未提交文件**：`src/server/server.mbt`、`src/store/store_sqlite.mbt`、
   `src/engine/engine_circuit.mbt`、`src/engine/cost_tool.mbt`、
   `src/omega/omega_tool.mbt`、`src/ops/ops_modes.mbt`、
   `cmd/cli/upgrade_{core,js,native}.mbt`。全量 `moon test` 需等并发会话
   提交后才可跑通。
3. **`plugins/*` 已漂移**：因并发会话修改 `src/server/server.mbt`，
   `check_plugin_sync.py` FAIL；`gen_plugins.py` 需在并发会话稳定后重跑。