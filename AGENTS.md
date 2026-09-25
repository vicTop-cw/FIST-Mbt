---
AIGC:
    Label: "1"
    ContentProducer: 001191440300708461136T1XGW3
    ProduceID: 9f2a11add43fbf12a546606fb2b962ab_ab739310b1b011f18304525400aeaaa3
    ReservedCode1: de9GcMa2Qm/A+/aWqrEO57ddJh84OqJkQdkBcuUrRFJzUUd6KS6o13YUUT1zn6RCmfsYUBcF5DO13gi34N9Ycnp8Qrd3Lw+WzPNXiEjeno8u86defuam4JXgYPCeSQ+o4fBX+PG+S/SsiwvHDMia3IgvzYTEkNGv0tmXFv1drGRpOiSSDpScnwLIkgM=
    ContentPropagator: 001191440300708461136T1XGW3
    PropagateID: 9f2a11add43fbf12a546606fb2b962ab_ab739310b1b011f18304525400aeaaa3
    ReservedCode2: de9GcMa2Qm/A+/aWqrEO57ddJh84OqJkQdkBcuUrRFJzUUd6KS6o13YUUT1zn6RCmfsYUBcF5DO13gi34N9Ycnp8Qrd3Lw+WzPNXiEjeno8u86defuam4JXgYPCeSQ+o4fBX+PG+S/SsiwvHDMia3IgvzYTEkNGv0tmXFv1drGRpOiSSDpScnwLIkgM=
---

# Project Agents.md Guide

This is a [MoonBit](https://docs.moonbitlang.com) project.

You can browse and install extra skills here:
<https://github.com/moonbitlang/skills>

## FIST 指挥官模式（默认行为）

本项目是 **FIST-Mbt** —— 用纯 MoonBit 重写的 FIST 指挥官任务分配体系，同时作为 MCP Server 暴露给 AI 客户端。

在此项目中启动 AtomCode 会话时，**默认启用 FIST 指挥官模式**：

### 角色边界（金条四）
- 你**不亲力亲为**可分配的具体工作（写代码、查资料、跑长命令）→ 交给子代理
- 你**亲自做**：理解用户意图、决定分流、写任务包、终审结果、沉淀记忆、汇报
- 不可逆操作（删除、发布、合并代码）→ 只给"方案 + 预案"，执行权留在指挥官或用户确认

### 分流决策树
1. **轻任务**（单文件修改、小重构、格式转换）→ 直接子代理
2. **中任务**（多文件、需要验证循环）→ 子代理 + 你终审
3. **重任务**（跨模块重构、新项目、PR/CI 闭环）→ 调 FIST MCP 工具发布任务
4. **不可逆任务**：出方案，挂起等用户确认

### 任务包格式
每个子任务必须带：目标 / 边界（只动哪些文件）/ 回传格式 / 验收标准

子代理回传强制格式（缺一打回）：结论 / 证据 / 分析 / 缺口与风险 / 建议入档位置

### 终审与验证（金条八）
- 所有子任务结果由你**终审**后才对外生效
- 不合格 → 带失败原因打回重做（最多 3 轮，超限挂起）
- 代码任务终审必须实际运行验证（`moon test` / `moon check`），不靠自述

### 记忆沉淀与汇报（金条五）
任务结束（终审通过后）立即：
1. 追加当日日志：`memory/YYYY-MM-DD.md`
2. 生成汇报：`reports/YYYY-MM-DD-<任务名>-report.md`
   必填：结果摘要 / 资源消耗 / 任务分配记录 / 遗留风险 / 后续建议 / 超额内容 / 来源

## Project Structure

- MoonBit packages are organized per directory; each directory contains a
  `moon.pkg` file listing its dependencies. Each package has its files and
  blackbox test files (ending in `_test.mbt`) and whitebox test files (ending in `_wbtest.mbt`).

- In the toplevel directory, there is a `moon.mod` file listing module metadata.

## Coding convention

- MoonBit code is organized in block style, each block is separated by `///|`,
  the order of each block is irrelevant. In some refactorings, you can process
  block by block independently.

- Try to keep deprecated blocks in file called `deprecated.mbt` in each
  directory.

## Tooling

- `moon fmt` is used to format your code properly.

- `moon ide` provides project navigation helpers like `peek-def`, `outline`, and
  `find-references`.

- `moon info` is used to update the generated interface of the package, each
  package has a generated interface file `.mbti`, it is a brief formal
  description of the package.

- In the last step, run `moon info && moon fmt` to update the interface and
  format the code. Check the diffs of `.mbti` file to see if the changes are
  expected.

- Run `moon test` to check tests pass. MoonBit supports snapshot testing; when
  changes affect outputs, run `moon test --update` to refresh snapshots.

> 环境要求：新环境首次先 `moon update` 刷新 registry（依赖全公开，无私有包）；
> **JS 目标需 Node.js ≥ 24**（项目默认 target，SQLite 后端依赖 `node:sqlite` 的 `returnArrays`，
> node <24 会退化为对象行导致列读取为空）。见 README「环境要求」。
> **JS 可执行产物 ESM 兼容**：moonc ≥0.10.14 对 `cmd/main` 输出 ESM，而 `mizchi/sqlite` 的 JS 桩用 CJS `require`，
> 直接 `node main.js` 会报 `require is not defined`。`scripts/mcp_smoke.py` / `demo.ps1` 启动前会自动调
> `scripts/patch_esm_main.py` 注入 require shim（幂等）；手动跑 server 请先 `python scripts/patch_esm_main.py`。

### native 目标构建环境要求

> 全部项目 `moon.pkg` 已内置 native 链接 flag `options(link: {"native": {"cc-link-flags": "-lsqlite3"}})`，
> Linux 下直接可链接系统 SQLite；Windows 下按下列要求配置 sqlite3.h/sqlite3.lib 与 MSVC 环境即可。
> **JS 与 Native 双后端均已在 Windows + WSL(Linux) 通过 233/233 测试。**

`src/store/store_sqlite.mbt` 依赖 `mizchi/sqlite`（native stub），其 `stub.c` 用尖括号 `#include <sqlite3.h>` 并 `#pragma comment(lib, "sqlite3.lib")` 链接系统 SQLite。

- **js 目标（MCP server 默认）**：无需额外安装，`moon test --target js` 直接可用。
- **native 目标**：需要系统 SQLite 开发库（`sqlite3.h` + `sqlite3.lib`）。Windows + MSVC 下：
  1. 下载官方 amalgamation（含 sqlite3.h/sqlite3.c），把 `sqlite3.h`、`sqlite3ext.h` 放进一个目录（如 `C:\sqlite-dev\include`），用 `cl` + `lib` 把 `sqlite3.c` 编译成 `sqlite3.lib`（放 `C:\sqlite-dev\lib`）；
  2. 编译/链接前在**同一会话**加载 `Enter-VsDevShell`（VS Build Tools）并追加 `INCLUDE`/`LIB` 指向该目录（注册表 User 级环境变量会被 moon 自发现的 MSVC 环境覆盖，不生效）；
  3. 之后 `moon test --target native` 即可通过。缺失时 `stub.c` 报 `fatal error C1083: 无法打开包括文件 "sqlite3.h"` / `LNK1104: sqlite3.lib`。
  一键装载上述环境（自动探测 VS + sqlite-dev）：`pwsh ./scripts/native-env.ps1`；
  Windows native **并行**跑全量测试偶发 `0xc0000374`（堆损坏/竞态），建议 `moon test --target native -j 1` 串行（可降低但不保证消除，实测偶仍复现于 server.whitebox）；**权威稳定门槛 = JS 后端（Node ≥ 24，Windows + Linux 233/233）**，见 README「已知边界」。

## MCP Server

本项目通过 `.mcp.json` 暴露 `fist-mbt` MCP Server（**83 tools** + 3 resources + 2 prompts）：

### 生命周期（12）
| 工具 | 说明 |
|---|---|
| `publish` | 发布根任务 |
| `plan` | 拆分子任务 |
| `claim` | 认领任务 |
| `execute` | 记录执行交付物 |
| `submit` | 提交验收 |
| `verify` | 验收通过 |
| `reject` | 验收拒绝（→已打回） |
| `retry` | 打回后重试（→执行中） |
| `pause` | 暂停任务（任意活跃→已暂停） |
| `resume` | 恢复任务（已暂停→已领取） |
| `archive` | 归档任务 |
| `delete` | 删除已归档任务 |

### 查询（2）
| 工具 | 说明 |
|---|---|
| `list` | 列出任务 |
| `get` | 查询任务详情 |

### 运维（6）
| 工具 | 说明 |
|---|---|
| `task_plan_deep` | AO 式递归拆解（可选 `gradient=true` 使子任务带难度梯度与"更简单变体 → 先易后逆推"LADDER 自举提示；可选 `calibrate` 按切片给真实难度 0..5 覆盖位置档） |
| `conflicts_check` | 认领冲突检测 |
| `heartbeat` | 活动信号上报 |
| `heal` | 超时任务回滚（内存版，人工流程） |
| `watchdog_tick` | 看门狗编排（推荐仅用于定时任务；跨进程 heal + 自动续轮） |
| `task_cleanup` | 归档清理 |

> 无人值守流水线统一元提示词模板：`templates/cron_pipeline_meta_prompt.md`（**统一版**，取代原 `watchdog_tick_meta_prompt.md`：单一提示词 + 单一定时任务，一次唤醒内四分支自决策——①心跳新鲜即退出；②心跳超时只交给 `watchdog_tick` 的 heal 分支、不自行重启；③无活跃任务且最新提示词未消费则用该提示词接一个新根任务；④无活跃任务且提示词已消费则分析项目现状生成下一份 `yyyyMMdd.HH.mm.ss.md`。含按目标项目替换的参数清单与无人值守边界说明，仅用于定时任务场景）。

### 项目看板 / 脉冲 / 预订 / 推荐 + DAG（12）
| 工具 | 说明 |
|---|---|
| `dag_critical_path` | 最长依赖链 |
| `dag_parallelism` | 可并行任务数 |
| `dag_ascii` | ASCII 依赖结构图 |
| `dag_check` | 依赖完成检查 |
| `dag_ready` | 可领取任务列表 |
| `dag_sort` | 拓扑排序 |
| `dag_depend` | 显式给任务追加前置依赖（构建 DAG 依赖边，不只靠 plan_deep 隐式父子） |
| `dag_publish` | 发布带依赖关系的根任务 |
| `board_ascii` | 实时任务看板：按状态分组 + 深度缩进渲染，一眼看项目全貌（namespace 可选） |
| `status_summary` | 项目脉冲：{version, total_tasks, by_status, by_difficulty(待领取难度结构 易/中/难/无), active_namespaces}，可接 namespace 过滤；by_difficulty 复用难度单一抽取来源（支柱②） |
| `reserve_scope` / `reserve_check` / `reserve_release` | 作用域预订（拿来主义：Interlinked 文件预订 → 多 agent 并发编辑冲突预防） |
| `task_triage` | 下一步推荐：可领取任务按 能力匹配(want)→优先级→重要度→深度 排行 + suggestion（agent 无需全量扫描即知下一单；want 为能力路由，Marketplookup 雏形）。每条含真实 DAG 依赖 `depends_on`（复用 dag_depend/gradient_dag 建边，"下一单"就绪前驱可见） |

### 自我记忆与自进化（7，F/G 新增强化）
| 工具 | 说明 |
|---|---|
| `memory_consolidate` | verify 通过后把交付物收敛写回 memory/{kind}.md（checkpoint 写时刻） |
| `memory_gc` | memory/{kind}.md 上限+软降权归档（超限把老人条目移入 memory/archive/，不硬删） |
| `memory_link` | 在 memory/links.md 追加 A-Mem 式关联记录，供 plan/claim 前检索注入 |
| `evolve_distill` | 自进化蒸馏：把 verify 通过的任务交付物蒸馏成 [principle] 原则写入 DGM（复用 evolve_upsert 落库） |
| `evolve_lesson` | 失败回流学习：把被打回/失败原因归档成 [lesson] 类目资产入 DGM，供 plan/claim 的 inject 检索「踩过的坑」 |
| `evolve_critic` | Critic 防漂移门禁（SAGE）：入库前纯计算评审拟议的 principle/lesson，与档案库重合≥70% 判「课程漂移/重复」拒收、综合分低于阈值暂缓，规避自进化课程漂移；只评审不写库 |
| `task_challenge` | Challenger 进阶变体（SAGE 四专家环）：对已完成/已归档任务按策略发布更难变体新根任务（[challenge] 标记 + from 溯源 + 重要度升档），构成「由易到难」自推进序列；可选 `critic=true` 开启防漂移门禁（挑战题发布前过 `critic_review`，当前策略漂移自动降档、全部漂移拒发） |

### Marketplace·执行者能力路由（Dynamic 范式） （4，R30-R32）
| 工具 | 说明 |
|---|---|
| `executor_register` | 执行者能力登记（Marketplace 雏形）：为执行者登记能力标签集合（如 [编排,json]），并持久化到 store（跨进程可复现） |
| `executor_route` | 能力路由推荐：给定任务所需能力 need，从已注册执行者按 { 能力覆盖率 desc → 负载(名下活跃任务数) asc } 排序，返回候选 + 最佳执行者，实现"按专长+负载分配"（而非仅靠 agent 自选）；启动会回灌已持久化注册 |
| `executor_clear` | 清空全部执行者能力注册（Marketplace 重置/整洁，防测试残留） |
| `selfdrive_dispatch` | 能力路由自动派单（R32/R33）：取 triage 顶部可领取任务 → 确定所需能力（显式 `want` 优先，否则从任务描述自动抽取已注册能力标签，R33 免手传）→ 经 executor_route 找最佳执行者 → **直接认领给该执行者**（待领取→已领取）；无匹配时回退 `agent`，把"推荐"落成动作 |

### 审计与权限（2）
| 工具 | 说明 |
|---|---|
| `audit_permission` | 角色权限查询 |
| `audit_log` | 追加式审计日志 |

### 多租户命名空间（3）
| 工具 | 说明 |
|---|---|
| `store_open` | 打开命名空间（`scratch=true` 落 temp/ 临时区，不污染仓库根） |
| `store_list` | 列出已打开 ns |
| `store_close` | 关闭命名空间 |

### Omega 强验证（可选开关，默认关闭）

`task_plan_deep` 的可选参数 `omega_strong_verify`（默认 `false`）控制本功能：不传 / `false` 时行为与既有完全一致；传 `true` 时，递归拆解写出的每个子任务带 `omega:required` 标记，进入「语料驱动」强验证流程——**语料创建者 `spec_author`** 创建语料（落 `specs` 表）→ **验证者 `verifier`** 审核并质疑语料（不合格打回创建者重做）→ 执行者执行 → 验证者复验成果与语料（不达标继续打回）。

| 工具 | 说明 | 关键参数 |
|---|---|---|
| `omega_spec_create` | 语料创建者创建本轮语料并持久化到 `specs` 表 | task_id, author(默认 spec_author), content, max_rounds(可选), now |
| `omega_spec_review` | 验证者审核语料：`approve` 放行，其它值为打回 | task_id, reviewer(默认 verifier), verdict, reason(可选), max_rounds(可选), now |
| `omega_result_verify` | 验证者复验执行成果与对应语料 | task_id, reviewer(默认 verifier), verdict, reason(可选), max_rounds(可选), now |
| `omega_status` | 查询强验证进度（开关 / 轮次 / 打回数 / 升级标志） | task_id |

- 打回上限 `max_rounds` 默认 3（最大 10），超限自动写入升级记录、暂停任务转人工裁决，禁止死循环。
- `execute` 与 `verify` 在开启强验证的任务上分别受语料门禁与成果复验门禁约束；未开启该开关的任务完全不受影响，既有生命周期语义不变。

Resources: `fist://map`, `fist://principles`, `fist://overview`
Prompts: `fist:check_in`, `fist:verify`

## 路径约定

| 项 | 值 |
|---|---|
| FIST 根 | `<FIST-项目根目录>` |
| FIST SKILL 全文 | `<FIST-项目根目录>/FIST-SKILL.md` |
| FIST-Mbt 根 | `<FIST-Mbt-项目根目录>` |
*（内容由AI生成，仅供参考）*
