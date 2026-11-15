# 轮 315 唤醒巡检报告（2026-11-15）

## 结果摘要

WIP 四件套冻结零变化第 32 轮；换面巡检 `check_tool_coverage`（r300~r314 未轮过·本轮首跑）
自检 10/10 + 实测 PASS（165 工具外壳 100% 覆盖）——但**深挖实测读数发现真判据缺陷**：
`check_tool_coverage` 是 `_tool_registry` 真源的**第 6 个消费者却从未接线**，只扫
`server.mbt`（165 工具）而真源是 41 份 `src/server/*.mbt` 的 183 工具并集 ⇒ **18 个工具
整体逃过外壳覆盖扫描，其中 7 个实测零覆盖**（`mcpcf.report/review/run_batch/verify`、
`supervisor_prompt_consume/inject/list`）。该判据是 CI 门禁（run_guards.py:283 selftest +
:429 本体 expect 0），现绿**只因为**它没看到那 18 个。零漂移双检 rc=0；Round C 三件维持过期不执行。

**新发现 1 件（BUG 临时号 636，落账待 WIP 解禁）**：中危判据缺陷，非功能缺陷（被漏的是
「测试有没有碰这个工具名」的外壳覆盖，非生产行为 bug）。修复面为「接真源 + 把 7 个新暴露
缺口按 BUG-455 先例登记 known-red/todo」，触 3~4 文件 + 验证，属**中任务**，本轮只立账定
修复规格、不在 30 分钟非阻塞唤醒里抢修（抢修会把 CI 打成半红，见「遗留风险」）。

## 巡检明细

1. **WIP 状态**（`git status --short` + `git diff --numstat`）：
   - 3 个已跟踪 WIP 文件 numstat 逐字同 r284~r314（`docs/improvement-plan-20261010.md` 7+/1-、
     `memory/bugs.md` 208+/0-、`memory/target.md` 1+/1-，合计 216+/2-）；
   - 未跟踪 `scripts/check_mcpcf_db_isolation.py` 无变化 ⇒ **冻结零变化第 32 轮**，非新 WIP 事件。
   - 内容面复核：`memory/bugs.md` 的 +208 行是 **vq 项目（Python+Vue+Rust）外来账 BUG-592~635**
     （`reported_by: P3 收口 / FIST-Mbt 生命周期闭环官` 等，`ask_router.py`/`vue-tsc`/`pytest` 形状），
     与本纯 MoonBit 仓无关 ⇒ 外来账持续挂 owner 裁决（r245/r281 同族），**本轮不碰、不落账**
     （提交 `memory/bugs.md` 会连带把这 208 行 WIP 一起带走，触发 commit-discipline 的「窗口」事故）。

2. **换面巡检 `check_tool_coverage`**（MCP 工具「外壳+实现两层」覆盖判据，r300~r314 未轮过·本轮首跑）：
   - 自检：`--selftest` **10/10 格 SELFTEST PASS**（all-covered-rc0 / missing0 / MUTATION-removed-test-rc1 /
     MUTATION-names-tool_b / impl-only-still-missing / impl-only-rc1 / impl-layer-detected /
     empty-self-reject-rc2 / coverage-note-in-output / pass-not-correct-in-output）；
   - 实测：`PASS rc=0`——`[扫描] 工具 165 个`、`[A 外壳面] 有覆盖 165/165`、
     `外壳零覆盖 0/165（0.0%）`、`[B 实现面] 已映射 18 个，实现函数在测试里出现 18 个`；
   - 选面理由：BUG-455 判据（外壳零覆盖 = 接线/回执类缺陷，BUG-453/436/439 的根因面），
     与「有 bug 优先修 bug」优先级直接相关，且近期未轮过。

3. **零漂移双检**：
   - `check_tools_sync` rc=0（183 工具面一致，R8 清单分组 19 组 ΣN=183）；
   - `check_instruction_budget` rc=0（AGENTS.md 50440 / 65536 字节，全部章节可见）。

4. **Round C 三件**：维持过期不执行——BUG-527 摘 cc-link-flags 已 owner 否决（CI A/B 实证有害）、
   BUG-530 已 FIXED（3699f012a）、`check_usage_tool_count` 已注册（run_guards.py:175）。

5. **新发现 / 新立账**：1 件（见下节，临时号 BUG-636）。

## 新发现（BUG 临时号 636）：`check_tool_coverage` 是未接线的第 6 真源消费者，漏扫 18 工具（7 个零覆盖）

### 结论

`check_tool_coverage.py` 与 `check_tools_sync` / `check_doc_surface` / `check_plugin_sync` /
`gen_plugins` / `mcp_smoke` 一样是「工具注册真源」的消费者，但**没有 import `_tool_registry.py`**
（本仓唯一真源读取实现），而是保留一份**过期的本地实现** `extract_tools()`：

| 维度 | 真源 `_tool_registry.real_tools()` | `check_tool_coverage.extract_tools()` | 差距 |
|---|---|---|---|
| 扫描面 | `src/server/*.mbt` 全 41 份（排除测试） | **只 `src/server/server.mbt` 1 份** | 漏 40 份文件里的注册 |
| 注册形态 | `instrumented_tool(<var>,"name")` + 链式 `<var>.tool("name")` 两形态**并集** | `TOOL_RX=(?:instrumented\|)tool\(\s*(?:s\d*\s*,\s*)?"([a-z][a-z0-9_]*)"` | 不认链式；名字字符类 `[a-z][a-z0-9_]*` **匹配不了含 `.` 的 `mcpcf.*`** |
| 实测工具数 | **183** | **165** | **漏 18 个** |

`_tool_registry.py` 的 selftest **第 7 格（口径收口）**正是为防这件事而设——它强制上面 5 个消费者
「无本地实现 + 真 exec_module + 真委托 real_tools」，防「下次拆分又只改一半」（本仓实测红过两次）。
**`check_tool_coverage` 不在那 5 个消费者清单里**，是第 6 个被漏接的消费者。

### 证据（本轮实测，可复现）

- 真源 vs 判据差集（`python` 复算，`_tool_registry.real_tools()` − `extract_tools()`）= **18 个**：
  `hat_debate` `hat_merge` `hat_run`（3，`hat_hexa_tools.mbt`）/
  `mcpcf.circuit` `mcpcf.ops_init` `mcpcf.report` `mcpcf.review` `mcpcf.run_batch` `mcpcf.verify`
  `mcpcf.watchdog`（7，`mcpcf_embed.mbt`，链式 + 含 `.`）/
  `supervisor_kill_plan` `supervisor_prompt_consume` `supervisor_prompt_inject`
  `supervisor_prompt_list` `supervisor_reminder_tick` `supervisor_status` `supervisor_task_tree`
  `supervisor_task_upsert`（8，`supervisor_tools.mbt`）。
- 其中 **7 个实测零 A 面（外壳）覆盖**——对全部 `*_test.mbt`/`*_wbtest.mbt` 逐名 `grep -rlF` 命中
  **0 份**：`mcpcf.report` `mcpcf.review` `mcpcf.run_batch` `mcpcf.verify`
  `supervisor_prompt_consume` `supervisor_prompt_inject` `supervisor_prompt_list`。
  即**若判据正确扫到它们，会当场报「外壳零覆盖」并红**——现在它们不在扫描面里，故判据绿。
- `grep -n _tool_registry scripts/check_tool_coverage.py` **无任何命中** ⇒ 坐实未接线。
- 该判据是 **CI 门禁**：`run_guards.py:283 case("check_tool_coverage.py","--selftest")` +
  `:429 case("check_tool_coverage.py")`（本体 expect 0）⇒ 现在绿是「没看到问题」的绿，不是「没问题」的绿。
- README 历史锚点（`scripts/README.md` check_tool_coverage 条目）：BUG-455 当年登记 **22/154 零覆盖**
  为 known-red，2026-10-28 各 lane 补齐后 **0/154**、转正 expect 0——**整个转正建立在 154→165 的
  过期扫描面上**，对真源 183 从未成立过。

### 根因

工具注册从 `server.mbt` 拆到多文件（`supervisor_tools`/`hat_hexa_tools`/`mcpcf_embed`…）时，
`_tool_registry.py` 被立为单一真源并收编了 5 个消费者；`check_tool_coverage` 作为第 6 个消费者
**没在收编清单里**，保留了拆分前的本地读取实现 ⇒ 与本仓反复实证过的「5 处复制、只改一半」
（BUG-153 同族 / `_tool_registry` docstring 头号教训）是**同一失效形态**，只是落点换了一把尺。

### 修复规格（中任务 · 下轮或委派执行 · 本轮不抢修）

**目标**：让 `check_tool_coverage` 扫到真源全部 183 工具，且 CI 不因「新暴露的真实缺口」半红。

1. **接真源**：`check_tool_coverage.extract_tools()` 改为 import `_tool_registry` 并委托
   `real_tools()`（与 5 个既有消费者逐字同款 importlib 加载 + `exec_module` + `real_tools()`），
   删掉本地 `TOOL_RX` 单文件读取。名字含 `.` 的 `mcpcf.*` 用真源的 `([^"]+)` 捕获即可，
   A 面 `t in tests` 是子串判断、对点号名天然成立，无需改判法。
2. **CI 不半红**：接真源后本体从 rc=0 变 rc=1（新暴露 7 个外壳零覆盖）。按 **BUG-455 先例**把这 7 个
   在 `run_guards.py` 登记为 **known-red / todo 清单**（带逐条理由注释），本体暂登记 expect-1，
   使 CI 保持绿、且 7 个缺口被点名跟踪；**不删、不静默豁免**（豁免必须有理由且锚点成立，
   见 `check_battery_count_doc` / 判例-5 纪律）。
3. **后续转正**：给 7 个工具补 A 面测试（各工具一条「接线/回执」外壳用例，真调工具名断言回执），
   补齐后把本体 known-red(expect 1) 转正回 `case(...)`(expect 0)，对齐 BUG-457 的转正先例。
4. **锚点同批**：`run_guards.py` 改动 + 本判据 README 条目（把「154/165 口径」改成真源 183 口径 +
   登记 7 个 known-red）+ `check_battery_count_doc` 锚点四键（若 known-red 格改变 battery/gate 计数）
   必须**同一笔提交**（判例-5：新脚本/新格漏改锚点 = `check_battery_count_doc` FATAL 全仓门禁停摆）。
5. **收尾验证**：`python scripts/check_tool_coverage.py --selftest`（10/10）+ 本体（登记后按新期望）
   + `python scripts/_tool_registry.py --selftest`（确认收口格把 check_tool_coverage 也纳入——
   **注意**：需把 `check_tool_coverage.py` 加进 `_tool_registry.consumers()` 清单，否则收口格仍只查 5 个、
   第 6 个消费者下次漂移又抓不到）+ `python scripts/check_battery_count_doc.py` + 全量 `moon test --target js`。
   ⚠️ 第 5 步的「把 check_tool_coverage 加进 consumers()」是本修复**最容易被漏的一环**——不加它，
   收口格形同虚设，等于这次只修了一处、留下同一失效形态的复发面。

### 为什么本轮不抢修（只立账定规格）

- 触 `check_tool_coverage.py` + `run_guards.py` + README + battery 锚点（3~4 文件）+ 后续 7 条测试，
  属**中任务**（多文件 + 验证循环）；
- 接真源后判据变红、known-red 登记与 battery 锚点必须**同批**，任何一步没跟上 CI 就半红——
  30 分钟非阻塞唤醒里抢修，风险 > 收益；
- FIST 指挥官模式：中任务应委派子代理 + 指挥官终审，而子代理（`task`/`team`）**无 shell/build/test**，
  跑不了 `moon test`/电池验证 ⇒ 本轮最稳的动作是**把规格写死、立账、定优先级**，交由有验证能力的
  专门轮次收口。

## 资源消耗

- 判据 5 支（1 换面巡检 selftest + 1 实测 + 2 零漂移 + 1 WIP 核验）+ 深挖 2 支（真源差集复算 +
  7 工具零覆盖 grep 核验 + run_guards/README 锚点核验）+ FIST 六步链 1 发；
- 本轮无子代理（巡检判据为轻量命令执行 + 只读深挖，命令结果需指挥官亲阅终审，故直跑；
  修复面为中任务且子代理无验证能力，留待专门轮次委派）。

## 任务分配记录

- FIST 闭环 T0r71 六步全链（wd-r315，ns watchdog）：`temp/fist_r315_chain.sh` 后台串跑
  （node 冷启动 ~2min/步），回盘 `temp/fist_r315_out/1..6_*.txt`
  （publish / agent_acl_grant / claim / execute / submit / verify）；六步目标全 rc=0，
  verify 回执 status=已完成、assignee=wd-r315。

## 遗留风险

- **BUG-636（临时号）待落账 + 待修复**：`memory/bugs.md` 属 WIP 四件套（且 +208 行是 vq 外来账、
  挂 owner 裁决），本轮**不能提交该文件**（会连带带走 WIP）⇒ 落账推迟到 WIP 解禁/owner 裁决后，
  届时复核号（当前工作树最大 BUG-635，临时取 636）。**发现已完整固化在本报告（已提交），不会丢**。
- WIP 四件套冻结第 32 轮，弃置裁决持续挂起等 owner。
- **owner 裁决件累计四件**（同 r314）：① WIP 四件套弃置 ② `scripts/check_mcpcf_db_isolation.py`
  双风险（`moon publish` 公开面 + 未注册 run_guards）③ r302 落账方式 ④ 外来账处置（搬移 vq 仓 /
  登记 WHITELIST kind=foreign-adjudicated）。**本轮新增 ⑤**：BUG-636 的 known-red 登记口径
  （7 个零覆盖工具是「补 A 面测试转正」还是「评估后豁免」，建议前者，需 owner 确认修复优先级）。
- **r309 遗留低优打磨点（维持挂起）**：`check_arg_face_strict.py` docstring 自述滞后，纯注释零逻辑不立账。
- 换面巡检轮换面持续消耗：r315 轮到 `check_tool_coverage`，下一轮候选
  `check_effective_catch` / `check_ns_write_gate_coverage` / `check_ci_step_position` 等
  （**注意**：BUG-636 修复前不要再轮 `check_tool_coverage` 本体当「换面巡检绿」的读数——它现在绿是
  漏扫的绿，修复转正前其 rc=0 不构成「183 工具全覆盖」的证据）。

## 后续建议

- **最高优先**：下轮（或 owner 确认后）按上文「修复规格」委派子代理执行 BUG-636，指挥官跑
  `moon test --target js` + 电池终审；务必包含「把 check_tool_coverage 加进 `_tool_registry.consumers()`」
  这一最易漏环节。
- Round C 三件维持过期（owner 已裁决面），唤醒轮继续非阻塞巡检。
- 换面巡检继续按注册面轮换，优先选近期未轮过且有 `--selftest` 的判据；`check_tool_coverage` 在
  BUG-636 转正前退出轮换候选。

## 超额内容

- 无。

## 来源

- `git status --short` / `git diff --numstat` / `git log --oneline` / `git show HEAD:memory/bugs.md`（2026-11-15 本轮实测）
- `python scripts/check_tool_coverage.py --selftest` + 实测（本轮）
- `python scripts/check_tools_sync.py` / `python scripts/check_instruction_budget.py`（本轮）
- `_tool_registry.real_tools()` vs `check_tool_coverage.extract_tools()` 差集复算 + 7 工具 `grep -rlF` 零覆盖核验（本轮）
- `scripts/_tool_registry.py`（真源 + 第 7 格收口判据）/ `scripts/check_tool_coverage.py:101-123`（本地过期实现）/
  `scripts/run_guards.py:283,429`（CI 门禁）/ `scripts/README.md` check_tool_coverage 条目（BUG-455/457 历史锚点）
- `reports/2026-11-15-r314-wakeup-patrol.md`（上一轮基线）
- `temp/fist_r315_out/`（FIST 六步链回盘）
