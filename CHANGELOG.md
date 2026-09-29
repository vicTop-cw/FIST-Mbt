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

## v0.3.5 (mooncakes 已发布 / GitHub Release 未发布) - BUG-128 出路①执行：版本号前进一位 + 注册表载荷逐件对表（盖章 2026-09-29T10:44:53Z）

- **版本真源三处同步（owner 裁决的代价那一格，逐字改）**：`moon.mod` `0.3.4→0.3.5`、
  `src/server/server.mbt::project_version`、`cmd/cli/help_topics.mbt::FIST_VERSION` —— R11 判据 +
  `src/server/fist-mbt_wbtest.mbt` 白盒锁要求三者相等；README 离线线的 `fist-mbt-js-v0.3.5.zip` 字面量随之（R13）；
  注册表发布版本的自述仍**只在 `BACKLOG.md` 一处**（J4，本轮我新写的 `scripts/README` 条目被它当场打回过一次，见下条）。
- **BUG-128 已修（盖章 2026-09-29T10:44:53Z，出路①）**：`moon publish --dry-run` 得 `202 Accepted`，真发**第一发传输层抛**
  `request or response body error … send failed because receiver is gone`（rc=127，`temp/v35_publish.log`；它前面的
  `Check passed` 与 zip 校验都已过 ⇒ 不是载荷问题），**先 `moon view --versions` 读回注册表确认这一版没登记上**（仍是 9 版）才重试，
  第二发 `Server status: 200 OK`（`temp/v35_publish_try1.log`）⇒ 注册表读回 `Latest: 0.3.5 / Versions: 10 /
  Published 2026-09-29T10:35:10.876305+00:00`。这一课写进了 USAGE §10 第 2 步：**只对传输层错重试、重试前必须读回注册表**
  （与 BUG-116/125 同族，但方向相反——这里 409 才是不能碰的那格）。
- **发布后对表升级到"树身份"（USAGE §10 第 3 步补的两格）**：空壳消费工程 `moon add vicTop-cw/fist-mbt@0.3.5` 后
  `moon check --target js` **rc=0（58 个任务）** ⇒ "别人拉这一版编得动"是量出来的；解包 **552 件**与 `git ls-tree -r 124a20a`
  的非点号跟踪面**双向差集 0/0**、逐件比字节（只归一 CRLF）**0 处不一致** ⇒ 注册表载荷 == 被打 tag 的那棵树。
  `__cli_pkg.mbt.tmp` 件数 **0**（BUG-127 的修在下一版载荷上兑现）；凭据形状扫载荷 **0 命中**（早前一次 `grep -E` 报的两处
  是 `memory/2026-09-27.md` 的散文与守卫自己的 `SECRET_RE` 文本，用守卫的权威口径复扫即 0）。
  本地 tag `v0.3.5` 与 `mooncakes-0.3.5` 同钉 `124a20a`；`fist-final-review-20260929` 不动（终审面仍指 `a0dfef3`）。
- **收口面复跑（0.3.5 树上，逐条 rc=0）**：`moon info && moon fmt`（190 tasks）→ `moon test --target js -j 1` **572/572**
  （`temp/v35_js_test.log`）→ 守卫族 tools_sync / test_sync（含 `--selftest` 8 变体）/ badge / scripts_index /
  plugin_sync（4 宿主 56 件 v0.3.5）/ doc_surface（含 `--selftest`）/ store_tables_wired / demo_isolation /
  ps_encoding / entry_paths / release_asset_names（`--selftest` R1–R14 + 全量）/ publish_payload /
  mcp_tool_tour `--surface-selftest`（12 支）/ store_isolation_probe。
  **探针点名跑了两个身份**：默认那发命中安装态 `fist-mbt.js (sha256:616b7632)`（本机仍是上一版安装产物），
  `FIST_PROBE_JS` 强制指本地 0.3.5 产物 `(sha256:11355248)` 那发同样 2 格 GREEN ⇒ 隔离判据对新产物也成立。
  **两处 rc=1 是我的调用姿势错，不是回归**：`check_test_sync` / `check_badge` 要接测试日志参数（CI 里传 `/tmp/moon_test.log`），
  补 `temp/v35_js_test.log` 后双双 rc=0。
- **台账现 0 条待修**：仓内现成计数器（`gen_plugins.py`）口径 = **BUG-1~129 共 128 条入账：0 待修 / 115 已修 / 9 重复并入 / 4 误报**
  （128 而非 129：编号 95 从未入账，独立正则复算与投影口径一致）。
- **有意留下的两格（不是已修）**：①**没有 push** ⇒ 公网安装线（GitHub raw/Release 资产 `fist-mbt-js-v0.3.5.zip`）还不存在，
  注册表这条线已是最新码；②`0.3.4` 同号两树的历史事实**撤不回**（版本不可覆盖），是否给注册表 0.3.4 打 `moon deprecate`
  留 owner 裁决——这是对外署名动作，不自行执行。

## v0.3.4 (unreleased) - 终审前收口：看护缺陷修到跨进程调用面、探索模式上线、demo 族解封（盖章 2026-09-29T06:18:10Z）

- **BUG-119 修复（开工时唯一 high）**：`heal` 从"读进程内内存心跳表"改为读**持久化心跳表**（唯一真相），
  「没有心跳行」不再等于首拍即死，而是退到任务行 `updated_at` 的兜底时钟（`src/ops/ops_heal.mbt::stale_by_task_clock`）；
  另一半根因是模块级 `let _init_hb : Unit = init_heartbeats()` 被 MoonBit 当未引用的非 pub 顶层绑定**消除**，
  "启动时回灌"从未进产物 ⇒ 删除该惯用法，`heartbeat` 改为按需跨进程回读并如实回执 `persisted`/`backend`，
  判死却回滚不了的条目走 `skipped` 披露。**常驻判据** `scripts/blackbox/e2e_heartbeat_xproc.py`（8 臂、两个真进程、
  隔离 `FIST_DB_PATH`）修后 8/8 绿；同一判据在 `git archive HEAD` 旧码树上 **3 绿 5 红**（旧码原样
  `healed=['T0','T0r2','T0r4']` + `active_tasks={'T0': ''}`）⇒ 锁承重；权威 CI 增配同名一步。
- **BUG-118 落定案的一半**：`moon fmt --check` 从狗食轨搬进权威 `ci.yml`（js-ubuntu），
  两条轨的格式步骤都先打 `moon version --all`——不再让"哪一版 formatter 判的红"靠猜；
  版本参数能否钉住（`moon upgrade` 无 `--version`、本机取安装脚本 TLS 失败 rc=35）如实留白，不猜着写 CI 配置。
- **探索模式 `explore` 上线（7 种模式）**：`src/ops/ops_modes.mbt` 注册 + 纯函数
  `estimate_complexity`/`select_mode_by_complexity`/`file_scopes_disjoint`/`explore_plan`（复用难度单一抽取来源，零 IO），
  模板 `templates/pipeline_mode_explore.md`（含 §步骤 3.5 递归拆解接法）；并行只在
  `reserve_scope` 预订成功 + `conflicts_check` 放行 + 作用域两两不相交时放行，否则退回单模式串行。
  **MCP 工具数保持 129**（`mode_list` 投影注册表，未新增工具）；`mode_templates` 名单改为从注册表反解。
- **demo 族解封**：`cmd/cli/main.mbt::run_serve` 的三行提示由 `println` 改 `eprintln`——
  stdout 只许走 JSON-RPC（BUG-101 的修复曾被并发改动重新启用），一条改动放行 27 个 stdio 判据/demo，
  `scripts/mcp_smoke.py` 当场 MCP-SMOKE PASS。
- **文档面**：定位语「fist-mbt —— AI 自驱式开发的项目管理者」与伴生仓 fist-evidence 指针落到
  README/README_EN/AGENTS/USAGE 首屏与证据段；现状面测试总数按 `check_test_sync` 从 535 全量同步到
  **572/572**（`moon test --target js -j 1` 实测，白盒 +34 条探索模式锁、看护成对改写 +3 条）。
- **BUG-116 结论（已 FIXED，盖章 2026-09-29T06:45:05Z）**：用户可见症状「一条命令装不上」现在有**三条在「取脚本」这一发判过线的出路**——
  主 `irm | iex`（BOM 安全形）、curl 兜底臂带 `--retry 5 --retry-delay 2 --retry-all-errors`（本机链路抖动时实测可通，
  BUG-116 的根因正是"一失败就换源把瞬时抖动放大成装不上"）、离线/内网 `-LocalZip` / `-BaseUrl`。
  公网侧瞬时不可达本身判为**环境面**，改为 `js-windows` 的 `Public install line e2e` 常驻观察臂（continue-on-error，
  红不拦合并但每天出账）；`e2e_irm_line.py` 的兜底臂仍硬拦退出码。
  **诚实边界**（车道回传，`temp/bug116-e2e-v10.log` / `temp/e2e-irm-receipts/`）：两臂换掉的只是「取脚本」这一发的传输栈，
  安装器**内部**下载 zip 仍走 .NET `Invoke-WebRequest`——run6/run7 的活证据是"脚本取回来了、红在内部那一发"；
  链路整断时两条线一起红，那种情况只剩 `-LocalZip` 离线线。彻底修要动 `install_onecmd.ps1` 的取数段，已另计入遗留面。
- **BUG-120（上报即收口，盖章 2026-09-29T07:05:54Z）**：同一车道的交接缺口②——README 离线/内网线的资产名
  `fist-mbt-js-v0.3.4.zip` 是**版本字面量**，而 R1 只扫安装器、J4 只认 `@x.y.z` 式声明 ⇒ 这一格落在两版守卫之间无人认领，
  版本一前进照抄即 404。补 `check_release_asset_names.py` 的 **R13**（README 里以数字开头的资产名版本 == `moon.mod`，
  无基线即自拒；模板形态 `v$VERSION` 不误红），`--selftest` 反解出 `R13×2`（漂移必红 + 模板不红），
  AGENTS 守卫族段与 `scripts/README.md` 索引同步。**台账现 0 条待修**（119 条入账 = 106 已修 / 9 重复并入 / 4 误报）。
- **BUG-121（上报即收口，盖章 2026-09-29T07:16:30Z）**：终审自证「文档点名的开发模式名 ↔ 注册表」时抓到插件态说谎——`plugins/source/SKILL.md` 与 `references/seven-modes.md` 写着 `hunt`、`fix-and-merge`、`night-loop` 三个服务端不接受的标识符，矩阵还整列漏了 `polish` 与新加的 `explore`（四宿主 SKILL 是 `gen_plugins.py` 投影出去的，消费方按名调用当场被拒）。改为注册表 7 个标识符 + 服务端 `mode_display_name` 中文名、补 explore 行（含四道并行门）、模板落点写明 `templates/pipeline_mode_<identifier>.md`，重投影后 cl7 逐字节一致。**台账现 0 条待修**（120 条入账 = 107 已修 / 9 重复并入 / 4 误报）。
- **BUG-122 / BUG-123（上报即收口，盖章 2026-09-29T07:28:19Z / 07:28:20Z）**：终审按文档命令逐条跑 demo 面时抓到两条指引缺陷——①`mcp_smoke.py`/`enrich_selfdrive.py`/`award_demo.py`/`omega_lesson_verify.py` 都不设 `FIST_DB_PATH`，而 README/USAGE/agent-map/deliverable 四处教人裸跑⇒ 演示任务与调用行写进仓库根的自举台账（实测根账 1986/6905 → 1987/6909，本轮这一次已进真实账，只追加不删）；四脚本现默认改道 `temp/<脚本名>.db`（显式设过的调用方不变），改道后裸跑 rc=0 且根账计数逐字不变。②`gen_help_docs.py` 自称是 `help_tools()` 文案的落笔依据，实测它反解的是 `fist://map` 的**定位图**（12 组/107 个简写 token）而非 129 个的注册表 ⇒ 照它写会把刚修好的 13 组/129 倒退回 12 组/107；docstring、脚本输出的边界行与索引条目都已改，CLI 权威面点名 = `node cli.js help tools` + AGENTS/README 表（J1/J2 钉）。**台账现 0 条待修**（122 条入账 = 109 已修 / 9 重复并入 / 4 误报）。
- **BUG-124（上报即收口）**：BUG-122 的**残留同型面**收干净——另外 21 个 spawn `serve` 的 demo/verify 脚本（`scratch_verify`/`dispatch_verify`/`fist.py`/`issue_scan.py`/`output_validate.py`/`*_selfdrive.py` …）同样裸跑即写仓库根自举台账；全部改为「未显式设置时默认落 `temp/<脚本名>.db`」，并补常驻判据 `scripts/check_demo_isolation.py`（I1 缺改道针必红 / I2 豁免面漂移必红 / I3 空扫描必自拒，`--selftest` 五支从已执行格子反解；现状面 29 个 spawn 脚本全合规）。**按文档命令逐条跑的 demo 审计**：README 的 DEMO 表 7 条 + 独立 CLI 表 2 条（`temp/demo_audit.log` 9 行）+ `scripts/README` 点名的 `demo.ps1`/`showcase.ps1` 2 条（`temp/demo_audit2.log`）= **11 条全 rc=0**，全程仓库根台账 **tasks=1987 / call_log=6909 逐字不变**。
- **BUG-125（上报即收口）**：BUG-116 的**内部半**补修——安装器内部取 `moon.mod` 定版本与取资产 zip 那两发以前只有 .NET 单栈（这就是「脚本取回来了、红在内部那一发」的来源），现两处都接上 curl 兜底臂，且只对「没有 HTTP 响应」的传输层错误换栈（404/403 仍直接换源，不拖慢用户）。承重证据 = `scripts/blackbox/e2e_transport_stack_fallback.py` 三格（A 换栈装通且回执带 `curl-fallback` / B 剥掉 curl 必红 / C 干净安装不误伤，PATH 逐字还原、真产物 sha 不变）；判据加 **R14**（五支变异），`--selftest` 反解 `R14×5`。
- **BUG-126（上报即收口，盖章 2026-09-29T08:19:52Z）**：`scripts/README` 的 `showcase.ps1` 条目把**读盘实时计数**当事实写死（548 tasks / 196 exec），而这两个数是脚本自己 `select count(*)` 现数的（`scripts/showcase.ps1:119-138`）⇒ 每次演示都在长；实测盘面真值 tasks=1987 / executions=461，写死的两个已漂。改为「读盘实时计数，索引不写死数字；数不到时降级 n/a 不崩」，顺带把取证侧一条实测坑写进同一行：默认码页下 `-File` 重定向出来的中文回执在**子进程内**就成了 `?`，外层按 UTF-8 或 GBK 都还原不回来，须先置 `[Console]::OutputEncoding=UTF-8`。缺口如实登记不假装有守卫：目前没有常驻判据把「文档里的活体计数字面量」打到盘上真值（R13 只管资产名形状，J 系列不管任务计数），已写进报告 §7 下一轮建议。
- **发布到 mooncakes（0.3.4，2026-09-29T09:26:54Z）**：`moon publish --dry-run` 得 `Server status: 202 Accepted`（包名/版本 `vicTop-cw/fist-mbt version 0.3.4`），正式发得 `Server status: 200 OK`、rc=0；`moon view` 回读 `Latest: 0.3.4 / Versions: 9 / Downloads: 31`。发布前置门：`moon test --target js` **572/572 rc=0**（`temp/publish_gate_js.log`，另一次独立复跑在 `temp/final_js4.log`）＋守卫族 11 步逐条 rc=0（含两个新守卫的 `--selftest`）＋`moon fmt --check` no work。
- **BUG-127（上报即收口，盖章 2026-09-29T09:36:03Z）**：`moon publish` 的**打包面是「工作树 − .gitignore」，不是 git 跟踪面**。发完把注册表真交付的载荷解出来对表：552 件里 **1 件根本不在 git 里**（`__cli_pkg.mbt.tmp`，moon 生成的 `cmd/cli` 包声明临时件，内容只有 5 行 import、无凭据无本机路径 ⇒ 卫生事故不是泄露事故），而**18 个被跟踪文件不在载荷里**（点号开头的文件/目录 moon 一律排除：`.github/*` 5、`.githooks/*` 2、`.codeartsdoer/*` 2、`.gitignore`、`.mcp.dev.json`、`.mcp.example.json`、`docs/*/.gitkeep` 3、`plugins/claude/.claude-plugin/*` 2、`plugins/claude/.mcp.json`）。修：`.gitignore` 追加 `*.mbt.tmp`（`git check-ignore -v` 可检），USAGE §10 补「发完解包对表」的第三步与载荷边界，BACKLOG P1 的发布自述改为实测注册表态。对表这一步当时**只有我在跑**——那格缺口另开 BUG-129 并当场补成常驻判据（见下条）。
- **BUG-128（入账，OPEN 等 owner 裁决）**：**同一个 0.3.4 现在有两份不同的码**。本地 tag `v0.3.4` = `af54d5e`（01:15 +0800，当时 `moon.mod` 已写 0.3.4），而注册表的 0.3.4 载荷取自 `a0dfef3`——两者之间隔着 **11 个提交、`src`+`cmd` 侧 21 个文件 +1643/−269**（看护跨进程修复、探索模式、R 系列判据等）。用户侧形状：`install_onecmd.ps1 -Version 0.3.4` 拿旧码（GitHub Release 资产），`moon add vicTop-cw/fist-mbt@0.3.4` 拿新码，而 `fist version` 只回显 0.3.4 ⇒ 无法分辨。**两条出路（发版不可撤销，等 owner 选）**：① `moon.mod` 前进到 0.3.5 + 重发注册表 + 打 `v0.3.5`（推荐，代价=一轮版本自述同步）；② 把 GitHub Release 的 `v0.3.4` 资产重做到当前树（代价=动已发布的 tag，需明确授权）。本轮**没有**自行 bump，也没有 push。（**追记**：owner 选出路①，已按 `v0.3.5` 段执行完并标 FIXED，盖章 2026-09-29T10:44:53Z；`0.3.4` 同号两树这一事实撤不回——注册表版本不可覆盖，是否给那一版打 `moon deprecate` 仍留 owner 裁决。）
- **BUG-129（上报即收口，盖章 2026-09-29T09:46:36Z）**：BUG-127 的 `### FIXED` 小记当时自己写了「这道对表没有常驻判据」——缺口挂在叙述面里没人认领就是 J10 型缝，而它已经真漏过一次东西，所以不等下一次发布。新增 `scripts/check_publish_payload.py`：P1 未被 `.gitignore` 挡住又未被 git 跟踪的非点号文件 ⇒ 红（点名 + 修法）；P2 红面里出现凭据形状 ⇒ 另判事故级；P3 打包面列不出任何文件 ⇒ FATAL(2) 自拒。离线可跑、不联网（载荷真值要 `moon add` 才拿得到，CI 不该跑网络），所以它是**代理门不是替身**：静态面数出将随包公开 552 件、注册表解包实测也是 552 件，**数目相等而集合不同**（载荷里有后来才被 ignore 挡掉的 `__cli_pkg.mbt.tmp`，静态面里有发布后新增的守卫件）⇒ 发完仍要解包对表一次。`--selftest` 四支（G1 干净不误红；工作树带未跟踪件时自动换 G1' 逐件点名且无幻影红 / M1 造未跟踪件必红 / M2 造被现成 `*.log` 挡住的件必不红 / M3 红面里塞凭据形状必点名 P2），实测 `PASS 发布载荷面干净：将随包公开 552 件，其中未被 git 跟踪的 0 件（另有 18 件点号条目 moon 本来就不打包）`。ci.yml JS 轨挂「先 --selftest 再全量」，守卫族 12→13；顺手把相邻那句「与上面 11 个 `check_*` 并列」改成不带数目的写法——**那个数已经过期过一次了**。两处自证踩坑也写进判据正文：守卫源码里不许出现完整 token 形状（我第一版把假串写字面量里，P2 当场打到守卫自己 ⇒ 改运行时拼接）；G1 在开发期必然失败（新守卫自己未跟踪 ⇒ 换成更强的 G1'，不删门也不放宽）。
**台账现 1 条待修**（128 条入账 = 114 已修 / 9 重复并入 / 4 误报 / **1 待修 = BUG-128**，与 `gen_plugins.py` 的投影行逐字同源；那 1 条不是漏修，是**发版方向的裁决位**）。
> **口径更正（同轮追加，改的是数不是事）**：上面 BUG-120 / BUG-121 / BUG-122·123 三条原写的「110 / 111 / 113 抬头」
> 各少算 9 条——我的计数正则要求第 4 个方括号之后直接跟状态词，而 `DUPLICATE →BUG-n` 抬头在状态词前带了箭头，
> 于是整类被静默丢掉（分栏里的「已修/误报」两个数一直对，只有总数偏小）。已按 `memory/bugs.md` 抬头状态位
> 逐条重算为 **119 / 120 / 122 / 124 / 125**。这是**尺子坏了不是账坏了**：叙述面一字未改，`### FIXED` 小记一字未动。
> 另一处更正：BUG-124 的 `### FIXED` 小记把 11 条 demo 全记在 `temp/demo_audit.log` 名下，实际那份只有 9 行，
> 两条 `.ps1` 的 rc 与根账不变记在 `temp/demo_audit2.log`（BUG-126 的小记里写的就是这个拆分）。

- **demo 车道回传**：一条 `println`→`eprintln` 解封 **27 个** stdio 判据/demo；`mcp_smoke.py` = MCP-SMOKE PASS、
  `atgc_selfdrive_demo` 与 `e2e_mirror_install` 本机跑绿，仓库根台账 **1986 任务 / 6905 调用** 跑前跑后逐字不变
  （只读证明）。产物硬门 `output_validate` 对本轮 14 件交付物判 **verdict=pass / evidence_layer=l4-pass**。

## v0.3.4 (unreleased) - 改进建议书逐条复测：4 条前提被证伪、1 条看护缺陷入账（盖章 2026-09-29T03:58:39Z）

- **复核方法**：`docs/improvement-proposals-20260928.md` 12 条 + 实验报告 4 条过程发现，逐条打到调用面/库面/守卫面
  重测（长驻交互式 Popen 直连 `cmd/cli` 产物 + `FIST_DB_PATH` 隔离库，仓库根 `fist-mbt.db` 只读）。
  落点 `docs/improvement-plan-20260929.md`（逐条判定表 + 修正后的 P0′/P1′/P2′ + 5 项待裁决）。
- **四条前提被实测证伪**（照原案修会修不到东西）：P1-1 server 响应全缓冲死锁（同进程两次往返 0.25s / 0.10s 各回 129 工具；
  真残留是 `serve` 往协议 stdout 先打两行横幅）；P1-3 pause 被 heal 撤销（`heal(ns,600)` 回执 `healed=[]`、暂停单被列进
  `blocked`，代码面 `ops_heal.mbt:82` 活跃集本就不含已暂停）；P2-3 盖章 ±1h 漂移（服务端 vs 客户端 UTC 实测 +0.2 秒，
  真病灶是库里 87 行非规范时间戳 + `iso_to_secs` 不看偏移，`+08:00` 被当 UTC 读偏 8 小时）；P1-4 list 的 ns 过滤失灵
  （BUG-85 已修，`list()` 全库 4 个 ns / `list(probeA)` 精确 1 行）。P0-1 `bug_close` 缺位也已兑现（`bug_fix` 单条即走）。
- **入账 BUG-119（high，OPEN）**：心跳跨进程不可见——进程 1 `heartbeat` 落库并 sqlite 只读确认那一行在，
  进程 2 的 `heal(namespace, timeout_sec=3600)` 仍回 `healed=["T0"]`、`watchdog_tick` 的 `active_tasks` 读回空串；
  叠加 `ops_heal.mbt:87` 的 `None => true`（无心跳行直接判死、`timeout_sec` 不起作用）⇒ 无人值守每拍清空在途任务。
  它是 P1-5（自动拉起执行器）的硬前置。
- **文档面顺手修两格**（同一形状：文档点的参数实现不读）：`AGENTS.md` Omega 表 6 行（3 行删 `now`；2 行把
  `omega_verify`/`omega_verify_fix` 的入参从 `task_id/判定/reason` 改成活体的 `specs`(+`max_rounds`) 并改写描述）；
  `USAGE.md` 摘掉 36 处 `now` 参数（含两个 JSON 示例，改后 13 块示例仍全部可解析）+ 两处「87 个工具」改为实测
  「129 个 MCP 工具」（写成带 MCP 的形状，好让 `check_tools_sync` 的 `RE_TOOL_CLAIM` 数得着）。
  §7 那条「返回 87 个工具」是那次实跑的截面记录，**没改数**，只加了限定语。
- **判据缺口定位**（本轮最有价值的一条，写进 P0′-3③/P1′）：手册的参数列与工具计数都不在任何守卫的扫描面上——
  `check_tools_sync` 判据 5 只扫 server.mbt 广告位、J2 只比工具名、J8 只比 `templates/*.md`、`RE_TOOL_CLAIM` 要带「MCP」。
  原型对表脚本量出的噪声形状也一并记档：14 处命中里仅 6 处真违例，另 8 处是取值枚举/散文被当参数名
  ⇒ 新判据必须带形状约束并把这 8 条钉成"干净不误红"格。
- **守卫复跑**：`check_tools_sync` 0 / `check_doc_surface` 0 / `check_plugin_sync` 0（BUG-119 入账后按 cl7 处置
  重投影 9 个插件文件，逐文件 diff 只有一行账本投影）。`check_scripts_index`（`gen_help_docs.py` 未登记）与
  `cleanup_artifacts --check`（77 根 .db + 366 temp 文件）两格红**不属本轮**，只登记不代改。

## v0.3.0 (unreleased) - 安装面自证：以用户身份装 + 用装好的全局命令打满 129 工具（盖章 2026-09-28T05:09:38Z）

- **判据三条新增**：`scripts/check_ps_encoding.py`（.ps1 要么纯 ASCII 要么带 UTF-8 BOM，空扫描面 FATAL 不出假绿，
  `--selftest` 含合成违例/不误红/增删 BOM 翻转三格）、`scripts/store_isolation_probe.py`（BUG-90 活判据：同一 cwd
  两格只差 `FIST_DB_PATH`，C1 断言行落指定库且 cwd 内不得长出默认库；`--selftest` 追一格合成违例）、
  `scripts/mcp_tool_tour.py`（129 工具调用面巡回，参数从 `tools/list` 的 `inputSchema` 反解，
  三面分栏 ok/refused/skipped/crashed + 基数自证）。ci.yml 守卫族 7 → 9。
- **两个 critical 修复**：① BUG-90 `store_open(scratch=true)` 的 ns 库不参与路由（`MultiStore::get` 全仓零调用，
  工具闭包统一用模块级 engine），行照落仓库根 `fist-mbt.db`——新增 `SqliteStore::db_path_from_env/default_db_path`
  与运维侧 `FIST_DB_PATH`（未设置时逐字回退默认库，零回归），白盒 `src/store/store_db_path_wbtest.mbt` 三条；
  ② BUG-91 `run_check` 无上限累积子进程 stdout/stderr 可被一次调用打死会话——`run_check_js.mbt` 每流末 1 MiB
  + `stdout_capped/stderr_capped` 旗（`output_truncated` 语义不变）。
  两处都有两态实测：修复前产物 C1 RED / 同夹具 2.1s 进程死；修复后两格 GREEN / 6.6s 正常回执。
- **分发面**：安装器补离线入口 `install_onecmd.ps1 -LocalZip`、`install.sh FIST_LOCAL_ZIP`；下载失败路径改为
  打印 HTTP 状态与候选 URL；`release.yml` 标签过滤 `v[0-9]+.[0-9]+.[0-9]+` → `v*`（GitHub ref 过滤器不支持
  字符类，实测 0 runs），发布版本源改正则读 `moon.mod`，4 处入口路径 `cmd/main` → `cmd/cli`（发布产物真身）。
- **PS 5.1 编码债清掉**：`native-env.ps1`（实测 12 处解析错误）、`showcase.ps1`（5 处）、`demo.ps1`（0 处但中文乱码）
  补 UTF-8 BOM，复测 `Parser::ParseFile` 三档全部 0 处。
- **BUG-94 续（同轮内定位到根因并修）**：`executions` 表补进 `create_schema` + `cost_stats` 读前 ensure
  （两层缺一不可：只补建表清单对**存量老库**无效）；白盒 `src/store/cost_stats_executions_wbtest.mbt` 两条，
  HEAD 源码下逐字复现 `Error: no such table: executions`（2 红），修复后包 23/23、JS 全量 **531/531**。
- **BUG-96/97/98（自报缺陷）**：巡回驱动读面把 `project_dir="."` 当探针项目 ⇒ `report_bug` 写进真账本两次，
  并与手写台账撞出两个 `## BUG-90` 抬头；处置=两条垃圾条目改判 FALSE_POSITIVE 并重编号消撞号，
  缺陷本体另立 BUG-98（FIXED，驱动加 `READ_PLANE_SKIP` 六只写工具 + 读面前后 sha256 相等为准绳）。
  账本现 97 条、无重复 id = 83 已修 / 9 重复并入 / 3 误报 / 2 待修。
- **BUG-92 改判 + BUG-93/99/100/101 收口（同轮追加，上一条 97 条的计数是当时的盘面）**：
  BUG-92 那句「split 要求状态 [待领取]，当前是 [待领取]」是我把 cp936 控制台乱码按字形猜出来的——  活探针 temp/bug92_probe.log 从回执 \u 转义逐字反解得到的是「要求状态 [已领取]，当前是 [待领取]」，
  两态本就不同 ⇒ 按 FALSE_POSITIVE 关闭；真缺陷（拒绝文案不带出路 + 两道门词汇分叉）重报为 BUG-99 并修。
  BUG-93 入口搬家补齐另一半：104 处 cmd/main→cmd/cli + 26 个启动点补 `serve` + 新守卫 `scripts/check_entry_paths.py`（同一守卫在 HEAD 树 119 条违例、修复树 0 条）；
  BUG-100 巡回读面在被测仓库留状态文件 ⇒ 读面 project_dir/data_dir 改指 temp/ 草稿项目并加外溢硬门
  （硬门首跑即抓到仓库根 tour-read-*.db，补后 129 工具 GREEN、取证面 172 项 0 新建 0 改动）；
  BUG-101 `serve` 往 JSON-RPC 的 stdout 打 3 处人类横幅 ⇒ run_serve 体内不再写 stdout，
  回归门就是 mcp_smoke（横幅回来第一行非 JSON 即红）。
  全量 JS **533/533**（temp/verify_eng_full.log）；提交树自证：`git archive` 出的 327bb7a 树 **531/531**
  （temp/verify_327bb7a_test.log），HEAD 派生树 + 本环修复 → `MCP-SMOKE PASS`（temp/smoke_e2e_proof3.log）。
  账本 100 条 = 87 已修 / 9 重复并入 / 4 误报 / 0 待修。已知红一项归并行改动面：`gen_help_docs.py` 未在 scripts/README.md 登记。
  **BUG-102 收口（同轮追加，上文那条「2 待修/1 待修」是当时的盘面，不改写）**：2026-09-28T06:45:59Z
  cl7 在全新 autocrlf 克隆里恒报 55 份「内容不一致」，实为 `tree_digest` 逐字节比撞上 「提交里 LF vs 检出后 CRLF」；改在**比较侧**做行尾归一（写盘字节不动、四宿主投影不动），真漂移与「仅行尾不同」分栏报数，`gen_plugins.py --selftest` 四格自证（相同 / 仅行尾 / 内容漂移 / 缺失与多余，并钉住 CRLF 夹具必须与 LF 字节不同以防夹具空转），该自检同时进 ci.yml 的 cl7 那一步（BUG-89 同型：自检不被执行等于没有）。
  承重实测：同一棵新克隆里旧守卫 55 漂移、新守卫 1 漂移，而那 1 份正是当时真没重生成的 plugins/README.md ⇒ 归一没把真问题放行；重生成后 `check_plugin_sync` rc=0。账本 101 条 = 88 已修 / 9 重复并入 / 4 误报 / 0 待修。
  **BUG-103 收口（同轮追加）**：安装器默认版本写死 `0.3.0-beta` 而发布资产名按 moon.mod 的 `0.3.0` 生成 ⇒ 不带参数的 `irm … | iex` 两条源都 404，且 CI 不发 Release 也看不见这条。改成运行时从 moon.mod 解析（`-LocalZip`/`FIST_LOCAL_ZIP` 从 zip 文件名反解），解析不到就 `exit 1` 并教用户手带 `-Version`，绝不静默用猜的版本号；新守卫 `scripts/check_release_asset_names.py` 钉住「三处资产名同源 + 禁字面量默认 + 空值即失败」（六格变异自证），守卫族 10→11。调用面实测：离线 zip 安装后 `fist doctor` 5/5、安装产物 serve 第一行即 JSON、tools/list 129。账本 102 条 = 89 已修 / 9 重复并入 / 4 误报 / 0 待修。
  **BUG-104 收口（同轮追加）**：AGENTS.md 自述的「3 resources + 2 prompts」与 `serverInfo.version ↔ moon.mod` 此前**没有任何判据认领**——tools 面被 `check_tools_sync`/`check_doc_surface` 钉到逐字对齐，恰好剩这两面全靠人偶尔手试一次，正是 J10 型缺口（自述有人写、判据没人认领）。补 `scripts/mcp_tool_tour.py` 的 `surface_probe()`：期望值从 AGENTS.md 的 `Resources:` / `Prompts:` 两行反解（不手抄常量），与服务端实回**双向**对表——少一条 / 多一条 / 读回空文本 / prompt 零消息 / 版本不符 / 验收位为空，一律计入红面 ⇒ 巡回退出码非 0；AGENTS.md 反解不出条目时判据自拒，不静默零问题。判据自身配 `--surface-selftest` 12 支对照（10 违例必红 + 干净支必绿 + 无声明行必自拒，桩 server 不起 node、不碰库），并作为独立一步进 ci.yml（BUG-89 同型：自检不被执行等于没有）。为什么它不是第 12 个 `check_*`：这两面必须真跑 MCP 协议才观测得到，离线脚本只能验文档自述。调用面实测（安装态产物 sha256:616b7632，`--plane read` / `--plane write` 各一遍，两遍自述面行逐字相同）：`resources=3(声明 3)[map=2182 overview=212 principles=606] prompts=2(声明 2)[check_in=1消息 verify=1消息] serverInfo=0.3.0 moon.mod=0.3.0`；read 面 129 工具 ok=76 refused=41 skipped=12 自述面红=0（读面外溢判据：新建 0 / memory 改动 0），write 面 ok=81 refused=42 skipped=6 自述面红=0。账本 103 条 = 90 已修 / 9 重复并入 / 4 误报 / 0 待修。**盘面现状本来就是对的**——这条修的不是一个错，是「它错了没人知道」。
  **BUG-105/106 收口与新开（同轮追加）**：从 PowerShell 里 `fist doctor` 5/5 的那个安装，在 Git Bash 里 `which fist` 直接 not found——Windows 安装器只产出 `.cmd`，而 POSIX shell 不解析 PATHEXT ⇒ 「装成功了但找不到命令」是同一次安装的两种真相（`install.sh` 那侧本来就是无扩展名 + `chmod +x`，缺的只有 Windows 半边）。补：安装器同目录再写无扩展名 `fist`/`fist-mbt`（`#!/bin/sh` + `exec node "<js>" "$@"`，**必须 LF**，CRLF 的 shebang 报的是 `bad interpreter` 且装完当场看不出来）＋两道硬门（四件不齐 ⇒ 点名缺哪件再 exit 1；shim 头不对或含 CR ⇒ exit 1）；旧注释里的 em dash 经 `-Encoding ASCII` 落成真 `?` 也一并清成 ASCII。判据：`check_release_asset_names.py` 从四条加到**五条**（R5 钉两类 shell 都可见），`--selftest` 六格 ⇒ 八格（R5×2：摘掉 Set-Content 必红、`chmod +x` 文件名写错必红），AGENTS 守卫族条目与 scripts/README 行同步；判据自己的负面向门：`temp/b105_gate_canary.py` 两格（M1 摘写入 rc=1 且点名 / M2 原样 rc=0）。调用面：隔离 bin 复跑安装器摘出的那段 ⇒ 四件齐、POSIX 两份 CR=0、bash 里 `fist version`→v0.3.0、`fist doctor`→5/5；真机 `~/.local/bin` 只**新增**两个无扩展名文件（不覆盖并行改动面装好的 .cmd 与产物）。另开 **BUG-106（medium，OPEN，交并行改动面）**：`fist --help/-h/--version/-V` 全被判"未知子命令"，且未知子命令的**退出码是 0** ⇒ `fist --version || exit 1` 这类包装会把失败读成成功。不开在这一环的理由与可粘贴补丁一起写进账本：`cmd/cli/main.mbt` 是对方**正在重写**的在写文件（工作树 dirty + 未跟踪 `cmd/cli/help_topics.mbt`），往那儿插臂会被整档写回静默吃掉。账本 105 条 = 91 已修 / 9 重复并入 / 4 误报 / **1 待修（BUG-106，跨环移交）**。
  **BUG-107 收口（同轮追加）**：只读探测（只 GET、不执行、不带凭据）发现照文档敲 `irm … | iex` 的第一步就坏——GitCode 三种 raw 形状（`/-/raw/`、`/raw/`、`raw.` 子域）匿名 GET 全回 **HTTP 200 + 一整页 HTML**（5527 字节的 `<!DOCTYPE html>`），GitHub 侧文档写的 `main` 分支取不到（默认分支是 master，raw/master 才是 200 + `#!/usr/bin/env pwsh` 的那条）。最坏的不是失败而是 200：旧代码只判「拿到内容 + 大于 10KB」，于是「源给的是网页」和「源不可达」在用户侧同一句模糊提示，BUG-103 修的版本解析也被这条死兜底污染。修法：首选线一律改 GitHub master raw、GitCode 降备用并写明实测形状；取 moon.mod 先 sniff `<(!DOCTYPE|html)` 并点名换源；下载资产先验 zip 魔数 `PK`（PS 侧比 0x50/0x4B、bash 侧 `head -c 2`）再看大小。判据 `check_release_asset_names.py` 五条 ⇒ 六条（R6），`--selftest` 八格 ⇒ 十一格（R6×3：摘 PK / 摘 HTML sniff / 首选线漂回 main 都要红）；自述同步：AGENTS 守卫族条目 + scripts/README 行（J10：范围自述==实现）。台账面：README「黑盒用户」两行仍写 GitCode raw（并行改动面本轮新加，对方在写 ⇒ 不代改，交过去一句改法）。顺带记一次判据自坏：R6 的首选线正则起初写成 `install_(?:onecmd\.ps1|sh)`，把 `install.sh` 拼成 `install_sh` ⇒ 干净输入被误判红（是尺子坏了，不是产品坏了）。账本 106 条 = 92 已修 / 9 重复并入 / 4 误报 / 1 待修（BUG-106）。
  **BUG-108/109 收口（同轮追加）**：`-LocalZip` 是**跳过**下载不是走下载，而公网 Release 在有推送授权前不存在 ⇒ URL 拼装/状态码/HTML sniff/zip 魔数/解压/ESM patch/shim/PATH/自检这一段此前一次也没跑过。补镜像入口（`install_onecmd.ps1 -BaseUrl` / `install.sh FIST_BASE_URL`，与 `-LocalZip` 同给即 exit 1）+ 常驻端到端 `scripts/blackbox/e2e_mirror_install.py`（本机 http.server 当镜像，装进沙箱：子进程 env 把 LOCALAPPDATA/USERPROFILE/TEMP 指 temp/、HKCU 用户级 PATH 跑前抓原值跑完逐字还原、真产物跑前跑后 sha256 必须相同；反面对照把资产换成 20KB HTML ⇒ 必须 rc=1 且点名「前两字节 3C-21」）。首跑抓到两处：**①** PS 5.1 下 `(Invoke-WebRequest).Content` 遇 `application/octet-stream` 是 `byte[]`，版本正则静默失配 ⇒ 改成非 string 先按 UTF-8 解码（**②即 BUG-109**）—— 自检在 `$ErrorActionPreference="Stop"` 下把 node:sqlite 每次启动都打的 `ExperimentalWarning` 当终止错误：两个 `try{}catch{}` 必吞错、`✅ fist-mbt.js 可执行` 却**无条件**打印（装饰性绿），`& fist version` 的 catch 还把「shim 跑通了」报成「当前会话 PATH 未刷新」（诊断指向不存在的原因，同一沙箱 bin 用 bash 跑 `fist version` 是 rc=0）。修法：`Invoke-FistNative`（调用期临时降 EAP + `2>$null`）＋空 stdout ⇒ `❌` 并 exit 1 ＋ `Get-Command fist` 把「解析不到」与「解析到却无回执」分成两条诊断。判据：`check_release_asset_names.py` 六条 ⇒ **七条**（R7 三支），`--selftest` 十一格 ⇒ **十四格**（R7×3：`2>$null` 改回 `2>&1` 必红 / ✅ 脱离 `if ($jsVer)` 必红 / 引入空 catch 必红），AGENTS 守卫族 + scripts/README 同步；端到端复跑 `=== 端到端镜像安装：PASS ===`，`安装器自检经 shim 跑到 fist` 由「永不命中」转为真命中（回执 `fist (PATH) → FIST-Mbt v0.3.0`）。账本 108 条 = 94 已修 / 9 重复并入 / 4 误报 / **1 待修（BUG-106，跨环移交）**。
  **BUG-110 收口（同轮追加）**：README 的两条安装线指 GitCode `/-/raw/**main**/` —— 既是 BUG-107 实测的「200 + 一整页 HTML」源、分支又写错（默认分支 master），于是文档面上用户抄的那条命令从来没对过；同段代码栅栏字节里还嵌着退格符 `0x08`（```bash 被写成 `\x08ash`）⇒ 整块不渲染、装后六条命令散在正文里分不清哪条要抄。修：首选线一律 GitHub master raw 直链、GitCode 降为「浏览备用」并写明实测形状（不许接进 `| iex`）、栅栏重写为合法围栏。落盘用整段唯一上下文锚点（坏字节含不可见字符，不能拿它当锚），自证：命中区间 461 字 / 退格符 1→0 / 死链归零 / 行数差==本节行差 / 前缀逐字未动。这一节的 20 行本体是并行改动面的未提交新增，本轮由用户指令「README 补丁你去改」由我落并随之提交（台账里点名，不静默带走）。账本 109 条 = 95 已修 / 9 重复并入 / 4 误报 / 1 待修（BUG-106，跨环移交）。
  **BUG-111 入账（OPEN · 发布作业依赖已修，资产待 CI 出）**：`v0.3.1` 标签触发的 `FIST-Mbt Blackbox Release` 是这条流水线的**第一次真跑**（run 1）且失败 ⇒ `releases/download/v0.3.1/fist-mbt-js-v0.3.1.zip` 实测 404、release 页面资产链接 0 条。先排掉两个误判方向：资产名同源（R3/R6）没问题；产物也造得出来——`git archive HEAD` 快照树里复跑 CI 的 JS 三步全绿（`moon build --target js` 0 errors / `patch_esm_main.py` rc=0 / zip 374KB 魔数 `PK`）。真因在作业依赖：`release` 正文引用 `needs.meta.outputs.version` 却没把 `meta` 放进自己的 needs（取空值 ⇒ Release 名与资产名漂成空版本形态），又把**可选的** `build-native-linux` 当一票否决项（同文件的 windows native 作业反而已有 `continue-on-error`）。修：`needs: [meta, build-js]` + `build-native-linux: continue-on-error: true`；判据加 **R8**（三支子判据各必红），`--selftest` 十四格 ⇒ 十七格，PASS 行自述同步 R1-R8。发布动作走纯快进：不删/不重指已发布标签，版本 0.3.1 → 0.3.2 打新标签触发 CI（盘面只有 moon.mod 与 USAGE.md 两处真写死版本）。**先记 OPEN**：修复与判据已落盘，但「Release 真出资产」还没发生——翻 FIXED 的判据写在账本条目里（匿名 HEAD 得 200 + `PK` + 真公网线装出 0.3.2）。另记一条不属于本轮成因的事实：Actions 上 run 178→186（多笔早于本轮的提交）全是 failed ⇒ 本仓 CI 长期红；匿名 API 403 rate limit，读日志需要 `FIST_GITHUB_TOKEN` 注入或在 UI 点开。
  **BUG-112 入账（OPEN · release.yml 工具链 bootstrap 与 CI 同源已修，资产待 v0.3.3 的 run）**：从匿名 `/actions/runs/<id>/jobs` 取到的失败步骤名把真因钉住——`meta` success / `build-js` 红在 **Build JS target** / `build-native-linux` 红在 **Build native** / `build-native-windows` 红在 **Install MoonBit** / `release` 是 **skipped**（不是跑挂）⇒ 工具链没到手，不是代码编不过。对照同仓跑通过的 `ci.yml`：它用 `install/unix.sh` 且 `echo "$HOME/.moon/bin" >> "$GITHUB_PATH"` + `moon update`，而 `release.yml` 三条全缺 ⇒ 同一个 `moon build` 在 CI 轨能跑、发布轨跑不了。**顺带纠正 BUG-111 的归因**：我在 `git archive HEAD` 快照树里复跑 JS 三步全绿，就写下「产物没问题」——那复跑用的是**本机全局 moon**，与 runner 的 PATH 不同形；它证明「代码编得过」，不能证明「CI 那一步也过得去」。修：build-js 与 build-native-linux 两侧 bootstrap 对齐 ci.yml（`.sh` + 导出 GITHUB_PATH + `moon update`）；windows 侧仍红在装工具链，但那是 `continue-on-error` 的非权威面，本轮只记账不扩大改动面。判据加 **R9**（只看去掉 `#` 注释后的代码面——第一版被自家注释里的 "GITHUB_PATH" 喂回针，那格变异不红，`--selftest` 当场抓到），`--selftest` 十七格 ⇒ 十九格；版本 0.3.2 → 0.3.3 打新标签走纯快进。
  **BUG-113 收口（同轮追加）**：资产终于出来之后第一次把「用户照抄的那一行」原样跑（沙箱档），文档线自己红——报「At line:22 char:22 [string]$Version 赋值表达式的左侧无效」，而同一个脚本 `powershell -File` 跑正常（之前所有 e2e 都走 -File ⇒ 这一格没人照过）。成因是两条各自正确的规矩撞车：BUG-88 要求含中文的 .ps1 带 UTF-8 BOM，而 `irm` 返回**字符串**且把 BOM 留成首字符 U+FEFF ⇒ `iex` 认不出 `param()` 是首语句。最小对照（`temp/bom_min_control.py`，-EncodedCommand）：无 BOM⇒OK / 有 BOM⇒FAIL / TrimStart(U+FEFF)⇒OK ⇒ 唯一变量是 BOM。我第一个修法也是错的：`.Content.TrimStart` 那条路上 `.Content` 是 null（InvokeMethodOnNull）⇒ 正确形 `.ToString().TrimStart([char]0xFEFF)`。修：README + 安装器头部改 BOM 安全形并各写理由；判据加 R10（十九格→廿一格，任一侧退回裸形必红，README 进判据面）；常驻 `scripts/blackbox/e2e_irm_line.py` 从 README **反解**那一行来跑，默认沙箱档、`--real` 才落真面带备份还原。实证 rc=0：0.3.3 / 资产名 / `fist (PATH)` / `POSIX shim, LF` 四格全命中，横幅 v0.3.3 安装完成，沙箱产物 sha256:2eaa4803，用户 PATH 逐字还原、真产物未动。同一次跑又暴露一格：`fist version` 仍回 v0.3.0 ⇒ 新开 BUG-114（版本自述有三个真源，其中两个常量在并行改动面手里，可粘贴补丁已入账、本轮不代改）。\n

  **BUG-106 / BUG-111 / BUG-112 / BUG-114 收口（同轮追加 · 账本 OPEN 清零 · 版本 0.3.4）**：用户指令「bugs.md 看下，有就启动修复模式 全部清掉」⇒
  四条 OPEN 一次落地，收尾后台账 **113 条 = 100 已修 / 9 重复并入 / 4 误报 / 0 待修**（`gen_plugins` 回执同源）。
  - **BUG-111+112（只翻状态）**：`v0.3.3` 那一次 run 已把两条条目末自写的判据全部兑现——meta/build-js/release 三作业绿、
    匿名 HEAD 资产 302 → `fist-mbt-js-v0.3.3.zip` 且前两字节 `PK`、公网线（不带任何参数）装进沙箱 rc=0 四格全命中。
    挂一条 `### FIXED(stamp / BUG-111, BUG-112)` 合并点名；111 的原始归因（"真因在作业依赖"）已被 112 证伪并留在叙述面，不回写。
  - **BUG-114（版本自述其实有三个真源）**：`moon.mod` 0.3.3 而 `src/server/server.mbt` 的 `project_version` 与
    `cmd/cli/help_topics.mbt` 的 `FIST_VERSION` 都还写着 `0.3.0` ⇒ 装出来的 `fist version` 回 v0.3.0、横幅回 v0.3.3。
    最不好受的一条事实：`src/server/fist-mbt_wbtest.mbt` 里那条「BUG-16 对外版本单一真源」常驻锁**在 master 上一直是红的**
    （它比的正是这两处），红着没人读等于没锁。修：三处 + `USAGE.md` 一起到 0.3.4；判据加 **R11**（`let project_version`
    与 `cmd/cli` 侧扫到的任何 `const *VERSION*` 必须 == moon.mod，读不到基线即自拒、可选面缺席不误红，五格对照）；
    另把 `e2e_irm_line.py` 里写死的 `0.3.3` 针改成从 moon.mod 反解（写死的针一升版就漂，漂成假绿最坏）。
  - **BUG-106（`fist --help` 被当未知子命令、且未知子命令回 0）**：跨环等并行改动面收口这条本轮不再等——新增 `cmd/cli/subcmd.mbt`
    把词法做成单一真源（`parse_subcmd` 展开 `version|--version|-V`、`help|--help|-h`；`USAGE_ERROR_EXIT_CODE = 2` + `exit_code_of`；
    `cli_exit` 三形态：js 走 `process.exit`、native 走 libc `exit`、其余运行时 abort 而不是静默回 0），`main.mbt` 只读它。
    锁两层：白盒 `cmd/cli/subcmd_wbtest.mbt`（别名归位 / 未知必非 0 且已知必 0，成对反向对照）+ **调用面新判据
    `scripts/cli_flag_probe.py`**（起真产物 `node cli.js <arm>` 看真 rc、读真首行；版本旗必须回显 moon.mod 版本、
    帮助面同规则、未知参数 rc≠0；文案针从 `cmd/cli/main.mbt` 反解、版本针从 `moon.mod` 反解；`--selftest` 七格）。
    为什么白盒不够：入口被改回字符串 match 或 `cli_exit` 被摘掉，纯函数测试照样全绿。实测：三格版本旗 rc=0 首行 `v0.3.4`、
    `__probe_not_a_subcommand__` rc=2、`--help` 走帮助不落未知臂。
  - **判据面顺带修掉两处自己的假账**：`check_release_asset_names --selftest` 的格子清单与 PASS 行范围从今**从实现反解**，
    不再手写计数——旧行写 `R5×2`，而其中一格因"变异只改注释"被循环 `continue` 跳过，**那一格从没跑过**（幻影判据）；
    现改成"删掉 POSIX shim 写入行"的真变异并把清单变成 `Counter(已执行格子)`。
  - **发布动作**：`moon.mod`/`USAGE.md` → 0.3.4，四宿主投影重生成（129 工具 / v0.3.4 / 0 条待修），
    本地 tag `v0.3.4` 走纯快进（不删不重指已发布标签），CI 新增一步 `cli_flag_probe`（先 `--selftest` 再全量）。
  - **测试面**：`moon test --target js` = **535/535**（533 + 本轮 `cmd/cli` 两支白盒），现状面声明由 `check_test_sync` 同步；
    native 本轮未复跑，不据旧数宣称双端同版全绿。
  - **结转（不装成已修）**：`cmd/cli/help_topics.mbt` 与 `main.mbt` 的 `fist help <topic>` 本体仍是并行改动面的未提交新增 ⇒
    本次提交只带我自己的那一处分发改动（HEAD 正文 + 我的 hunk，摘段双向验：暂存里不含对方行、工作区仍含），
    对方那半边留在工作区不代为发布；`check_scripts_index` 在本地因对方未登记的 `gen_help_docs.py` 报红，HEAD 面上不存在该文件 ⇒ 不随本次提交进 CI。
  **BUG-115 收口（同轮再追加 · 第 3 笔）**：验证"我提交的那一棵树"时撞上——`temp/staged-tree` 首轮
  `moon test --target js` = 535/532/**3 failed**，随后 4 次（含删 `_build` 冷构建）全绿。第二次撞上就不叫偶发：
  在 HEAD 的干净 worktree 里 `rm -rf temp` 后必红，三条全出自 `src/engine/engine_execute_r2_test.mbt`，
  错误是 "unable to open database file"。成因是**测试之间隐性依赖**——该文件的 `r2e_engine` 打开
  `temp/r2_bug2_*.db` 却不建 `temp/`（SQLite 只造文件不造父目录），靠同包 `docs_gate_test.mbt` 里那句
  `@fs.create_dir("temp")` 先跑赢竞速；主工作树永远绿（`temp/` 早就在），于是"本机全绿"在这条上纯属假证据。
  修：helper 补 `@fs.create_dir("temp") catch { _ => () }`（沿用同包惯用法），对照实证同一无 `temp/` 条件下
  修前 532/535、修后 **535/535**（`temp/fixed_no_temp.log`）。另点名一条可能性：BUG-111 记过
  "Actions run 178→186 全 failed 但匿名 API 403 读不到日志"，本条是它的一个可复跑解释，
  但不据此宣称已把 CI 全量跑绿（native 轨与别的红还没归因）。同形风险只查不铺：
  另 9 个用 `temp/` 路径的测试文件在同样条件下都不红 ⇒ 只在被观测到的这一处落修。
  **BUG-116 入账（OPEN · 环境侧）与 BUG-117 收口（同轮第 4 笔）**：推 `v0.3.4` 之后跑公网复验，
  第一次得到"四格针全未命中"——真相是**判据自己假红**：沙箱里留着上一轮 0.3.3 的产物，
  文档线不带 `-Force` 直接 exit 1，测的是"沙箱脏了"而不是"文档线坏了"（BUG-117）。
  清场后重跑，失败点往前挪一格才看见真东西：被打红的是 `irm https://raw.githubusercontent.com/…/install_onecmd.ps1`
  **本身**（`Invoke-RestMethod` 抛"基础连接已经关闭"），产品码一行都没跑到。三条链路事实：
  `curl --noproxy '*'` 取 github.com = 000（直连不通）、系统代理开着（127.0.0.1:7897）、
  同一时刻经代理的 curl 能取到资产 200 + 372,836 字节 + `PK` 而 PowerShell 9/9 传输层被对端关闭
  （TLS 三档各试三次同一错误）⇒ 成因在本机代理/TLS 中间盒，**不伪装成已修**：BUG-116 保持 OPEN，
  关闭证据 = 链路健康时 `e2e_irm_line.py` 跑绿。本轮为该形状落了 **R12**（下载重试只许对准传输层错误：
  "有 HTTP 响应就 break" 的闸 + 退避间隔，两支变异必红）与两处判据自纠
  （沙箱每次清场；探针点名跑沙箱那一份 `fist`，不许摸真用户面的旧产物顶数）。
  账本现状：**116 条 = 102 已修 / 9 重复并入 / 4 误报 / 1 待修（BUG-116，环境侧）**。

- **账本**：BUG-90~94 五条入账（90/91 FIXED 并落 `### FIXED` 小记；92 拒绝文案自相矛盾、93 退役入口 `cmd/main`
  仍散在 15+ 处脚本/文档、94 `cost_stats` 未捕获 `ERR_SQLITE_ERROR` 杀会话 三条 OPEN 交裁决）；
  现状 95 条 = 3 待修 / 81 已修 / 9 重复并入 / 1 误报。
- **测试面**：JS 后端 **529/529**（HEAD 基线 526 + 本轮 3 条白盒，在 `git archive HEAD` 快照树跑，避开并行改动面）；
  native 本轮未复跑。
- **测试面同轮再动（追加，不改写上一条）**：BUG-94 的两条白盒 `cost_stats_executions_wbtest.mbt` 之后落地，
  收口实测 **531/531**（`temp/relbuild_test_r4.log`，rc=0），徽章/AGENTS/ARCHITECTURE/docs 等**现状面**由
  `check_test_sync` 从该日志反解同步到 531。**历史面不动**：`CHANGELOG.md` 在 `check_test_sync` 的
  `HISTORY_FILES` 豁免表里，本轮一度把下文 2026-09-27 记录中的 `508/508` 一并扫成 531，已逐字还原
  （叙述面只追加不删改，把旧实测数改成新数即伪造历史）。
- **汇报**：`reports/2026-09-28-installed-cli-tour-report.md`（含逐字拒绝文案清单指针 `temp/tour_evidence.txt`）。

## v0.3.0 (unreleased) - 缺陷账本兑账 + 已知 OPEN 全部独立清零（不走流水线）

- **规则先成文（`memory/bugs.md`「记账规则」段）**：应「这么死板……修了的当然能标记，递归弄的报告只能增不能删」这句质询而立。
  状态词汇闭集 `OPEN / FIXED / DUPLICATE / FALSE_POSITIVE`（`误报` 的英文即 `FALSE_POSITIVE`）；**状态只存在于条目抬头一行**
  `## BUG-n [时间] [严重度] 状态 [→BUG-m]`；抬头以下的叙述面（detail / `### FIXED` 小记 / 证据）只追加不删——历史过程照得到，
  当前结论只认抬头。计数口径同时改判：旧式 `open_cnt = 总条数 − 小记条数` 把"小记有几条"当成"修了几条 bug"，
  而一条小记可收 1~16 条、也可一条都不收 ⇒ 那句"30 条待修"从来没有定义，现一律从抬头状态位反解。
- **四条硬门进生成器**（`gen_plugins.ledger_status`，违例即 `die()`、不产出"看着正常"的插件）：
  ① 标 FIXED 必须被某条小记抬头点名（防空口标修好）；② 被小记点名的必须已标 FIXED（防两套话）；
  ③ DUPLICATE 必须带合法主编号（存在、非自指、非链条）；④ 闭集外的状态词一律红。判据抽成纯函数是为了能被变异直接考。
- **控制面补齐（BUG-9 的可操作那半）**：`src/server/bugreport.mbt` 新增 `bug_fix`（抬头 + `### FIXED` 小记**同一笔**写、幂等、
  整笔原子）与 `bug_mark_status`（OPEN/DUPLICATE/FALSE_POSITIVE 改判，DUPLICATE 三种非法形状必拒且带原因），
  并登记为 MCP 工具 ⇒ **120 → 122**。刻意拒绝"只改抬头标 FIXED"：那会绕过硬门①、产出一本生成器拒绝产出的红账本。
- **兑账 + 独立清零**：84 条逐条归属（58 FIXED / 16 OPEN / 9 DUPLICATE / 1 FALSE_POSITIVE），随后 16 条 OPEN **不走 FIST 流水线、
  逐条独立修**——BUG-8/9/11/20/23/25/26/27/28/29/30/34/35/79/80/81。修复过程中**新入账并当场收口 5 条**：
  BUG-85（内存/SQLite 两后端语义分歧，锁 `store_backend_semantics_test.mbt`）、BUG-86（启动参数真源搬家后投影不可解析，
  J5 补「真源不存在⇒红」）、**BUG-87**（`github_sync.mbt` 里 `"${FIST_GITHUB_TOKEN}"` 被 MoonBit 当**字符串插值** ⇒
  JS 运行时 `ReferenceError: FIST_GITHUB_TOKEN is not defined`，即 flush_plan 的产物一跑就死，critical）、
  **BUG-88**（severity 词表两侧各写一份：写侧收 `open/critical`、抬头文法只认 `high|medium|low` ⇒ 一条**完全合法**的
  `report_bug` 就能写出判据读不到的抬头，生成器 FATAL、整条投影链停摆）、**BUG-89**（文档面守卫的 `--selftest` 从不被自动面执行）。
  BUG-88 的触发者是我自己：本轮把 BUG-87 按 `critical` 入账，`gen_plugins` 立刻拒绝生成 ⇒ 修法两侧同改并加
  **跨语言单源门禁** `severity_vocab_drift()`（从 `bugreport.mbt` 反解闭集与自己的文法做集合相等，漂移即 FATAL，四方向合成对照实测）。
- **账本最终态（由新工具自己写盘，无一手改 markdown ⇒ 控制面的调用面证据就是这次收口本身）**：
  `BUG-1~89 共 89 条：0 条待修 / 79 条已修 / 9 条重复并入 / 1 条误报`。
- **全量与投影**：JS 后端 `moon test --target js` **508/508**（连跑两次同数，`temp/phaseC/full_final.log` /
  `temp/phaseC/full_final2.log`）；七守卫 rc=0 +
  `check_doc_surface --selftest` rc=0（覆盖面清单改由自检正文反解，现为 **J4/J6/J7/J8/J9/J10**）+ `mcp_smoke` PASS；
  四宿主插件态重投影 cl7 逐字节一致（4 宿主 / 56 生成文件 / 122 工具 / v0.3.0）。计数面（README 徽章/自检注释、AGENTS、
  ARCHITECTURE、docs、scoring_rubric、README_EN/.mbt）由 `check_test_sync`/`check_badge` 从实测日志反解同步，不手抄。
- **测试总数在同一条命令上移动过 487 → 508（差 21，机制未定位，如实记）**：本轮中段 `moon test --target js` 实测
  **487/487**（`temp/phaseC/full487.log`），收口前连跑两次都是 **508/508**（`temp/phaseC/full_final.log` /
  `full_final2.log`）。21 这个数恰好等于 `src/server/github_gitcode_wbtest.mbt` 里的 `test` 块数——该文件在 HEAD 就有、
  本轮从未被我改动、`git status` 全程干净；同一时刻该工作区有并发进程在活动（仓库根新落 `alpha.db`/`cb_b34_t*.db` 等、
  `.fist-gitcode-20260927/` 里有 `selfdrive_*.py`）。**"哪一次是真的"这个问题我不给猜测答案**，按可复现者定稿：
  收口数以连跑两次的 508 为准，计数面全部由 `check_test_sync`/`check_badge` 从该日志反解同步；
  487 那次同样真实发生过，两份日志都留着。
- **如实留下的缺口**：① 本轮一次**未带 ns 的 `heal`** 在共享根库 `fist-mbt.db` 上回滚了 **23 个命名空间的 396 条在途任务**
  （`2026-09-27T09:47:56Z`，影响面清单 `temp/phaseC/unscoped_heal_affected.json`）；事前没留快照 ⇒ 无法逐条还原，
  这正是 BUG-81 立的那条面（`heal` 唯一不带 ns 的入口扫 `list_all()`）在真实库上的兑现，只补了作用域、补不回数据；
  ② `executor_run` 真跑分支仍只证到 `dry_run` 与记账路径（BUG-4 边界，真执行未获授权）；③ native 轨本轮未复跑；
  ④ BUG-88/89 的残余：跨语言词表门禁靠正则读两侧源码，形状是**约定**不是证明；rc 被管道吞掉这类读数姿势只能靠"落盘日志再读 rc"的习惯约束。

## v0.3.0 (unreleased) - 四模式流水线自我迭代 · Round 5（寻虫 → 修复 → 验证 → 打磨 + 勘误）

- **寻虫段**（承接 Round 4 验证段入账的 BUG-74/75，另起子代理扫插件态/路由/存储/看护面）：
  入账 **BUG-76~82 共 7 条**（3 high / 3 medium / 1 low，修复单 `T0r387~T0r393`）。子代理候选一律
  **先独立复验再入账**（不采信转述）：本轮 7 条全部打到调用面或读回真源行号才落账，形状分布在
  看护/编排的**承诺落空** 2 条（`pipeline_tick` 的 mode 从不读模板、`watchdog_tick` 的 mode 静默覆盖
  调用方显式 `meta_prompt_path` 且 detail 回显被忽略的那个路径）、存储面消毒缺口 1 条
  （`store_open` 只消毒 ns、`data_dir` 不过任何校验 ⇒ 可在仓库外任意目录落 `.db`）、
  判据自身是装饰 1 条（BUG-33 残留：28 处描述仍广告 `now`，而守卫的正则在真源上命中 0）、
  看护越界 1 条（`heal` 唯一不带 ns 的入口扫 `list_all()` ⇒ 一次调用回滚全库在途任务）、
  字面量冒充值 1 条（`selfdrive_export_tasks` 把 `"now"` 当导出时间写进 `memory/task.md`）。
- **修复段**（ns `pmode-r5-fix`，根 `T0r394`，18 叶 → 全树 25 已完成）：闭合
  **BUG-74/75/76/77/78/82 共 6 条**，逐条带**成对锁**（正向不误拒 + 反向必拒），承重证明先落码再复算：
  `temp/r5/mut_b75.py` 摘掉三个回执字段 + status 退回回显 ⇒ `og_1~og_3` **3 条发红**（finally 里逐字节复原）；
  `temp/r5/prove_j9.py` 逐一抠必查工具描述里的「返回」⇒ J9 逐条点名发红。**BUG-79/80/81 本轮只入账未修**
  并写明去处（79 需换"先校持有者再删"两段式 + SQLite 后端夹具；80 的正则一放宽就立刻 28 红，属批量文案工程；
  81 要加可选 `namespace` 参数、触碰公开工具签名面），三者转结下一轮，不静默消失。
- **验证段（本轮真正的收获在这里）**：ns `pmode-r5-verify`，根 `T0r395`，11 条判据交服务端 `run_check`
  真跑 + `output_validate` 正门/必然违例对照门。**首跑打印的「判据 11/11 / 结论 GREEN」是伪结论**——
  驱动取的是 `run_check` 回执顶层 `ok`（含义＝判据已跑完并落库），而通过与否在 `status`；
  同一份 `temp/r5/r5_round_report.json` 里 `j9_load_bearing` 的 `status` 就是 `failed`。
  两条线各自查到底：① 那条红不是 J9 退化，是承重证明脚本自己坏了 —— 对 `bug_list` 只 `replace(…,1)`，
  而它的描述里「返回」实测出现 **2 次**，抠掉一处仍含契约 ⇒ 变异不生效；② 误读面按 **BUG-83** 入账，
  修在真源描述（两个 ok 的分工写在脸上）＋ J9 第三判据 `RET_MUST_EXPLAIN`（抹词必红 / 良性追加不误红 /
  清单落空必红）。复算 `temp/r5/r5_recheck.py` 按 `status` 口径重跑同一批 ⇒ **11/11 passed**（`run_check` 在
  `call_log` 里累计 22 次，前后两跑都在账上）。
- **勘误落账**（ns `pmode-r5-erratum`，根 `T0r399`，12 叶全已完成）：已完成的 `T0r395.*` 正文里那句
  "全树 11/11" **不改写**（与账本"只追加不关闭"同一条路子），另起一棵勘误树把口径修正、真因与闭合判据落账，
  两条判据仍交服务端真跑（`temp/r5/b83_closure_check.py` 七断言 + `prove_j9.py`），硬门双态 `pass`/`fail`。
  闭合判据里刻意包含一条"**首跑的伪结论日志 `temp/r5/r5_round.log` 仍留痕**"，防止事后把证伪的那份抹掉冒充一直是对的。
- **勘误段又抓到一条自己上轮留的债（BUG-84）**：`AGENTS.md:299`、`AI-DEVELOPMENT-STANDARD.md:15`、
  `templates/pipeline_mode_tidy.md:45` 三处现状表面仍写文档面判据为 **J1-J8**，而真源 Round 4 就有 J9、本轮有 J10
  —— 同一族第二次（上一轮 J1-J5→J1-J8 也是人肉同步、没留判据）。修法是让范围数字本身可判：
  新增 **J10 判据范围自述==实现**（实现侧读本脚本 `def jN_`/`---- JN` 标记，声明侧扫 AGENTS/规范正文/templates/
  plugins-source 中含 `check_doc_surface` 的行），少写=声明滞后、多写=幻影判据、整块删掉=空扫描，三种都点名发红；
  承重证明 `temp/r5/prove_j10.py` 在真实文件副本上做四向变异。
  过程中正则初版写成 `J1-(\d+)` 而表面实际是 `J1-J8` 双 J 形态 ⇒ 声明恒抓不到，
  **正是"空扫描必红"那条哨兵把它当场抓住**，而不是让解析器坏了的判据以全绿蒙混。
- **全量与投影**：JS 后端 `moon test --target js` **458/458**（`temp/r5/full4.log`），六守卫 rc=0 +
  `check_doc_surface --selftest` PASS（J9 反向对照 2 → 4 条，另加 J10 五条对照）；缺陷账本
  **BUG-1~84 共 84 条**（25 high / 48 medium / 11 low；**30 待修 / 54 已挂 FIXED 小记**，本轮 8 条），
  四宿主插件态重投影后 cl7 逐字节一致（4 宿主 / 56 生成文件 / 120 工具 / v0.3.0），同真源两次投影内容哈希不变。
- **如实留下的缺口**：`executor_run` 真跑分支仍只证到 `dry_run` 与记账路径（BUG-4 边界默认收紧，真执行未获授权）；
  native 轨本轮未复跑；BUG-79/80/81 结转为流程债；GitHub 同步 `enabled=false`（凭据只走环境变量注入），
  `github_queue_status.total=0` 是"未开同步"而不是"无 bug 待同步"，两栏不许混读。

## v0.3.0 (unreleased) - 四模式流水线自我迭代 · Round 4（寻虫 → 修复 → 验证 → 打磨）

- **寻虫段**（ns `pmode-r4-bugfind`，重点覆盖本轮新合并的插件态与路由/执行器）：入账
  **BUG-61~72 共 12 条**（4 high / 5 medium / 3 low），修复单挂 `T0r375~T0r377` 等。形状分布：
  路由语义 4 条（只问不消耗却写盘、config_json 对象态被静默丢弃、executor 记账错位、ns 不做安全校验）、
  假绿测试锁 1 条、插件投影真源 2 条、守卫族 4 条、扫描器噪声 1 条。
- **修复段**（ns `pmode-r4-fix`，根 `T0r379`）：12 条逐条带**成对回归锁**修复，修复中新发现并当场收口
  **BUG-73**（`pool_pick` 循环变量不参与下标 ⇒ 游标停在耗尽格时整档判死、免费池还有满血模型就切付费档）。
  锁先落码再改产品：rt_15 在未修复码上实测红（`"paid-a" != "free-ok"`）。13 条全部走 Omega 链，
  根下 **21 张叶 → 已完成 21 / 未闭合 0**。承重证明两条并列：`temp/r4/prove_locks_red.py`
  （退回修复前形态 ⇒ mo_2/4/6/7/8/9 六条全红）、`prove_locks_red2.py`（4 组合成违例各钉一条新锁）。
- **验证段**（ns `pmode-r4-verify`，根 `T0r382`）：六条泳道、**13 条判据交给服务端 `run_check` 真跑**
  （不让指挥官自己 subprocess —— 那正是"防自写自测恒绿"要防的事），全 passed；调用面另计
  `temp/router_smoke.py` 27/27、`temp/r4/verify_r4_callsite.py` 14/14、`scripts/mcp_smoke.py` PASS。
  `output_validate` 正门 `verdict=pass`，**同批配一条必然违例对照门** `verdict=fail`（抽掉一条真结果 +
  引用不存在的 check_key/path），证明这道门不是空的。自证走 `call_log`：最近 400 行覆盖 27 个工具，
  本轮关键能力（publish/laya_decide/task_plan_deep/run_check/output_validate/issue_scan/
  project_standards/bug_list/report_bug/github_queue_status）在表里逐条可查，17 条 ok=false 全部来自
  刻意的负路径探针与两处本方键名取错（不是产品静默失败）。树最终 **29/29 已完成**。
- **两条新判据留在验证段**（下次可复跑）：`temp/r4/v4_idem_plugins.py` —— 同一棵真源连跑两次
  `gen_plugins`，生成文件内容哈希必须不变（cl7 每次拿最新产物当基准，抓不到生成过程自身的不确定）；
  `temp/r4/v4_ledger_three_way.py` —— 从账本反解总数/待修/FIXED，与 9 份投影文件的 17 处投影句逐字相等，
  缺戳或枚举面过小即 FATAL。
- **验证段又抓到 2 条**（只入账不就地改，交 Round 5 修复段）：**BUG-74** `task_plan_deep` 描述只列参数
  不写返回形状，指挥官脚本按自然键名取值当场打印"直接子任务 0 个"而服务端其实已建 21 叶；
  **BUG-75** `run_check` 回执不含 stdout/stderr、落库的完整结果又无工具可读回 ⇒ 判据红了举不出红在哪，
  无人值守只能本地重跑（等于把证据梯降级回自述）。
- **全量与投影**：JS 后端 `moon test --target js` **453/453**（`temp/r4/full4.log`），六守卫 rc=0 +
  四份 `--selftest` 全 PASS；缺陷账本 BUG-1~75（29 待修 / 46 已挂 FIXED 小记），四宿主插件态重投影后
  cl7 逐字节一致（4 宿主 / 56 生成文件 / 120 工具 / v0.3.0）。
- **如实留下的缺口**：BUG-61 的 `executed=true` 真跑分支无端到端证据（宿主执行器真跑未获授权，
  BUG-4 边界默认收紧，只证到记账路径与 dry_run）；native 轨本轮未复跑，不据旧数宣称双端同版全绿；
  GitHub 同步 `enabled=false`（凭据只走环境变量），队列为空是"未开同步"而不是"无 bug 待同步"，两栏不许混读。

## v0.3.0 (unreleased) - 双远端同步（GitCode）+ 遗留 OPEN 缺陷 BUG-50/51 闭合

- **同步**：本轮起仓库同时发布到 **GitCode**（`https://gitcode.com/VictorTop/Fist-Mbt.git`，
  远端名 `gitcode`）与 GitHub `origin`。GitCode 侧 HTTPS 无凭据可用（凭据只走环境变量注入，
  仓库不读 `.env`），故 remote 配 `URL=https` + `pushurl=git@gitcode.com:…`，推送用 SSH；
  两侧 hooks 均 PASSED，本地附 `v0.3.0` 标签。
- **BUG-50 收口（判据重设计）**：`scripts/check_test_sync.py` 从"实测数出现在 4 份白名单文档"
  升级为四条判据 —— R1 全量反向扫 **99 份现状文档**（含本轮新补的 `README_EN.md`/`BACKLOG.md`，
  此前整面在扫描口径之外，里面的 `307 tests / 104 tools / 316 aligned` 无人认领）、
  R2 五份 must-carry 文档必须携带实测数（防止"删掉声明"消解违例）、R3 防空转（现状面一条声明都没有
  即红：正则饿死 ≠ 没有问题）、R4 豁免表 `(文件, 数, 理由)` 逐条点名且**条目失效即红**。
  新增 `--selftest`：**8 个违例变体各命中自己指名的判据**（含"自洽的谎"型与"不得误抓引文/年份/编号"
  反向对照），已挂进 ci.yml。首跑即抓到旧白名单看不见的两份文档写着 `148/148`、`191/191` ⇒ 已按实测改写。
- **BUG-51 收口（路径口径统一）**：`run_check` 的 `workdir` **相对路径一律按任务 `project_dir` 解析**
  （`.` 就是该项目目录本身，与 project_dir 绝对/相对无关），并新增 `run_check_effective_workdir`
  把归一后的绝对路径交给 spawn ——只改判定不改执行面就是新漏洞（判据说"在里面"、进程跑在 server cwd）。
  反向仍拒且文案自带两条出路：绝对 workdir 配相对 project_dir 无法判定归属；`..` 冲出自身起点在拼接前就拒。
  两条口径（`run_check.workdir` 相对任务项目 vs `report_bug/output_validate.project_dir` 相对 store 根）
  在规范正文 §5、工具描述与参数描述三处同时写明。
- **回归与验收**：新增 3 个用例块（ALLOW/REJECT 成对 + 归一 + 拒绝文案出路）；
  **开关对照**不动工作区源码（`temp/b51_red/` 用 HEAD 判定 + 新版归一组包，同一份测试在其上
  `10 tests / 2 failed`，红的正是缺陷本体那两条）；**调用面终审** `temp/b51_callsite.py`
  打真实 MCP 入口 13 条判据 0 红，含 S02b（harness 特意把 server 起在 `temp/`，排除
  "继承 server cwd"的替代解释）。JS 后端 `moon test --target js` **442/442**，六守卫 rc=0。

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
