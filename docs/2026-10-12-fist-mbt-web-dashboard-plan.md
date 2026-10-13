---
AIGC:
    Label: "1"
    ContentProducer: 001191440300708461136T1XGW3
    ProduceID: 9f2a11add43fbf12a546606fb2b962ab_78365689c61711f19063525400393706
    ReservedCode1: KtadPNgpjEQ+ghHaqVDfs3Gk2Rljqrp4zLXmWWhn//GU6l5ggHiizwtDTUnMlqhX8DTpLC3JNawpfGuLuThgjL35IN+eLJ2vcVEYZegC1dAceiZ0JbkfXdtoId1TAEpoEZPqqSvcO/3fqx8wvpykRmwuPCz845mUG3yvbSApIemKVMqBdWFAq/1be8U=
    ContentPropagator: 001191440300708461136T1XGW3
    PropagateID: 9f2a11add43fbf12a546606fb2b962ab_78365689c61711f19063525400393706
    ReservedCode2: KtadPNgpjEQ+ghHaqVDfs3Gk2Rljqrp4zLXmWWhn//GU6l5ggHiizwtDTUnMlqhX8DTpLC3JNawpfGuLuThgjL35IN+eLJ2vcVEYZegC1dAceiZ0JbkfXdtoId1TAEpoEZPqqSvcO/3fqx8wvpykRmwuPCz845mUG3yvbSApIemKVMqBdWFAq/1be8U=
---

# fist-mbt Web 管理面板计划（fist-mbt Dashboard）

- 日期：2026-10-12
- 状态：计划 v0.2（一源五态总计划）
- 定位：一源五态总计划。一期先落地"态5：Web 管理面板"（作为 MCP Server 的可视化操作层，覆盖一源四态之上的可视化管理）；军旗体制（军衔体系）、士兵分类、特种兵路由等远期规划见 §8，本期不实施，仅占位设计。

---

## 1. 背景与定位

现状：已有 `fist-config.html` 静态配置页 + `scripts/fist-mbt-http.py` HTTP/SSE 桥，但**没有交互式管理看板**。任务状态、路由决策、成本归因都只能靠 MCP 工具/CLI 查。

目标：做一块交互式 Web 面板，把 fist-mbt 的三大核心资产可视化：
- **任务**：DAG/树形结构、状态流转、日志、失败重试
- **路由**：free/paid 池、各模型健康度、Star 门命中、失败归因
- **成本**：每任务/每模型 token 消耗与费用估算（OFM 免费池价值可见）

## 2. 技术选型

| 项 | 选型 | 理由 |
|---|---|---|
| 后端 | 新增 `scripts/fist-mbt-web.py`（Python，复用 stdlib http.server 或极简依赖） | 现有 HTTP 桥已是 Python，延续技术栈；不污染 `fist-mbt-http.py`（它是 MCP 转发职责） |
| 前端 | 单页原生 HTML + JS + CSS（零构建链） | 延续 `fist-config.html` 零依赖风格，契合项目"少依赖、可解释"基调；避免引入 Node 工程 |
| 实时推送 | SSE（复用 /events 模式） | 已有 SSE 先例，WebSocket 过重 |
| 数据源 | SqliteStore（任务）+ router 状态（内存查询接口）+ 配置文件 | 不新增存储；router 状态经 MCP 工具透出 |
| 认证 | 本地绑定 + 可选 token（`FIST_WEB_TOKEN`） | 防局域网误暴露 |

## 3. 功能模块（页面）

| 页面 | 核心内容 | 数据来源 |
|---|---|---|
| 任务看板 | 任务树/DAG 可视化、状态流转（PENDING→RUNNING→COMPLETED/FAILED）、子任务展开、执行日志、失败重试/打回 | SqliteStore + MCP `task_*` 工具 |
| 路由监控 | free/paid 池状态、各模型成功率/延迟/失败归因（INVALID_CREDENTIAL/RATE_LIMIT/UPSTREAM_DOWN）、Star 门命中记录、最近路由决策 | `model_route` / `model_auth_status` / router 状态工具 |
| 成本仪表盘 | 每任务/每模型 token 消耗、费用估算、免费/付费占比（OFM 价值可视化） | 模型用量统计（P1 需补 usage_report，当前可先做估算占位） |
| 配置管理 | config_json 编辑（路由参数、帽子配置）、env 检查、OFM 通道状态灯 | 配置文件 + OFM health |
| 帽子视图（可选，联动 HexaMind） | 六帽并行结果对比、分歧清单 divergence[] 展示、辩论回合时间线 | HexaMind 落库后接入 |

## 4. 架构

```
浏览器 (SPA: index.html + app.js + style.css)
   │  fetch / SSE
   ▼
scripts/fist-mbt-web.py  （管理 API + 静态资源服务）
   ├── spawn MCP stdio server（子进程，复用 cmd/cli serve）
   ├── 读 SqliteStore（任务数据）
   ├── 调 MCP 只读工具（model_route / model_auth_status / lock_status ...）
   └── 读/写 config_json
```

与现有组件的关系：
- `fist-mbt-http.py`：保持不动（MCP 转发职责）
- `fist-config.html`：保留（静态配置页），面板的"配置管理"页可链接过去
- MCP Server：面板是它的**客户端之一**，不做任何改动（零侵入）

## 5. MVP 分期

| 阶段 | 内容 | 验收 | 建议时间 |
|---|---|---|---|
| M0 任务看板 | 只读版：任务树 + 状态 + 日志 + 刷新 | 打开页面看到真实任务 DAG 与状态 | P1 完成后（10.25 起，1-2 天） |
| M1 路由+成本 | 池状态、成功率、失败归因、成本估算（占位） | 路由决策与 OFM 免费池价值可视化 | +2 天 |
| M2 交互+帽子 | 重试/暂停、配置编辑、HexaMind 帽子对比视图 | 面板可反向操作任务，联动六元决策 | +3 天（HexaMind 落地后） |

## 6. 与黑客松节奏的关系

- Web 面板放进 **P2 赛事工程化**（10.25-10.31）：直接服务验收四维中的"用户体验"（25%）与"可解释性"（25%）
- **不建议抢占 P1 时间**：路由增强（10.18-10.24）是面板展示内容的上游，P1 未完成时面板"路由监控"页无内容可画
- 若时间紧张，M0 任务看板单独即可作为演示亮点，M1/M2 顺延

## 7. 风险与取舍

- 不做前端框架构建链：原生 JS 手写图表/DAG 渲染工作量可控（任务树用简单树图，不引 d3）
- SSE 推送粒度：按 1s 轮询 + 事件推送双轨，避免连接风暴
- 认证：默认仅本机访问；token 可选开启，不默认占用配置
- 面板是"观察+轻操作"层，重操作仍走 MCP 工具（职责不越界）
*（内容由AI生成，仅供参考）*

---

## 8. 远期规划（本期不实现，仅占位设计）

> 军旗体制（军衔体系）、士兵分类、特种兵路由等属于**未来规划**，当前版本不实施。
> 本节内容仅为设计占位，供后续版本（建议 v0.4+ 或 P3 之后）落地参考；实施时需与
> `fist-mbt-supervisor-role-design`（角色注册表）、`model_route`（池标签/Star 门）联动。

### 8.1 军衔体系（完整 *长 总表）

**设计原则**：协议层不感知军衔。除统帅/士兵/政委外，所有 *长 在协议层一律映射为 `Leader` 角色；
军衔（司令/军长/师长/…/排长）只是**展示层标签**，由 `rank_of(任务层级)` 动态定级，
协议与存储零改动，仅 Web 面板与汇报文案消费。

| 军衔 | 角色映射 | 说明 |
|---|---|---|
| 统帅 | `HumanSteward`（人类唯一主权） | 唯一顶层主权，不下放协议层；所有自动执行均在其授权体系内 |
| 司令 | `Leader`（rank L=0） | 总览全局、拍板方向；展示层最高军衔 |
| 军长 | `Leader`（rank L=1） | 大项目/战役级统筹 |
| 师长 | `Leader`（rank L=2） | 子战役/模块级统筹 |
| 旅长 | `Leader`（rank L=3） | 阶段级统筹 |
| 团长 | `Leader`（rank L=4） | 任务簇统筹 |
| 营长 | `Leader`（rank L=5） | 任务组统筹 |
| 连长 | `Leader`（rank L=6） | 小任务组统筹 |
| 排长 | `Leader`（rank L=7） | 叶子之上最后一档统筹 |
| 士兵 | `Executor`（叶子原子任务强制士兵级） | 任何叶子原子任务固定为士兵，绝不显示军衔 |
| 政委 | `Reminder`（未来新增枚举，政工线） | 方向纠偏/提醒/偏离检测（呼应提醒者角色 R1-R4） |

**参谋线**（非 *长，参谋军职，挂靠 Leader 体系）：

| 参谋军职 | 角色映射 | 职责 |
|---|---|---|
| 侦察参谋 | `Searcher` | 情报搜集、可行性调研 |
| 后勤参谋 | `Allocator` | 资源分配、池/模型调度 |
| 验收宪兵 | `Verifier` | 交付验收、门禁把关 |
| 军务文书 | `Recorder` | 记录、台账、日志归档 |
| 监察参谋 | `Observer` | 状态监察、异常上报 |
| 训练教官 | `SpecAuthor` | 规范/提示词编写、训练 |

**定级规则**：

- `rank_of(L)` = 总表自上而下第 `L+1` 档（统帅除外），即：L=0 → 司令，L=1 → 军长，…，L=7 → 排长。
- **叶子恒为士兵**：`depth == 叶子` 的任务无论层级一律 `Executor` 士兵级。
- 当前默认 `root depth=3`，实际生效 4 档（司令→军长→师长→士兵）；其余职级（旅长及以下）**占位**，
  调大 `root depth` 后自动激活，无需改协议。

### 8.2 士兵分类表（兵种 × 模型档位 × 攻坚任务类型）

士兵（`Executor`）按「任务性质 × 模型档位」细分为兵种，供路由与面板展示标签使用（展示层，非协议枚举）：

| 兵种 | 执行角色 × 模型档位 | 攻坚任务类型 |
|---|---|---|
| 侦查兵 | `Searcher` + 便宜快速模型 | 情报搜集 / 可行性调研 / 搜索与文档速读 |
| 骑兵 | 轻载执行 + 低延迟中端模型 | 短平快 / 高频小任务 / 批量琐事 |
| 炮兵 | 重载执行 + 强力模型（LongCat/旗舰） | 大重构 / 算法攻坚 / 疑难排障 |
| 特种兵 | 白名单专属 + 最强模型 | 高价值关键任务 / 紧急修复 / 架构决策 |
| 工兵 | 工具链 + 通用模型 | 环境搭建 / 依赖修复 / 脚本编写 |
| 医疗兵 | 排障 + 中端模型 | 错误修复 / 故障恢复 / 数据抢救 |
| 通信兵 | 通知 + 快速模型 | 消息同步 / 状态汇报 / 提醒 |
| 后勤兵 | 资源管理 + 通用模型 | 文件整理 / 资源分配 / 归档 |

### 8.3 与自动路由的联动

- 兵种 ↔ `model_route` 池标签（`free` / `paid` / Star 门）建立映射：
  - **特种兵**：走强模型白名单（人工授权、最贵档、Star 门最高级）；
  - **炮兵**：走付费池重任务（旗舰/LongCat 档，成本敏感但允许高花费）；
  - **侦查兵/骑兵/通信兵**：走免费池轻任务（便宜快速模型，低花费）；
  - 其余兵种按 `model_route` 常规策略（通用模型）路由。
- 面板「路由监控」页可增加「兵种分布」视图（展示层）：按兵种聚合任务数/成功率/成本，验证兵种-模型映射效果。
- 实施前提：`core_role` 新增 `Reminder` 枚举、`Executor` 增加兵种元数据（或复用 `assignee`/`ns` 约定）、
  `model_route` 支持兵种标签 → 池标签映射；上述均属远期变更，本期不做。
