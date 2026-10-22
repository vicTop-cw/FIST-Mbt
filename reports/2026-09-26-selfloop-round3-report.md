# 自我迭代 Round 3 收口报告（寻虫 → 修复 → 验证 → 打磨）

- 日期：2026-09-26（11:28 ~ 12:14 UTC）
- 执行：FIST 指挥官（本会话）+ 寻虫子代理 1 名（批级候选产出，指挥官逐条独立复核）
- 根任务：`T0r322`（default ns）；修复单 `T0r317`（bugs ns，由 `report_bug publish_task=true` 自动发布）
- 规范版本：project_standards **R115**（一源四态 + cl1~cl7 七项 checklist）

## 一、结果摘要

| 指标 | Round 3 前 | Round 3 后 | 来源 |
|---|---|---|---|
| MCP 工具数 | 116 | 116（零签名变更，schema 广告面收缩） | `tools/list` 实测 |
| JS 测试 | 394/394 | **404/404** | `moon test --target js -j 1` |
| 守卫族 | 5 | **6**（本会话内补 `check_doc_surface`；本轮给 `check_tools_sync` 加 3 条判据） | 六脚本逐个退出码 0 |
| 缺陷账本 | 31 条 / 7 FIXED | **40 条 / 14 FIXED**（+2 条 NOT-FIXED 带理由与出路） | `bug_list` count=38→40 |
| 调用面终审 | 14/15（R2） | **30/30 PASS** | `temp/r3_callsite_audit.py` |
| 交付物硬门 | — | **verdict=pass（12 件 / 0 失败，`evidence_layer=l4-pass`）** | `fist.py call output_validate --artifacts @temp/r3_artifacts.json --require_evidence true` |

本轮按四模式各走完一拍：

1. **寻虫**：新账 9 条（BUG-32~40）。两条最有价值：
   - **BUG-32**：`scripts/fist.py` 不校验入口产物新鲜度 → 我自己第一次 Round 2 终审全程在度量旧二进制（假绿诱因）。
   - **BUG-38**：四份流水线模板指示主流程调用 `run_check_external({cwd,command,timeout_sec})`，而该工具**未注册**（真名 `run_check`，五个参数名全不同、且漏两个必填），根因是模板把 `src/server/server.mbt:1162` 的**引擎内部函数名**抄成了对外工具名。
2. **修复**：7 条挂 FIXED —— BUG-31（交付物硬门先校验规格；pass 文案只声明真正评估过的不变量）、BUG-32（新鲜度自检 + `FIST_NO_AUTOBUILD=1` 显式拒绝）、BUG-33（删 45 处 `"now"` schema 广告 + 清 6 处描述文案）、BUG-36（非法 kind 拒绝且不落笔）、BUG-37（禁发名单换真实注册名 + 模板同源清理）、BUG-38（9 处调用点改真名真参）、BUG-39（CLI 不再因数组结果崩溃）。
3. **验证**：`temp/r3_callsite_audit.py` 自己 spawn `main.js` 走 JSON-RPC，J00 先钉「入口不早于源码」的顺序不变量（过期即 FATAL、判据作废），其余逐项打真接口，**30/30**。含 Omega 强验证全链与 `call_log` 记账核对。
4. **打磨**：`check_tools_sync.py` 新增 3 条判据 + 三处人工漂移负向矩阵；`memory_18/19` 双站点开关对照；USAGE 明示覆盖边界（BUG-30 建议 2）；一次性文档计数同步 394→404。

## 二、资源消耗（实测，非估算）

- `cost_stats`：`total_records=306`、`total_tokens_in/out=130997/130997`、`total_cost=0`、`rate_limited=0`。
- `call_log`：limit=3000 仍可取回整轮调用序列（含被 BUG-19 硬门拒绝的调用及其拒绝文案，`J21/J22` 自证）。
- 本轮全量测试串行 `-j 1`；一次自动重建（BUG-32 生效，`main.js` 19:01 → 19:36 → 12:08）。
- 子代理：寻虫批 1 名（150 轮上限被系统截断一次，剩余接线与终审由指挥官完成）。

## 三、任务分配记录

| 任务 | 承接 | 结果 | 终审 |
|---|---|---|---|
| BUG-33~37 候选清单 | 寻虫子代理 | 5 条候选，指挥官逐条独立读源复算 | 全部成立（逐条附 file:line + 判据） |
| 一源四态插件生成 + cl7 | 插件子代理（被 150 轮截断） | 56 文件生成，剩余接线指挥官完成 | cl7 负向矩阵 + 真漂移捕获 |
| Round 3 修复批 | 指挥官本人 | 7 修 + 2 明挂 | 每项开关对照或负向注入 |
| 调用面终审 | 指挥官本人 | 30/30 | 判据自纠 3 处（见下） |

## 四、判据自纠（本轮的"红"其实是判据坏了 3 次）

1. `J01`：以为该走 `initialize` 握手拿 serverInfo。实测本 server 说 **MCP 2026-07-28**，协议**无 `initialize`**（返回 -32601 并附 supportedVersions），服务端身份在 `tools/list` 的 `result._meta["io.modelcontextprotocol/serverInfo"]`。BUG-21 到这一步才是**真·调用面可审**。
2. `J06`：`dag_publish` 不接收调用方给的 `task_id`（id 由引擎发号），我传了 `r3a` 导致 `dag_mc` 报 `insufficient`——判据自造的假红，改为回读真实 id 后 BUG-24 的钳制直接可证。
3. `J19c`：Omega 成果复验的放行标志是 `status:approved`，不是 `verdict:approved`；同时 `J19b` 证明「无交付物即拒」是 fail-closed 的正确行为。
4. 另记一次**开关对照打错靶**：第一次摘修复用 `s.index("if not(mem_kinds_contain(kind))")` 命中了 `memory_consolidate`（同串两处），全量仍 91/91 绿——顺带暴露"consolidate 非法 kind 从未有锁"，于是补了 `memory_19`。

## 五、遗留风险

- **26 条待修**（账本 40 - 14 FIXED）。其中三条已写明"为什么不半修"：
  - BUG-34：熔断 Half-Open 探测配额需扩 `cb_get/cb_save` 表结构（7 元组 → 含 probe 计数），跨 js/native 后端；内存版计数在多进程 MCP 下每进程各计，比现状更误导。
  - BUG-35：github `--data` 需 `Json::stringify` + `--data @file` 消掉 shell 引号层，并解决 win32 `cmd.exe /c`；真验证要连 GitHub（凭据只走环境变量注入，本轮不探测 token）。另发现新前置缺口：`github_queue_append` **不是注册工具**（实测 Tool not found），队列只能手写文件。
  - BUG-40：`project_dir` 在 bug 族只收相对路径是 `bugreport.mbt:10` 的**声明设计**，放宽=改动已声明的加固，需人裁决（两条出路已写进账本）。
- **BUG-32 的修复未进守卫族**：CI 上"干净克隆未构建"时该 mtime 不变量必假，做成守卫会产生假红；当前只有调用面证据（可复跑命令已入账本）。
- **一源四态的插件态**：目录与清单为生成投影并通过 cl7 一致性检查，但**未在真实宿主（atomcode/codearts/deepseek-harness/claude）里逐一装载验证**。
- BUG-30 的 mooncakes 已发布版本自相矛盾（0.2.4 vs 0.2.5）本轮未联网核对，保持原样不臆改。

## 六、后续建议

1. 下一轮优先做 **BUG-35 的离线判据**（对生成的 `--data` 段做 `json.loads`，不需要 token），把「不可验证」变成「可红灯」。
2. **BUG-34 单开一轮**做表结构迁移（store 层加列 + 双后端回归），别混在文案轮里。
3. `project_standards` 的 cl 系列应扩到"契约说谎"这一类：把「广告了没人读的入参」「名单里名字不存在」做成 checklist 项，让三形态/四态都吃同一门禁。
4. 插件态补一次真宿主装载记录（截图或客户端 `tools/list` 回显），否则 cl7 只证明"自洽"，不证明"可用"。

## 七、超额内容（本轮多做/越界的）

- 给 `check_tools_sync.py` 加了 UTF-8 输出钉（cp936 下判据文案乱码，守卫不可读≈不可用）。
- 把 `mode_forbidden_tools` 的**文档面**（polish/tidy/verify 三份模板）一起改了，超出 BUG-37 条目本身的代码范围。
- 新增 `temp/r3_callsite_audit.py`（一次性终审器，含最小 JSON-RPC 客户端），不是产品代码、未登记进 `scripts/README`（守卫 `check_scripts_index` 只管 `scripts/`，故不红）。

## 八、来源

- 会话内实测输出：`/tmp/r3_audit*.out`、`/tmp/moon_test.log`、`temp/r3_*.out`（等价留存于本仓 temp/）
- 账本：`memory/bugs.md`（BUG-31~40 条目 + 本轮 FIXED/NOT-FIXED 小记）
- 代码：`src/server/{memory,output_validate,server}.mbt`、`src/ops/ops_modes.mbt`、`scripts/{fist,gen_plugins,check_tools_sync}.py`、`templates/pipeline_mode_*.md`
- 规范：`src/server/project_standards.mbt`（R115）、`AGENTS.md`

---
*报告由 FIST 指挥官生成；数字全部来自本轮实测，非估算。*
