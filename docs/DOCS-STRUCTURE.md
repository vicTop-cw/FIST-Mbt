# DOCS-STRUCTURE — 文档放置与命名规范

> 立此规范的任务：`docs/tasks/backlog/TASK-006-docs-structure.md-spec.yaml`（R85，2026-10-21）。
> 风语者首轮巡检实测：全仓 609 个 md —— 根目录 10 / docs/ 63（跟踪面）/ reports/ 501 / memory/ 29。
> 本规范回答一个问题：**想写的东西该放哪儿、叫什么名**。它同时是一份现状声明——文中每一条
> 「钉住」都有守卫出处；迁走任何一份被钉住的文件，必须同批改守卫，否则 CI 当轮变红。

## 四类文档的定位与去向

| 类 | 目录 | 定位 | 命名 | 写入纪律 |
|---|---|---|---|---|
| 1 入口面 | 仓库根 | 对外门面 + **守卫判据面**（见下表） | **固定名，禁改名禁迁移** | 与真源（moon.mod / server 注册表 / 实测数）对齐，由 `check_doc_surface` / `check_test_sync` / `check_badge` 当轮判 |
| 2 计划/设计/决策 | `docs/` | 计划、设计稿、SOP、决策与评估归档、任务池 | 归档评估类必须 `YYYY-MM-DD-<主题>-<plan\|design\|report\|playbook>.md`；常驻参考类（`SOP.md`、`agent-map.md`、本文件）不带日期 | 追加不改写；日期前缀由 `check_doc_surface` **J15** 判（纯参考文档豁免） |
| 3 轮次报告 | `reports/` | 每轮任务的七段报告（结果摘要/资源消耗/任务分配/遗留风险/后续建议/超额/来源） | `YYYY-MM-DD-<任务名>-report.md` | **只追加**；历史报告（存量 501 份）不强制迁移、永不回写 |
| 4 运行记忆 | `memory/` | 当日日志（追加式）、缺陷账本、产品/思考长文 | `YYYY-MM-DD.md` 日志；`bugs.md` 账本 | 日志只追加；`bugs.md` 抬头文法受 `gen_plugins` 硬门①~④ + `check_bug_reference_integrity` 判据管 |

另有一个特殊面：`docs/tasks/`（任务池 yaml，`TASK-<NNN>-<主题>.yaml`）——主机/风语者写入、
下游 agent（AtomCode/副机）认领，格式见同目录既有条目。

## 根目录文件清单：每一份都被守卫钉住（迁移 = 改守卫）

TASK-006 验收②原拟「根目录只留 README.md + ARCHITECTURE.md + CHANGELOG.md（其他迁走或删除）」。
**现状核查后此条按原样执行会直接挂红 CI**——根目录 9 份 md 全部是守卫的判据输入：

| 文件 | 钉住它的守卫 |
|---|---|
| `AGENTS.md` | `check_doc_surface` J2（逐工具覆盖）+ J10；agent 工具约定俗成只读根 AGENTS.md |
| `README.md` | J2/J3（分组和==实测）、badge 守卫、R13（zip 资产名字面量）、`check_model_auth_no_key` 扫描面 |
| `README.mbt.md` | `check_test_sync` R2 must-carry + 枚举自锁（漏它即 SELFTEST FAIL） |
| `README_EN.md` | `check_test_sync` 现状面扫描 |
| `USAGE.md` | `check_doc_surface`（`USAGE = ROOT / "USAGE.md"`，BUG-30 版本自述） |
| `ARCHITECTURE.md` | `check_test_sync` R2 must-carry + 枚举自锁 |
| `CHANGELOG.md` | `check_doc_surface` J13（发布状态短语 ↔ BACKLOG release-fact） |
| `BACKLOG.md` | `check_doc_surface` J4（发布版本**唯一**权威自述处）+ J13 |
| `AI-DEVELOPMENT-STANDARD.md` | `check_doc_surface` J6（规范正文真源 ↔ `project_standards` 机器投影逐条一致）+ J7（旧口径禁词） |

**结论**：根目录 md 的定员就是这 9 份（外加未来确需新增的入口文件）。它们不是「散落」，
是**被守卫钉在根上的入口面**。迁移目标降级为：**不再往根目录新增第 10 份普通 md**——
新写的计划/设计/评估进 `docs/`，报告进 `reports/`，本轮结论进 `memory/当日.md`。
若未来确要迁移其中某份，先改钉住它的守卫，再动文件，同批一个 commit。

## 「治理主题散在 19 个文件」的处理口径

巡检把「治理」关键词命中 19 个文件视为债务。口径与 `check_doc_surface` J7 一致：
**规范性表面只有一处真源**（`AI-DEVELOPMENT-STANDARD.md`，机器投影 = `project_standards` 工具）；
其余命中文件（reports/、memory/ 日志、CHANGELOG、docs/ 归档计划）是**历史陈述面**——
按「叙述面只追加、不改写」纪律，历史面不追改、不算债。治理主题的新增叙述一律写到
AI-DEVELOPMENT-STANDARD.md 或当日 memory，不在第二个规范文件里复制规则。

## docs/ 内部分层：先立命名，不做目录迁移

现有 `docs/` 63 份平铺 + `archive/`。分层子目录（plans/ reports/ design/ skill/）属低优先级
迁移（TASK-006 scope 原话「规范先出」），本轮**不迁移**——迁移会让 63 份文件的既有引用
（守卫、AGENTS、README、脚本内的路径常量）一次性失配。暂行的分层规则：

- 新增**计划/设计/评估归档**：平铺在 `docs/`，名字带 `YYYY-MM-DD-` 前缀（J15 判）。
- 新增**常驻参考**（SOP / 地图 / 本规范这类会被反复引用的）：平铺、不带日期、名字即定位。
- 已完成使命的旧文档：移 `docs/archive/`（现成惯例），不删除。

## 新人速查

| 你想写的东西 | 放哪 | 叫什么 |
|---|---|---|
| 使用说明 / 环境要求 | 改 `README.md` / `USAGE.md`（根，勿新建） | — |
| 开发规范 / 治理规则 | `AI-DEVELOPMENT-STANDARD.md`（真源） | — |
| 计划 / 设计稿 / 决策评估 | `docs/` | `YYYY-MM-DD-<主题>-<plan\|design\|report>.md` |
| 给 agent 的任务 | `docs/tasks/backlog/` | `TASK-<NNN>-<主题>.yaml` |
| 轮次报告 | `reports/` | `YYYY-MM-DD-<任务名>-report.md` |
| 当轮结论 / 踩坑 | `memory/YYYY-MM-DD.md` | 追加小节 |
| 缺陷 | `memory/bugs.md`（走 `report_bug` 工具，勿手写） | 抬头文法见该文件头部 |
