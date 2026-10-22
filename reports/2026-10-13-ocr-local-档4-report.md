# 2026-10-13 · ocr-local 集成 · 档4（boundary_probe 边界输入建议生成器）汇报

- **档位**：档4（`boundary_probe` MCP 工具，stretch 档）
- **对应计划**：`docs/2026-10-13-ocr-local-integration-plan.md` §档4（L258-294）
- **FIST 闭环**：ns `ocr-local-integration`，根 `T0r5`（已 `verify` → 已完成）
- **Commit**：`feat(boundary_probe): add boundary input generator MCP tool (#ocr-4)`（24 files / +561 / -50）

## 一、结果摘要

把 bugfind 模板里「构造边界 case」从人工提示词变成 MCP 工具：新增 `boundary_probe` 工具，给定 finding（rule/code/line/file）按规则类型路由返回该位置的边界输入建议数组，每条带 `confirmed=false`；调用方把 `input` 喂给 `run_check`，能触发 panic/崩溃才回写 `confirmed=true`。与档3 的 `ocr_scan` 一起，把 bugfind 从「扫描 → 边界构造 → 真实验证」补成完整三段闭环。

| 验收项 | 结果 | 证据 |
|---|---|---|
| `src/server/boundary_probe.mbt` 编译 0 错误 | ✅ | `moon check src/server` = 0 error |
| 白盒测试 15 条 | ✅ | `moon test --target js src/server` = **249/249** |
| `divide-by-zero` → 含 `y=0` | ✅ | `bp_divide_zero_contains_y0` |
| `string-index` → 含空串 + 超长串 | ✅ | `bp_string_index_contains_empty_and_huge`（`1000000`） |
| `race-condition` → 含并发交错 | ✅ | `bp_concurrency_contains_interleave`（并发交错/重入/屏障） |
| 不同规则类型不同集 | ✅ | 14 类路由（除零/下标/unwrap/empty-match/overflow/secs/race/json/path/float/resource/async_main/abort/discard/noop/long/generic） |
| 纯计算不执行 | ✅ | `confirmed` 恒 false（`bp_confirmed_always_false`）+ `note` 明示「不执行」 |
| `rule`+`code` 空显式报错 | ✅ | server.mbt 注册分支 `{ok:false,error:"rule 与 code 均为必填"}` |
| bugfind 模板第四步接上 | ✅ | `templates/pipeline_mode_bugfind.md` 第三步改调 `boundary_probe` + `run_check` |
| 四态对齐 | ✅ | `gen_plugins.py` 重投影 **148 工具**；`check_plugin_sync.py`（cl7）= **PASS** |
| 文档同步 | ✅ | `AGENTS.md` +`boundary_probe` 工具描述；`README.md` 运维·验证·规范 23→24（+`boundary_probe`） |

## 二、关键设计（防走样）

1. **纯计算，零副作用**：`boundary_probe` 不 spawn 不跑测试，`confirmed` 恒 `false`。判真伪**靠 `run_check` 实测**，不许把建议当结论（模板显式钉这句）。
2. **按规则类型路由**（`boundary_suggestions` 单真源）：`rule.contains(...)` 关键词分流到 14 类边界族；未知规则回退 `generic-empty/extreme/illegal` 三连，不静默空返回。
3. **MCP 工具与 `task_plan_deep` 的 `boundary_probe=true` 参数同名不同义**：本档新增的是 MCP 工具（bugfind 第四步前置），AGENTS.md 里 `task_plan_deep` 描述已有的 `boundary_probe=true` 是递归拆解时给叶挂「边界四问」的参数（atgc-merge 归因报告机理 1/2）。两者互补不冲突，本档工具描述里点明出处。
4. **与档3 形成闭环**：`issue_scan`（内建规则）→ `ocr_scan`（OCR LLM review 双轨）→ `boundary_probe`（边界建议）→ `run_check`（真实验证）→ `report_bug`（上报）。

## 三、资源消耗

- **编译/测试**：`moon check src/server`（0 error）+ `moon test --target js src/server`（249/249）+ `moon info`（0 error）+ `moon fmt --check`（0）。
- **四态**：`gen_plugins.py` 重投影（148 工具）+ `check_plugin_sync.py`（cl7 PASS）。
- **FIST**：`T0r5` publish → claim → execute → submit → verify 全流程。
- **耗时**：约 25 分钟（含 2 处 MoonBit 命名参数报错修复、模板控制字符用 Python 替换）。

## 四、任务分配记录

- **未委托 subagent**：档4 是纯计算工具接入（`boundary_probe.mbt` + 白盒 + server 注册 + 模板 + 四态），边界紧、须同步终审，直接由指挥官实现。
- **未拆 FIST 子任务**：单点工具，深度 2，一次到位；走 `T0r5` 单根闭环。
- **MoonBit 编译报错 2 处已修**：位置参数后不能接命名参数（`line="?"` → `"?"`），MoonBit 只在 `~param` 定义下才支持命名参数。

## 五、遗留风险

1. **边界建议 ≠ 已验证 bug**：`boundary_probe` 只出建议，`confirmed` 恒 false；真实确认依赖调用方跑 `run_check`。本轮未做端到端「建议 → run_check 确认」实跑（需一个真实会崩的目标程序），留在后续真实验证轮。
2. **规则路由覆盖度**：14 类覆盖 issue_scan 31 条主类，但个别规则可能落在 generic 回退里（`bp_unknown_rule_generic_fallback` 已锁回退不空）。规则名与 issue_scan 的 `by_rule` 种类未做逐条对表，建议下一轮把 `issue_scan` 全部规则名喂 `boundary_probe` 做一次覆盖巡检。
3. **全仓测试未跑**：`atgc-old`（并发 WIP）当前在 `moon check` 报 4 个 4085 错误，导致全仓 `moon test --target js` 不可判绿；本档以 `src/server` 249/249 为准，全仓绿待并发 WIP 收口。
4. **文档旧口径遗留**：`docs/issue-scan-skill.md` / `templates/pipeline_mode_advance.md` / `cron_pipeline_meta_prompt.md` 仍有「内建 10 条」旧口径，本轮未改（避免引入无关 diff），建议下一轮一并 sync 到 31 条。
5. **AGENTS.md「152 tools」vs 实测 148**：口径差异（AGENTS 自述含未注册/debug），`check_tools_sync`/`gen_plugins` 均以实测 148 为准，AGENTS 的 152 未改（避免引入新 diff）。

## 六、后续建议

1. **端到端确认闭环实测**：在 windows-x64 上挑一个真实会崩的程序片段，用 `boundary_probe` 拿建议 → `run_check` 跑 → 回写 `confirmed=true`，把 `ocr_hits + boundary confirmed` 端到端数据落一次到报告。
2. **规则覆盖巡检**：把 `issue_scan` 的 `by_rule` 种类全量喂 `boundary_probe`，核对每一类是否命中专项路由（而非 generic 回退），补缺口。
3. **并发 WIP 收口后**：跑 nightly `moon fmt` 全仓重排 + 全仓 `moon test --target js` 复绿，撤销 `continue-on-error`。
4. **遗留文档旧口径 sync**：`docs/issue-scan-skill.md` / `templates/pipeline_mode_advance.md` / `cron_pipeline_meta_prompt.md` 三处「内建 10 条」→ 31 条。

## 七、超额内容

- `README.md` 运维·验证·规范组 23→24 的计数与 `boundary_probe` 工具名同时落，四态 cl7 一次过。
- `boundary_probe` 工具描述显式点出与 `task_plan_deep` 的 `boundary_probe=true` 参数**同名不同义**（atgc-merge 机理 1/2 溯源），防后人误以为参数就是工具。

## 八、来源

- 计划：`docs/2026-10-13-ocr-local-integration-plan.md`（档4 L258-294，验收证据链 L285-294）
- 代码：`src/server/boundary_probe.mbt`（新）、`src/server/boundary_probe_wbtest.mbt`（新）、`src/server/server.mbt`（注册）
- 模板：`templates/pipeline_mode_bugfind.md`
- 文档：`AGENTS.md`、`README.md`
- 插件态：`plugins/`（`gen_plugins.py` 重投影 148）
- FIST 台账：ns `ocr-local-integration` / `T0r5`（已完成）
- Commit：`feat(boundary_probe): add boundary input generator MCP tool (#ocr-4)`