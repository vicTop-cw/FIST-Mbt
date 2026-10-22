# FIST-Mbt · R12 收口后续汇报（12 轮闭环后的遗留处置）

- **日期**：2026-10-11
- **驱动模式**：`advance`（按指挥官建议推进 R12 遗留：重启过期 server + live 回归 + 描述侧落后守卫 + BUG-210 终态评估）
- **前置**：R1~R12 四模式流水线完整闭环（12 份 cycle 汇报全落盘）

## 结果摘要

R12 闭环时留下三件遗留，本次逐一处置：

| # | 遗留项 | 处置 | 结果 |
|---|---|---|---|
| 1 | 过期 MCP server（PID 34528 跑旧码） | 重建 cli.js + 重启 server | ✅ 四项 live 回归全过 |
| 2 | 契约面缺「描述侧落后检测」 | 新增 `scripts/check_desc_enum_sync.py` | ✅ 首发 severity，自证通过 |
| 3 | BUG-210 终态（是否真 flush） | 评估后**保持 plan-only** | ✅ 判为正确终态，非缺陷 |

## 证据（判据全景）

- `moon test --target js`：**721/721** 通过（R12 收口时 686，并发 agent 新增测试至 721）
- `moon check`：0 errors（1663 warnings 既有基线）
- `check_doc_surface.py`：PASS（J1~J15 全绿，含 J9 返回契约、J11 三向对表）
- `check_tools_sync.py`：PASS（server.mbt 注册 136 工具）
- `check_plugin_sync.py`（cl7）：**PASS**（4 宿主 / 64 文件 / 136 工具 / v0.3.8）
- `check_scripts_index.py`：PASS（新脚本已登记）
- `check_desc_enum_sync.py`（新增）：PASS + `--selftest` OK

## 任务分配记录

本阶段按指挥官思路直接执行（无子代理委派）：重建→live 回归→守卫→评估，均为指挥官亲自核验。

## 一 · MCP server 重建 + live 回归（BUG-211~214）

### 重建
- 旧 `_build/js/debug/build/cmd/cli/cli.js` LastWrite **2026-10-11 01:18**，而 `server.mbt`（04:40）/`cost_tool.mbt`（04:15）/`omega_tool.mbt`（04:15）都在其后 ⇒ **运行中的 server 未反映 BUG-211~214 修复**。
- `moon build --target js` 重建成功（cli.js → 08:16，2881KB）；`python scripts/patch_esm_main.py` 注入 require shim（ESM 输出 + CJS sqlite 桩，AGENTS.md 明示）。
- **备份**：重建前把旧 cli.js 备份到 `temp/cli.js.bak-20261011-0815`。
- 冒烟：`node cli.js --version` → `FIST-Mbt v0.3.8`。

### live 回归（对新构建 server，stdio JSON-RPC，隔离库 temp/live_regress_r12.db）

| 缺陷 | live 断言 | 结果 |
|---|---|---|
| **BUG-214** | `tools/list` 抓 `report_bug` 描述，不得含 `severity(可选 open/` | ✅ PASS（描述已删 open，对齐闭集） |
| **BUG-212** | `omega_verify specs=[]` → total=0, accuracy=100, veto=false | ✅ PASS |
| **BUG-213** | `dag_sort task_ids=["x"]`（原生数组）→ 不报错 | ✅ PASS（回 `{"sorted":["x"]}`） |
| **BUG-211** | `cost_budget_check limit=0` → rejected | ✅ 正确（回 `valid=false, action=rejected, reason="limit 必须为正数（收到 0）"`） |

**BUG-211 的一个诚实边界**：`cost_tool.mbt` L58 的修复是 `match args.value("limit") { Some(Number) => n  _ => 0.0 }`——`_` 分支（非 Number 的 limit）**被 MCP schema 拦截**（`limit` 是 `number_prop` 且 required），live MCP 调用不可达。它是**直接引擎调用的防御面**（如其它工具/单测直调 `budget_check_json`）。live 可观察的是 limit=0 → rejected（此路径修复前也成立）。故 BUG-211 的修复价值在防御纵深，而非 live 行为变更。这再次印证 R11 元教训：**MCP 类型校验会在进 handler 前拦截，防御代码常无效**。

### server 重启

- 停旧 PID 34528（旧码）→ 起新 PID 40616 → **发现误把 FIST_DB_PATH 指向隔离测试库**，会丢失真实数据 ⇒ 修正：停 40616，**清 FIST_DB_PATH 用默认库 fist-mbt.db** 重启（PID 41248）。
- 验证读到真实数据：`mcp__fist-mbt__list` 返回真实任务树（default/cron-auto 等 ns），`store_list`/`call_log` 正常。MCP 工具连接正常。
- **教训**：重启持久 server 必须保持原有 DB 路径约定（`.mcp.dev.json` 无 FIST_DB_PATH ⇒ 默认 `fist-mbt.db`）；误设测试库会导致客户端看到空数据。

## 二 · 契约面「描述侧落后」守卫（新）

### 为什么（BUG-214 的类形态）
`check_doc_surface.py` 的 J 判据只查「desc ↔ schema ↔ 真源」三方**当前一致**，不查「工具描述是否引用了源码闭集里**已删除**的枚举值」。BUG-214：`bug_severities()` 早删 `open`，而 `report_bug` 描述还写 `severity(可选 open/…)`——schema 与闭集都已是新值，唯独描述落后，现有判据看不见。

### 实现
`scripts/check_desc_enum_sync.py`：登记表 `ENUM_REGISTRY` 逐项（描述文件, 闭集文件, 闭集函数名, 工具名, 参数名, 子句正则），解析闭集数组字面量 → 到描述里抽 `<参数>(可选 …)` 子句 → 逐值比对。闭集或子句解析不到 ⇒ 自拒 exit 2（不出假绿）。`--selftest` 合成违例必红 + 干净不误红。

- 首发登记：`report_bug.severity ↔ bugreport.mbt::bug_severities`（闭集 `["critical","high","medium","low"]`）。
- 已登记到 `scripts/README.md`（紧邻 check_doc_surface，同属契约面），`check_scripts_index` PASS。
- 结果：**PASS**（当前描述未引用闭集外值）；**SELFTEST OK**（合成 `severity(可选 open/…)` 必红，抓到 `report_bug.severity 描述列了闭集外的值 open`）。

### 可扩展性
后续 enum 参数（status/verdict/mode/action 等）往 `ENUM_REGISTRY` 加一行即可。原则：**描述里出现的枚举取值必须逐字落在源码闭集内**。

## 三 · BUG-210 终态评估（结论：保持 plan-only，非缺陷）

### 现状（已读真源 L2372~2496）
`watchdog_tick flush_bug_queue=true` 时：`github_env_check` → 若 ready 则 `github_flush_plan`（**只生成 curl、不执行网络**）→ `gh_ok`/`gc_ok` 硬编码 false → `any_success` 恒 false → `flush_status=plan_only_not_executed`。GitCode 同理。

### 评估
- **凭据未配置**：live `github_env_check` → `enabled=false, token_present=false, ready=false`（`hints` 明示需设 `FIST_GITHUB_TOKEN`）。GitCode 侧同样无 token。
- **真 flush 的风险**：需真实网络（curl 到 GitHub/GitCode）+ 凭据 + **绕过 `github_flush_execute` 的 `force=true` 硬门**（该门为防误操作而设，watchdog 自动调用会绕过其意图）+ 可能拖慢 watchdog。
- **结论**：`any_success=false, flush_status=plan_only_not_executed` 是**在无凭据环境下的唯一正确行为**，诚实标注本身即 R11 修好的缺陷（旧码假称 `any_success=true`）。**plan-only 不是"降级"而是安全默认**；真正要 flush 时走手动 `github_flush_execute(force=true)`。

### 遗留建议
- 若将来配置了 `FIST_GITHUB_TOKEN`/`FIST_GITCODE_TOKEN`，再评估是否给 watchdog 加一个**显式 opt-in** 的真执行开关（不默认开），且须保留 force 门或同等护栏。
- 此前报告里"诚实但降级中间态"的措辞偏负面，**本次更正：这是正确的安全终态**。

## 遗留风险

- **并发 WIP 未合并**：`memory/bugs.md`、`src/server/server.mbt` 等仍 ` M`（并发 agent 活跃，已新增 BUG-215~217，账本现为 BUG-1~217 共 216 条）。我重跑 gen_plugins 把插件态同步到当前账本（cl7 PASS），但并发 agent 继续改会再次漂移，需他们自行复跑。
- **moon build / MCP server 重启的持续性**：我重启的 server（PID 41248）跑的是我 08:16 构建的码；若并发 agent 再改 server.mbt，server 又会落后。建议稳定期统一重建。
- **守卫登记表仅首发 severity**：status/verdict/mode 等 enum 尚未登记，后续可扩。
- **BUG-205（熔断真滚动窗，需加列迁移）** 与 **BUG-142（moon exit-0 不可靠）** 仍 OPEN，已知不重报。
- `temp/` 下新增 `live_regress_r12.py` / `lr_cost_budget.py` / `live_regress_r12.db` / `cli.js.bak-*`（临时验证产物，可清理）。

## 后续建议

1. **稳定期统一重建 server**：等并发 agent 完成 server.mbt 改动后，`moon build --target js` + `patch_esm_main.py` + 重启，确保客户端跑最新码。
2. **扩守卫登记表**：把 status（bug 抬头）/ verdict（omega）/ mode（pipeline）等 enum 参数补进 `ENUM_REGISTRY`，把 BUG-214 类彻底关死。
3. **清理 temp/**：删除本次临时验证产物（live_regress_*.py/*.db、cli.js.bak-*），或移到明确的测试残留区。

## 超额内容

- 新增守卫脚本 `scripts/check_desc_enum_sync.py`（本为 R12 遗留建议项）。
- 新增 `scripts/README.md` 条目。
- 临时验证脚本 `temp/live_regress_r12.py` / `temp/lr_cost_budget.py`（验证用，非交付物）。

## 来源

- 读源：`src/server/server.mbt`（L2308~2499 watchdog flush、L4601~4614 cost_budget_check、L5083 report_bug 描述）、`src/engine/cost_tool.mbt`（L55~65 budget_check_json）、`src/server/bugreport.mbt`（L12~26 bug_severities）
- 构建：`moon build --target js`；`python scripts/patch_esm_main.py`
- 判据：`check_doc_surface.py` / `check_tools_sync.py` / `check_plugin_sync.py` / `check_scripts_index.py` / `check_desc_enum_sync.py` / `moon test` / `moon check`
- MCP live：`tools/list` / `omega_verify` / `dag_sort` / `cost_budget_check` / `github_env_check`