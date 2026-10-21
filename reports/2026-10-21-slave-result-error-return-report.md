# 2026-10-21 R28 汇报：`slave/fix/result-error-return` —— 0078 result_error_return 伪 Result 通道清到契约边界（13→3）

- 分支：`slave/fix/result-error-return`（stacked on `deprecated-derive-show`(#14, 2a0c0ec) → `implicit-impl-as-method`(#13) → `reserved-keyword-and-priv`(#12) → `unused-value-locals`(#11) → … → `moonc-0.10.16-result-api`）
- FIST：根任务 `T0r9` 走完整生命周期 publish→claim→execute→submit→verify 至「已完成」（deliverable 落库），连续第十一轮自我迭代可证
- 台账：BUG-352（low，FIXED，轮次 R28）—— 本链上第一份「方向被试点证伪后改轴」的单

## 结果摘要

| 判据 | 改前 | 改后 |
|---|---|---|
| `moon check --target js --json` warnings | 581 | **571** |
| 同判据 errors | 0 | **0** |
| `error_code` 0078 result_error_return | 13 | **3**（残留 = `to_result`/`to_ids_result`/`to_unit_result`，owner 决策） |
| 其余族 1 / 2 / 6 / 7 / 9 / 20 / 27 | 9 / 17 / 12 / 2 / 3 / 524 / 1 | **逐格不变** |
| `moon test --target js -j 1` | 1302/1302/0 | **1302/1302/0** |
| `moon build cmd/cli --target js` | rc=0 | **rc=0** |
| moonfmt 非漂移分歧（2 份 .mbt） | — | **0** |
| `check_mbti_sync` / `check_pkg_imports` | PASS（654 / 30） | **PASS（654 / 30）** |

改动 2 份文件，+34/−36 行，零行为变更、零接口变更：9 处私有声明剥掉伪 Result 通道 + 3 处体内 `Ok(...)` 剥除 + 7 个注册 lambda 边界包 `Ok` + 1 处 `run_check_deny` 改返回 `@mcp_types.MCPError` + 3 个调用点包 `Err`。

## 资源消耗

- 工具调用：约 30 次；`moon check` 全量 2 次（`temp/chk29.json` 571/0 终判据、`temp/chk30.json` 571/0 格式修复复跑）、包级 check 2 次（含一次暴露返工缺陷）、`moon test` 全量 2 次、`moon build cmd/cli` 2 次、moonfmt 逐文件 3 轮 × 2 份、守卫 1 轮 × 5 项、试点 3 次（pilot A/B/C）+ 语义探针 1 份（`_wbtest`，用完删除）、批量工具 1 版（`temp/fix28.py`）+ 定点补皮 1 次、FIST 生命周期 6 次调用。
- 本机墙钟：本单约 16 分钟（含一次方向重定与两次返工）。
- 返工：2 次 —— ① 首版批量工具 `assert RES not in load(EMB)` 忽略「7 个注册 lambda 故意保留 Result」，中止（断言后落盘设计 ⇒ 树未受损），改为白名单 lambda 形态行并要求恰 7 条；② `Err(...)` 抬升切片 off-by-one（`o+5/o+6` 应为 `o+4/o+5`）留下悬空逗号与不平衡括号，包级 check 实发后定点修复。

## 任务分配记录

- 指挥官亲自做：0078 契约面取证（读 `colmugx/mcp@0.17.4` 源码到 `temp/mcpsrc/`）、三格 raise 试点与语义探针、方向重定（从"改 raise"改到"剥假通道 + 边界包 Ok/Err"）、承重划分（10 处假通道 vs 3 处合法数据）、终审判据（check/test/build/fmt/守卫实跑）、记忆沉淀。
- 子代理：未派（2 份文件、19 个 loc 驱动点，派单成本高于收益）。
- FIST 自我迭代：`scripts/fist.py`（本机构建产物）驱动 `T0r9` 全生命周期，连续第十一轮。

## 遗留风险

1. **0078 残 3 条是 owner 决策，不是技术遗留**：`to_result`/`to_ids_result`/`to_unit_result` 的语义是「失败当普通数据」，正是告警文案允许的一半；要清零必须同时改 13 处调用面与 `pub instrumented_tool` 的 handler 类型（动外部契约 + 动接口面）。本单按"不动契约面"收敛。
2. **`to_ids_result` 全仓 0 调用点**：它同时是死码族候选（0001/0006），删它比改它更省——但与 0078 不同族，未混入本单。
3. **stacked 合并顺序**：本支依赖 #14 → #13 → #12 → #11 → #10 → #9 → #8 → #7 → #6 → #5 → `moonc-0.10.16-result-api`（master 树当前不可编译，BUG-328 未合）。MR base 若为 master，diff 含全部祖先改动。
4. **6 处预存 CI 红**逐项与改前一致（badge 1108、test_sync 现状面、其 selftest 基准夹具、scripts_index 的 `run_check_t0r21.py`、doc_surface 的 USAGE 0.3.8、entry_paths 的 SOP.md:44），非本单引入；`cleanup_artifacts --check` 仍 DIRTY，属本机取证件累积，未跑破坏性清理。
5. **"零 WARNING" 这一硬指标在本仓当前不可达**：571 条是历史累积（0020 语义档 524 条为绝对主体）。本单做到的是 0 errors + 净减 10 条 + 零新增；按既定裁决「交 CI 当门，PR 里如实标注」。

## 后续建议

1. 下一单建议 **0002 unused_value 参数位 17 条**：机械、零契约风险（改 `_` 前缀或删除参数），可预期 571 → 554。
2. **死码族单独立项**（0006 12 / 0001 9 / 0009 3 / 0007 2）：一次判据可清 ~26 条，且顺手解决 `to_ids_result`；需要 owner 先确认「零调用点即死码」的判定权。
3. **0078 残 3 条 + `StarVerdict` 残 1 条合并成一份 owner 决策清单**：两格都需要跨契约面的授权，不适合继续由副机单方面推进。
4. 0020 语义档 524 的入口仍是那个决策：`Json::value` 主体（430 条）要不要引入包内 `priv fn` 辅助。
5. 建议把本轮两条方法论写进 `docs/SOP.md`：① 「先试点证伪方向，再批量落子」；② 「格式比对必须用 norm 后 unified diff，逐行 zip 会把行差放大成假分歧」。

## 超额内容（本单边界之外做了什么、为什么）

- 加做了三格 raise 试点（`temp/pilot78.py` / `pilot78b.py` / 包级 pilot C）与一份临时白盒语义探针 `src/server/probe78_wbtest.mbt`（用完即删），把"`Result[T,E]` → `T raise E` 能不能机械铺开"从推测变成编译器实证（4014 / 4118 原文），后续同类单可直接引用；代价是本单方向重定一次。
- 加做了格式比对工具改造（`temp/fvdiff.py`：norm 后 unified diff），产出可复用的"真实分歧"判据，避免下一轮再被 zip 对齐噪声误导。
- 未做：未加 `warnings = "-..."` 压制、未改 `pub instrumented_tool` handler 类型、未删 `to_ids_result` 死码、未动 0020 语义档、未跑破坏性 `cleanup_artifacts.py`、未替 owner 决定 0078 残 3 条走哪条路。

## 来源

- 判据：`temp/chk28.json`（581/0，改前，0078=13）、`temp/chk29.json` 与 `temp/chk30.json`（**571/0**，终态与格式修复复跑，0078=3）、`temp/c29a.json`（包级 check 0 errors）、`temp/pt15.log` 与 `temp/pt15b.log`（`Total tests: 1302, passed: 1302, failed: 0`）、`temp/build15.log`（rc=0）。
- 契约取证：`temp/mcpsrc/`（`colmugx/mcp@0.17.4` 解压源，读 `MCPServer::tool` handler 签名与 raise/try-catch 惯用法）、`src/server/server.mbt:1266`（`pub fn instrumented_tool`）。
- 试点证据：`temp/p78.json` / `p78b.json` / `p78c.json`（4014 / 4118 实发）、`temp/probe78.log`（语义探针输出，探针文件已删）。
- 镜像保护：`temp/keep30/`（24 份 `.mbti` 快照，终态 `git restore` 后与之等价）。
- 守卫：`check_mbti_sync` PASS（654 条）、`check_pkg_imports` PASS（30 条）、`gen_plugins --check` / `--selftest` / `check_plugin_sync` PASS（4 宿主 / 64 生成文件 / 170 工具 / v0.3.9）。
- 台账：`memory/bugs.md` BUG-352 + `### FIXED(2026-10-21 轮次 R28 / BUG-352)`；`memory/2026-10-21.md` R28 小节。
- 改法脚本：`temp/fix28.py`（断言后落盘 + lambda 白名单），`temp/t9_drive.py`（FIST 驱动），`temp/fvdiff.py`（格式真实分歧判据）。
- 既有结论：BUG-344（复跑命中才算收口）、BUG-346/348/349/350/351（mbti 工序，本单第七次确认）、BUG-330（拼写漂移）、BUG-32/329（fist.py 驱动次序）。
- 仓库规范：`AGENTS.md` 金条四/五/八、`docs/SOP.md:33`（禁 `git add -A`，逐路径显式 staging）。
