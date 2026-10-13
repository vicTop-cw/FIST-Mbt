---
AIGC:
    Label: "1"
    ContentProducer: 001191440300708461136T1XGW3
    ProduceID: 9f2a11add43fbf12a546606fb2b962ab_f165d974c62911f19063525400393706
    ReservedCode1: umJSpUs+dAmd1zrtosVr/EQTIn3fMkInbHVLFy14vXe5qPY6GIvc6Cb4X1egQ5JjTaIGDRveWNvnM14QIVlK1YtfTBxEZeR4jM9Lx9rAYZ/arqM9bo4s7CZS6t1fsrDRIZ57On33M8MLUPNaGdU52/ri26Y1iQwJOM0K2adghv1QoO57F/kx16knXXY=
    ContentPropagator: 001191440300708461136T1XGW3
    PropagateID: 9f2a11add43fbf12a546606fb2b962ab_f165d974c62911f19063525400393706
    ReservedCode2: umJSpUs+dAmd1zrtosVr/EQTIn3fMkInbHVLFy14vXe5qPY6GIvc6Cb4X1egQ5JjTaIGDRveWNvnM14QIVlK1YtfTBxEZeR4jM9Lx9rAYZ/arqM9bo4s7CZS6t1fsrDRIZ57On33M8MLUPNaGdU52/ri26Y1iQwJOM0K2adghv1QoO57F/kx16knXXY=
---

# fist-mbt 超级管家与角色体系设计（v0.1）

- 日期：2026-10-12
- 状态：设计 v0.1（基于全项目角色盘点，避免重复创建角色）
- 前置：fist-mbt 已是一源四态（MCP/CLI/Skill/Plugin），已有 core 角色注册表、审计三角色、HexaMind 六元、SAGE 四专家环、"项目助理"设计稿（未落地）

---

## 0. 一句话目标

引入**超级管家**作为统一调度入口：用户发布任务即撤，超级管家下发任务给各项目的**项目助理**，项目助理指挥**拳长/拳节/执行者**干活；进度按需查询，由超级管家汇报。**不新造执行类角色**，全部复用现有角色体系；仅新增「超级管家」入口与「提醒者」轮询监督两个非执行角色。

---

## 1. 角色全景盘点（探索结论，2026-10-12）

### 1.1 FIST-Mbt 已实现角色

| 体系 | 角色 | 出处 | 状态 |
|---|---|---|---|
| core 注册表 | `human_steward` 人类指挥官 / `leader` 领队 / `searcher` 搜证 / `allocator` 资源分配 / `executor` 执行者 / `verifier` 验收者 / `recorder` 记录者 / `observer` 观测者 / `spec_author` 语料创建者 | `src\core\core_role.mbt` | 已实现（含权限矩阵 `can()`） |
| 审计三角色 | `human_steward` / `leader` / `agent`（publish/archive/delete 仅人类指挥官；claim 三者皆可） | `src\ops\audit.mbt` | 已实现 |
| HexaMind 六元 | `stargazer` 观星者(白) / `pulse` 脉冲(红) / `wallbreaker` 破壁者(黑) / `golddigger` 掘金者(黄) / `nova` 新星(绿) / `nucleus` 星核(蓝) | `src\hat\hat_defs.mbt` | 已实现（R119） |
| SAGE 专家环 | `Challenger` / `Planner` / `Solver` / `Critic` | `docs\improvement-plan-20261010.md` | 部分实现（evolve_critic + task_challenge） |

### 1.2 已设计、未落地

| 角色 | 设计出处 | 内容 | 状态 |
|---|---|---|---|
| **项目助理**（每项目唯一，选举制，持 kill 权） | `docs\2026-10-11-multi-agent-lock-design*.md`（v1-v3） | 4 子职能 mode：锁管家 LockKeeper / 清道夫 Reaper / 警察 Sheriff / 审计员 Auditor；大型项目可加副助理（无 kill 权，可晋升） | 仅锁基础已实现（file_locks 表 + lock_acquire/renew/release）；assistant_reg 表与 assistant_claim/kill/sweep/audit 工具未落地 |
| Agent 分级（kill 白名单依据） | 同上 | `role=planner` 拳长（不可杀）/ `role=sublead` 拳节（不可杀）/ `role=worker` 执行者（可杀） | 设计态 |
| **提醒者 Reminder**（轮询调度监督，不执行） | `docs\2026-10-12-fist-mbt-reminder-role-plan.md` | 职责 R1 引导提醒 / R2 方向偏离 / R3 事项提醒 / R4 心跳汇报；轮询周期 10/30/10 分钟；偏离检测口径见独立计划 §4 | 计划待实施（夜间开发批次） |

### 1.3 FIST 框架参照（E:\IDEProjects\AI\_archive\FIST，v2.3.0）

层级：**人类 → human_steward 人类管家 → leader 拳长 → 拳节（searcher/reviewer/cleaner/verifier/documenter）→ executor 执行者**。
注册：`agents` 表（agent_id/role/name/focus/permissions/status）+ `roles`/`whoami`/`register`/`sink-skill` 命令；`human_steward` 唯一 skill 沉淀权。
→ 本设计的"超级管家"即对应 `human_steward` 定位；"拳长/拳节/执行者"分级与 FIST 同构。

---

## 2. 超级管家架构

```
你（老板）
  ↓ 发布任务（发布即撤，回会话聊天）
超级管家（Marvis / human_steward 定位）── 只调度与汇报，不执行
  ├─ 提醒者 Reminder（轮询监督：引导/方向/事项，到点提醒，只读审计，不执行）
  ↓ 下发（按项目路由）
项目助理（每项目唯一，复用 multi-agent-lock-design 设计）── 统筹该项目
  ├─ 拳长 planner（拆解/指挥，不可杀）
  │    ├─ 拳节 sublead（非执行者职能：searcher/reviewer/cleaner/verifier/documenter）
  │    └─ 执行者 worker/executor（原子任务，可杀）
  ├─ LockKeeper 锁管家（并发资源锁）
  ├─ Reaper 清道夫（临时/中间产物清理）
  ├─ Sheriff 警察（违规/权限守护）
  └─ Auditor 审计员（审计追踪）
  ↑ 进度/结果逐级上报
超级管家汇总 → 用户问进度时汇报
```

### 2.1 职责边界（关键）

| 角色 | 做什么 | 不做什么 |
|---|---|---|
| 超级管家 | 接收用户意图、按项目路由下发、查询进度并汇报 | 不拆解具体任务、不执行、不直接指挥执行者 |
| 项目助理 | 统筹项目：拆解、调度、锁/清理/警察/审计、汇总上报 | 不亲自执行原子任务 |
| 拳长 | 任务拆解与下达、指挥拳节/执行者 | 不越级向超级管家汇报细节 |
| 拳节/执行者 | 执行原子任务、验证、记录 | 不直接对接用户 |

### 2.2 发布即撤与按需汇报

- 用户发布 → 超级管家下发 → 返回任务树根 id，即可退出会话
- 任务树多层持久化（根任务 → 助理任务 → 叶子任务），状态落库可查
- 进度接口：`GET /tasks/tree/{root_id}` + 项目助理 `summary`（结构：状态/当前环节/关键产物/阻塞点）
- 用户问进度 → 超级管家按任务树查询 → 汇报

### 2.3 提醒者（Reminder）——轮询调度角色

- **定位**：超级管家（human_steward）体系下的轮询调度角色，不执行业务任务，专职「盯着状态、到点提醒」；复用 supervisor 工具集（supervisor_status / task_tree / prompt_inject / prompt_list / prompt_consume / task_upsert），以只读审计 + 定向注入为主要动作。
- **职责**：R1 引导提醒（未消费引导/提示词 → prompt_inject 提醒消费，超时升级管家）；R2 方向偏离提醒（对照 plan 目标与 task_tree 进展，偏差超阈值生成偏离报告并注入修正建议）；R3 事项提醒（依赖到期 / 任务超时 / 风险项 / 需人类决策事项 → 注入管家决策队列）；R4 心跳汇报（轮询摘要写入状态存储）。
- **轮询调度**：基础轮询 10 分钟/轮，R2 偏离审计 30 分钟/轮，R3 事项扫描 10 分钟/轮（可配置）；事件触发优先（task_upsert / prompt_inject 后追加增量检查）；优先级 R1>R2>R3，同轮批量注入防刷屏；同一条提醒最多提醒 3 次（间隔递增），已解决自动归档。
- **偏离检测口径（R2 初步）**：plan 目标未拆解 / 节点长期 pending / 产出物缺失；执行产出与任务描述关键词/产出物清单比对；连续 N 轮 heartbeat 停滞判定疑似卡死，提醒续跑或 kill_plan 重排。
- **与体系融合**：注册角色名 `reminder`（core 角色扩展或 audit 补充）；复用 task_tree / supervisor_status 输出为轮询输入，提醒记录追加状态存储新段 `reminder_log`；动作全走 prompt_inject，无新增 MCP 工具可先行落地；提醒者不具任务派发与终止权。
- **完整计划**：详见 `docs\2026-10-12-fist-mbt-reminder-role-plan.md`（含落地步骤，供夜间开发批次使用）。

---

## 3. 角色映射决策（避免重复造角色）

| 新概念（用户表述） | 映射到 | 决策 |
|---|---|---|
| 超级管家 | FIST `human_steward` 定位；Marvis 作为入口 | 复用，不新建 |
| 项目管家 | **项目助理**（multi-agent-lock-design，每项目唯一、持 kill 权、4 子职能） | **直接复用，不新建"项目管家"** |
| 拳长 | `leader` / `planner`（不可杀） | 复用 |
| 拳节 | `sublead`（searcher/reviewer/cleaner/verifier/documenter） | 复用 |
| 执行者 | `worker` / `executor` / `allocator` | 复用 |
| 提醒者 | `reminder`（新角色：轮询调度监督，R1-R4） | **新建**（已设计未落地，见独立计划文档） |

结论：**新增概念为「超级管家」角色（human_steward 的对外入口形态）与「提醒者」角色（`reminder`，轮询调度监督，详见独立计划文档），其余全部复用现有角色定义。**

---

## 4. 待落地清单

| 项 | 内容 | 依赖 |
|---|---|---|
| 项目助理本体 | `assistant_reg` 表 + `assistant_claim/kill/sweep/audit` 工具（已有设计稿，照 v3 实现） | 锁基础已就绪 |
| 多层任务树 | 任务层级扩展：根任务 → 助理任务 → 叶子任务，逐层汇总 | 现有 task_* |
| 进度接口 | `GET /tasks/tree/{root_id}` + 助理 `summary`（结构：状态/当前环节/关键产物/阻塞点） | 任务树持久化 |
| 超级管家入口 | Marvis 侧流程：发布即撤、按需查进度（可配合 MCP 端使用） | 上述接口 |
| 提醒者角色 | `reminder` 轮询模块：R1-R4 + 周期/阈值配置 + 状态存储新增 `reminder_log` 段（实现步骤见独立计划 §6） | 任务树 / supervisor 状态 / prompt 注入工具已就绪 |
| 角色注册表统一 | 将 core/audit/项目助理/分级统一暴露为 `roles` 查询（参考 FIST agents 表） | 已有 core_role.mbt |

## 5. 与现有计划的关系

- 不推翻一源四态/HexaMind/actus：超级管家是**编排角色层**，跑在现有引擎之上
- HexaMind 六元可被项目助理作为"帽子"调度手段（同一任务多视角对比）
- actus 动作层可承载"拳长/拳节"的确定性执行动作（#!config 声明）
- Web 面板（态5）可展示任务树与进度汇报，天然配套
*（内容由AI生成，仅供参考）*
