# 2026-10-21 R29 汇报：`slave/fix/unused-value-params` —— 0002 参数位子族的形态分界（17 条里 6 条可机械清，10 条是契约决策）

- 分支：`slave/fix/unused-value-params`（stacked on `result-error-return`(#15, a03e50a) → `deprecated-derive-show`(#14) → `implicit-impl-as-method`(#13) → … → `moonc-0.10.16-result-api`）
- FIST：根任务 `T0r10` 走完整生命周期 publish→claim→execute→submit→verify 至「已完成」，连续第十二轮自我迭代可证
- 台账：BUG-353（low，FIXED，轮次 R29）+ BUG-354（medium，**OPEN**，10 条声明后不消费的参数清单）

## 结果摘要

| 判据 | 改前 | 改后 |
|---|---|---|
| `moon check --target js --json` warnings | 571 | **565** |
| 同判据 errors | 0 | **0** |
| `error_code` 0002 unused_value | 17 | **11**（清 6 处 positional；残 = 10 条 `~`/`?` + 1 条包级 `let`） |
| 其余族 1 / 6 / 7 / 9 / 20 / 27 / 78 | 9 / 12 / 2 / 3 / 524 / 1 / 3 | **逐格不变** |
| `moon test --target js -j 1` | 1302/1302/0 | **1302/1302/0** |
| `moon build cmd/cli --target js` | rc=0 | **rc=0** |
| moonfmt 非漂移分歧（5 份 .mbt） | — | **0** |
| `check_mbti_sync` / `check_pkg_imports` | PASS（654 / 30） | **PASS（654 / 30）** |

改动 5 份文件、6 格、+6/−6 行，零行为变更、零接口变更：`engine_circuit.mbt:250 now_secs`、`engine_eval.mbt:42 self`、`omega_strong.mbt:229 self` + `230 task_id`、`curriculum.mbt:200 goal`、`store.mbt:211 now`。

## 资源消耗

- 工具调用：约 22 次；`moon check` 全量 1 次（`temp/chk31.json` 565/0）、包级 check 2 次（探针 A/B）、`moon test` 全量 1 次、`moon build cmd/cli` 1 次、moonfmt 逐文件 1 轮 × 5 份、守卫 1 轮 × 4 项、语义探针 2 轮（同一文件改写重跑）、批量工具 1 版（`temp/fix29.py`）、FIST 生命周期 6 次调用。
- 本机墙钟：本单约 9 分钟（探针 A 因 `derive` 前置属性被拒多跑一轮）。
- 返工：1 次 —— 探针 A 首版把 `derive(Copy, Show)` 写成前置属性，3002 解析错误掩盖了部分判定；改尾随形态后探针 B 一次通过。批量改动本身 6 格一次成型，无返工。

## 任务分配记录

- 指挥官亲自做：形态分类（positional vs `~` vs `?`）、两轮探针设计与定性、接口面零变化的取证方式（mbti 里 positional 只写类型）、BUG-354 的逐格现状核对（含 server 层 `by` 传递链与 `engine_for_ns` 缓解事实）、终审判据、记忆沉淀。
- 子代理：未派（6 格改动，判据驱动一次成型）。
- FIST 自我迭代：`scripts/fist.py`（本机构建产物）驱动 `T0r10` 全生命周期，连续第十二轮。

## 遗留风险

1. **BUG-354 是 OPEN，不是本单收尾**：10 条 `~`/`?` 参数里 4 条直接关乎可追溯性（`plan`/`reject_task` 的 `by~`、`cold_publish` 的 `created_by~`）。已核实的事实链：server 层从 JSON 取 `by`（缺省 `human_steward`）→ 传给 engine → engine 不消费 → 该分支无独立 audit 写入。是否要在 engine/任务面落地，属行为变更，需 owner。
2. **两条"能消警但不诚实"的路我没走**：`warnings = "-2"` 定向压制、`let _ = by` 空消费。前者违反本链一贯原则，后者把设计缺口藏进噪声。判据面因此留下 11 条。
3. **stacked 合并顺序**：本支依赖 #15 → #14 → #13 → #12 → #11 → #10 → #9 → #8 → #7 → #6 → #5 → `moonc-0.10.16-result-api`（master 树当前不可编译，BUG-328 未合）。MR base 若为 master，diff 含全部祖先改动。
4. **6 处预存 CI 红**逐项与改前一致（badge 1108、test_sync 现状面、其 selftest 基准夹具、scripts_index 的 `run_check_t0r21.py`、doc_surface 的 USAGE 0.3.8、entry_paths 的 SOP.md:44），非本单引入；`cleanup_artifacts --check` 仍 DIRTY（本机取证件累积，未跑破坏性清理）。
5. **"零 WARNING" 在本仓仍不可达**：565 条里 0020 语义档占 524 条。本单做到 0 errors + 净减 6 + 零新增 + 零契约变化；按既定裁决「交 CI 当门，PR 里如实标注」。

## 后续建议

1. **owner 决策清单**（当前四格，缺一即无法继续清零）：BUG-354（10 条参数）、0078 残 3（`to_result`/`to_ids_result`/`to_unit_result` + `pub instrumented_tool` handler 类型）、0027 残 1（`StarVerdict` Show）、死码族 0001(9)/0006(12)/0007(2)/0009(3)（含零引用常量 `laya_client_budget_ms` 与零调用点 `to_ids_result`）。
2. 下一单若继续独立可推进的机械项，只剩 **0020 语义档的 `str[:]` 子族 42 条**（切片 → `sub`/`String::slice` 之类机械改名，需先试点确认 0.10.16 的推荐写法是否引入新告警）。`Json::value` 主体 430 条仍需「包内 `priv fn` 辅助」的决策。
3. 建议把本轮定律写进 `docs/SOP.md`：**同一告警族内先按参数形态分流**——positional 可机械 `_` 前缀、`~`/`?` 是契约变更；并记「MoonBit 无 `~label as _var` 语法」。
4. 建议把「接口面零变化的两种取证」（`.mbti` 只写类型 ⇒ 名字不入契约 / 受影响名在 mbti diff 命中 0）固化为终审必查项。

## 超额内容（本单边界之外做了什么、为什么）

- 加做了 BUG-354 的逐格现状核对（10 格函数体 + server 层 `by`/`ns` 传递链 + `engine_for_ns` 缓解事实），把「10 条告警」升级成有证据的 API 真实面清单——这是主机/owner 能直接决策的形态，而不是一行待办。
- 加做了 `.mbti` 契约取证方法（positional 只写类型 vs 带 label 写名），为后续所有参数面清理单提供判定依据。
- 未做：未压制任何告警、未做假消费、未删 pub 参数、未动 0020 语义档、未动 0078/0027 残量、未跑破坏性 `cleanup_artifacts.py`、未替 owner 决定 BUG-354 走哪条路。

## 来源

- 判据：`temp/chk30.json`（571/0，改前，0002=17）、`temp/chk31.json`（**565/0**，终态，0002=11）、`temp/pt16.log`（`Total tests: 1302, passed: 1302, failed: 0`）、`temp/build16.log`（rc=0）。
- 语义探针：`temp/p29.json`（探针 A：`~y as _yy` ⇒ 3001/3002；`_x~`/`_z?` 使调用点报 4085/4086；`derive` 前置属性解析失败）、`temp/p29b.json`（探针 B：0 errors，证明 `_self` 接收者与 positional `_` 前缀合法）、探针文件 `src/engine/probe29_wbtest.mbt` 已删除。
- 契约取证：`src/engine/pkg.generated.mbti` 复跑态（`audit_execute_gate(Self, String, String)` / `plan(Self, task_id~ , split_n? , by~ , now~)` 的形态对比）、`git diff -- '**/*.mbti'` 237/237 全为 BUG-330 `Int`/`Int32` 漂移、受影响 pub fn 名命中 0。
- 现状核对：`src/server/server.mbt:1516-1520`（`by` 取值后传给 engine.plan）、`1800-1802`（`reject_task` 同形）、`4174`（`engine_for_ns(ns).plan_revise(...)`）、`src/engine/engine.mbt:645`（`get_task` 无 ns 形参）。
- 守卫：`check_mbti_sync` PASS（654 条）、`check_pkg_imports` PASS（30 条）、`gen_plugins --check` PASS、`check_plugin_sync` PASS（4 宿主 / 64 生成文件 / 170 工具 / v0.3.9）。
- 台账：`memory/bugs.md` BUG-353 + `### FIXED(2026-10-21 轮次 R29 / BUG-353)`、BUG-354（OPEN）；`memory/2026-10-21.md` R29 小节。
- 改法脚本：`temp/fix29.py`（逐格断言行内容后落盘）、`temp/list02.py`（按 `error_code` 列站点）、`temp/ctx02.py`（站点回溯到函数头）、`temp/t10_drive.py`（FIST 驱动）、`temp/fvdiff.py`（格式真实分歧判据）。
- 既有结论：BUG-344（复跑命中才算收口）、BUG-348（0002 非参数绑定子族，本单是其剩余面）、BUG-346/348/349/350/351/352（mbti 工序，本单第八次确认）、BUG-330（拼写漂移）、BUG-32/329（fist.py 驱动次序）。
- 仓库规范：`AGENTS.md` 金条四/五/八、`docs/SOP.md:33`（禁 `git add -A`，逐路径显式 staging）。
