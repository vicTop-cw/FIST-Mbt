# scripts/ 脚本分类规范

> 目的：项目整洁——临时脚本任务完即清理，正式工具统一管理，避免根目录/scripts 堆垃圾。

## 命名约定

| 前缀 | 含义 | 处理 | 示例 |
|---|---|---|---|
| **无前缀** | 正式、可复用工具 | 保留，写入 README 说明 | `mcp_smoke.py`、`patch_esm_main.py`、`omega_lesson_verify.py`、`demo.ps1`、`gen_apply_pdf.py` |
| **`_` 前缀** | 临时/一次性/诊断脚本 | **任务完即删**，或移入 `temp/`（gitignored） | `_diag_*.py`、`_scratch_probe.py` |
| `m9_* / m18_*` | 历史迁移遗留 | gitignore 覆盖；无需再产生 | — |

## 约束（Golden Rule）

1. **不产生带 `_` 前缀的正式工具**：`_` = 临时代码生成物，用完即删。
2. **临时产物落 `temp/` 或系统 tmp**：不要污染仓库根；`temp/` 已在 `.gitignore`。
3. **正式工具**：无前缀 + 文件头 docstring 说明用途/用法/前置 + 退出码约定。
4. **改完即验**：新增/改动脚本后，确保它能在干净环境跑（依赖公开）。
5. **不留绝对路径**：脚本内路径用 `os.path.join(dirname, ...)` 或环境变量，禁止硬编码盘符。

## 现有正式工具速查

**基础 / 演示**
- `mcp_smoke.py` — MCP server 一键自检（129 工具 + publish/get 链路 + issue_scan 命中校验）。**已知边界（BUG-93）**：候选入口是 `_build/js/debug/build/cmd/cli/cli.js` 且不带 `serve` 子命令，而发布产物是 `cmd/cli/cli.js`（见 `blackbox/build_release.ps1`）⇒ 它绿不等于装好的 `fist-mbt` 全局命令能用；调用面全量巡回请用 `mcp_tool_tour.py`。
- `mcp_tool_tour.py` — **全工具调用面巡回**：从 `tools/list` 的 `inputSchema.required` 反解参数，把 129 个工具逐个真打一遍，三面分栏记账（`ok` / `refused`=按设计拒绝 / `skipped`=授权边界内主动不打 / `crashed`=进程死掉后复活继续数）。写面跑在临时 box + `FIST_DB_PATH` 隔离库，仓库根 `fist-mbt.db` 一行不动。用法：`python scripts/mcp_tool_tour.py --plane write --json`（0=无崩溃/无未打到，1=有，2=入口或工具数自证失败）。
- `store_isolation_probe.py` — **存储隔离调用面探针（BUG-90 活判据）**：同一个 cwd 两格只差 `FIST_DB_PATH`，断言行落被指定的库且 cwd 里不得长出默认库；`--selftest` 追加合成违例（库路径指到不存在的目录 ⇒ 必须报红）。用法：`python scripts/store_isolation_probe.py --selftest`（0=两格符合预期，1=违例未被抓到或隔离失效，2=找不到 server 产物）。
- `check_ps_encoding.py` — **PowerShell 脚本编码守卫（BUG-88 分发面同源）**：Windows PowerShell 5.1 读无 BOM 的 UTF-8 `.ps1` 会按 ANSI(cp936) 解，多字节序列吞掉字符串收尾引号 ⇒ 用户在 `irm | iex` 那一步直接 ParserError，产品码一行没跑。判据：每个 `.ps1` 要么纯 ASCII，要么带 UTF-8 BOM；扫描面为空即 FATAL(2)（一个都没抓到 ≠ 没有问题）；`--selftest` 用合成违例 + 合规不误红 + 增删 BOM 变异三条自证。用法：`python scripts/check_ps_encoding.py [--selftest]`（0=PASS，1=违例，2=判据无法自证）。
- `issue_scan.py` — **规则驱动源码扫描 CLI（打磨收尾：issue_scan 三形态之 CLI）**：薄封装 MCP 工具，扫描逻辑单真源在 MoonBit 端；用法 `python scripts/issue_scan.py <dir> [--max-findings N] [--include-tests]`（默认跳过测试文件，`--include-tests` 连 `_test/_wbtest` 一起扫），先 `moon build --target js cmd/cli`。skill 文档见 `docs/issue-scan-skill.md`。
- `award_demo.py` — **获奖自驱 DEMO（评审一条命令演示）**：串演 map→递归拆解(gradient)→验收闭环→Challenger→Critic→作用域预订→脉冲/看板 全链路，结尾自动清理临时区并 `--check` 守卫仓库干净。用法：`python scripts/award_demo.py`。
- `cleanup_artifacts.py` — **项目整洁/生成物清理**：删除仓库根"除交付库 `fist-mbt.db` 外"的全部被 gitignore 的 `*.db / -shm / -wal` 测试/演示残留，清空 `temp/`，并把 `scripts/` 下 `_` 前缀临时脚本移入 temp/ 后清理（任务完即清策略，R66）；`--check` 模式作 CI 干净度守卫（0 = 干净，非 0 退出码 1）。用法：`python scripts/cleanup_artifacts.py` / `python scripts/cleanup_artifacts.py --check`。
- `score_gate.py` + `scoring_rubric.md` — **4-AI 概率自评分门禁**：统一 rubric 提示词（维度/稍宽口径/SCORE_JSON 契约）作为正式工具统一管理（原 `_ai_prompt.md` 从临时命名升级）；全档达标 AND 聚合、error 不降级。
- `patch_esm_main.py` — moonc≥0.10.14 ESM 输出注入 createRequire shim（幂等）。
- `check_badge.py` — **README 测试徽章一致性守卫（R34）**：比对 `moon test` 实测测试数与 README 徽章 `tests-N%2FN`，不一致即退出码 1（挂 CI 作"徽章不过时可复现"门禁，杜绝手改漏同步）。已经在 `.github/workflows/ci.yml` 的 JS 轨道里自动执行。
- `check_tools_sync.py` — **工具清单单一真源守卫（R46）**：以 `src/server/server.mbt` 实际注册工具名为唯一真源，校验 AGENTS 表格工具名 ⊆ 真源、真源全部入 AGENTS、README/AGENTS/deliverable/scoring_rubric 工具总数==实测（双向防幽灵/漏写）。已在 ci.yml JS 两轨自动执行。
- `check_test_sync.py` — **测试总数单一真源守卫（R47；BUG-50 收口时判据重设计）**：从 `moon test` 日志
  或 `--total N` 取实测总数，四条判据——**R1** 反向扫全部现状面文档（含 README_EN/BACKLOG，99 份），
  每条测试总数声明必须 == 实测（窄口径四种形状：`N/N` 等值对、`N 项|个|条 [测试|用例] 全绿|通过|passed`、
  `total=N`、日志回显 `Total tests: N, passed: N`；不等值对是引文/年份/编号，不算声明）；
  **R2** must-carry 5 份文档必须携带实测数（不许靠删声明消解违例）；**R3** 防空转（现状面一条命中声明
  都没有即红）；**R4** 历史数/别的 target 必须在 `EXEMPT` 里逐条点名 `(文件, 数, 理由)`，条目失效也判红。
  历史记录（`memory/`、`reports/`、`CHANGELOG.md`、`docs/superpowers/plans/`、`YYYY-MM-DD` 前缀文件）
  整面豁免。`--selftest` 用 8 个违例变体证明判据会红（含"自洽的谎"型与"不得误抓引文"反向对照）。
  已在 ci.yml JS 轨自动执行（真判据 + selftest 两条步骤）。
- `check_scripts_index.py` — **工具类辅助代码单一索引守卫（R62）**：校验 `scripts/README.md` 已登记全部「正式」辅助脚本（无 `_` 前缀），防新生脚本不留说明就堆积——把地图/整洁下沉到工具层。用法：`python scripts/check_scripts_index.py`（0=PASS，1=漏登记）。
- `check_plugin_sync.py` 的索引缺口补齐登记（本轮 cl7 落地时实测出的历史欠账）：
- `flush_github.mjs` — **GitHub 缺陷外发通道 Node 入口**：走 MCP stdio 调 `github_flush_execute`，把 `report_bug` 入账的缺陷推到远端 issue。用法：`node scripts/flush_github.mjs [--limit 50] [--timeout-ms 30000]`（需 `GITHUB_TOKEN`，凭据只从环境注入）。
- `output_validate.py` — **交付物硬门 CLI 形态**：`output_validate`(R113) 的命令行入口（与 MCP/skill 同一真源），逐件校验 path/check_key + invariant，退出码即门禁结论。用法：`python scripts/output_validate.py <project_dir> --artifacts '[{"path":"README.md","contains":"FIST"}]'`。
- `mcp_bug_loop.py` — **修复闭环历史验证脚本（Round 1）**：对 5 个已修 bug 逐个走 publish→claim→execute→submit→verify 的 MCP 客户端；保留作活证据，非日常工具（一次性验证，跑前注意命名空间隔离）。
- `pentad_fist.py` — **Pentad 衍生项目 MCP 客户端**：基于 `mcp_smoke.py` 的 rpc 模式注册 Pentad 项目并开 `omega_strong_verify` + `call_log`，供跨项目自驱演示。
- `test_mcp_bugs.py` — **缺陷相关工具的 MCP 冒烟测试**：对 `report_bug/bug_list/run_check` 等做端到端调用；与 `mcp_bug_loop.py` 同批历史脚本，保留作证据。
- `gen_plugins.py` — **一源四态·插件态生成器（cl7 生成侧）**：以 `src/server/server.mbt` 工具数 / `moon.mod` 版本 / `memory/bugs.md` 账本 / `plugins/source/` 正文 / 根 `.mcp.json` 启动参数为唯一真源，生成 atomcode→codearts→deepseek-harness→claude 四宿主插件目录（字节稳定、无时间戳）。插件目录是**投影**，手改必被 `check_plugin_sync.py` 拦。用法：`python scripts/gen_plugins.py [--check]`（0=已生成/无漂移，1=--check 发现漂移，2=真源解析失败）。
- `check_plugin_sync.py` — **一源四态·插件态一致性守卫（cl7）**：子进程重跑 `gen_plugins.py --check` 做漂移判定，另校验四宿主入口齐全、无残留 `{{占位符}}`、claude manifest 版本==moon.mod、`plugins/claude/.mcp.json` 与根 `.mcp.json` 逐字节相等、每个生成 SKILL.md 的 `tools=` 等于实测工具数；实测<=100 直接 FATAL(2) 不自证为绿。用法：`python scripts/check_plugin_sync.py`（0=PASS，1=漂移/缺项，2=判据无法自证）。
- `check_doc_surface.py` — **文档面一致性守卫（Round 2 验证模式产物，BUG-22/30 的机械化闭环）**：以 `server.mbt` 注册表为真源，校验 ① 每个工具在 AGENTS **和** README 逐个可查（防"标题数字对、正文没跟上"）；② README 功能全景分组计数之和==实测；③ 各文档自述版本==`moon.mod`（历史/时间线文件豁免）；④ 反幻影哨兵——真源解析到 <=100 个工具即 FATAL(2)，绝不因空清单报 PASS。用法：`python scripts/check_doc_surface.py`（0=PASS，1=漂移，2=无法自证）。**R116 新增**：J6 规范正文(`AI-DEVELOPMENT-STANDARD.md`)↔机器投影(`project_standards.mbt`) 的 id/版本一致；J7 规范性表面（README/AGENTS/docs/templates/对外工具描述）禁残留「三形态/一源三态」旧口径；J8 `templates/*.md` 里对已注册工具的调用示例与参数表，顶层参数必须 ∈ 真源 schema 且不缺 required（`_instrument` 只校验 required，未知键静默丢弃）；`--selftest` 对合成违例必须发红；J9 `server.mbt` 每个工具描述的**返回契约**——必查清单必须写「返回 {…}」（认中文「返回」）、歧义键（如 `run_check` 的 ok/status）必须分工、写了契约的工具数走棘轮只许升；J10 AGENTS/模板/插件真源里「J1-JN」式范围声明 == 本脚本反解出的实现上界（少写=声明滞后，多写=幻影判据）；J4 子判据：注册表**发布版本**只在 `BACKLOG.md` 一处自述（本机无注册表复核通道，第二处只能与权威面打架）。ci.yml 先跑 `--selftest` 再跑全量（BUG-89：自检从不被执行 = 自检坏了也报绿）。
- `check_store_tables_wired.py` — **store schema 接线守卫（BUG-28）**：以 `src/store/store_sqlite.mbt` 的 CREATE TABLE 清单为真源，逐张表对两件事——要么在 `src/**` 里有写入点（INSERT/UPDATE/DELETE/REPLACE），要么在 store 源文件里用机器可读的 `schema-reserved: <表名>` 显式声明为预留。两个方向都发红：「无写入点且未声明」= 第二张 runs（恒 0 行的死 schema 被当可用能力）；「声明预留却有写入点」= 声明滞后。解析不到任何表 ⇒ FATAL(2)（空扫描面不出绿）。`--selftest` 用合成违例证明判据会红、干净输入不误红。用法：`python scripts/check_store_tables_wired.py`（0=PASS，1=违例，2=无法自证）。
- `demo.ps1` — 一键演示（build+patch+smoke）。
- `calibrate_goal_drift.py` — **判据标定器（BUG-25，非 CI 守卫）**：以 `fist-mbt.db`（只读、机器本地）为语料，实测 `goal_drift_check` 词法判据的假阳性/检出分离度，输出三组样本（全量父子对 / 改写型父子对 / 随机错配对照）+ 族内相对离群规则的对照结果。口径与 `src/evolve/evolve.mbt` 的 `tokens/coverage`、`engine_dag_ext.mbt` 的 `drift_similarity` 逐字对齐——**改判据常量必须先重跑本脚本**，注释里的 1.9%/59%/81.3% 是它打印出来的，不是手写的。因语料不入库 ⇒ 故意不挂 CI（挂了就是一台机器上恒红的装饰）；用法：`python scripts/calibrate_goal_drift.py`（0=标定完成，2=语料缺失、判据无法自证）。
- `showcase.ps1` — **30~60 秒视觉终端巡演**：Header/徽章、九态生命周期、DAG、自举采用（读盘真实 548 tasks/196 exec/6 review）、自治派送闭环（triage→dispatch_next→executor_route→watchdog autodispatch 零参数），ANSI+box；实测 exit 0 / ~1.7s，无盘符。用法：`pwsh -NoProfile -File scripts/showcase.ps1`。
- `fist-mbt-http.py` — **HTTP/SSE 传输服务**：把 stdio MCP server 桥接成 HTTP，`GET /health` 健康检查 + MCP over HTTP/SSE。
- `laya_decide.py` — **Laya 决策 sidecar**：把 Laya ML 模型包成可被 fist-mbt MCP server 调用的 JSON sidecar（冷启动选档/探测）。
- `native-env.ps1` — Windows native 环境一键装载（VS + sqlite-dev）。
- `gen_apply_pdf.py` — 一页项目申报书 PDF 生成（个人档，不入库）。
- `check_entry_paths.py` — **入口清单守卫（BUG-93/101）**：可执行入口清单从 `cmd/*/moon.pkg` 的 `pkgtype(kind:"executable")` 反解，发布入口从 `scripts/blackbox/build_release.ps1` 反解，其余为退役入口。R1 禁现状面（脚本/文档/CI/根 .md/.mcp*.json）用命令或产物路径指向退役入口；R2 禁 `Popen([node, cli.js])` 的 argv 少 `serve`（cmd/cli 裸跑只打印 help，客户端第一行就不是 JSON-RPC）。历史面（memory/ reports/ CHANGELOG.md）与守卫自身不判；扫描面为 0 或退役清单为空 ⇒ FATAL（判据空转绝不报绿）。`--selftest` 四格自证。用法：`python scripts/check_entry_paths.py [--selftest]`（0=PASS，1=违例，2=判据无法自证）。
- `check_release_asset_names.py` — **发布资产名同源守卫（BUG-103）**：安装器（`install_onecmd.ps1` / `install.sh`）与 `build_release.ps1`/`release.yml` 必须共用 `fist-mbt-js-v<moon.mod 版本>.zip` 这一个资产名；R1 禁给版本号写字面量默认值（写死一个字 ⇒ 用户跑不带参数的 `irm | iex` 永远 404）、R2 必须真的解析 `moon.mod` 里的 `version = "…"`、R3 三处资产名模板同源、R4 版本解析为空必须 `exit 1`（不许静默用猜的版本）。必读文件缺席即 FATAL（判据无法自证不出假绿）；`--selftest` 六格变异 + 干净不误红。用法：`python scripts/check_release_asset_names.py [--selftest]`（0=PASS，1=违例，2=判据无法自证）。

**自驱闭环（selfdrive）**
- `log_fix_selfdrive.py` — call_log 缺陷修复自驱闭环。
- `enhance_verify.py` — 三块增强 E2E 验证。
- `enrich_selfdrive.py` — 获奖提升增强自驱闭环。
- `atgc_selfdrive_demo.py` — ATGC 极简双链虚拟机自驱+Omega DEMO。
- `lesson_selfdrive.py` / `scratch_selfdrive.py` — 失败回流 / 临时隔离 技能自驱闭环。

**能力 E2E 验证（verify）**
- `map_verify.py` — 项目地图（`fist://map`）E2E。
- `lesson_verify.py` — 失败回流（evolve_lesson 独立工具）E2E。
- `lesson_chain_selfdrive.py` — 打回→lesson 归档→dead_ends 闭环演示。
- `dag_depend_verify.py` — DAG 显式依赖 E2E。
- `scratch_verify.py` — `store_open(scratch)` 临时隔离 E2E。
- `omega_lesson_verify.py` — **Omega 打回自动落 [lesson] + 进程内可见** E2E（三类打回自动沉淀 + scratch 隔离 + 结束精确清理根库）。
- `plan_gradient_verify.py` — `task_plan_deep gradient=true` 难度梯度 + 更简单变体 E2E（默认关闭零回归 + scratch 隔离）。
- `evolve_critic_verify.py` — `evolve_critic` Critic 防漂移门禁 E2E（84 工具 + 放行/拒收/收紧阈值 + 只评审不写库）。
- `task_challenge_verify.py` — `task_challenge` Challenger 进阶变体 E2E（84 工具 + [challenge]溯源/扩规模 + 未完成任务拒绝 + scratch 隔离）。
- `executor_route_verify.py` — **执行者能力路由（Marketplace 雏形）E2E**：`executor_register` 登记能力 + `executor_route` 按「能力覆盖率 desc → 负载 asc」路由最佳执行者（84 工具）；R31 跨进程三步：进程A注册→进程B路由读到→clear 消失。
- `dispatch_verify.py` — **能力自动派单（R32）E2E**：`selfdrive_dispatch` 按 want 能力路由并把任务直接认领给最佳执行者（待领取→已领取）；运行后会向交付库写演示任务，完成即 `git checkout -- fist-mbt.db` 恢复整洁。
- `board_ascii`（内建 MCP 工具 + 测试）— 实时任务看板 ASCII：按状态分组 + 深度缩进，一眼看全貌（`src/server/board_ascii_test.mbt` 全绿）。

> 所有 `*_verify.py` 共用同一 MCP STDIO 启动模式（`moon build --target js cmd/cli` + `patch_esm_main` → node）。