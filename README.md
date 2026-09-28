# FIST-Mbt

[![Made with MoonBit](https://img.shields.io/badge/MoonBit-0.1.20260827-blue)](https://www.moonbitlang.com)
[![License](https://img.shields.io/badge/License-Apache--2.0-green)](./LICENSE)
[![Tests](https://img.shields.io/badge/tests-533%2F533-brightgreen)](./src)
[![CI](https://github.com/vicTop-cw/FIST-Mbt/actions/workflows/ci.yml/badge.svg)](https://github.com/vicTop-cw/FIST-Mbt/actions) (js ×2 + native)

**FIST-Mbt** 用**纯 MoonBit** 重写并 MCP 化的 **AI 指挥官任务编排底座**——不是又一个 agent 框架，而是"人类指挥、AI/定时器持续自推动"的自治系统。完整闭环：**发布→认领→拆分→执行→提交→验收→归档**，叠加 **自驱审视、DGM 演化采样、Omega 强验证、跨进程看门狗**。全部以 **129 个 MCP 工具** 暴露给任意 MCP 客户端。

**为什么 MoonBit**：任务编排天然"正确性敏感"（状态机、权限矩阵、追加式审计、递归拆解），MoonBit 的强类型、无运行时依赖、JS+Native 双端交叉编译让这套逻辑在 Windows 与 Linux 上以 JS 目标 533 项测试全绿、跨环境可复现。

> 它用**它自己的**自驱式 + 递归拆解把自己打磨到了可交付态——完整自我迭代证据见 `docs/selfdrive-walkthrough.md`，CLI `python scripts/fist.py call project_standards` 可一键拉取本项目遵守的 AI 开发规范。

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
4. ✅ `moon test` 全绿？ → 533/533 零回归（`--target js`，本轮 Windows 实测）
5. ✅ 交付物过 `output_validate` L4 硬门？ → verdict=pass
6. ✅ README / AGENTS.md 计数同步？ → 工具数、测试数
7. ✅ 插件态已重生成且与真源一致？ → `python scripts/gen_plugins.py && python scripts/check_plugin_sync.py`（cl7）

---

## 功能全景（129 个 MCP 工具）

### 生命周期（14）
`publish` · `publish_parallel` · `plan` · `claim` · `execute` · `submit` · `verify` · `reject` · `retry` · `pause` · `resume` · `reopen_task` · `archive` · `delete`

### 查询（2）
`list` · `get`

### 运维·编排（14）
`task_plan_deep` · `conflicts_check` · `heartbeat` · `heal` · `watchdog_tick` · `task_cleanup` · `phi_accrual` · `saga_register` · `saga_rollback` · `saga_repair` · `circuit_fail` · `circuit_succeed` · `circuit_status` · `tx_contract`

### 自驱闭环（9）
`selfdrive_init` · `selfdrive_append` · `selfdrive_get` · `selfdrive_export_tasks` · `selfdrive_review_tick` · `selfdrive_review_ready` · `selfdrive_publish_next` · `selfdrive_parse_next_tasks` · `selfdrive_pick_next`

### 运维·验证·规范（20）
`call_log` · `bug_list` · `bug_fix` · `bug_mark_status` · `report_bug` · `issue_scan` · `eval_feedback` · `run_check` · `output_validate` · `project_standards` · `schedule` · `pipeline_tick` · `cost_stats` · `cost_budget_check` · `cost_budget_split` · `progress_gate` · `laya_decide` · `loop_create` · `loop_tick` · `loop_status`

### 模型路由·外部执行器（4）
`model_route` · `model_router_status` · `model_router_reset` · `executor_run`

### 衍生（3）
`atgc_old_compile` · `atgc_old_run` · `atgc_old_talk`

### 看板·DAG·规划（22）
`dag_critical_path` · `dag_parallelism` · `dag_ascii` · `dag_check` · `dag_ready` · `dag_sort` · `dag_depend` · `dag_publish` · `dag_slack` · `dag_schedule` · `dag_cost_route` · `dag_mc` · `plan_revise` · `goal_drift_check` · `board_ascii` · `status_summary` · `project_health` · `health_check` · `reserve_scope` · `reserve_check` · `reserve_release` · `task_triage`

### 自我记忆·自进化（11）
`memory_consolidate` · `memory_gc` · `memory_link` · `evolve_distill` · `evolve_lesson` · `evolve_critic` · `evolve_sample` · `evolve_snapshot` · `evolve_submit` · `evolve_asset_register` · `task_challenge`

### Marketplace·能力路由（5）
`executor_register` · `executor_route` · `executor_auction` · `executor_clear` · `selfdrive_dispatch`

### 审计·多租户（5）
`audit_permission` · `audit_log` · `store_open` · `store_list` · `store_close`

### GitHub/GitCode 同步·缺陷外发（12）
`github_env_check` · `github_queue_status` · `github_flush_plan` · `github_flush_execute` · `github_queue_mark_sent` · `github_issue_close` · `github_issue_comment` · `github_issue_webhook_parse` · `gitcode_env_check` · `gitcode_queue_status` · `gitcode_flush_plan` · `gitcode_queue_mark_sent`

### 开发模式与模板（2）
`mode_list` · `mode_templates`

### Omega 强验证（6）
`omega_spec_create` · `omega_spec_review` · `omega_result_verify` · `omega_status` · `omega_verify` · `omega_verify_fix`

---

## 快速开始

```bash
# 1. 构建 + 测试
moon update            # 首次：刷新 registry 索引
moon build --target js cmd/cli
moon test --target js  # → Total tests: 533, passed: 533, failed: 0

# 2. 启动 MCP Server（STDIO）
python scripts/patch_esm_main.py  # ESM shim（moonc ≥0.10.14 输出 ESM，sqlite JS 桩用 CJS）
node _build/js/debug/build/cmd/cli/cli.js serve   # 必须带 serve：裸跑只打印 help

# 3. 或用 HTTP/SSE 桥接
FIST_MCP_PORT=3000 python scripts/fist-mbt-http.py

# 4. CLI 通用网关（一源四态·CLI 形态）
python scripts/fist.py list-tools                     # 列出 122 个工具
python scripts/fist.py call project_standards          # AI 开发规范
python scripts/fist.py call store_open --namespace scratch --scratch true
python scripts/fist.py call output_validate --project-dir . --artifacts '[{"path":"moon.mod","contains":"vicTop-cw"}]'
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
| `python scripts/issue_scan.py src` | 四态对齐：CLI 扫描 → 10 条 MoonBit 高危规则 → findings 可喂 report_bug |
| `python scripts/fist.py call project_standards` | AI 开发规范基线（R116）：10 条通用+FIST 强制规范 + 7 项四态 checklist；正文真源 `AI-DEVELOPMENT-STANDARD.md` |
| `python scripts/gen_plugins.py` | 一源四态·插件态生成：真源 → atomcode/codearts/deepseek-harness/claude 四宿主投影 |
| `python scripts/check_plugin_sync.py` | cl7 守卫：四宿主插件目录必须等于真源投影（手改/漏重生成/数字漂移即红） |

更多 walkthrough 见 `docs/selfdrive-walkthrough.md`、`docs/issue-scan-skill.md`、`docs/output-validate-skill.md`。

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

## 环境要求

- **MoonBit ≥ 0.1.20260827**（支持 errdefer 与 async）
- **Node.js ≥ 24**（JS 目标必需，SQLite JS 后端依赖 node:sqlite）
- **Native 目标**：系统 SQLite 开发库（sqlite3.h + sqlite3.lib）。一键装载：`pwsh ./scripts/native-env.ps1`

> **JS 后端**：`moon test --target js` = **533/533**（本轮 2026-09-28 Windows 实测，含一源四态 cl7、模型路由与外部执行器合并（4 工具 + 24 项回归锁）、BUG-4/18 与三轮自我迭代回归锁 BUG-19/21/24/31/36）。
> **Native 后端**：上一轮在 Windows + WSL(Linux) 通过 317/317；本轮四模式流水线未复跑 native，故不据旧数宣称双端同版全绿，见「已知边界」。

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

- **MochaCakes**: `vicTop-cw/fist-mbt`（注册表上实际发布到哪个版本以 BACKLOG P1 条目为准；本行刻意不写版本号——
  本机没有可复核注册表的通道，写死数字就会和 BACKLOG 的发布记录互相矛盾，这是 BUG-30 的原始形状）
- **GitHub**: https://github.com/vicTop-cw/FIST-Mbt
- **GitCode 镜像**: https://gitcode.com/VictorTop/Fist-Mbt （`master` + 标签与 GitHub 同步发布；
  本机 `git remote gitcode` 配的是 HTTPS 取 / `pushurl` 走 `git@gitcode.com:…` 推，凭据只来自环境变量）
- **fist-evidence**（实证伴生仓）: https://github.com/vicTop-cw/fist-evidence —— 本系统三组受控实验
  （A/B 编排对照 / 三方合并裁决 / 复杂度阶梯含幻觉实锤）+ 八项目驱动实例的原始证据链，一字可回溯；
  「证据梯至少 L4」的实物展示
- **License**: Apache-2.0

---

## 历史版本

- **0.2.5** (2026-09-26) — 105 工具 / 329 测试。新增 `output_validate`(R113)、`issue_scan`、`laya_decide` · `loop_create` · `loop_tick` · `loop_status`、`project_standards`(R114)；统一 CLI 网关 `scripts/fist.py`；MCP/CLI/Skill 三处手写形态对齐（插件态于 0.2.6 起成为第四态）。
- **0.2.4** (前置) — 104 工具 / 317 测试。完整生命周期闭环、自驱体系、Omega 强验证、看门狗、Saga、熔断器。
