---
AIGC:
    Label: "1"
    ContentProducer: 001191440300708461136T1XGW3
    ProduceID: 9f2a11add43fbf12a546606fb2b962ab_da2a1851a8e311f1be88525400aeaaa3
    ReservedCode1: bjwlVhY//jNc6vR1bak3cQP2fFnNxgXBoSwyG/1vXO7RcmiUeNogpvg5bJX8+s1vJkJCExuCTwep3TAb/zQpNOc6AWonho81iZe+p4SycFt/sYdnqYcCf39VAq7CINccbtup0lAEG79KluaHEsQ+mLNy7+YuOSrRqa2dF5S5nZlk8Py6wb5xilxTI2M=
    ContentPropagator: 001191440300708461136T1XGW3
    PropagateID: 9f2a11add43fbf12a546606fb2b962ab_da2a1851a8e311f1be88525400aeaaa3
    ReservedCode2: bjwlVhY//jNc6vR1bak3cQP2fFnNxgXBoSwyG/1vXO7RcmiUeNogpvg5bJX8+s1vJkJCExuCTwep3TAb/zQpNOc6AWonho81iZe+p4SycFt/sYdnqYcCf39VAq7CINccbtup0lAEG79KluaHEsQ+mLNy7+YuOSrRqa2dF5S5nZlk8Py6wb5xilxTI2M=
---

# CHANGELOG

本项目变更记录（参赛期间每日至少 1 条，保证提交可追踪）。

## v0.3.0 (unreleased) - 合并兄弟项目 fist-model-router + 接入 aider/atomcode 执行器（六模式自驱轮）

- **推进（合并本体）**：`src/router/`（`model_router.mbt` 决策核心 + `router_config.mbt` 配置回落 + `router_state.mbt` 状态
  schema）与 `src/executor/cli_argv.mbt`（aider/atomcode argv 形状）从兄弟项目/衍生项目迁入，纯计算零 IO；
  `src/server/model_router_ops.mbt` 只做三件必须 IO 的事（状态落盘 `{project_dir}/memory/model-router-{ns}.json`、
  时间戳服务端盖章、spawn 执行器）。MCP 面新增 **4 个工具**（116→120）：`model_route` / `model_router_status` /
  `model_router_reset` / `executor_run`，四态同批补齐（CLI `fist.py call`、`docs/model-router-skill.md`、插件态重投影）。
- **合并时的三处裁决**（不是顺手改，全部入账）：时钟不接受调用方注入（BUG-33 政策，上游可注入 `now`）、
  时间↔秒改 civil-days 精确算法（上游「365 天固定年 + 每月 31 天」跨月/闰年把 5h 窗口判偏 —— BUG-52）、
  空池不再索引 `[0]` panic（上游必然崩溃点 —— BUG-53）。
- **安全边界**：`executor_run` 只认登记表 `aider|atomcode`，argv 形状固定、不经 shell（恶意提示词始终是**一个**
  argv 元素），可执行文件名由登记表推导 ⇒ 不给调用方注入命令的口子；新增 `dry_run=true` 只回显 argv、
  一个进程都不起（宿主命令能力默认收紧，先审后跑）。BUG-4 的白名单策略未被本次合并放宽。
- **寻虫→修复**：入账并闭合 **BUG-52~60** 共 9 条。其中三条是本轮新代码自己的缺陷：负游标取模落负下标
  （`assert_eq(-7 % 2, -1)` 实测语义，`router_restore` 现夹紧并点名 —— BUG-54）、`config_json` 解析失败被静默
  当作"没传配置"（现显式拒绝 —— BUG-55）、`usage_report.current_model` 报的是轮询游标位而非本次选中模型
  （同一响应自相矛盾，现 `last_pick` 单点登记 + `cursor_model` 分栏 —— BUG-56）；三条是工具链缺陷：
  `issue_scan.py` 把 `--include-tests false` 当开启（BUG-57）、守卫族在 GBK 控制台抛 UnicodeEncodeError
  冒充红色（BUG-58）、**父节点自动提升为待验收时不带交付物 ⇒ 与 Omega 成果复验门禁互锁无出路**
  （BUG-59，本轮 5 个父节点实测全中，现提升即继承子叶交付）。
- **验证**：`moon test --target js` **439/439**（本轮新增 33 项回归锁：rt_1~13 / rs_1~5 / ca_1~7 / mo_1~5 /
  BUG-59 两条）；六守卫 rc=0；调用面冒烟 `temp/router_smoke.py` **27/27**（tools/list 120 工具、路由跨进程复现、
  越界/坏输入必拒、dry_run 零副作用）；L4 硬门 `output_validate` verdict=pass（23 件产物 + 外部判据），
  并配一条必然违例的对照证明判据能发红。
- **自我迭代四开关全开**：laya（`laya_decide` 冷启动，sidecar 不可用→确定性回退）、issue_up（9 条入账：BUG-52~60）、
  call_log（`model_route` 34 次 / `executor_run` 24 次实跑留痕）、Omega（拆解树 21 节点全部走完语料门禁 +
  成果复验后「已完成」）。任务树 `router-merge` 收口：`by_status={已完成: 21}`。
- **已知边界**：`dry_run=false` 会真起外部 agent 烧真实配额，本轮只验证到 argv 与拒绝路径，真跑留人点头；
  配额记"次数"不记 token，`cost_estimate` 是占位。

### 🧭 atgc-merge 防御完备性补丁（报告抓手 1/2/3，12:38 落地）

- 归因来源：`_fist_meta_prompts/实验/atgc-merge/归因报告_防御完备性.md`——A/B 里裸推进组做了 k>5 溢出防护、编排组没有，
  差异不在能力而在**动机与视野**：递归拆解把全局视角压缩掉了（全局不变量无 owner），弱语料让执行体理性地停在判据边界。
- 引擎新增 `boundary_probe`（默认 false 零回归）：深拆时追加一条**边界审视叶**作为全局输入域 owner，
  并给每条叶挂「边界四问：空输入/极值/非法输入/资源极限」——把"spec 没写"从无人负责变成有主、可领取、可验收。
- 实例侧（抓手 3）：两份含 `## 完成标准` 的模板补两条完成标准（边界与域外行为 + 深拆默认 `reinject_context=true`）。
- 证据：`engine_boundary_test.mbt` 两条锁 + 开关对照（摘掉注入 → `2 != 3` 红，恢复 → 107/107）；
  调用面终审 34/34，其中零回归对照打在对照组 12 条子任务上。
- **未落地**：抓手 4 的外部模板库七份——工作区外写入被作用域策略拦截，补丁与幂等脚本备在
  `temp/atgc_handoff_抓手4_外部模板补丁.md`，交发起人执行。

## v0.3.0 (unreleased) - 开发规范**单文件成文**（R116）+ 文档面守卫扩到 J1-J8

### 📐 规范从"散在 README 里的 prose"变成单一真源
- 新增 `AI-DEVELOPMENT-STANDARD.md`（规范性正文）：术语表 / 通用 5 条 / **目标项目必备文档集骨架**（README·AGENTS·CHANGELOG·docs skill·memory bugs 账本·日报与汇报·templates 各自的必填段与门禁）/ FIST 专项 5 条 / 自我迭代四开关的**可量化判据表**（call_log·issue_up·laya·Omega + reinject_context·boundary_probe）/ 四态验收 checklist 7 项 / 一轮标准流程（真实参数名）/ 违例分级与历史豁免 / 已知边界。
- `project_standards` 升 **R116** 并新增 `canonical_doc` 字段：正文=人类真源，工具=机器投影，摘要不得各写一套（README/AGENTS 已改为"摘要 + 指向正文"）。
- 描述面纠偏（BUG-48）：工具描述不再自称"一源三态/三形态 checklist cl1-cl6"，并如实声明"只下发清单、不扫描文件"。

### 🔍 自驱式【验证】模式跑出来的缺陷与修复
- **BUG-48**：对外描述与工具输出矛盾（`server.mbt` 描述旧口径）→ 描述/属性说明/注释三处对齐 + wbtest 钉 canonical_doc。
- **BUG-49**：`templates/*.md` 的 FIST 调用示例用了**未声明参数**（`output_validate.check_results`、`project_standards.project_dir/dry_run`、`evolve_distill.round`、`publish/watchdog_tick.now`）且缺 required；`_instrument` 只校验 required ⇒ 未知键静默丢弃，照模板执行等于"以为跑了硬门其实什么都没验" → 五份模板改为真实参数并补齐 required。
- **BUG-50**：`docs/agent-map.md` 宣称 316 项全绿（实测 406）→ 更正；`check_test_sync` 的白名单判据测不到"第 5 份文档写别的数"，该缺口如实入账未闭合。
- 35 处旧口径批量对齐（README/AGENTS/docs×4/templates×5/scripts×2/server.mbt），历史陈述（memory/reports/CHANGELOG）按规范 §2 豁免**不追改**。

### 🛡️ 守卫族扩面（`check_doc_surface` J1-J5 → J1-J8）
- **J6** 规范正文 ↔ 机器投影：17 个 id 全在、version 一致、`canonical_doc` 可达、README/AGENTS 点名正文。
- **J7** 规范性表面禁旧口径（`三形态`/`一源三态`），历史表面豁免。
- **J8** 模板调用面契约：解析每工具真源属性集，只取 `tool({…})` 的 **depth-1 键**（不误伤 `artifacts` 子 schema）+ 参数表核对。
- `--selftest` 新增合成违例：三条判据抓不到违例即 SELFTEST FAIL（防"判据是装饰"）。
- **单调性证明**：`temp/j_before_after.py` 把三条新判据跑在 HEAD 内容上 ⇒ J6=2 / J7=11 / J8=19 共 **32 条发红**；工作树 **0**。

### ✅ 验证证据
- 调用面终审 `temp/stdalign_verify.py` **21/21 PASS**（ns=stdalign，真实 MCP 入口）：正文 L4 落盘、投影一致、laya 可用、publish→task_plan_deep(omega+boundary+reinject)→叶级 Omega 语料链→claim→execute→成果复验→submit→verify 闭环、report_bug 入账、`output_validate` 15 项含 6 条 `not_contains` 反证 verdict=pass、call_log 记录 31 个不同工具（自我迭代活证据）、对照组零回归（默认关不注入边界文本）。
- `moon test --target js` = **406/406**；六守卫全绿；插件态重投影 56 文件与真源一致（cl7）。

---

## v0.3.0 (unreleased) - 四模式流水线自我迭代 · Round 3 收口（寻虫→修复→验证→打磨）

### 🐞 寻虫（本轮新账 9 条：BUG-32 ~ BUG-40）

- **BUG-32 [high]** 调用面验收可能在度量旧二进制：`scripts/fist.py` 直接拉起 `_build/.../main.js`，不比新鲜度（实测源码比产物新 68 分钟）。
- **BUG-33 [high]** 45 个工具向调用方广告可选入参 `now`，全仓 0 处读取——BUG-1 的服务端盖章落地后契约在说谎。
- **BUG-36** `memory_gc` 对非法 kind **静默改靶**到 `target` 再截断：打错一个字母就写坏你没点名的文件。
- **BUG-37** `mode_list.forbidden_tools` 写的是**不存在的工具名**，polish/tidy「禁发新功能」红线在机器面上是空的。
- **BUG-38 [high]** 四份流水线模板教主流程调用 `run_check_external({cwd,command,timeout_sec})`，该工具**未注册**（真名 `run_check`，参数名 `task_id/cmd/args/workdir/timeout_ms` 全不同）；根因是模板把 `server.mbt:1162` 的**引擎内部函数名**当成了对外工具名。
- **BUG-39** CLI 形态对返回顶层数组的工具（`mode_list` / `call_log` 等）AttributeError 崩溃：判退出码只兜 `JSONDecodeError`。
- **BUG-40** 同名字段 `project_dir` 在 bug 族拒绝绝对路径、在任务族接受绝对路径（`bugreport.mbt:10` 自述「一律相对拼接」=有意设计）⇒ 一条流水线两套口径，绝对路径客户端默认调不动账本。
- 另 BUG-34（熔断 Half-Open 无探测节流）、BUG-35（github `--data` 非合法 JSON + win32 `cmd.exe` 引号语义）由本轮寻虫批入账。

### 🔧 修复（7 条挂 FIXED，2 条明写 NOT-FIXED 与出路）

- **修**：BUG-31（`output_validate` 先校验规格再解释 + pass 文案只声明**真正评估过**的不变量）、BUG-32（产物落后即自动重建，`FIST_NO_AUTOBUILD=1` 显式拒绝）、BUG-33（删 45 处 schema 广告 + 清 6 处描述文案「now 时间戳」）、BUG-36（非法 kind 拒绝且不落笔）、BUG-37（名单换真实注册名 + 三份模板同源清理）、BUG-38（9 处模板调用改真名真参）、BUG-39（数组结果不再崩）。
- **不修，但把理由与出路写进账本**：BUG-34（探测配额要扩 `cb_get/cb_save` 表结构，跨后端契约变更；内存版计数在多进程 MCP 下每进程各计，比现状更误导）、BUG-35（真验证需连 GitHub，凭据只走环境变量注入；只换 Json 构造会留下 Windows 侧引号坑=半修）。

### 🚦 验证（打到 MCP 入口，30/30）

- `temp/r3_callsite_audit.py`：自己 spawn `main.js` 走 JSON-RPC，J00 先钉「入口不早于源码」的顺序不变量（过期即 FATAL 作废全部判据），其余 29 条逐项打真接口，**30/30 PASS**；含 Omega 强验证全链（`[omega:required]` 建根 → `task_plan_deep` → 建语料 → 审语料 → 无交付物时复验被拒 → 交付后放行）、`laya_decide` 降级决策、`call_log` 记到被拒调用、`bug_list` 见新账。
- 判据自纠 3 处（都不是产品缺陷）：本 server 说 MCP 2026-07-28、**协议无 `initialize` 握手**，服务端身份在 `tools/list` 的 `result._meta["io.modelcontextprotocol/serverInfo"]`（BUG-21 据此才真正可审）；`dag_mc` 因我传了臆造 `task_id` 而报 `insufficient`；`J19c` 误用 `verdict` 字段名（实为 `status:approved`）。

### 🧱 守卫族加固（6 个全绿）与开关对照

- `check_tools_sync.py` 新增 3 条判据：forbidden_tools ⊆ 真注册集（BUG-37）、禁止再广告 `"now"` 入参与「now 时间戳」文案（BUG-33）、模板里 `` `name(` `` 调用形状必须真注册（BUG-38）；解析退化即 FATAL 不出绿灯。
- **负向矩阵实测**：人工注入三处漂移（臆造名 / 重新广告 now / 模板调用 `run_check_external(`）→ 三条判据**分别点名报错**、还原即绿。
- **开关对照**：同时摘掉 BUG-36 的两处修复 → `memory_18` / `memory_19` 同时红（92 项中 2 failed），恢复 → 92/92；顺带暴露「consolidate 非法 kind 此前无锁」的覆盖缺口并补上。

### 📐 规范与文档面收口

- 测试总数 394 → **404**（本轮 +10 条锁），守卫族 5 → **6**（补 `check_doc_surface`），徽章/README/AGENTS/deliverable/scoring_rubric 一次性同步。
- `USAGE.md` 顶部把「只覆盖到 0.2.3 的调用面」写成显式边界并指向 AGENTS + `templates/pipeline_mode_*.md`（BUG-30 建议 2 落地：把陈旧变成声明，而不是补写 41 个工具）。
- 账本 40 条：14 条已挂 FIXED 小记、26 条待修（账本只追加不关闭，见 BUG-9）。

### ⚠ 本轮自陈的不足

- 一源四态的**四宿主插件目录**本轮只随生成器重投影，未逐一在真实宿主里装载验证；BUG-32 的新鲜度自检只有调用面证据，**没有**进守卫族（干净克隆未构建时该不变量必假）。
- 熔断 Half-Open、github 落地面这两条高价值缺陷本轮未收口，已带出路挂在账本与 `bugs` 命名空间（BUG-40 的修复单 `T0r317` 即由 `report_bug publish_task=true` 自动发布）。

## v0.3.0 (unreleased) - 一源四态 · 插件态落地（cl7）

### 🧩 形态扩展：三形态 → 一源四态（新增宿主插件态）

- **skill 真源迁入主仓**：外部 `E:\IDEProjects\moonbit-skills\skills\fist-mbt`（SKILL.md + 10 references）与 AtomCode 侧 `~/.atomcode/skills/fist-commander` 收进 `plugins/source/`。旧外部副本长期把工具数写成「41」，正是 BUG-22/30 那类"文档面落后真源、守卫覆盖面窄于主张"的活证据。
- **`scripts/gen_plugins.py`（生成侧）**：以 `src/server/server.mbt` 工具数 / `moon.mod` 版本 / `memory/bugs.md` 账本 / `plugins/source/` 正文 / 根 `.mcp.json` 启动参数为唯一真源，按指定顺序投影 **atomcode → codearts → deepseek-harness → claude** 四宿主插件目录（56 个文件，字节稳定、无时间戳，可 diff）。正文数字改成 `{{TOOL_COUNT}}` 等占位符，宿主侧不再存在第二份手写数字。
- **`scripts/check_plugin_sync.py`（cl7 守卫，挂进守卫族与 ci.yml）**：子进程重跑生成器 `--check` 判漂移，另查四宿主入口齐全、无残留 `{{占位符}}`、claude manifest 版本==moon.mod、`plugins/claude/.mcp.json` 与根 `.mcp.json` **逐字节**相等、每个生成 SKILL.md 的 `tools=` == 实测；实测 <=100 直接 FATAL(2)——解析失败绝不报 PASS。

### 📐 规范升档 R114 → R115

- `r2-single-source`：一源三态 → **一源四态**，并写明插件态必须是生成投影。
- `f2-three-forms-aligned` → **`f2-four-forms-aligned`**：四态必须对齐（MCP / CLI / Skill / Plugin）。
- checklist 6 → **7 项**：新增 `cl7-plugin-forms-sync`（gate=hard）。
- 补 `src/server/project_standards_wbtest.mbt` 3 条白盒锁——该工具此前**零测试覆盖**（它自称什么守卫就信什么）。

### 🔧 判据自纠（本轮两个"红是判据坏了"）

- `String::split` 在本 moonc 版本返回**消费式 `Iter`**，`r2_count` 里连调两次 `.length()`（第一次 4、第二次 0）→ 恒返 -1 → BUG-18 两条文本锁假红。改为逐字符扫描计数；实现侧实测 `laya_probe_cached(`=3、`route_decision(context, split_n_hint)`=5、`300000,`=0，BUG-18 修复本已到位。
- BUG-4 拒绝文案说"其子目录"而契约要求"子树"→ 文案补齐（守卫族 cl 系列的红必须靠实现/文案改，不许改判据）。

### 🧹 一次性文档同步

- 测试总数 376 → **394**（README 徽章/正文、AGENTS、deliverable、scoring_rubric 全量同步；`moon test --target js -j 1` = 394/394）。
- `check_scripts_index` 实测暴露 5 个历史欠账脚本未登记（`flush_github.mjs` / `output_validate.py` / `mcp_bug_loop.py` / `pentad_fist.py` / `test_mcp_bugs.py`），连同 2 个新脚本一并补登。
- 守卫族 4 → **5** 个，ci.yml 增 cl7 步骤；五守卫本轮全绿。

### ⚠️ 过程中被外部流水线入账

- `BUG-31`（10:41:50 由 Cypy 侧 polish 流水线写入本仓账本）：`output_validate.parse_artifact` 不校验未知字段，artifact 键拼错被静默降级为"存在+非空"仍判 pass——**L4 硬门可被空检查满足**。列入 Round 3 修复队列。cl7 恰好因这条入账触发了真实漂移报警（非合成测试）。

## v0.3.0 (unreleased) - 四模式流水线 Round 1

### 🐛 BUG 清偿（寻虫→修复→验证→打磨 第一轮，至多 4 单全部闭环）

- **BUG-14 [high] laya_decide 决策契约缺失**：工具描述承诺返回 `decision:{source/feature_route/split_n/...}`，实测 4 条返回路径里只有「探测失败」那一条真的带 `decision`——sidecar（`scripts/laya_decide.py`）从不产出 decision，`laya_js.mbt` 在退出码非 0 时把 `available` 覆写为 false 后仍返回 `Ok(...)`，于是 handler 的 `Ok(res) => res.stringify()` 原样透传，调用方按文档取 `decision.feature_route` 拿到 `undefined`。修法：新增包内私有 `laya_ensure_decision`（自带 decision 原样保留，否则合并 `route_decision` 并附 `decision_note`），`Ok`/`Err` 两条分支都过这道补齐。源码：`src/server/server.mbt`
- **BUG-15 [medium] issue_scan 精度（自噪声）**：扫描器对**每一行原文**做子串匹配，既跳不掉整行 doc 注释（`0xcbf29ce484222325 / 0x100000001b3` 因含 `"/ 0"` 被判 div-by-zero high），也不排除自身规则表（`pattern: ["rows[0]"]` 必然命中 index-out-of-bounds）。修法：新增 `scan_is_comment_line` / `scan_is_rules_table` 两个私有谓词各接一处；规则表判定用「文件名后缀 + 含 `fn scan_rules(`」而非硬编码路径，且仍计入 `scanned_files`。源码：`src/server/issue_scan.mbt`
- **BUG-16 [medium] 对外版本三处硬编码漂移**：`status_summary` / `project_health` / `fist://overview` 汇报 `version:0.2.4`，而 `moon.mod` 已是 `0.3.0`。修法：收敛为包内常量 `project_version`（非 pub，不进 `.mbti`），三处调用点改为引用；刻意不采用「三处各自改成同一个新值」的假修法。源码：`src/server/server.mbt`
- **账本卫生 BUG-6/BUG-7（low）**：两条 `summary: BUG-5 resolved_path check` 的探针残留（无 detail、无源码位置）就地标注作废。按 append-only 原则**未删条目、未手翻状态位、未新增 close API**——它们仍显示 OPEN 是 BUG-9（账本只写不销）的表现，不是遗漏。活判据：`grep -n '^- detail: (缺失)$' memory/bugs.md` 全文只命中这两条。

### ✅ 验证与回归

- 新增回归锁 **10 条**：`src/server/laya_decide_wbtest.mbt` 6 条（补齐 / 退出码非 0 / 自带 decision 不被覆盖 / 脏数据不 panic / split_n 越界夹紧 / 确定性）、`src/server/issue_scan_test.mbt` 追加 3 条（注释与代码同文件的**双向断言**、扫真实 `src/server` 的自命中回归 + `scanned_files>0` 前置哨兵、扫真实 `src/omega` 的明细与 `by_severity` 双口径 high==0）、`src/server/fist-mbt_wbtest.mbt` 1 条（版本守卫，含「坏解析恒空串」的反假绿哨兵）。
- 全量测试：`moon test --target js` **366 → 376 passed / 0 failed**；`moon check` 0 errors；三形态守卫 `check_tools_sync` / `check_test_sync` / `check_badge` 通过。
- 调用面实跑（不只看单测）：`laya_decide` 顶层 keys 修复前后差集为 `decision` + `decision_note`；`issue_scan --dir src --include_tests false` total **101→66**、high **8→4**、自命中 **17→0**；`status_summary` / `project_health` 的 `version` 由 `0.2.4` → `0.3.0`。

### 🔍 验证与打磨补记（指挥官收口）

- **BUG-17 [medium] 文档三套口径漂移（verify 发现 → polish 当轮闭合）**：`check_tools_sync` 实测报出 server 注册但 AGENTS.md 零记载的工具 **10 个**（8 个 GitHub 同步通道 + `mode_list` + `mode_templates`），同时工具总数在 AGENTS=105 / deliverable=104 / scoring_rubric=104 而实测 **116**，测试数在 README=329 / AGENTS·deliverable=317 而实测 JS **376**。修法：AGENTS.md 补「开发模式与模板（2）」「GitHub 同步 · 缺陷上报通道（8）」两节；四份文档计数统一到实测值；把「JS 与 Native 双后端均通过 329/329」这类绑定表述**拆成分后端各自声明**（native 本轮未复跑，不据旧数宣称双端同版全绿）。三守卫 `check_tools_sync`/`check_test_sync`/`check_badge` 由 FAIL 转 PASS。源码：`AGENTS.md` `README.md` `docs/deliverable.md` `scripts/scoring_rubric.md`
- **verify 硬门**：`output_validate` 对 12 条 Round 1 交付产物判定 **verdict=pass / evidence_layer=l4-pass**；`project_standards` 6 项三形态 checklist 逐条外部实测，cl3/cl5/cl6 三项在改动当轮为红灯（即 BUG-17 活证据）并在 polish 中转正。
- **BUG-18 [medium] 新发现未修**：`laya_decide` 单次调用实测阻塞 >150s——`server.mbt` 每次调用无条件重跑 `--probe`（15s）且 sidecar 决策超时预算 300s，而 `.mcp.json` 的 server `timeout_ms=30000`；客户端先超时，看到的是"无响应"而非 BUG-14 承诺的降级决策。留给 Round 2 修复队列。
- 全量测试基准：**`moon test --target js` 376/376**（`moon info && moon fmt` 0 errors，`.mbti` 零漂移）。

### 🔁 自驱与流程（dogfooding）

本轮由 FIST 自身跑通四模式流水线：`publish` + `task_plan_deep --omega_strong_verify true` 拆 12 单，4 张修复单全部走完 Omega 强验证闭环（`omega_spec_create` → `omega_spec_review` → `claim` → `execute` → `submit` → `run_check` 外部判据 → `omega_result_verify` → `verify`），证据留档 `temp/r1_flow_*.json`；全程 `call_log` 自动记账。

### ⚠️ 遗留

- 行尾注释（`code // rows[0]`）仍未处理，需 token/AST 级判定；本轮 `include_tests=false` 的 8 条 high 复核后**真 bug 为 0**，high 档语义建议重估。
- `project_version` 与 `moon.mod` 仍需人工同步（守卫只判红不自动改）。
- 账本无 close API（BUG-9），已修条目仍显示 OPEN；本轮按硬约束未新增 API，只在条目下追加 `FIXED(...)` 证据段。

## [0.2.6] - 2026-09-26

### 🐛 BUG 清偿（5 单全部闭环）

- **BUG-1 [high] 时间戳服务端盖章**：publish/claim/execute/submit/verify 的持久化时间戳从"调用方 now 透传"改为**服务端 `@env.now()` 统一盖章**；now 参数保留 schema（零回归）但不再读取。源码：`src/server/server.mbt` `now_default()` + 9 处写库点切换
- **BUG-2 [medium] retry 后 execute 死角**：execute 的合法前态从 `[拆分中/已领取]` 扩到 `[拆分中/已领取/执行中]`，`src/core/core_task.mbt` 守卫放宽 + 新增白盒测试 `bug2_execute_after_retry_ok`
- **BUG-3 [medium] audit_log 进程内假空**：返回结构从裸数组改为 `{scope:"process", entries, note}`，让跨进程空结果可区分；`src/ops/audit.mbt` + `src/server/server.mbt`
- **BUG-4 [high] run_check workdir 限定（最小收口）**：新增 `run_check_workdir_ok` 拦截空串/`..`/绝对路径/盘符，拒绝后返回明确错误；白名单机制**不做**（留活口）。源码：`src/server/bugreport_resolve.mbt`
- **BUG-5 [medium] project_dir 契约分裂**：`report_bug` 返回值补 `resolved_path`（绝对 + normalize 后）让落点可审；server.mbt 参数描述补「相对 server 进程 cwd」说明。源码：`src/server/bugreport_resolve.mbt` + `src/server/bugreport.mbt`

### ✨ 自驱编程 6 模式流水线

新增 `ops_modes.mbt` 模式注册表 + 三引擎扩展（watchdog_tick / pipeline_tick / selfdrive_publish_next 接受 `mode` 参数）+ 6 份元提示词模板：

| mode | 核心动作 | 禁止 |
|------|----------|------|
| advance（默认） | 四分支自决策 | 无 |
| polish | 扫 FIXME/TODO 补边角 | 不加新功能 |
| verify | API 枚举 + 文档自洽 | 不改源码 |
| bugfind | issue_scan + ocr-cli 预留 | 不修复 |
| fix_and_merge | github issues → 分派 → 合并 | 不引入新功能 |
| tidy | 盘点 → 清理 → 补注释 | 不新增功能代码 |

MCP 新工具：`mode_list` / `mode_templates`

### 🔧 其他

- **GitHub 同步扩展**：8 个 github_* 工具 + selfdrive_round_tick 轮次决策
- **CI Workflows**：fist-ci.yml + fist-bug-sync.yml
- **工具脚本**：mcp_bug_loop.py（MCP 闭环验证）、flush_github.mjs、pentad_fist.py
- **fist-mbt.db 移出 git 跟踪**：保留 `*.db` 忽略规则
- **测试基线**：366/366 ✅（含 BUG-2/BUG-4/BUG-5 回归测试 + ops_modes 25 条）
- **MCP 工具数**：57 → 116

### 回归验证

```
moon test --target js -j 1 → Total tests: 366, passed: 366, failed: 0
moon info                  → 0 errors
moon fmt                   → tasks_failed=0
git log --oneline          → 7/7 commit 线性落地
```

---

## [0.2.3] - 2026-09-24

### 打磨与跨环境稳定化

- **可复现构建**：依赖全部来自公开 mooncakes registry；新环境首次需 `moon update` 刷新索引后即可 `moon build`/`moon test`，无需私有包或 vendor。
- **JS 目标 Node 版本约束**：SQLite JS 后端依赖 `node:sqlite` 的 `returnArrays`（Node ≥ 24 生效；<24 退化为对象行导致列读取为空）。已实测：node 25 → 135/135 全绿，node 23 → 28 失败。使用要求：**Node ≥ 24**。
- **绝对路径清理**：测试/smoke 的 `E:/proj/*` project_dir 样例统一改为 `/proj/*`，消除盘符硬编码。
- **文档对齐**：README/USAGE/AGENTS/申报书 工具数统一为 57、测试数 135；版本号统一 0.2.3。
- **新增功能**（0.2.0 后并入）：DGM 档案库 `evolve_*`、自驱闭环 `selfdrive_*`×8、看门狗 `watchdog_tick` 整合、Laya 可选决策 `laya_decide`（探针+降级）、多租户 namespace、并行发布 `publish_parallel`、`reopen_task` 等，MCP 工具由 41 → 57。

## [0.1.1] - 2026-09-09

### 源码重排（src/ 分类收拢）

- 根包散落的 `.mbt` 全部按职责收拢进 `src/` 子包并拆分子包，根包仅保留 `lib.mbt` 门面
  （导出 `Task/TaskStatus/SqliteStore/FistEngine` 与 `run_server`）。
- 新子包布局：`src/core/`（core_task/core_role/core_principle）、`src/store/`（store/store_sqlite）、
  `src/engine/`、`src/decompose/`、`src/ops/`、`src/omega/`、`src/server/`；`cmd/main`、`smoke` 保留。
- 跨包子包封装：新增 `StoreBackend::memory()/sqlite()` 工厂、`TaskStatus` 状态谓词
  （is_pending/is_claimed/is_splitting/is_executing/is_completed/is_reviewing/is_archived）、
  `Task::with_updated_at/with_deliverable`，消除跨包直接构造 readonly 类型；`plan_deep` 迁入 engine。
- 修根包 `typealias` 为 `type`（废弃语法）；更新 README 目录结构与全部 `@core./@store.` 引用。
- 验证：`moon check` 0 错误，`moon test` 全绿（engine/server/ops/omega 测试 + smoke）。

## [0.1.0] - 2026-09-05

### 首版（root commit 147e642）

- 新建 MoonBit 工程 `vicTop-cw/fist-mbt`，声明依赖 colmugx/mcp@0.17.4、mizchi/sqlite@0.3.1、
  moonbitlang/async@0.21.0。
- 领域核心：
  - `core_task.mbt`：任务实体 + 七态状态机（待领取/已领取/拆分中/执行中/待验收/已完成/已归档）与状态迁移校验。
  - `core_role.mbt`：八角色权限矩阵。
  - `core_principle.mbt`：FIST 七条金条原则。
  - `store.mbt`：Store trait + MemoryStore 内存实现。
  - `engine.mbt`：FistEngine 完整闭环（publish/plan/claim/execute/submit/verify/archive/list/get/delete）。
- MCP 层：
  - `server.mbt`：注册 10 tools + 2 resources（fist://principles、fist://overview）+ 2 prompts（fist:check_in、fist:verify）。
  - `cmd/main`：async 可执行入口，`run_stdio()` 启动 STDIO 传输。
- 修复记录：
  - 根包别名含点号非法 → 使用 @mcp_types/@mcp_resource。
  - main 入口 async/raise 问题 → 引入 moonbitlang/async 并改用 `catch` 包裹 run_stdio。
  - engine.claim 此前一步跳到「执行中」，导致 plan（要求已领取）无法走通 → 改为 claim 只做
    待领取→已领取，execute 进入执行中；同步更新 server 文案。
- 质量：`moon test` 7 项黑盒单测全绿；MCP STDIO 全链路冒烟通过。
*（内容由AI生成，仅供参考）*

## [0.2.0] - 2026-09-13

### M6 — Omega 验证闭环 + 智能调度 + 执行器抽象层

**新增工具（+8 个，总计 57 个）：**
- `omega_verify` — 批量验证 spec JSON（schema + fingerprint 校验，accuracy < 100% 一票否决）
- `omega_verify_fix` — 失败 spec 根因分类 → 定向修复 → 回归验证（3 轮循环）
- `schedule` — 调度预览：根据任务描述自适应计算分级/拆分/成本档/执行器（不落库）
- `cost_stats` — 执行成本聚合统计（total_records/total_cost/total_tokens/by_executor）
- `cost_budget_check` — 预算超限告警（exceeded/remaining/action）

**元数据扩展：**
- `execute` 工具向后兼容扩展：支持 executor/model/tokens_in/tokens_out/cost/duration_ms/rate_limited/failure_reason 元数据
- `StoreBackend::record_execution` — 执行记录持久化到 executions 表
- `engine.execute_with_meta` — 统一入口写入元数据

**新增子包：**
- `src/omega/`：spec.mbt / gate.mbt / check.mbt / omega_tool.mbt — 可解释性子包
- `src/engine/scheduler.mbt`：L1-L4 分级调度（根据描述长度/n_files 自适应计算 split_n/cost_tier/executor）
- `src/engine/router.mbt`：成本档路由（low→本地/delegate, medium→mcp_delegate, high→mcp_delegate:priority）
- `src/engine/cost_tool.mbt`：aggregate_stats + budget_check
- `src/executor/`：base.mbt（Executor trait + ExecResult）/ mcp_delegate.mbt / registry.mbt

**验证：** `moon check` 0 错误，`moon test` 77 项全绿。

### M7 — 成本追踪 + 心跳持久化 + WAL 并发修复

**核心修复与增强：**
- `StoreBackend::cost_stats()` — 聚合 executions 表统计（total_cost/total_tokens/by_executor 分组）
- 心跳持久化：`write_heartbeat`/`read_heartbeat`/`delete_heartbeat`/`list_all_heartbeats` 四层 CRUD
- `SqliteStore::open` 启用 WAL 模式 + `synchronous=NORMAL`（提升并发读写性能）
- 启动时 `init_heartbeats()` 从 SQLite 加载残留心跳；heartbeat/heal 操作同步落库
- `is Some(_)` 语法修复 → `match` 表达式（MoonBit 不支持该语法）
- 测试 base_dir 修复：`"test-data"` → `"."`（SQLite 不自动创建父目录）

**验证：** 77/77 测试通过（含新增 WAL 并发测试 3 ns × 5 tasks）。

### M8 — 文档体系完善 + 用户体验增强

**文档更新：**
- README.md：工具数 22→36、测试数 57→77；新增 Omega/调度/成本工具表；新增项目结构 executor/ 子包
- CHANGELOG.md：补录 M6/M7/M8 条目（本条）
- USAGE.md：新增 Omega 验证/调度/成本/心跳完整示例；更新测试验证命令

**验证：** `moon check` 0 错误，`moon test` 77/77 全绿，`moon info` 8 个 .mbti 接口文件生成。

---
