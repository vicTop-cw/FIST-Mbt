# 2026-10-14 · 抽单一 `_tool_registry` 实现报告（5 消费者收口）

## 结果摘要

**一句话**：落地上轮报告「后续建议 #1」——把复制在 **5 个消费者**里的"工具数真源怎么读"抽成
唯一实现 `scripts/_tool_registry.py`，5 处改为委托；并用**等价性验证**（改前先证读数不变）+
**变异实测 3/3** + **十项判据全绿**收口。

| 项 | 读数 |
|---|---|
| 等价性（改前） | 新模块 166 vs 旧口径 166，**集合完全相同（差异：无）** |
| 新模块 `--selftest` | **9 格全过**（含新增"收口两格"）|
| 变异实测 | **3/3 被抓住**（本地实现复活 / 断掉 exec_module / 清空链式正则）|
| 十项判据 | 全绿（tools_sync 166 / doc_surface 166 / plugin_sync 4 宿主 166 / scripts_index / pkg_imports / mbti_sync 597 / py_stdout / ps_encoding / gen --check / mcp_smoke 166）|

提交 `d35c2f0`（6 文件：1 新模块 + 5 消费者），已推 origin + gitcode。

## 为什么必须收口（本仓实测过两次红）

工具注册从 `src/server/server.mbt` 拆到独立文件后，"工具数真源怎么读"被复制到 5 处：

```
check_tools_sync.py  check_doc_surface.py  check_plugin_sync.py  gen_plugins.py  mcp_smoke.py
```

实测后果两次：
1. **假绿**：拆分发生时 5 处里只 3 处跟上 ⇒ `check_doc_surface` 拿 148 口径**自洽 PASS**
   （它跟自己旧口径一致，看起来全绿）——比没有判据更危险。
2. **互掐**：补齐 3 处后剩 2 处与新口径冲突 ⇒ 守卫报
   `README 分组和 166 != 注册表 148 ⇒ 拒绝投影（先修 README）`，
   而 **README 的 166 是对的**。照该提示改会把正确文档改回错值（反向指引）。

⇒ 收敛到一处后，"5 处口径是否一致"从"靠人记得改"变成"结构上只有一处"。

## 单一实现的设计

`scripts/_tool_registry.py`（`_` 前缀 ⇒ 按 `check_scripts_index` 的既有机制免登记，实测该守卫仍 PASS）：

| 导出 | 说明 |
|---|---|
| `real_tools()` | 工具名列表（去重排序）；`src/server/*.mbt` 排除 `_test/_wbtest`；两形态并集 |
| `tool_count()` | 长度（配合 `MIN_EXPECTED` 判解析是否退化）|
| `server_files()` | 参与扫描的文件（调用方可打印"扫了几份"）|
| `MIN_EXPECTED = 100` | 反幻影门槛（低于即视为解析失败，调用方自拒）|
| `RE_TOOL` / `RE_TOOL_CHAIN` | 两形态正则（供调用方复用，不再各写一份）|

**形态①正则放宽变量名**：原实现钉 `instrumented_tool(\s*s1\s*,`，而 `gen_plugins` 历史实现里
出现过别的变量名 ⇒ 统一为 `instrumented_tool(\s*\w+\s*,`。
**这处放宽先做了等价性验证**（见下）才落地。

## 等价性验证（改前先证不改变读数）

替换任何判据的实现前，必须先证"读数不变"，否则会把"修 bug"变成"改读数"：

```
新模块 real_tools = 166
旧口径（钉 s1）    = 166
集合相同? True
差异: 无
```

⇒ 放宽变量名在本仓当前源码上**未引入任何增减**（166 个工具名逐个一致）。

## 5 个消费者的改造

每个消费者的 `real_tools()` / `registry_tool_names()` 只剩一行委托 + 一段说明（为什么不再本地实现）：

| 文件 | 改造 |
|---|---|
| `check_tools_sync.py` | `return _tool_registry.real_tools()` |
| `check_doc_surface.py` | 同（原三处调用点已统一走 `real_tools()`）|
| `check_plugin_sync.py` | 同 |
| `gen_plugins.py` | 同（`measure()` 调它）|
| `mcp_smoke.py` | `return set(_tool_registry.real_tools())`（该处消费 set）|

各自加 `importlib.util` 加载头（脚本名带 `_` 前缀，不是包）。

## L4 实测

**新模块 `--selftest` = 9 格全过**：
1. `real-count-above-min`（166 > 100）2. `real-has-instrumented-form`（publish 在）
3. `real-has-chain-form`（`mcpcf.*` 7 个）4. `re-instrumented` 5. `re-chain`
6. `chain-not-eat-instrumented`（链式正则不误吃 `instrumented_tool`，不重复计数）
7. `tests-excluded`（31 份测试不入扫描面）
8. **`consumers-no-local-impl`**（5 个消费者无本地实现）9. **`consumers-wired-to-registry`**

**变异实测 3/3 被抓住**：

| # | 变异 | 抓它的格 |
|---|---|---|
| 1 | 把本地实现塞回 `mcp_smoke` | `consumers-no-local-impl` |
| 2 | 删掉消费者的 `exec_module` 调用 | `consumers-wired-to-registry` |
| 3 | 清空 `RE_TOOL_CHAIN`（链式形态漏扫）| `real-has-chain-form` |

**十项判据全绿**：
```
check_tools_sync         PASS 166 个，四份文档对齐
check_doc_surface        PASS 166 逐个可查、分组和=166
check_plugin_sync        PASS 4 宿主 / 64 生成文件 / 166 工具 / v0.3.8
check_scripts_index      PASS（新模块 _ 前缀免登记机制生效）
check_pkg_imports        PASS 23 份 moon.pkg / 30 条 import
check_mbti_sync          PASS 23 份 .mbti / 597 条 pub 声明
check_py_stdout_encoding PASS 29/29
check_ps_encoding        PASS 7 个 .ps1
gen_plugins --check      PASS 插件态与真源一致（166）
mcp_smoke                PASS tools/list → 166 个工具 + MCP-SMOKE PASS
```

## 判据强度经变异校准（一处真实改进）

**首版收口格只查 `_tool_registry` 子串** ⇒ 变异②（删 `exec_module` 那行）**抓不住**：
因为 `spec_from_file_location(..., "_tool_registry", ...)` 的参数字面量里仍含该子串。

改为同时要求：
- `exec_module(_tool_registry)`（真加载）
- `_tool_registry.real_tools()`（真委托）

⇒ 变异②从此被抓住。**这是"变异测试发现判据强度不足"的又一次实证**（本会话第 N 次同型收获）。

## 资源消耗

- 新模块 190 行；`--selftest` 跑 4 次（初版 / 改强度后 / 变异前后）
- 变异实测 2 轮（首轮 3 处中 1 处未抓住 ⇒ 改判据强度 ⇒ 重跑 3/3）
- 十项判据各 1 次；`gen_plugins --check` 1 次；`mcp_smoke` 1 次（起真 server）
- 零 `.mbt` 改动、零网络请求（除 push）

## 任务分配记录

- 指挥官亲自：确认 5 处复制 → 写单一实现 → **等价性验证** → 逐个改造 5 消费者（每个改完立即验）
  → 加收口判据 → 变异实测（发现强度不足）→ 改强度 → 重跑变异 → 十项全绿 → 提交。
- **未派子代理**：本链要害是"改实现前先证读数不变"与"判据强度是否够"，误判会改坏读数或留假判据。
- 边界：只新增 1 内部模块 + 改 5 处读取实现；**未改任何判定逻辑与阈值**；精确 add 6 文件。

## 遗留风险

1. **`fist help tools` 分组表仍手写**（连续两轮已记）：工具增减需人工同步该表；
   建议改由真源生成（本模块已提供 `real_tools()`，可直接喂）。
2. **`_tool_registry.py` 的 `MIN_EXPECTED=100` 是硬编码门槛**：工具数若因重构降到 100 以下会误判
   "解析失败"。当前 166 有充裕余量；但门槛本身是"反幻影"与"过度保守"的折中。
3. **收口判据靠字符串匹配**（`exec_module(_tool_registry)`）：若未来改用 `from _tool_registry import real_tools`
   这种更 Pythonic 的写法，第 9 格会误报"未接上"（可加容忍分支，属小改进）。
4. **`check_scripts_index` 的免登记靠 `_` 前缀约定**：本轮实测生效；但若有人给该模块改名去掉前缀，
   会被要求登记（属正确行为，非缺陷）。

## 后续建议

1. **`fist help tools` 分组表改真源生成**（价值直接）：`_tool_registry.real_tools()` 已可直接喂。
2. **给"五处口径一致"再补一支独立判据**（可选）：现在收口检查在 `_tool_registry.selftest` 内，
   若有人不跑该 selftest 就改，仍可能漏。可把它挂进 CI（或让某支守卫调 `--selftest`）。
3. **收口格的字符串匹配加容忍**（可选）：支持 `from _tool_registry import ...` 写法，防误报。
4. **`check_plugin_sync` 的 J1 提示语**（上轮已记）：仍写"先修 README"，方向错误；
   建议改为"先核真源扫描面是否跟上工具拆分"。

## 超额内容

- 顺带**做了"改实现前先证读数不变"的等价性验证**：新模块与旧口径集合完全相同（差异：无）才落地——
  这是本会话反复强调的纪律在"重构判据"场景的应用（改判据比改产品更需先证读数不变）。
- 顺带**用变异测试发现并修掉判据强度不足**：首版收口格只查子串 ⇒ 变异②抓不住；
  改为"真加载 + 真委托"双条件后才抓住。**若不做变异，会交付一支看起来有 9 格、实际漏一格的 selftest**。
- 顺带**验证了 `_` 前缀免登记机制**：新内部模块未登记而 `check_scripts_index` 仍 PASS
  （该守卫既有机制的实证，非猜测）。
- 顺带**把"口径复制"这一结构性问题消除**：从 5 处实现 → 1 处实现 + 5 处委托，
  下次工具注册再搬家只需改 1 个文件。

## 来源

- 新模块：`scripts/_tool_registry.py`（190 行；`real_tools` / `tool_count` / `server_files` /
  `MIN_EXPECTED` / `selftest` 9 格）
- 改造：`scripts/check_tools_sync.py` / `check_doc_surface.py` / `check_plugin_sync.py` /
  `gen_plugins.py` / `mcp_smoke.py`（各只剩一行委托）
- 等价性验证输出：`新模块 real_tools = 166 / 旧口径 = 166 / 集合相同 True / 差异 无`
- 变异：`temp/mutate_registry.py`（3 处变异，3/3 被抓住）
- 十项判据读数：见上表（全 PASS）
- 提交：`d35c2f0`（6 文件，+190/-58）；三端同步 `d35c2f0`
