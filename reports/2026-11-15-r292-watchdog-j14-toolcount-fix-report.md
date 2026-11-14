# 轮 292 巡检+修复报告（ExploreWatchdog · 2026-11-15）

## 结果摘要

**本轮破例发现并修复一处真漂移（J14/J16 文档面工具计数 182≠183）**，不再是「零新发现」的纯巡检轮。WIP 四件套维持冻结零变化第 9 轮（跨日 11-14→11-15 两天内仍冻结，`git diff --stat` 与 r284~r291 逐字相同：3 文件 208+/2-，相对 r291 零新增量）。Round C 三件维持过期不执行。

- **发现**：换面巡检 `check_doc_surface`（J14 工具计数自述 / J16 分组表点名）实测 **rc=1**（r285~r291 从未跑过这一面，本轮首次现形）。真源 `server.mbt` 注册 **183** 个工具，但 5 个「现状面」仍自述 **182**。
- **根因**：`git log -S 'commissar_gc'` 定位到 `8b1a0fd11 feat(mcp): commissar_gc 接线 182→183` —— 该提交把 `commissar_gc` 接入 `server.mbt`（真源 182→183）并同步更新 README/AGENTS/USAGE/插件态（「投影同批」），但**漏掉 `check_doc_surface` J14/J16 认领的这 5 面**；`check_tools_sync` 只认 README/AGENTS 面所以一直 183 绿，没人发现这 5 面漂了。
- **修复**：5 文件纯字符串计数校正（`help_topics.mbt` 182→183×3 + `[Board-DAG 32]→[33]` + 组表补 `commissar_gc`；`ARCHITECTURE.md`/`tool_use_rubric.md`/`agent-map.md`×3/`deliverable.md` 各 182→183），零逻辑改动。
- **验证**：`check_doc_surface` 实跑+selftest **双绿**、`check_tools_sync` 183、`check_instruction_budget`、`check_fmt_gate`（`moon fmt --check`）均 rc=0、targeted `cmd/cli` 测试 **10/10 绿**。`check_plugin_sync`(cl7) rc=1 判为 **WIP 投影**（bugs.md +44 条在飞是插件输入），非本轮回归、不代行重投影。

## 发现与根因（本轮重点）

### 漂移面（`check_doc_surface` 实测点名）

| 面 | 行 | 旧自述 | 真源 |
|---|---|---|---|
| `cmd/cli/help_topics.mbt` | 13 / 28 / 58 | 「182 MCP tools」×3 | 183 |
| `cmd/cli/help_topics.mbt` | 64 | `[Board-DAG 32]` 组表**漏点名 `commissar_gc`**（分组和=182） | 183 |
| `ARCHITECTURE.md` | 93 | 「182 工具分组」 | 183 |
| `templates/tool_use_rubric.md` | 13 | 「暴露 182 个工具」 | 183 |
| `docs/agent-map.md` | 12 / 27 / 61 | 「182 个工具」×3 | 183 |
| `docs/deliverable.md` | 17 | 「MCP 工具 \| **182**」 | 183 |

### 根因链（`git log -S` 实证）

`8b1a0fd11`（commissar_gc 接线 182→183）的 `--stat` 显示它**确实**更新了 `README.md`/`AGENTS.md`/`USAGE.md`/`docs/AGENTS-mcp-inventory.md`/`docs/deliverable.md`/全部 `plugins/**`（「投影同批」），但 `cmd/cli/help_topics.mbt` 的最近一次变更是 `a2d8e0a26`（filebind 179→182）、`ARCHITECTURE.md`/`tool_use_rubric.md`/`agent-map.md` 三面的计数也停在 182 ⇒ 这 5 面在 182→183 那一步**没被同步**。

这是 J14 的固有盲区（与 BUG-136/BUG-155 同形「写死一个数 + 之后没人钉」）：`check_tools_sync` 的文件面宽但**形状窄**（漏这 5 面里的中文三元组/`| **N**` 表形），`check_doc_surface` J14 形状宽但**文件面窄**（认领面名单）——两面各留缝，`commissar_gc` 那一步恰好只喂了 `check_tools_sync` 认的面。

### 为什么现在才现形

`check_doc_surface` 是 CI 门（`ci.yml` + `fist-ci.yml` 均在列），r285~r291 的换面巡检**没轮到它**（轮的是 `check_foreign_ledger_entries`/`check_publish_payload`/`check_arg_face_strict`/`check_store_tables_wired`/`check_sql_bind_alignment`）⇒ 这一格在 CI 上本会红，只是本地巡检轮还没扫到。本轮扫到即修复，把 CI 红面提前在本地收掉。

## 修复（5 文件 · 纯字符串 · 零逻辑）

- `cmd/cli/help_topics.mbt`：`(182 MCP tools)→(183)`、`182 MCP tools / 3 resources → 183`、`182 MCP tools (19 groups) → 183`、`[Board-DAG 32]→[33]`、组表末尾 `commissar_read→commissar_read commissar_gc`（补上漏点名的工具，使分组和 182→183、J16 点名补齐）。
- `ARCHITECTURE.md`：`- 182 工具分组：→ - 183 工具分组：`
- `templates/tool_use_rubric.md`：`暴露 182 个工具 → 暴露 183 个工具`
- `docs/agent-map.md`：3 处 `182 个工具 → 183 个工具`
- `docs/deliverable.md`：`MCP 工具 | **182** → **183**`

未动任何插件输入（`server.mbt`/`moon.mod`/`memory/bugs.md`/`.mcp.dev.json`）⇒ **无需 `gen_plugins.py` 重投影**（插件态本就说 183 工具 / 0.3.11，已正确）。

## 验证

| 检查 | 结果 |
|---|---|
| `check_doc_surface`（实跑，J14+J16 目标面） | ✅ **rc=0**「183 工具…分组和=183」 |
| `check_doc_surface --selftest` | ✅ **rc=0**（真面不再红 ⇒ 自检从 rc=2 解除，合成违例各面均发红） |
| `check_tools_sync` | ✅ rc=0（server.mbt 183，AGENTS/README/deliverable/scoring_rubric 对齐，R8 19 组 ΣN=183） |
| `check_instruction_budget` | ✅ rc=0（AGENTS.md 50440/65536） |
| `check_fmt_gate`（内部 `moon fmt --check`） | ✅ rc=0（格式干净 ⇒ 改动的 `.mbt` 无需再 `moon fmt`，纯字符串不改缩进） |
| targeted `moon test --target js cmd/cli`（`moon_test_env.py`） | ✅ **10/10 passed, rc=0**（node 解析到真 `.exe`，非 `.cmd` 垫片） |
| `check_plugin_sync`（cl7） | ⚠️ **rc=1 = WIP 投影**（见下，非回归，不修） |

**全量套件说明**：`python scripts/moon_test_env.py`（全仓 `moon test --target js`）本机冷编译 **6min+ 未完**（输出缓冲、无失败行）⇒ 按「忌空转」转 targeted。targeted `cmd/cli` 是**唯一受改动影响**的包（`help_topics.mbt` 属 `cmd/cli` 可执行包，其 pub fn 不被其它包的 test 导入；grep 全 `cmd/` 无 test 断言该计数），且 `check_fmt_gate` 已证该 `.mbt` 可解析 ⇒ targeted 10/10 + 各守卫 + 分析已充分覆盖；**CI 全量套件为权威确认面**。

**`check_plugin_sync`(cl7) rc=1 判读（WIP 投影，非回归）**：插件 SKILL.md 内嵌 `memory/bugs.md` 的账本摘要（「共 585 条入账…」）。实测工作树 `bugs.md` = **625** 条 vs 提交面（HEAD）= **581** 条（WIP 在飞 `+44` 条：BUG-582~635 一批 P3~P7 跨项目误落账）。`gen_plugins.py --check` 读**工作树**账本 ⇒ 与**提交面**插件态不符 ⇒ 红。这是冻结 WIP 的投影（同 `check_foreign_ledger_entries` 脏树投影一族，非本轮回归）。**不代行 `gen_plugins.py` 重投影**：那会把另一 agent 未提交的账本 bake 进提交面插件态，违反「另一 agent 的 WIP 文件绝不碰」。**本轮改动不触及任何插件输入**，故不触发「改计数面⇒同批重投影」纪律。干净 CI 检出（HEAD）不受本影响。

## 资源消耗

- 工具调用 ~30 次（WIP/日志核对 3 + 守卫枚举 1 + 根因 `git log -S`/`git show --stat` 2 + 修复 edit_file 11 + 验证守卫 6 + 目标测试 2 + FIST 闭环脚本 2 + 报告/日志 4）。
- 有 targeted 构建/测试（`cmd/cli` 10/10）、无全量测试（转 targeted，理由见上）、无 FIST 之外的网络面。
- **禁区零碰**：4 个 WIP 文件零改、不提交；`memory/bugs.md`（WIP）只读核数、未改。

## 任务分配记录

无子代理派发。本仓「成员无 shell、不委派构建/测试」约束下，改动的验证（`moon test`/守卫）必须由持 shell 的指挥官亲跑；且改动为 5 文件机械字符串校正 + 已完成的根因调查，委派收益为负 ⇒ 指挥官直查直改直验。

## WIP 面（未收口 —— 冻结零变化第 9 轮 · 跨日）

| 文件 | mtime | 本轮变化 |
|---|---|---|
| `scripts/check_mcpcf_db_isolation.py` | 2026-11-14 11:11:49 | 未动（内容零变化 ⇒ mtime 同 r284~r291） |
| `memory/bugs.md` | 2026-11-14 10:47:48 | 未动（工作树 625 条 / HEAD 581 条，白名单外 23 条零增长，现最高 BUG-635） |
| `docs/improvement-plan-20261010.md` | 2026-11-14 10:55:34 | 未动 |
| `memory/target.md` | 2026-11-10 10:34:16 | 未动（Round 24 孤儿行） |

`git diff --stat` 与 r284~r291 逐字相同（3 文件 208+/2-）⇒ 四文件内容零变化。均为另一 agent（或 vq 项目记账通道）的 WIP，**禁区零碰、不提交**。

**弃置信号判读（维持 r287 提请）**：WIP 面连续 9 轮零变化（r284 检测未收口 → r285~r292 逐轮零变化，跨日 11-14→11-15 两天内仍冻结）。r287 已正式提请 owner 裁决，**本轮维持挂起**；清理权保留给 owner / 另一 agent，指挥官不代行（跨仓不可逆 + 禁区文件）。

## 守卫面（换面巡检 + 零漂移基线）

| 守卫 | 读数 | 与上轮 |
|---|---|---|
| `check_doc_surface`（实跑） | **rc=1→修复后 rc=0**（J14/J16 漂移现形并修掉） | r285~r291 未跑，本轮首跑 |
| `check_doc_surface --selftest` | **rc=0** | 首跑（真面红时曾 rc=2，修复后解除） |
| `check_tools_sync` | rc=0（183 零漂移） | 同 r285~r291 |
| `check_instruction_budget` | 50440/65536，rc=0 | 同 r283~r291 |
| `check_plugin_sync`(cl7) | rc=1（WIP 投影，非回归） | 本轮新纳入核验 |
| `check_fmt_gate` | rc=0（`moon fmt --check` 干净） | 本轮新纳入核验 |

## FIST 闭环（T0r48 · wd-r292 · ns watchdog）

**6 步全链后台串跑**（脚本 `temp/fist_r292_loop.sh`：publish 后从回包 JSON 提取 task_id 再串后 5 步，沿用 r285~r291 结构）：

| 步 | 状态迁移 |
|---|---|
| publish | 发布 T0r48（claim_ready） |
| agent_acl_grant | can_write=true（wd-r292） |
| claim | 已领取（assignee=wd-r292） |
| execute | 执行中（deliverable=本报告） |
| submit | 待验收 |
| verify | 已完成（completed_by=wd-r292） |

各步回包落盘 `temp/fist_r292_out/1..6_*.txt`（6 步 rc 全 0，CHAIN DONE，verify 回执 status=已完成）。

## Round C 队列状态（依据记忆裁定，不重推导）

- BUG-527 摘 cc-link-flags：owner 已否决（CI A/B 实证有害，d43a06a28 治本→8a669992d 回滚）
- BUG-530：已 FIXED（3699f012a）
- check_usage_tool_count：已注册（run_guards.py:175）

⇒ 队列三件全部过期，本轮不执行（即便 `src/**` 未被 WIP 占用也不重推导）。

## 遗留风险

1. **`check_doc_surface` J14 盲区（本轮修了值、没修面）**：`commissar_gc` 那步只喂 `check_tools_sync` 认的 README/AGENTS 面，5 个 J14 面无人认领 ⇒ 下次「加/删工具」若同样只更新 README/AGENTS，这 5 面会**再漂**。根治面：给 `check_tools_sync` 的 R3b/R7 扩形状（认 `| **N**` 表形 + `N 工具` 中文三元组）或把这 5 面显式并入 J14 认领名单并各补正/反夹具。**本轮只校了当前值，未扩守卫面**（扩面是内容决策 + 需补夹具，建议单列）。
2. **`check_plugin_sync`(cl7) 干净面验证缺口**：本轮在脏树看到 rc=1（WIP 投影）无法确认干净 HEAD 是否真绿（HEAD 581 条 vs 插件态 585 条摘要存在潜在不同步）。**干净 CI 检出才是权威**；若 CI 上 cl7 也红，则是历史某笔「改 bugs.md 未同批重投影」的一源四态违约，需单列追查。
3. **BUG-583 方向④ 守卫未注册电池（r284 起维持）**：`scripts/check_mcpcf_db_isolation.py` 仍为未跟踪 WIP、无执行面（风险双格见 r291）。
4. **P3~P7 跨项目误落账（vq 项目缺陷，现最高 BUG-635，白名单外 23 条零增长）**：维持呈报待 owner 裁决。
5. **WIP 面连续 9 轮零变化（r287 已提请裁决，跨日两天仍冻结）**：owner 裁决前继续观察 `bugs.md` mtime。
6. **唤醒轮收口中断风险（r206/r272 实证）**：维持每轮退出前两格核对（报告已 scoped 提交 + 当日日志已追加本地留置）。

## 后续建议

1. **【新 · 建议单列】扩 `check_doc_surface` J14 / `check_tools_sync` R3b 守卫面**：把 `help_topics.mbt`/`ARCHITECTURE.md`/`tool_use_rubric.md`/`agent-map.md`/`deliverable.md` 这 5 面的「N 工具」形状显式认领（各补正/反夹具），杜绝「加工具只更 README/AGENTS ⇒ 5 面再漂」复发。本轮只校值、未扩面（扩面是内容决策，留裁决）。
2. **【维持 r287 提请 · owner 裁决】WIP 弃置信号已达标且跨日两天加强**：四件套连续 9 轮零变化（跨日 11-14→11-15），建议 owner 裁决另一 agent 收口（配 BUG-583 执行面 + 注意发布载荷面 P1）或确认弃置。清理属跨仓不可逆 + 禁区文件，**指挥官不代行**。
3. **核对干净 CI 的 `check_plugin_sync`(cl7)**：确认 HEAD 插件态是否真与提交面 bugs.md 同步；若 CI 红则追查历史「改账未重投影」那一笔。
4. 若 `bugs.md` mtime 再变，优先核对是新增误落账批次（P8）还是 owner 裁决后的清理提交。

## 超额内容

无（targeted `cmd/cli` 测试是标准验证的必要替代，非超额；全量套件转 CI 权威面）。

## 来源

- `git status --short` / `git log --oneline -6` / `git diff --stat`（本轮实跑）
- `git log -S 'commissar_gc' -- src/server/server.mbt`（定位 8b1a0fd11）+ `git show --stat 8b1a0fd11`（证实该提交更新了哪些面、漏了哪些面）
- `git show HEAD:memory/bugs.md | grep -c` vs 工作树 `grep -c`（625 vs 581，WIP 投影判读）
- `python scripts/check_doc_surface.py`（实跑 rc=1 现形 → 修复后 rc=0）/ `--selftest`（rc=0）
- `python scripts/check_tools_sync.py`（rc=0，183）/ `check_instruction_budget.py`（rc=0，50440/65536）/ `check_plugin_sync.py`（rc=1 WIP 投影）/ `check_fmt_gate.py`（rc=0）
- `python scripts/moon_test_env.py cmd/cli`（targeted JS 测试 10/10 passed, rc=0）
- FIST 闭环 T0r48 收口（wd-r292，ns watchdog，6 步后台串跑 `temp/fist_r292_loop.sh`，回包落盘 `temp/fist_r292_out/`，verify 回执 status=已完成）
- r291 报告磁盘原件（`reports/2026-11-15-r291-watchdog-patrol-report.md`，结构对齐）
