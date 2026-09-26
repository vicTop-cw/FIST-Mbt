# FIST-Mbt

[![Made with MoonBit](https://img.shields.io/badge/MoonBit-0.1.20260827-blue)](https://www.moonbitlang.com)
[![License](https://img.shields.io/badge/License-Apache--2.0-green)](./LICENSE)
[![Tests](https://img.shields.io/badge/tests-329%2F329-brightgreen)](./src)
[![CI](https://github.com/vicTop-cw/FIST-Mbt/actions/workflows/ci.yml/badge.svg)](https://github.com/vicTop-cw/FIST-Mbt/actions) (js ×2 + native)

**FIST-Mbt** 用**纯 MoonBit** 重写并 MCP 化的 **AI 指挥官任务编排底座**——不是又一个 agent 框架，而是"人类指挥、AI/定时器持续自推动"的自治系统。完整闭环：**发布→认领→拆分→执行→提交→验收→归档**，叠加 **自驱审视、DGM 演化采样、Omega 强验证、跨进程看门狗**。全部以 **105 个 MCP 工具** 暴露给任意 MCP 客户端。

**为什么 MoonBit**：任务编排天然"正确性敏感"（状态机、权限矩阵、追加式审计、递归拆解），MoonBit 的强类型、无运行时依赖、JS+Native 双端交叉编译让这套逻辑在 Windows 与 Linux 上 329 项测试双端全绿、跨环境可复现。

> 它用**它自己的**自驱式 + 递归拆解把自己打磨到了可交付态——完整自我迭代证据见 `docs/selfdrive-walkthrough.md`，CLI `python scripts/fist.py call project_standards` 可一键拉取本项目遵守的 AI 开发规范。

---

## 一源三态（One Source, Three Forms）

FIST-Mbt 的每个功能都有**三种调用形态**，核心逻辑**只写一遍**（MoonBit 单真源），CLI/Skill 都是薄封装：

| 形态 | 是什么 | 谁用 | 示例 |
|---|---|---|---|
| **MCP**（主形态） | MoonBit server 暴露的 JSON-RPC 工具 | Claude Desktop / Trae / AtomCode / 任何 MCP 客户端 | `tools/call output_validate` |
| **CLI** | Python 薄封装脚本（拉起 server → 调工具 → 打印 JSON） | CI 管道、手动验证、无 MCP 客户端场景 | `python scripts/output_validate.py . --artifacts '[...]'` |
| **Skill** | Markdown 文档（何时用 / 怎么用 / 怎么闭环） | AI agent 读的使用手册 | `docs/output-validate-skill.md` |

**三形态对齐检查清单**（6 项硬门，`project_standards` 工具内建）：
1. ✅ MCP 工具注册了？ → `server.mbt` instrumented_tool 块
2. ✅ CLI 封装到位？ → `scripts/fist.py call <tool>` 或独立 `scripts/xxx.py`
3. ✅ Skill 文档写了？ → `docs/xxx-skill.md`
4. ✅ `moon test` 全绿？ → 329/329 零回归
5. ✅ 交付物过 `output_validate` L4 硬门？ → verdict=pass
6. ✅ README / AGENTS.md 计数同步？ → 工具数、测试数

---

## 功能全景（105 个 MCP 工具）

### 生命周期（14）
`publish` · `publish_parallel` · `plan` · `claim` · `execute` · `submit` · `verify` · `reject` · `retry` · `pause` · `resume` · `reopen_task` · `archive` · `delete`

### 查询（2）
`list` · `get`

### 运维·编排（14）
`task_plan_deep` · `conflicts_check` · `heartbeat` · `heal` · `watchdog_tick` · `task_cleanup` · `phi_accrual` · `saga_register` · `saga_rollback` · `saga_repair` · `circuit_fail` · `circuit_succeed` · `circuit_status` · `tx_contract`

### 自驱闭环（9）
`selfdrive_init` · `selfdrive_append` · `selfdrive_get` · `selfdrive_export_tasks` · `selfdrive_review_tick` · `selfdrive_review_ready` · `selfdrive_publish_next` · `selfdrive_parse_next_tasks` · `selfdrive_pick_next`

### 运维·验证·规范（14）
`call_log` · `bug_list` · `report_bug` · `issue_scan` · `eval_feedback` · `run_check` · `output_validate` · `project_standards` · `schedule` · `pipeline_tick` · `cost_stats` · `cost_budget_check` · `cost_budget_split` · `progress_gate` · `laya_decide`

### 衍生（3）
`atgc_old_compile` · `atgc_old_run` · `atgc_old_talk`

### 看板·DAG·规划（20）
`dag_critical_path` · `dag_parallelism` · `dag_ascii` · `dag_check` · `dag_ready` · `dag_sort` · `dag_depend` · `dag_publish` · `dag_slack` · `dag_schedule` · `dag_cost_route` · `dag_mc` · `plan_revise` · `goal_drift_check` · `board_ascii` · `status_summary` · `project_health` · `health_check` · `reserve_scope` · `reserve_check` · `reserve_release` · `task_triage`

### 自我记忆·自进化（11）
`memory_consolidate` · `memory_gc` · `memory_link` · `evolve_distill` · `evolve_lesson` · `evolve_critic` · `evolve_sample` · `evolve_snapshot` · `evolve_submit` · `evolve_asset_register` · `task_challenge`

### Marketplace·能力路由（5）
`executor_register` · `executor_route` · `executor_auction` · `executor_clear` · `selfdrive_dispatch`

### 审计·多租户（5）
`audit_permission` · `audit_log` · `store_open` · `store_list` · `store_close`

### Omega 强验证（6）
`omega_spec_create` · `omega_spec_review` · `omega_result_verify` · `omega_status` · `omega_verify` · `omega_verify_fix`

---

## 快速开始

```bash
# 1. 构建 + 测试
moon update            # 首次：刷新 registry 索引
moon build --target js cmd/main
moon test --target js  # → Total tests: 329, passed: 329, failed: 0

# 2. 启动 MCP Server（STDIO）
python scripts/patch_esm_main.py  # ESM shim（moonc ≥0.10.14 输出 ESM，sqlite JS 桩用 CJS）
node _build/js/debug/build/cmd/main/main.js

# 3. 或用 HTTP/SSE 桥接
FIST_MCP_PORT=3000 python scripts/fist-mbt-http.py

# 4. CLI 通用网关（一源三态·CLI 形态）
python scripts/fist.py list-tools                     # 列出 105 个工具
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
| `python scripts/issue_scan.py src` | 三形态对齐：CLI 扫描 → 10 条 MoonBit 高危规则 → findings 可喂 report_bug |
| `python scripts/fist.py call project_standards` | AI 开发规范基线：10 条通用+FIST 强制规范 + 6 项三形态 checklist |

更多 walkthrough 见 `docs/selfdrive-walkthrough.md`、`docs/issue-scan-skill.md`、`docs/output-validate-skill.md`。

---

## AI 项目开发规范（本项目遵守）

拉取规范清单：`python scripts/fist.py call project_standards --include-checklist true`

**通用 5 条**（跨项目复用）：
1. 📄 **文档即实现** — 接口签名 doc 注释 + README 速查表，验收先过文档再验功能
2. 🔗 **一源三态** — 核心逻辑单真源，CLI/Skill/MCP 薄封装，禁止重复造轮子
3. 🎯 **确定性优先** — 验证类逻辑（扫描/验产物/看门狗）全部确定性实现，LLM 只做决策不做判定
4. 📉 **增量零回归** — 每加一功能全量测试必过，临时脚本任务完必须清理
5. 🔁 **自我迭代** — 先做最小可用，用自身能力（evolve/task_challenge）边做边学

**FIST 强制 5 条**（`hard` 级，违反打回）：
1. ✅ **必须用 FIST 自身能力迭代** — 新功能必须 publish 根任务 + 拆 DAG，自证 dogfooding
2. ✅ **三形态必须对齐** — 新 MCP 工具上线同步 CLI + skill 文档
3. ✅ **证据梯至少 L4** — verify 前必须 output_validate verdict=pass
4. 🗂️ **重任务先拆 DAG** — 跨 3 文件/5 人日以上必须先 publish + plan_deep
5. 🏷️ **工具命名即文档** — 动宾结构、语义化参数名

---

## 环境要求

- **MoonBit ≥ 0.1.20260827**（支持 errdefer 与 async）
- **Node.js ≥ 24**（JS 目标必需，SQLite JS 后端依赖 node:sqlite）
- **Native 目标**：系统 SQLite 开发库（sqlite3.h + sqlite3.lib）。一键装载：`pwsh ./scripts/native-env.ps1`

> JS 与 Native 双后端均已在 Windows + WSL(Linux) 通过 329/329 测试。

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

- **MochaCakes**: `vicTop-cw/fist-mbt@0.2.5`
- **GitHub**: https://github.com/vicTop-cw/FIST-Mbt
- **License**: Apache-2.0

---

## 历史版本

- **0.2.5** (2026-09-26) — 105 工具 / 329 测试。新增 `output_validate`(R113)、`issue_scan`、`laya_decide`、`project_standards`(R114)；统一 CLI 网关 `scripts/fist.py`；三形态对齐。
- **0.2.4** (前置) — 104 工具 / 317 测试。完整生命周期闭环、自驱体系、Omega 强验证、看门狗、Saga、熔断器。
