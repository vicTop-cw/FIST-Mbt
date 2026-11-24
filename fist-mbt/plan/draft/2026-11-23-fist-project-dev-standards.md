---
status: 提案中
decided_by:
decided_at:
decision:
proposed_by: file-agent
based_on:
  - docs/plans/README.md（计划治理中枢硬规则）
  - docs/DOCS-STRUCTURE.md（文档放置与命名规范）
  - DEC-2026-10-22-001（双层目录治理，提案 docs/plans/2026-10-22-fist-dir-layout-governance-proposal.md）
  - docs/plans/2026-11-22-autoplan.md（计划四区生命周期 v2）
  - docs/plans/2026-10-26-4pools-rhop-roadmap-proposal.md（4 池子 + R96 定案口径 + 2026-11-13 M1 落地记录）
---

# fist 项目开发规范（fist-mbt 文件体系规范）

> 本文档综合既有已定案治理决策，作为 **fist-mbt、rx-mbt、mcp-watcher 三个项目文件归档与开发流程的统一基准**。
> 生效说明：本文档为汇编基准，非新决策；与既有守卫（`check_plan_location` / `check_fist_layout` / `check_doc_surface`）冲突时，以守卫真源为准，并须同步修订本文档对应条款。
> 定案状态：`status=提案中`，待 `human_steward` 确认；定案前本基准先行生效用于归档。

---

## 1. 双层目录总则（DEC-2026-10-22-001）

所有工件按「机器边界 / 团队边界」归入两层：

| 层 | 位置 | 语义 | 版本控制 |
|---|---|---|---|
| 公开侧（团队共享） | 项目根下 `fist-mbt/`（同构于各项目根公开目录） | 跨机器、随主仓走 | **committed，git 跟踪** |
| 私有侧（机器独有） | 项目根下 `.fist-mbt/` | 每台机器各自不同的运行时态 | **gitignored，每机一份、可随意删** |

**硬规则**
1. 计划只进公开侧 `plans/`；完成汇报只进公开侧 `reports/`。
2. 临时文件只进 `.fist-mbt/tmp/`，绝不进 `src/`、`docs/`、`plans/`、`reports/`。
3. 未定案计划（`status != 已定案`）禁止发布任务（`plan_publish` 门禁）。
4. 定案权仅 `human_steward`；agent 只提不定。

---

## 2. 目录结构硬规则

### 2.1 公开侧（团队共享，committed）

```
fist-mbt/                    # 公开侧根（各项目同构）
├── plans/                   # 计划治理中枢（提案、在流计划、已定案待执行计划）
│   ├── decisions/           # 定案记录留痕（DEC-YYYY-MM-DD-NNN-*.md）
│   └── archived/            # 已完成 / 已驳回 / 已推迟的终态计划
├── reports/                 # 轮次报告（完成汇报只进这里）
├── docs/                    # 文档面（入口面固定名文档除外）
├── memory/                  # 运行记忆（当日日志、缺陷账本、长文）
├── scripts/                 # 脚本与工具
├── templates/               # 模板
└── pool/                    # 跨机任务池 / 跨机消息池（共享侧；**已推迟，等 owner 信号**，暂不建）
```

- **根目录定员**：入口面固定名文档（README.md / ARCHITECTURE.md / CHANGELOG.md / BACKLOG.md / AGENTS.md / USAGE.md / AI-DEVELOPMENT-STANDARD.md 等）由守卫钉住，**禁改名禁迁移**；根目录**禁止再新增散落 PLAN-*.md 或普通 md**。
- 新增计划/设计/评估归档进 `docs/` 或 `plans/`，报告进 `reports/`，当轮结论进 `memory/YYYY-MM-DD.md`。

### 2.2 私有侧（机器独有，gitignored）

```
.fist-mbt/
├── tmp/                      # 临时文件（temp_*、build*.log、中间产物）——唯一临时落点
├── data/                     # SQLite 库 + 模型路由状态 + 账本（autoplan-plans.json 等）
├── logs/                     # 运行日志
├── cache/                    # 构建缓存 / __pycache__
├── state/                    # cron / 已处理状态
├── pool/                     # 同机任务池（正式区）
├── lock/                     # 文件锁
└── db/                       # 数据库目录（实测存在，沿用）
```

- `.gitignore` 以 `/.fist-mbt/` 整体忽略（2026-11-13 已补小写条目，大小写敏感文件系统同样生效）。
- **私有侧不随主仓提交**；跨机同步靠 git（公开侧）+ 每机自建（私有侧）。

### 2.3 同机消息池（`.commissar/`）

- 位置：项目根 `.commissar/`（`events/` / `inbox/` / `reminder_log/` / `archive/`），由 `commissar_*` 工具族承载：
  - `commissar_send`：同机发消息（写 `.commissar/events/*.rhop`）
  - `commissar_read`：同机读消息（无状态短轮询，调用方维护 `since_seq` 游标）
  - `commissar_gc`：回收（保留最近 N 条，显式调用，不隐式删）
- **硬规则**：不在 `.fist-mbt/pool/` 下另建 `messages/`，避免「两处都说自己是消息池」。

### 2.4 同机任务池（`.fist-mbt/pool/`）

- 位置：`.fist-mbt/pool/tasks/`（正式区，机器独有）。
- **双区流转口径（R96 定案）**：

```
候选区（.git/fist/，随主仓提交）
  fist-gate.py --scan 产候选
        │  人工提升（不许机器自动落地）
        ▼
正式区（.fist-mbt/pool/tasks/，机器独有，gitignored）
  任务在单机多 agent 之间交接与流转
```

- **不建**四态中文子目录（预案/定案/执行中/归档）——R96 裁决迁移收益为负；状态沿用三态口径（`backlog/done/failed`），维护在 frontmatter 的 `status` 字段。
- 跨机侧（`fist-mbt/pool/tasks/`、`fist-mbt/pool/messages/`）**已推迟**：阻塞点是 rx-mbt `rhop_native.mbt` 仍为占位 stub，等 owner 给「跨机是否近期目标」信号后再建。

---

## 3. 文件命名硬规则

| 想写的东西 | 落位 | 命名 | 纪律 |
|---|---|---|---|
| **计划** | 公开侧 `plans/` | `YYYY-MM-DD-<topic>.md` | 只进 plans；头部强制字段缺一即红 |
| 报告 | 公开侧 `reports/` | `YYYY-MM-DD-<topic>-report.md` | 只进 reports；只追加、永不回写 |
| 临时文件 / 中间产物 | `.fist-mbt/tmp/` | 任意 | 绝不进 src/、docs/、plans/、reports/ |
| 定案记录 | `plans/decisions/` | `YYYY-MM-DD-<NNN>-<topic>.md` | 留痕不改写 |
| 常驻参考（SOP/地图/规范） | `docs/` 或 `plans/` | 不带日期，名字即定位 | 本文件属此类 |
| 轮次结论 / 踩坑 | `memory/YYYY-MM-DD.md` | 追加小节 | 只追加 |
| 缺陷 | `memory/bugs.md` | 走 `report_bug` 工具 | 勿手写 |

**硬规则**
1. **计划只进 plans**：`YYYY-MM-DD-<topic>.md` 统一入 `plans/`；历史 `-proposal.md` 形态不追改，新计划兼容两种形态但**一律落在 plans/**（`plans/` 根 或 `plans/archived/` 终态）。
2. **报告只进 reports**：命名必须 `YYYY-MM-DD-<topic>-report.md`，且**只追加**；存量历史报告不强制迁移。
3. **临时只进 `.fist-mbt/tmp/`**：任何中间态、WIP、临时脚本、构建日志一律私有侧；中间态**永不进编译树**（`src/`）。
4. **根目录禁止新增散落 PLAN-*.md**：根目录定员即入口面固定名文档；新计划/报告一律走 `plans/` / `reports/`。
5. **计划头部强制字段**（缺一即红，`check_plan_location` 守卫）：
   ```yaml
   ---
   status: 提案中   # 提案中 | 已定案 | 已驳回 | 已推迟 | 已完成
   decided_by:      # 定案人（仅 human_steward）
   decided_at:      # 定案时间戳
   decision:        # approved | rejected | deferred
   ---
   ```

---

## 4. 生命周期规则（autoplan 四区）

计划记录的状态机（v2 约定层；任务池九态机构零改动）：

```
                 drop（只入初稿，不执行）
   ┌──────────┐                        ┌──────────┐
   │  初稿区   │ ──── finalize（定案）──▶ │  执行区   │  仅定案计划的任务在池内流转
   └──────────┘                        │ (定案)   │  claim→execute→submit→verify
   ┌──────────┐                        └────┬─────┘
   │  终止区   │ abort（夭折，记录原因）      │ 全部任务终态（sweep）
   └──────────┘                           ▼
                                    ┌──────────┐
   feedback（功能反馈区，独立账）      │  归档区   │
   └──────────────────────────────▶  └──────────┘
```

| 区 | 入口命令 | 语义 | 硬规则 |
|---|---|---|---|
| **初稿区** | `drop <计划.md>` | 只建计划记录，任务**不入池**；改到满意再定案 | "改计划"永不产生执行噪音 |
| **执行区（定案）** | `finalize <plan_id>` | 把工作项/裁决项 publish 进池流转 | 仅定案计划的任务在池内流转 |
| **归档区** | `sweep` | 定案计划全部任务终态后自动归位 | 归档 = 任务终态 + 报告在 reports/ |
| **终止区** | `abort <plan_id> "<原因>"` | 记录夭折原因 | 不静默删除池内已发布任务，如实标注 |

- 命令面：`drop` / `plans` / `finalize` / `abort` / `sweep` / `decisions` / `resolve` / `feedback`（`scripts/autoplan.py`）。
- 账本：`.fist-mbt/data/autoplan-plans.json`（计划记录）、`.fist-mbt/data/autoplan-feedback.jsonl`（反馈，append-only）。
- 与 plans/ 状态字段映射：`提案中 ↔ 初稿区`；`已定案 ↔ 执行区`；`已完成 ↔ 归档区`；`已驳回/已推迟 ↔ 终止区`。

---

## 5. 验收规则（finalize 前置断言 + 报告强制）

1. **finalize 前必须写验收断言**：每条计划/工作项在 finalize（定案入执行区）之前，必须写明**可验证的验收判据**（预期输出、判据编号、通过标准），禁止「做完再说」式无断言计划。
2. **执行完必须产出 report**：计划对应任务全部终态后，必须产出 `YYYY-MM-DD-<topic>-report.md` 进 `reports/`（七段：结果摘要/资源消耗/任务分配/遗留风险/后续建议/超额/来源）。
3. **无报告的「已完成」视为未完成**：任何标记为已完成/已归档的计划，若 `reports/` 中无对应报告，一律视为未完成，不得进入归档区（sweep 拒绝）。
4. **sweep 前置**：归档区仅接受「全任务终态 + 报告在位」的计划；缺报告先补报告再 sweep。
5. **abort 例外**：终止区不要求报告，但必须记录夭折原因（`abort <plan_id> "<原因>"`）。

---

## 6. 违规检查与守卫（速查）

| 守卫 / 检查 | 管什么 |
|---|---|
| `check_plan_location` | 计划只进 `plans/`、头部三字段（status/decided_by/decision）在位 |
| `check_fist_layout` | 双骨架（公开侧 + 私有侧）目录在位、根目录无机器独有工件散落 |
| `check_doc_surface` | 根目录定员文档与真源对齐、日期前缀（J15）判归档类命名 |
| `check_test_sync` | README.mbt.md / ARCHITECTURE.md 枚举自锁 |

**常见违规与正确做法**

| 违规 | 正确做法 |
|---|---|
| 把计划塞进 `reports/` | 计划进 `plans/`，报告进 `reports/` |
| 根目录新增 `PLAN-xxx.md` | 进 `docs/plans/`（`YYYY-MM-DD-<topic>.md`） |
| 临时 WIP 挂在 `src/` 或 `docs/` | 进 `.fist-mbt/tmp/`，自洽后一次性移回编译树 |
| 标记「已完成」但无报告 | 补 `reports/YYYY-MM-DD-<topic>-report.md` 后才算完成 |
| 未写验收断言就 finalize | 先补断言（预期输出/判据/通过标准）再 finalize |
| 两处都说自己是消息池 | 同机消息池只认 `.commissar/`（commissar 工具族） |

---

## 7. 对三个项目的适用

| 项目 | 适用方式 |
|---|---|
| **fist-mbt** | 全量适用本文档（公开侧 `fist-mbt/` + 私有侧 `.fist-mbt/` 均已落地，按 §2/§3/§4/§5 执行） |
| **rx-mbt** | 按同构骨架归档：治理文档面走公开侧 `plans/`（`YYYY-MM-DD-<topic>.md`）、`reports/`（`-report.md`）、`docs/`、`memory/`；源码树（`src/`、`test-suit/`、`rhop/`）保持不动，不强行迁移 |
| **mcp-watcher** | 同 rx-mbt：治理文档面按规范落位，源码与配置保持项目自身结构 |

> 归档动作一律「只动不删、重名保护」；批量归档走 `file-organizer` 流程，先出蓝图再执行。

---

## 8. 定案与修订

1. 本文档 `status=提案中`，待 `human_steward` 定案确认；定案后回填头部 `decided_by / decided_at / decision`。
2. 修订方式：**追加不改写**——既有已定案决策引用一律不追改；新规则以追加小节 + 修订记录形式进入本文档。
3. 与本文档冲突的历史口径（如 `.fist-mbt/pool/README.md` 上级 README 中的旧「单向迁移」表述）以本文档为准，历史文件不回写。

---

## 附：规范要点速查（一句话版）

- **放哪**：计划 → `plans/`；报告 → `reports/`；临时 → `.fist-mbt/tmp/`；消息 → `.commissar/`；任务 → `.fist-mbt/pool/tasks/`（正式区，候选区 `.git/fist/`）。
- **叫啥**：计划 `YYYY-MM-DD-<topic>.md`；报告 `YYYY-MM-DD-<topic>-report.md`；根目录不加散落 PLAN-*。
- **怎么走**：初稿区 → finalize → 执行区 →（任务全终态 + 报告在位）→ sweep → 归档区；夭折 → abort → 终止区。
- **算不算完成**：无报告的「已完成」= 未完成；finalize 前必须有验收断言。
