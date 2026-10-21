# 副机报告 · 0001 unused function 死代码清零（T0r37 / BUG-380）

- 日期：2026-10-21
- 分支：`slave/fix/unused-function-0001`（基点 `659afac`，强制 `slave/` 前缀）
- 任务：T0r37
- 台账：BUG-380（FIXED）
- 交付面：5 文件 +3/−120 行（`src/engine/dag_mc_test.mbt`、`src/server/issue_scan.mbt`、`src/server/model_router_ops.mbt`、`src/server/server.mbt`、`src/symbolic/symbolic.mbt`）

## 结果摘要

1. **0001 由 10 条降到 2 条**：`moon check --target js` 总 warning **515 → 504**，errors 仍为 0。
2. **删除 8 条全域零引用的私有死代码**：`mc_top_crit`、`scan_filter_guarded`、`mr_caf_read`、`intlist`、`to_ids_result`、`lit_var`、`lit_sign`、`lit_neg`。
3. **保留 2 条「仅测试引用」的函数**：`should_upgrade`（upgrade-5 白盒锁 6 处断言）与 `scan_outside_literal`（BUG-72 成对锁 10 处断言）——删函数等于删覆盖，按 BUG-351 留档口径不动。
4. **测试零回归**：`moon test --target js` 保持 **1340 / 1340 / 0**；公开 `pub` 面与 `.mbti` 零变化。

## 证据（真实读数）

| 项 | 命令 / 判据 | 读数 | 证据文件 |
|---|---|---|---|
| warning 面（改前） | `moon check --target js` | 515 warnings / 0 errors；0001 = 10 | `temp/t36_check_full.log` |
| warning 面（改后） | `moon check --target js` | **504 warnings / 0 errors**；0001 = 2 | `temp/t37_check_full.log` |
| 分族分布（改前） | `grep -oE 'Warning: \[[0-9]+\]'` | 0020 473 / 0006 12 / 0002 11 / 0001 10 / 0009 3 / 0078 3 / 0023 2 / 0027 1 | `temp/t36_check_full.log` |
| 分族分布（改后） | 同上 | 0020 471 / 0006 12 / 0002 11 / 0009 3 / **0078 2** / 0023 2 / **0001 2** / 0027 1 | `temp/t37_check_full.log` |
| 测试面 | `moon test --target js` | `Total tests: 1340, passed: 1340, failed: 0` | `temp/t37_test_full.log` |
| 格式面 | `moonfmt.exe` 逐份比对（CR 归一） | 5 份全 FMT-OK，bareLF = 0 | 会话输出 |
| 守卫电池 | `run_guards.py` | 38 格 / 失败 5 / SKIP 5 / 缺执行面的尺 0（与改前逐格相同） | `temp/t37_battery.log` |

### 预存红（本单未引入、未代修）

| 守卫 | rc | 成因 |
|---|---|---|
| `check_scripts_index.py` | 1 | 6 个脚本未在 `scripts/README.md` 登记（含 `run_guards.py`） |
| `check_exit_code_contract.py --selftest` | 2 | 判据自检不通过——尺子自身坏了，先修判据再读读数 |
| `check_plugin_sync.py` | 1 | 下游 `gen_plugins` 被账本重复编号挡住 |
| `gen_plugins.py --check` | 2 | 账本 5 组重复编号（BUG-183/192/328/329/330 各×2） |
| `check_plan_landing.py --gate` | 1 | 历史计划面文档缺失/移动超上限 |

## 分析

- **真死与假死分开**：10 条里 8 条在 `src/` + `cmd/` 全域零引用（产品与测试都无调用）；剩下 2 条在主单元判未用，但白盒测试真在引用：`upgrade_wbtest.mbt` 的 upgrade-5 有 6 处 `should_upgrade` 断言，`issue_scan_wbtest.mbt` 有 10 处 `scan_outside_literal` 断言（BUG-72 的字面量边界成对锁）。警告文本相同，处置不能相同。
- **两条是「被取代」而非功能缺失**：`scan_filter_guarded` 的批量守卫过滤已内联进主扫描路径（`issue_scan.mbt:1907` 直接调 `scan_finding_guarded`，且 BUG-268 的 12 行窗口说明随实现保留）；`mr_caf_read` 已被 `mr_caf_read_diag` 取代（后者区分「不存在 / 坏 JSON / 合法 JSON」）。删旧符号时同步把 `model_router_ops.mbt` 两处文档里的指名改成行为描述，避免注释指向不存在的函数。
- **连带减少必须能逐条归因**：总数 515→504 减 11，其中 8 条是 0001 本体；另 2 条是 `mc_top_crit` 自带的 `j.value(...)` 弃用命中（0020 473→471），1 条是 `to_ids_result` 的 `Result[@mcp.ToolResult, @mcp.MCPError]` 签名（0078 3→2）。没有新族、没有把警告搬去别的文件。
- **零公开面**：8 个函数全是私有 `fn`（含 1 个测试文件内的私有辅助），`pub` 面与 `.mbti` 零变化；`intlist` 的历史注释去掉已删符号名，但保留 BUG-26 的成因叙述（静默饱和/截断/丢元素）。

## 资源消耗

- 模型：本地副机 agent（无外部计费）；成本 0。
- 本单 token 估算：输入约 5.2 万 / 输出约 0.9 万。
- 本单耗时：约 10 分钟（含一次漏带 `MOONC_OVERRIDE` 触发的自动重建失败与重跑）。

## 任务分配记录

- T0r37：`publish --created-by human_steward` → `claim --assignee slave-agent` → 逐条读引用面后实现与验证 → `execute`（读数入 deliverable）→ `submit` → `verify --verifier commander`。
- 无二次分包；未触碰不可逆操作（删的是无调用点的私有函数，删除属本单授权范围）。
- 纪律记录：首次 `publish` 未带 `MOONC_OVERRIDE`/`PATH` 三件套，`fist.py` 自动重建（BUG-32）报 build 失败；补工具链环境后同一条命令成功，非代码问题。

## 遗留风险

1. **504 条 warning 仍在**：`deprecated` 471 条以 `Json::value` 为主，按 BUG-356 属 owner 决策项。
2. **0001 余 2 条是「仅测试引用」**：要清零须改写白盒锁到生产原语（`scan_outside_literal` 可等价改写为 `scan_code_part(...).contains(...)`），或把 `should_upgrade` 的纯逻辑内联回真正的生产调用点——后者还需先确认 upgrade 模块是否已接线，属结构调整，按金条四另开单。
3. **0002 余 11 条**全是参数位或包级 `let`（BUG-354 / R24 既有结论），改名会动签名；**0009 3 条**（constraint 包的 `pub struct`）与 **0006 12 条**（公开枚举变体）都在公开接口面。
4. **`.mbti` 抖动会复现**（BUG-330）：每次 `moon check`/`moon test` 都会重写，需继续按 `git restore -- '*.mbti'` 处理。

## 后续建议

1. 下一顺位优先读 `0023 unused_try` 2 条：若与 `store_sqlite` 的 catch 兜底注释冲突，先改注释或维持现状，不要为清零改语义。
2. 给 0001 最后 2 条单独立项：先核实 upgrade 模块的调用链是否已接入 CLI，再决定「内联回生产」还是「改写白盒锁到原语」。
3. `deprecated` 471 条继续挂在 owner 决策（BUG-356），不在副机侧机械改写。

## 超额内容

- 对每一条被删函数做了「全域引用面」核对（`src/` + `cmd/`，含白盒/黑盒测试），把「真死」与「仅测试引用」分档处理，避免为降数删掉覆盖。
- 对总数减少做了逐条归因（0020 −2、0078 −1），并用逐族分布证明没有跨族搬家。
- 把「副机每次调用 fist.py 必须带工具链三件套 env」写进当日记忆，降低后续 BUG-32 误报。

## 来源

- 台账：`memory/bugs.md` BUG-380
- 日志：`memory/2026-10-21.md` R55 段
- 证据：`temp/t37_check_full.log`、`temp/t37_test_full.log`、`temp/t37_battery.log`、基线 `temp/t36_check_full.log`
- 提交面：待本单 commit（`slave/fix/unused-function-0001`），推送 gitcode 后由 owner 开 MR
