# FIST-Mbt

> **fist-mbt —— AI 自驱式开发的项目管理者**：一等的打磨对象只有两件——**自驱**与**递归拆解**，
> 而它迭代自己所用的，正是这两件能力（实证见下文引言）。

[![Made with MoonBit](https://img.shields.io/badge/MoonBit-0.1.20261016-blue)](https://www.moonbitlang.com)
[![License](https://img.shields.io/badge/License-Apache--2.0-green)](./LICENSE)
[![Tests](https://img.shields.io/badge/tests-1743%2F1743-brightgreen)](./src)
[![CI](https://github.com/vicTop-cw/FIST-Mbt/actions/workflows/ci.yml/badge.svg)](https://github.com/vicTop-cw/FIST-Mbt/actions) (js ×2 + native)

**FIST-Mbt** 用**纯 MoonBit** 重写并 MCP 化的 **AI 指挥官任务编排底座**——不是又一个 agent 框架，而是"人类指挥、AI/定时器持续自推动"的自治系统。完整闭环：**发布→认领→拆分→执行→提交→验收→归档**，叠加 **自驱审视、DGM 演化采样、Omega 强验证、跨进程看门狗**。全部以 **173 个 MCP 工具**（18 组）暴露给任意 MCP 客户端。

**为什么 MoonBit**：任务编排天然"正确性敏感"（状态机、权限矩阵、追加式审计、递归拆解），MoonBit 的强类型、无运行时依赖、JS+Native 双端交叉编译让这套逻辑在 Windows 与 Linux 上以 JS 目标 1743 项测试全绿、跨环境可复现。

> 它用**它自己的**自驱式 + 递归拆解把自己打磨到了可交付态——完整自我迭代证据见 `docs/selfdrive-walkthrough.md`，CLI `python scripts/fist.py call project_standards` 可一键拉取本项目遵守的 AI 开发规范。
> 「它说自己有效」不算证据：本项目的**叙事与实证面**在伴生仓 **fist-evidence** <https://github.com/vicTop-cw/fist-evidence>——三组受控实验 + 十份真实项目驱动实例（覆盖八项目），报告/日志/裁判测试一字可回溯（详见「资源」节）。

---

## ⚠️ 环境要求（先看这一节：装错工具链会直接编不过）

- **MoonBit ≥ 0.1.20261016**——本仓使用 `is` 模式匹配表达式（`d799f56` 起替代已移除的 `is_ok` / `is_err`），更早的工具链在 `moon check` 阶段就会红。新环境先 `moon update` 刷新 registry（依赖全公开，无私有包）。
- **Node.js ≥ 24**（JS 目标必需）——SQLite JS 后端依赖 `node:sqlite` 的 `returnArrays`；node < 24 会退化为对象行，列读取为空。
- **Native 目标**：系统 SQLite 开发库（`sqlite3.h` + `sqlite3.lib`）。一键装载：`pwsh ./scripts/native-env.ps1`；Windows 需 VS Build Tools，细节见 AGENTS.md「native 目标构建环境要求」。
- **Windows 上跑 `moon test --target js`**：若 PATH 上的 `node` 是 `node.cmd` / `.bat` 垫片，测试参数经 `cmd.exe` 转发会吞掉引号（BUG-380）⇒ 用 `python scripts/moon_test_env.py --target js`（自动剔除垫片并注入 `MOONC_OVERRIDE`，同时绕开 moonc 的 `\\?\` 路径 ICE）。

> **JS 后端**：`moon test --target js` = **1743/1743**（2026-10-28 Windows 实测；权威稳定门槛 = JS 后端）。
> **Native 后端**：2026-10-01 在 WSL ubuntu-22.04 实测 `moon test --target native -j 1` = **572/572**（与 JS 同数，工作树含上几轮构建残留时）；
> 同一 commit 的 `git archive HEAD` **干净树**上同一条命令必崩（native 测试二进制被信号打死），根因在依赖的 native FFI，
> 见账本 BUG-133 与判据 `scripts/blackbox/e2e_native_heap_probe.py`；上一版这句写的是「native 未复跑」，就此作废。边界条款见 `AI-DEVELOPMENT-STANDARD.md` §7「已知边界」。
> **CI 的 native 臂已按 2026-10-01 owner 裁决③改造**：两条臂都在全量测试前挂 `Native heap gate (BUG-133 探针当门)`，
> 跑的就是上面那支判据；红话逐字点名 BUG-133，`crashes=0/12` 才放行全量测试（测试步骤没删，依赖修好后这一臂自己恢复覆盖）。

---

## 一源四态（One Source, Four Forms）

FIST-Mbt 的每个功能都有**四种调用形态**，核心逻辑**只写一遍**（MoonBit 单真源），CLI/Skill/Plugin 都是薄封装或**生成投影**：

| 形态 | 是什么 | 谁用 | 示例 |
|---|---|---|---|
| **MCP**（主形态） | MoonBit server 暴露的 JSON-RPC 工具 | Claude Desktop / Trae / AtomCode / 任何 MCP 客户端 | `tools/call output_validate` |
| **CLI** | Python 薄封装脚本（拉起 server → 调工具 → 打印 JSON） | CI 管道、手动验证、无 MCP 客户端场景 | `python scripts/output_validate.py . --artifacts '[...]'` |
| **Skill** | Markdown 文档（何时用 / 怎么用 / 怎么闭环） | AI agent 读的使用手册；真源 `plugins/source/` | `docs/output-validate-skill.md` |
| **Plugin**（宿主插件态） | 四宿主插件目录，由 `scripts/gen_plugins.py` 从真源**生成**（禁手改，cl7 守卫拦漂移） | AtomCode / CodeArts Doer / DeepSeek Harness / Claude | `plugins/claude/.claude-plugin/plugin.json` |

**四态对齐检查清单**（7 项硬门，正文真源 [`AI-DEVELOPMENT-STANDARD.md`](AI-DEVELOPMENT-STANDARD.md)，机器投影 `project_standards` R116）：
1. ✅ MCP 工具注册了？ → `server.mbt` instrumented_tool 块
2. ✅ CLI 封装到位？ → `scripts/fist.py call <tool>` 或独立 `scripts/xxx.py`
3. ✅ Skill 文档写了？ → `docs/xxx-skill.md`
4. ✅ `moon test` 全绿？ → 1743/1743 零回归（`--target js`，本轮 CI 实测）
5. ✅ 交付物过 `output_validate` L4 硬门？ → verdict=pass
6. ✅ README / AGENTS.md 计数同步？ → 工具数、测试数
7. ✅ 插件态已重生成且与真源一致？ → `python scripts/gen_plugins.py && python scripts/check_plugin_sync.py`（cl7）

---

## 功能全景（173 个 MCP 工具 · 18 组）

### 生命周期（14）
`publish` · `publish_parallel` · `plan` · `claim` · `execute` · `submit` · `verify` · `reject` · `retry` · `pause` · `resume` · `reopen_task` · `archive` · `delete`

### 查询（2）
`list` · `get`

### 运维·编排（14）
`task_plan_deep` · `conflicts_check` · `heartbeat` · `heal` · `watchdog_tick` · `task_cleanup` · `phi_accrual` · `saga_register` · `saga_rollback` · `saga_repair` · `circuit_fail` · `circuit_succeed` · `circuit_status` · `tx_contract`

### 自驱闭环（9）
`selfdrive_init` · `selfdrive_append` · `selfdrive_get` · `selfdrive_export_tasks` · `selfdrive_review_tick` · `selfdrive_review_ready` · `selfdrive_publish_next` · `selfdrive_parse_next_tasks` · `selfdrive_pick_next`

### 运维·验证·规范（28）
`call_log` · `bug_list` · `bug_fix` · `bug_mark_status` · `report_bug` · `issue_scan` · `ocr_scan` · `boundary_probe` · `eval_feedback` · `run_check` · `output_validate` · `project_standards` · `text_diff` · `rank_of` · `soldier_type_of` · `soldier_route` · `staff_label_of` · `schedule` · `pipeline_tick` · `cost_stats` · `cost_budget_check` · `cost_budget_split` · `progress_gate` · `laya_decide` · `loop_create` · `loop_tick` · `loop_status` · `mcp_config_scaffold`

### 模型路由·外部执行器（5）
`model_auth_status` · `model_route` · `model_router_status` · `model_router_reset` · `executor_run`

### 衍生（3）
`atgc_old_compile` · `atgc_old_run` · `atgc_old_talk`

### 看板·DAG·规划（27）
`dag_critical_path` · `dag_parallelism` · `dag_ascii` · `dag_check` · `dag_ready` · `dag_sort` · `dag_depend` · `dag_publish` · `dag_slack` · `dag_schedule` · `dag_cost_route` · `dag_mc` · `plan_revise` · `goal_drift_check` · `board_ascii` · `state_flow_ascii` · `status_summary` · `project_health` · `health_check` · `reserve_scope` · `reserve_check` · `reserve_release` · `lock_acquire` · `lock_renew` · `lock_release` · `lock_status` · `task_triage`

### 自我记忆·自进化（11）
`memory_consolidate` · `memory_gc` · `memory_link` · `evolve_distill` · `evolve_lesson` · `evolve_critic` · `evolve_sample` · `evolve_snapshot` · `evolve_submit` · `evolve_asset_register` · `task_challenge`

### Marketplace·能力路由（5）
`executor_register` · `executor_route` · `executor_auction` · `executor_clear` · `selfdrive_dispatch`

### 审计·多租户（8）
`agent_acl_grant` · `agent_register_key` · `agent_revoke_key` · `audit_permission` · `audit_log` · `store_open` · `store_list` · `store_close`

### GitHub/GitCode 同步·缺陷外发（12）
`github_env_check` · `github_queue_status` · `github_flush_plan` · `github_flush_execute` · `github_queue_mark_sent` · `github_issue_close` · `github_issue_comment` · `github_issue_webhook_parse` · `gitcode_env_check` · `gitcode_queue_status` · `gitcode_flush_plan` · `gitcode_queue_mark_sent`

### 开发模式与模板（2）
`mode_list` · `mode_templates`

### Omega 强验证（6）
`omega_spec_create` · `omega_spec_review` · `omega_result_verify` · `omega_status` · `omega_verify` · `omega_verify_fix`

### 六顶帽 · 辩论裁决（7）
`hat_list` · `debate_convene` · `debate_register` · `debate_verdict` · `hat_run` · `hat_debate` · `hat_merge`

### 超级管家专属工具（8）
`supervisor_status` · `supervisor_task_tree` · `supervisor_kill_plan`（只出方案不执行）· `supervisor_prompt_inject` · `supervisor_prompt_list` · `supervisor_prompt_consume` · `supervisor_task_upsert` · `supervisor_reminder_tick`

### 项目助理（5）
`assistant_claim` · `assistant_status` · `assistant_sweep` · `assistant_resign` · `assistant_heartbeat`

### 嵌入式 MCPCf 内部工具（7）
`mcpcf.ops_init` · `mcpcf.circuit` · `mcpcf.report` · `mcpcf.review` · `mcpcf.run_batch` · `mcpcf.verify` · `mcpcf.watchdog`

---

## 快速开始

```bash
# 1. 构建 + 测试
moon update            # 首次：刷新 registry 索引
moon build --target js cmd/cli
moon test --target js  # → Total tests: 1743, passed: 1743, failed: 0

# 2. 启动 MCP Server（STDIO）
python scripts/patch_esm_main.py  # ESM shim（moonc ≥0.10.14 输出 ESM，sqlite JS 桩用 CJS）
node _build/js/debug/build/cmd/cli/cli.js serve   # 必须带 serve：裸跑只打印 help

# 3. 或用 HTTP/SSE 桥接
FIST_MCP_PORT=3000 python scripts/fist-mbt-http.py

# 4. CLI 通用网关（一源四态·CLI 形态）
python scripts/fist.py list-tools                     # 全量工具名清单（数量以本命令末行为准，不抄数——抄一次就是下一次漂移）
python scripts/fist.py call project_standards          # AI 开发规范
python scripts/fist.py call store_open --namespace scratch --scratch true
python scripts/fist.py call output_validate --project-dir . --artifacts '[{"path":"moon.mod","contains":"vicTop-cw"}]'
```

### 在 DeepSeek Harness 里安装（插件态）

npm 包自带预构建 CLI（`dist/fist-mbt.js`），装插件不需要 moon、不需要源码构建：

```bash
dsh plugin --profile web add fist-mbt        # 命令行宿主；桌面端在「设置 → 插件」里装
fist-mbt-mcp                                  # 可选：只想要终端里的 stdio server（npx fist-mbt-mcp 亦可）
```

装好后 MCP server `fist-mbt` 随会话启动，工具数**以 `tools/list` 为准**。账本（SQLite）落在
`~/.fist-mbt/`，可用 `FIST_MBT_DATA` 改位置；运行环境需要 **Node ≥ 24**（`node:sqlite`）。
插件层真源是 `packaging/dsh/cordis.patch.yml`（社区安装）与 `.dsh/fist-mbt-plugin/cordis.patch.yml`（本机源码安装）。

### 黑盒用户（无需源码）

Release zip 只含 MoonBit 编译产物，零源码依赖：

```bash
# Windows PowerShell（首选：2026-09-28 实测唯一匿名能取到脚本正文的 raw 直链）
iex ((irm https://raw.githubusercontent.com/vicTop-cw/FIST-Mbt/master/scripts/blackbox/install_onecmd.ps1).ToString().TrimStart([char]0xFEFF))

> Windows 这条为什么不是 `irm … | iex` 而是先 `.TrimStart([char]0xFEFF)`：
> 安装器 .ps1 含中文，按本仓 `check_ps_encoding`（BUG-88）必须带 UTF-8 BOM；
> `irm` 会把 BOM 留成首字符 U+FEFF，`iex` 于是在 `param()` 里报「赋值表达式的左侧无效」（BUG-113 实测）。
> `powershell -File` 读磁盘没这个问题 ⇒ 三条调用面（-File / -Command / `irm | iex`）不同形，别互相背书。

# Windows 兜底线（BUG-116：系统代理 / TLS 中间盒让上面那条 `irm` 取不到脚本时——本机 2026-09-29 实测 `irm` 6/6 传输层红、同一时刻同一 URL 用 curl.exe 6/6 得 200）
curl.exe --retry 5 --retry-delay 2 --retry-all-errors -fsSL https://raw.githubusercontent.com/vicTop-cw/FIST-Mbt/master/scripts/blackbox/install_onecmd.ps1 -o $env:TEMP\install_onecmd.ps1; powershell -NoProfile -ExecutionPolicy Bypass -File $env:TEMP\install_onecmd.ps1

> 诚实的边界（2026-09-29 更新）：这条换掉的是「取脚本」这一步的传输工具，并把 R12 那条「重试只许对准传输层错误」的规矩搬到这一发上（`--retry 5 --retry-delay 2 --retry-all-errors`——本机实测的失效形态是**同一个 URL 有些连接被 RST、有些拿到 200**，单发不成立；`--retry-all-errors` 是必需的，因为 curl 默认只对"响应前"的连接错误重试）。安装器**内部**那两发（取 `moon.mod` 定版本、取资产 zip）以前只有 .NET 单栈，是「脚本取回来了、红在内部那一发」的真来源——现已同样接上 curl 兜底臂（判据 R12 + R14；承重证据 `python scripts/blackbox/e2e_transport_stack_fallback.py`：同一镜像三格，".NET 抛传输层错误 + 有 curl" 装通、同样条件剥掉 curl 必红、干净安装不误伤）。链路**整断**时两条栈一起红，那种情况只剩 `-LocalZip` 离线线。

# 离线 / 内网线（两条公网线都被中间盒挡住时的出路；开关真源 = `install_onecmd.ps1` 的 `param()`）
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\blackbox\install_onecmd.ps1 -LocalZip C:\path\to\fist-mbt-js-v0.3.10.zip
# 或指一个内网镜像（与 GitHub Release 同形状：`<Base>/releases/download/<ver>/<asset>`，且 `<Base>/moon.mod` 必须可读）
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\blackbox\install_onecmd.ps1 -BaseUrl http://内网镜像:端口

# WSL / Linux
curl -fsSL https://raw.githubusercontent.com/vicTop-cw/FIST-Mbt/master/scripts/blackbox/install.sh | bash
```

> 分支名是 **master** 不是 main（该仓默认分支为 master，`raw/main` 实测取不到东西）。
> GitCode 上同名仓库只当**浏览备用**：实测它的三种 raw 形状（`/-/raw/`、`/raw/`、`raw.` 子域）
> 匿名 GET 都返回 **HTTP 200 + 一整页 HTML** 而不是脚本正文 ⇒ 别把它接进 `| iex`
> （「200 不等于拿到文件」；安装器内部那道正文形状检查是给下载资产用的，不是给这条线用的）。

安装后（shim 在 `~/.local/bin`，Windows 下 POSIX shell 里同样可见）：

```bash
fist help          # 列出 6 大 topic
fist help tools    # 134 MCP tools 分组清单
fist help mcp      # .mcp.json 配置模板
fist serve         # 启动 MCP server（stdio）
fist demo          # 七态闭环 demo
fist doctor        # 5 项健康检查
```

### 独立 CLI 脚本（P0 强化验证类）
| 脚本 | 对应 MCP | 场景 |
|---|---|---|
| `scripts/issue_scan.py <dir>` | `issue_scan` | CI 扫描潜在 MoonBit 高危模式 |
| `scripts/output_validate.py <dir> --artifacts ...` | `output_validate` | 交付物 L4 硬门验证 |
| `scripts/mcp_smoke.py` | 多工具联动 | 一键 MCP 冒烟自检 |

---

## DEMO 脚本（本项目自身迭代的历史证据）

`scripts/` 目录下的 `*_demo.py` 和 `*_verify.py` 不是测试——它们是**本项目用自身能力打磨自身的自证**：

| DEMO | 证明什么 |
|---|---|
| `python scripts/award_demo.py` | 能力链全通：publish → plan → claim → execute → verify → archive，结尾自动 cleanup |
| `python scripts/atgc_selfdrive_demo.py` | 自驱闭环：selfdrive_init → review_tick → publish_next → pick_next |
| `python scripts/scratch_verify.py` | 递归拆解正确性：task_plan_deep 产出的 DAG 能被 dag_ready 正确消费 |
| `python scripts/issue_scan.py src` | 四态对齐：CLI 扫描 → 31 条 MoonBit 高危规则（11 内建 + 20 ocr-local）→ findings 可喂 report_bug |
| `python scripts/fist.py call project_standards` | AI 开发规范基线（R116）：10 条通用+FIST 强制规范 + 7 项四态 checklist；正文真源 `AI-DEVELOPMENT-STANDARD.md` |
| `python scripts/gen_plugins.py` | 一源四态·插件态生成：真源 → atomcode/codearts/deepseek-harness/claude 四宿主投影 |
| `python scripts/check_plugin_sync.py` | cl7 守卫：四宿主插件目录必须等于真源投影（手改/漏重生成/数字漂移即红） |
| `python scripts/check_model_auth_no_key.py` | 凭据形状守卫：config_json/HTML/default-fist.mcp.json 里禁止出现 `api_key`/`Bearer`/`sk-` 值形状（对齐 BUG-127） |
| `python scripts/check_host_installable.py` | 宿主可装守卫：deepseek-harness 宿主侧真的能装上（补 cl7「等于投影」却「装不上」的旧边界） |
| `python scripts/check_skill_inject.py` | 注入命中守卫：evolve_asset_register 注入路径可测命中（plan/claim 传了 `inject` 时 `injected_assets` 非空才算命中） |

更多 walkthrough 见 `docs/selfdrive-walkthrough.md`、`docs/issue-scan-skill.md`、`docs/output-validate-skill.md`、`docs/loop-mode-skill.md`（组合环编排 × 自驱七模式）、`docs/phi-accrual-heal-skill.md`（Phi Accrual 判活 × 心跳回滚 × 看门狗编排）。

---

## AI 项目开发规范（本项目遵守）

> **规范正文 = [`AI-DEVELOPMENT-STANDARD.md`](AI-DEVELOPMENT-STANDARD.md)**（R116 单真源文本，目标项目照此开发）。
> 下面是摘要；机器投影 = `python scripts/fist.py call project_standards --include-checklist true`。摘要与正文的不一致由 `scripts/check_doc_surface.py`（J6/J7）拦。

**通用 5 条**（跨项目复用）：
1. 📄 **文档即实现** — 接口签名 doc 注释 + README 速查表 + skill 使用时机，验收先过文档再验功能；目标项目必备文档集见规范正文 §2
2. 🔗 **一源四态** — 核心逻辑单真源（MoonBit），CLI/Skill 薄封装、Plugin 态为**生成投影**，禁止重复造轮子
3. 🎯 **确定性优先** — 验证类逻辑（扫描/验产物/看门狗）全部确定性实现，LLM 只做决策不做判定
4. 📉 **增量零回归** — 每加一功能全量测试必过，临时脚本任务完必须清理
5. 🔁 **自我迭代** — 先做最小可用，用自身能力（evolve_distill/evolve_lesson/task_challenge）边做边学

**FIST 强制 5 条**（`hard` 级，违反打回）：
1. ✅ **必须用 FIST 自身能力迭代** — 每轮 publish → plan → claim → execute → submit → verify，且四个开关是活的：**call_log**（调用取证）、**issue_up**（`report_bug` 入账）、**laya**（冷启动选档）、**Omega 强验证**（语料驱动）；防漂移另开 `reinject_context` / `boundary_probe`。判据表见规范正文 §3
2. ✅ **四态必须对齐** — 新 MCP 工具上线同步 CLI + skill 文档 + 重生成四宿主插件（`gen_plugins.py`，cl7）
3. ✅ **证据梯至少 L4** — verify 前必须 `output_validate verdict=pass`
4. 🗂️ **重任务先拆 DAG** — 跨 3 文件以上必须先 publish + `task_plan_deep`
5. 🏷️ **工具命名即文档** — 动宾结构、语义化参数名；名实不符=契约说谎

---

## 架构

```
┌─────────────────────────────────────────────────────────┐
│                    MCP 客户端层                           │
│  Claude Desktop  Trae  Cursor  自研 JSON-RPC             │
└────────────────────┬────────────────────────────────────┘
                     │ JSON-RPC
┌────────────────────▼────────────────────────────────────┐
│              FIST-Mbt MCP Server (MoonBit)               │
│  ┌──────────┐  ┌───────────┐  ┌──────────┐  ┌────────┐ │
│  │ Engine   │  │ Decompose │  │  Store   │  │  Ops   │ │
│  │ (状态机) │  │ (递归拆解) │  │ (SQLite) │  │ (自驱) │ │
│  └──────────┘  └───────────┘  └──────────┘  └────────┘ │
│  ┌──────────┐  ┌───────────┐  ┌──────────┐  ┌────────┐ │
│  │  DAG     │  │  Verify   │  │  Evolve  │  │ Omega  │ │
│  │ (PERT)   │  │ (run+L4)  │  │ (DGM)    │  │ (强验) │ │
│  └──────────┘  └───────────┘  └──────────┘  └────────┘ │
└────────────────────┬────────────────────────────────────┘
                     │ SQLite / FileSystem
┌────────────────────▼────────────────────────────────────┐
│  SQLite (任务状态/审计日志/档案库) + FileSystem (产物)    │
└─────────────────────────────────────────────────────────┘
```

## 资源

- **MochaCakes**: `vicTop-cw/fist-mbt`（注册表上实际发布到哪个版本**只在 BACKLOG 的 P1 条目自述一处**；本行刻意不写版本号——
  写死就会和 BACKLOG 的发布记录双向漂移，这是 BUG-30 的原始形状。要当场核对就跑 `moon view vicTop-cw/fist-mbt --versions`）
- **GitCode（同步源）**: https://gitcode.com/VictorTop/Fist-Mbt —— **同步/发布只需推 GitCode 即可**：
  GitHub 镜像由 CI 自动同步（GitCode 根目录 `.sync-to-github` 开关控制，只增不删，以 GitCode 为源覆盖同名分支），无需手动推送 GitHub；
  本机 `git remote gitcode` 配的是 HTTPS 取 / `pushurl` 走 `git@gitcode.com:…` 推，凭据只来自环境变量
- **GitHub（镜像）**: https://github.com/vicTop-cw/FIST-Mbt —— 由 GitCode 自动同步，勿直接改动
- **fist-evidence**（实证伴生仓 · 本项目的叙事与证据面）: https://github.com/vicTop-cw/fist-evidence —— 本系统三组受控实验
  （A/B 编排对照 / 三方合并裁决 / 复杂度阶梯含幻觉实锤）+ 十份真实项目驱动实例（覆盖八项目，总表在该仓 `cases/cases.md`）
  的原始证据链，报告/日志/裁判测试一字可回溯（原件在该仓 `stories/experiment-0*.md` 与 `stories/evidence/`——**该路径属伴生仓，本仓无 `stories/` 目录**）；
  「证据梯至少 L4」的实物展示
- **License**: Apache-2.0

---

## 开发进度

| 里程碑 | 日期 | 内容 |
|---|---|---|
| M8 | 2026-09 | 36+ MCP 工具 + 77/77 测试；文档体系（README/CHANGELOG/USAGE）全面更新到 0.2.0 |
| 四模式流水线 Round 1~3 | 2026-10-15 | 自迭代收口：一源四态 cl7 + 模型路由与外部执行器合并 + 多管家/supervisor + web 面板 M0 + 五语言接入示例 |
| Unsafe 扫描 | 2026-10-17 | `engine_dag_ext` / `issue_scan` / `issue_scan_wbtest` 三文件裸 `.unwrap()`/`unsafe_get()`/`expect()` 零命中；`unwrap_or` 3 处中高风险（P1: `budget_split_by_dag` L910 语义反转） |
| Engine 回归 | 2026-10-17 | `moon test --target js src/engine` 162/162 全绿 |

**当前分支**：`marvis-verify-20261017`  
**当前验证状态**：Unsafe 扫描通过 + Engine 回归全绿  
**下一步**：按 unsafe-scan 建议修复 P1（`budget_split_by_dag` L910 语义反转），追加白盒测试后合入主线

---

## 历史版本

- **0.2.5** (2026-09-26) — 105 工具 / 329 测试。新增 `output_validate`(R113)、`issue_scan`、`laya_decide` · `loop_create` · `loop_tick` · `loop_status` · `mcp_config_scaffold`、`project_standards`(R114)；统一 CLI 网关 `scripts/fist.py`；MCP/CLI/Skill 三处手写形态对齐（插件态于 0.2.6 起成为第四态）。
- **0.2.4** (前置) — 104 工具 / 317 测试。完整生命周期闭环、自驱体系、Omega 强验证、看门狗、Saga、熔断器。
