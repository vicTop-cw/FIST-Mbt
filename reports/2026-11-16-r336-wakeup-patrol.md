# 轮 336 唤醒巡检报告

**日期**：2026-11-16
**轮次**：r336
**执行者**：wd-r336（FIST-Mbt-ExploreWatchdog）

## 结果摘要

**WIP 非冻结增长后静止第 17 轮（numstat 与 r326~r335 逐字同）** —— `memory/bugs.md` 维持 **216/0**
（r335 后零再增长、无 BUG-637+ 新外来账），其余 5 个已跟踪 WIP 文件（`improvement-plan` 7/1、
`target.md` 1/1、`README` 2/1、`run_guards` 9/0、`engine_circuit_test` 5/0）与 2 个 untracked
（`check_mcpcf_db_isolation.py` 545 行、`pipeline_mode_loop.md` 211 行）**逐字同 r335**；
R192 车道自 r318 后持续停摆。`src/**` + `scripts/run_guards.py` 仍 M ⇒ **巡检分支**
（Round C 三件仍锁）。

换面巡检 `check_mcp_stdio_purity`（BUG-477 MCP server **stdout 纯净性**守卫·**判例-33 服务本体≠
服务接入**的完美实例：`moon test` 走引擎层函数调用、**不经过 stdio 传输** ⇒ 结构上看不见「一行
`println` 打死整个 MCP server」这类缺陷——R33 实测里 `moon test` 1835/1835/0 全绿而 server 对任何
客户端都不可用；本尺**直接看进程 stdout 里出现了什么**，按**语义**抓「往 stdout 写了非 JSON-RPC
的东西」而不按 `println` 字面。三层：**L1 静态**扫 `src/server/**/*.mbt` 写 stdout 调用〔按语义抓
`print`/`println`/`print_char`、剔除 `eprintln` 等走 stderr 的〕/ **L2 动态握手**用**生产启动描述**
（`.mcp.json` 的 `command`+`args` **原样**、判例-33 硬要求不自己拼更好走的路）spawn、喂一行
`initialize`、断言 **stdout 首行合法 JSON** / **L3 动态工具调用**发 `tools/call`、断言回执**有
`result.content`**〔R33 直接复刻 `KeyError: 'content'`〕；扫描面完全避开 WIP 面 `src/engine/`）
selftest **rc=0**（**19/19 格**反解：L1 干净不误红 + 变异必红 / L2L3 非 JSON 行与缺 `content` 必判脏
+ 空输出自拒 / 缺 server 目录与零 `instrumented_tool` 反脱锚 rc=4）+ 实测 **PASS rc=0**（**L1**
静态扫 **41** 个产品文件、**181** 处 `instrumented_tool`，无写 stdout 调用；**L2** 用 `.mcp.json`
生产启动描述 `node …\serve-launcher.cjs serve` spawn、stdout **2 行全部合法 JSON-RPC**；**L3**
`tools/call` 的 `result.content` 存在；**动态层本次无 MemoryError**）。

零漂移 `check_tools_sync` **183** / `check_instruction_budget` **50440/65536** 均 rc=0。Round C 三件
维持过期不执行。**无新发现（类型）、无新立账**（vq 外来账队列规模与 r326~r335 持平，全挂 owner
裁决，同 BUG-565 持续模式）。**FIST 闭环 T0r92 六步全链 rc=0**（wd-r336，ns watchdog，verify
status=已完成、completed_by=wd-r336，deliverable=本报告）。禁区零碰（8 WIP 文件含 bugs.md 零改零提交）。

## 巡检明细

1. **WIP 状态**（`git status --short` + `git diff --numstat`，本轮实读，逐文件对表 r335）：
   - `memory/bugs.md` **216+/0-**（与 r326~r335 逐字同 ⇒ **零增长**；无 BUG-637+ 新条目）；
   - 其余 5 个已跟踪 WIP 文件**逐字同 r335**：`improvement-plan` 7/1、`target.md` 1/1、`README` 2/1、
     `run_guards` 9/0、`engine_circuit_test` 5/0 ⇒ R192 车道面**仍静止**（自 r318 后无再推进）；
   - 2 个 untracked（`check_mcpcf_db_isolation.py` 545 行 / `pipeline_mode_loop.md` 211 行）未变。
   - 结论：**WIP 非冻结增长后静止第 17 轮**（r321 记非冻结增长第 1 轮 = vq BUG-636 落账；r322 静止第 2；
     r323 静止第 4；r324 静止第 5；r325 静止第 6；r326 静止第 7；r327 静止第 8；r328 静止第 9；
     r329 静止第 10；r330 静止第 11；r331 静止第 12；r332 静止第 13；r333 静止第 14；r334 静止第 15；
     r335 静止第 16；r336 本轮 = 静止第 17）。
   - 禁区处置：8 个 WIP 文件（含 bugs.md）**本轮零改、零提交**。

2. **换面巡检 `check_mcp_stdio_purity`**（BUG-477 MCP server stdout 纯净性·判例-33 服务本体≠服务接入；
   三层 L1 静态 + L2/L3 动态、按语义不按字面，扫描面与 WIP 面零交集）：
   - 自检：`--selftest` **rc=0**（**19/19 格**反解：L1 干净不误红 + 变异〔注入 `println`〕必红 /
     L2L3 非 JSON 行必判脏 + 缺 `result.content` 必判脏 + 空输出自拒 rc=2 / 缺 `src/server` 目录与
     零 `instrumented_tool` 反脱锚 rc=4〔尺子自己坏了，绝不冒用被判面退出码〕）；
   - 实测：**PASS rc=0** —— 三层全绿：
     · **L1 静态**：扫 **41** 个产品文件、**181** 处 `instrumented_tool`，**无写 stdout 的调用**
       （`print`/`println`/`print_char`/`output`/`js_console_log` 皆无，`eprintln` 等走 stderr 的已剔除）；
     · **L2 动态握手**：启动描述来源 **`.mcp.json`**，`node C:\Users\…\FIST-Mbt\serve-launcher.cjs serve`
       **原样** spawn（判例-33 硬要求：不得自己拼更好走的路），stdout **2 行全部是合法 JSON-RPC**；
     · **L3 动态工具调用**：同一进程发 `tools/call`，回执 **`result.content` 存在**（非 error）；
   - 动态层本次**无 MemoryError**（无 patch_esm_main transient 压力，一发收口）；
   - 判据工作结论：**无漂移** —— stdout 纯净面、动态握手/工具调用面自 r335 未变，无污染。

3. **零漂移双检**：
   - `check_tools_sync` rc=0（server.mbt 注册 183，AGENTS/README/deliverable/scoring_rubric 对齐；
     R3b/R7 扫现状面 168 份、历史面豁免 25 份；R8 清单分组 19 组 ΣN=183 对表一致）；
   - `check_instruction_budget` rc=0（AGENTS.md 50440 / 65536 字节，全部章节可见）。

4. **Round C 三件**：维持过期不执行——BUG-527 摘 cc-link-flags 已 owner 否决（CI A/B 实证有害）、
   BUG-530 已 FIXED（3699f012a）、`check_usage_tool_count` 已注册（run_guards.py:175）；`src/**` +
   `run_guards.py` 仍 M ⇒ 队列仍锁。

5. **FIST 闭环 T0r92 六步全链一发收口**（wd-r336，ns watchdog）：
   - 链脚本 `temp/fist_r336_chain.sh`（沿 r321~r335 稳健 TID 提取，逐行取能解析为 JSON 的那行）；
   - 六步 `publish / agent_acl_grant / claim / execute / submit / verify` 全 rc=0（后台一发收全），
     verify 回执 **status=已完成、completed_by=wd-r336**、deliverable=
     `reports/2026-11-16-r336-wakeup-patrol.md`（回盘 `temp/fist_r336_out/`）。

## 资源消耗

- 判据 4 支（1 换面巡检 check_mcp_stdio_purity selftest + 实测〔含 L2/L3 动态 spawn server 1 发〕
  + 2 零漂移）+ WIP numstat 核验 1 支 + FIST 六步链 1 发（后台串跑一次收全）；
- 本轮无子代理（巡检判据为轻量命令执行 + 只读核验 + 1 次动态 spawn + FIST 链为网关记账，
  命令结果需指挥官亲阅终审，故直跑）。

## 任务分配记录

- **r336 FIST 闭环 T0r92 六步全链**（wd-r336，ns watchdog）：`temp/fist_r336_chain.sh`（稳健 TID 提取，
  六步全 rc=0），回盘 `temp/fist_r336_out/`（`1_publish..6_verify.txt` / `chain.log` / `task_id.txt`；
  verify status=已完成、completed_by=wd-r336）。

## 遗留风险

- **vq 外来账队列**：白名单外 **23 条（BUG-613~635）** + 契约不命中 1 条（BUG-636）待 owner 裁决
  （搬移 vq 仓 / 带理由登记 WHITELIST kind=foreign-adjudicated）；本轮账本零增长，规模与 r326~r335
  持平，同 BUG-565 持续模式，指挥官不代行清理、不立新账。
- **WIP 非冻结增长后持续静止**：`memory/bugs.md` 216/0 无再增长；四件套核心 R192 车道面自 r318 后
  无再推进（连续第 17 轮静止）。
- **owner 裁决件**（同 r321~r335，本轮无增减）：① WIP 四件套弃置 ③ r302 落账方式 ④ 外来账处置
  （BUG-613~636，规模 23+1）⑤ BUG-636（FIST 自留临时号）known-red 登记口径（②
  check_mcpcf_db_isolation.py 缺执行面/未注册已被 R192 车道推进消解）。
- **FIST 链提取鲁棒性（r318 遗留）**：35 份 `temp/fist_r*_chain.sh` 同形脆弱提取（本轮 +1）；
  durable 修复在 `scripts/fist.py`（notice→stderr / stdout 纯 JSON）或 tracked 链脚本模板稳健取
  JSON 行，留专门轮次。本轮稳健提取是**临时绕过**，非 durable 修复。
- **`check_arg_face_strict.py` 头注释「已知债」段文档滞后**（r332 新发现·非缺陷）：27 把债已消解、
  注释仍写现状，留专门轮次更新（注释属该尺本体、非 WIP 面）。
- **R192 在飞 WIP 的发布载荷暴露**（r334 check_publish_payload 实测确认）：`check_mcpcf_db_isolation.py`
  + `pipeline_mode_loop.md` 两 untracked 文件会在下一次 `moon publish` 被公开（P1）。R192 车道收口时
  应 `git add` 入库（属真交付物、不该 ignore）；在那之前若有人 `moon publish`，会把这两份在飞稿公开——
  发布前须先收口 R192 车道。

## 后续建议

- **最高优先仍为 BUG-636（FIST 自留临时号·check_tool_coverage 盲区修复规格）**：待 `memory/bugs.md`
  WIP 解禁后专门轮次委派（含「加进 `_tool_registry.consumers()` 收口格」最易漏环节）。
- **vq 外来账队列（BUG-613~636）owner 裁决**：规模与 r335 持平（白名单外 23 条 + 契约不命中 1 条），
  裁决面完整，可一次批了。
- **FIST 链提取鲁棒性专门轮次修复**（口径见遗留风险）。
- **`check_arg_face_strict.py` 头注释「已知债」段更新**（r332 新发现·轻微文档滞后）。
- **R192 车道收口时 git add 两份在飞交付物**（check_publish_payload P1 点名）：`check_mcpcf_db_isolation.py`
  + `pipeline_mode_loop.md` 属真交付物应入库而非 ignore。
- 换面巡检下轮候选：`check_tool_coverage` 的**盲区修复**（r315 发现·临时 BUG-636·中危判据缺陷：
  该判据未接 `_tool_registry` 真源、本地过期 `extract_tools()` 漏扫 18 工具含 7 个零 A 面覆盖）
  仍待 `memory/bugs.md` WIP 解禁后专门轮次委派；在此之前换面候选继续按注册面轮换
  （`check_deprecated_site_list` / `check_sql_bind_alignment` / `check_exit_code_contract` 等近期未轮过
  且有 `--selftest` 的判据）。
- Round C 三件维持过期（owner 已裁决面），唤醒轮继续非阻塞巡检。

## 超额内容

无。

## 来源

- `git status --short` / `git diff --numstat`（2026-11-16 本轮实读：bugs.md **216/0**、其余 5 文件逐字同
  r335；2 untracked 未变：check_mcpcf_db_isolation.py 545 行 / pipeline_mode_loop.md 211 行）
- `reports/2026-11-16-r335-wakeup-patrol.md`（r335 WIP 基线 + per-file 拆分）
- `python scripts/check_mcp_stdio_purity.py --selftest`（rc=0，19/19 格反解）+ 同判据实测
  （PASS rc=0：L1 静态 41 产品文件/181 instrumented_tool 干净 / L2 动态握手 .mcp.json 生产启动描述
  spawn、stdout 2 行全合法 JSON-RPC / L3 tools/call result.content 存在；动态层无 MemoryError）（本轮）
- `python scripts/check_tools_sync.py`（183 PASS）/ `python scripts/check_instruction_budget.py`
  （50440/65536 PASS）（本轮）
- `temp/fist_r336_out/`（六步回执 + `chain.log` + `task_id.txt`，TID=T0r92，verify status=已完成）
