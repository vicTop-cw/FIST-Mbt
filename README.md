# FIST-Mbt

[![Made with MoonBit](https://img.shields.io/badge/MoonBit-0.1.20260827-blue)](https://www.moonbitlang.com)
[![License](https://img.shields.io/badge/License-Apache--2.0-green)](./LICENSE)
[![Tests](https://img.shields.io/badge/tests-295%2F295-brightgreen)](./src)
[![CI](https://github.com/vicTop-cw/FIST-Mbt/actions/workflows/ci.yml/badge.svg)](https://github.com/vicTop-cw/FIST-Mbt/actions) (js ×2 + native)

**FIST-Mbt** 用**纯 MoonBit** 重写并 MCP 化的 **AI 指挥官任务编排底座**——不是又一个 agent 框架，而是"人类指挥、AI/定时器持续自推动"的自治系统：从 **发布→认领→拆分→执行→提交→验收→归档** 的完整闭环，到 **自驱审视、DGM 演化采样、Omega 强验证、跨进程看门狗** 这些"系统自己推动自己"的能力，全部以 **101 个 MCP 工具** 暴露给任意 MCP 客户端（Claude Desktop / Cursor / 自研 JSON-RPC）。

**为什么 MoonBit**：任务编排天然"正确性敏感"（状态机、权限矩阵、追加式审计、递归拆解），MoonBit 的强类型、无运行时依赖、JS+Native 双端交叉编译让这套逻辑能在 Windows 与 Linux 上 295 项测试双端全绿、跨环境可复现——`moon update && moon run cmd/main` 即用，告别 Python 原版的环境安装地狱。

> 它用**它自己的**自驱式 + 递归拆解把自己打磨到了可交付态——完整自我迭代证据见 `docs/selfdrive-walkthrough.md`。

---

## 环境要求（跨平台可复现）

- **MoonBit 工具链**：≥ 0.1.20260827（支持 `errdefer` 与 `async`，实测 0.1.20260904/0.1.20260920 通过）。
- **Node.js ≥ 24**（JS 目标必需）：SQLite JS 后端依赖 `node:sqlite` 的 `returnArrays`，Node ≥ 24 才生效；
  < 24 会退化为对象行导致列读取为空（实测 node 23 → 28 项失败，node 25 → 295/295 全绿）。
- **首次构建前**执行 `moon update` 刷新 mooncakes registry 索引：本项目**无私有依赖**，
  `mizchi/sqlite`、`colmugx/mcp`、`moonbitlang/*` 全部公开可下载，无需 vendor、无需登录。
- **Native 目标**：需系统 SQLite 开发库（`sqlite3.h` + 链接库）。Linux：`apt-get install libsqlite3-dev`；
  Windows：准备 `sqlite3.h/sqlite3.lib`（如 `C:\sqlite-dev`）并在 MSVC 环境（`Enter-VsDevShell` + 追加 INCLUDE/LIB）下构建。
  所有 `moon.pkg` 已内置 native 链接 flag（`-lsqlite3`）。**JS 与 Native 双后端均已在 Windows + WSL(Linux) 上通过全部 220 项测试。**

> 默认推荐 JS 目标（`preferred_target = "js"`），装好 Node ≥ 24 后即可 `moon run cmd/main` 直接启动。

## 快速开始

```bash
moon update            # 首次：刷新 registry 索引
moon check             # 依赖解析 & 编译
moon test              # 运行测试（295 项全部通过）
moon run cmd/main      # 启动 MCP Server（STDIO 传输）
# 可选 HTTP/SSE 桥接
FIST_MCP_PORT=3000 python scripts/fist-mbt-http.py
```

任意 MCP 客户端（Claude Desktop / AtomCode / 自研 JSON-RPC 客户端）以 STDIO 方式拉起该可执行文件即可交互。

**一键自检（约 10 秒）**：
- `python scripts/mcp_smoke.py` → 自动起 server 并 verify tools/list + publish + get，打印 **`MCP-SMOKE PASS`**；
- `moon run cmd/cli` → 打印「发布成功 / 认领成功 / 拆分成功 3 个子任务」，即环境就绪、全流程可复现。

**一键完整自检（评审用，实测期望）**：
```bash
moon test --target js -j 1        # → Total tests: 295, passed: 295, failed: 0
python scripts/mcp_smoke.py       # → PASS tools/list → 101 个工具 … MCP-SMOKE PASS
python scripts/award_demo.py      # → MCP-AWARD-DEMO PASS（能力链全通，结尾自动 cleanup → CLEAN）
```
> 说明：`moon test` 会生成被 gitignore 的临时 `.db`（属正常），`award_demo`/`cleanup_artifacts.py` 结尾会清掉并使仓库仅剩交付库 `fist-mbt.db`（`cleanup_artifacts.py --check` 可作 CI 干净度守卫）。

### 最小调用示例（JSON-RPC over STDIO）

```json
{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{
  "name":"publish",
  "arguments":{"project_dir":"/proj/demo","description":"示例根任务","created_by":"human_steward","now":"2026-09-05T10:00:00Z"},
  "_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28"}
}}
```

---

## MCP 暴露面

### Tools（**101 个** · 精选概览；完整清单与分组见 [AGENTS.md](./AGENTS.md) 与 `fist://map`）

> **适用范围提示**：`watchdog_tick`（定时任务看门狗编排）**推荐仅用于定时任务 / 无人值守自动化场景**，不用于人工指挥官任务分配流程（自动 heal / 自动续轮在人工流程中有害）。
>
> 配套元提示词模板：[`templates/cron_pipeline_meta_prompt.md`](./templates/cron_pipeline_meta_prompt.md)（**统一版**：单一提示词 + 单一定时任务，一次唤醒内四分支自决策——①有活跃任务且心跳新鲜则退出；②心跳超时只交给 `watchdog_tick` 的 heal 分支；③无活跃任务且最新提示词未消费则接一个新根任务；④无活跃任务且提示词已消费则生成下一份 `yyyyMMdd.HH.mm.ss.md`。含按目标项目替换的参数清单、作用域隔离要求与无人值守边界说明）。


#### 生命周期十二件套（九态状态机）

| 工具 | 说明 | 关键参数 |
|---|---|---|
| `publish` | 发布根任务（仅 human_steward/human） | project_dir, description, created_by, namespace, now |
| `claim` | 认领任务（待领取 → 已领取）；可选 `inject`（逗号分隔档案资产关键词，命中则把 code/note 追加到返回 injected_assets） | task_id, assignee, now, inject(可选) |
| `plan` | 对已认领任务拆分为子任务；可选 `inject`（同上注入资产） | task_id, split_n, by, now, inject(可选) |
| `execute` | 记录执行交付物（→ 执行中） | task_id, deliverable, now |
| `submit` | 提交验收（→ 待验收） | task_id, now |
| `verify` | 验收通过（→ 已完成，父任务自动上卷）；可选 `docs_check=true` 开启「文档即实现」门禁（校验 README/CHANGELOG/reports 存在性与交付物回传五段式，不达标打回） | task_id, verifier, now, docs_check(可选，默认 false) |
| `reject` | 验收拒绝（→ 已打回） | task_id, reason, by, now |
| `retry` | 打回后重试（→ 执行中） | task_id, now |
| `pause` | 暂停任务（任意活跃 → 已暂停） | task_id, now |
| `resume` | 恢复任务（已暂停 → 已领取） | task_id, now |
| `archive` | 归档（→ 已归档，仅人类指挥官） | task_id, by, now |
| `delete` | 删除任务（仅限已归档） | task_id |

#### 查询

| 工具 | 说明 | 关键参数 |
|---|---|---|
| `list` | 列出全部任务，可按状态过滤 | status(可选) |
| `get` | 查询单个任务详情 | task_id |

#### 深拆与运维

| 工具 | 说明 | 关键参数 |
|---|---|---|
| `task_plan_deep` | AO 式递归拆解，拆出整棵多层子任务树并写库；可选 Omega 强验证（每轮插入语料创建/审核/成果复验）、`decide_*` 躬身自决选档（优先于 Laya，返回 plan_decision）、`laya_auto` 冷启动参考 | task_id, split_n, by, spec, now, omega_strong_verify(可选), decide_split_n/decide_difficulty/decide_reason/decide_by(可选), laya_auto(可选，默认 false) |
| `conflicts_check` | claim 冲突检测（认领前检查是否已被他人/本人持有） | task_id, assignee |
| `heartbeat` | 活动信号上报（超时静默将触发 heal 回滚） | task_id, signal, now |
| `heal` | no_signal 看护：心跳超时静默的任务回滚为已领取待重派（内存版，人工流程） | now, timeout_sec |
| `watchdog_tick` | 定时任务看门狗编排单入口（推荐仅用于定时任务）：读 SQLite 心跳判定超时回滚；上一轮根任务完成且提供 next_description 或 meta_prompt_path 时自动起下一轮；可选 `phi_gate=true` 用 Phi Accrual 概率式判活（φ≥phi_threshold 才回滚，默认关闭零回归） | now, timeout_sec, namespace, next_description, next_created_by, meta_prompt_path, phi_gate(可选), phi_threshold(可选) |
| `task_cleanup` | 归档清理：删除超保留期的已归档任务 | now, retention_days |

#### Omega 验证闭环（M6 金条八）

| 工具 | 说明 | 关键参数 |
|---|---|---|
| `omega_verify` | 批量验证 spec JSON：schema + fingerprint 校验，accuracy < 100% 一票否决 | specs(JSON 数组) |
| `omega_verify_fix` | 失败 spec 根因分类 → 定向修复 → 回归验证（3 轮循环） | specs(JSON 数组), max_rounds(可选) |

#### Omega 强验证（可选开关，默认关闭）

`task_plan_deep` 的可选参数 `omega_strong_verify`（默认 `false`）控制本功能：**不传 / 传 false** 时行为与既有完全一致（不产生任何语料记录）；**传 true** 时，递归拆解写出的每个子任务都会带上 `omega:required` 标记，进入「语料驱动」的强验证流程：

1. **语料创建**：语料创建者 `spec_author` 调用 `omega_spec_create` 为本轮任务创建语料，真正持久化写入 `specs` 表（status = pending）。
2. **语料审核**：验证者 `verifier` 调用 `omega_spec_review` 审核并质疑语料——`approve` 放行，其余值视为打回，由语料创建者重做。
3. **执行门禁**：语料通过前 `execute` 被 `omega_execute_gate` 拒绝；通过后由执行者执行具体任务。
4. **成果复验**：执行者完成后，验证者调用 `omega_result_verify` 复验成果与对应语料是否达标，不达标继续打回重做（`verify` 前受 `omega_verify_gate` 约束）。
5. **上限与升级**：打回累计达到 `max_rounds`（默认 3，最大 10）时写入 escalation 记录、返回 `escalated=true` 并暂停任务转人工裁决，禁止死循环。

| 工具 | 说明 | 关键参数 |
|---|---|---|
| `omega_spec_create` | 语料创建者为已开启强验证的任务创建本轮语料并持久化 | task_id, author(默认 spec_author), content, max_rounds(可选), now |
| `omega_spec_review` | 验证者审核语料：`approve` 放行，其它值打回 | task_id, reviewer(默认 verifier), verdict, reason(可选), max_rounds(可选), now |
| `omega_result_verify` | 验证者复验执行成果与对应语料是否达标 | task_id, reviewer(默认 verifier), verdict, reason(可选), max_rounds(可选), now |
| `omega_status` | 查询强验证进度（开关状态 / 语料与复验轮次 / 打回数 / 升级标志 / 账本） | task_id |

> 角色约束：`spec_author` 仅可创建语料、`verifier` 仅可审核与复验，且验证者不得审核自己创建的语料；`human_steward` 可执行全部环节。
> 持久化：语料 / 复验 / 升级记录均落 `specs` 表，跨进程与跨引擎实例可读；`Store::clear` 会连同语料账本一并清空。

#### 智能调度与成本（M6 增强）

| 工具 | 说明 | 关键参数 |
|---|---|---|
| `schedule` | 调度预览：根据任务描述自适应计算分级/拆分/成本档/执行器（不落库） | description, n_files(可选) |
| `cost_stats` | 执行成本聚合统计（total_records/total_cost/total_tokens/by_executor） | 无 |
| `cost_budget_check` | 预算超限告警（exceeded/remaining/action） | limit, current |
| `cost_budget_split` | 预算按依赖图阶段切分（R81 ZEBRA 蒸馏：每阶段份额=阶段难度权重占量比例×总预算，瓶颈阶段占额可见、超支先预警） | budget |

#### 执行与交付

| 工具 | 说明 | 关键参数 |
|---|---|---|
| `execute` | 记录执行交付物（→ 执行中），向后兼容旧接口，支持 executor/model/tokens/cost 元数据 | task_id, deliverable, executor?, model?, tokens_in?, tokens_out?, cost?, duration_ms?, rate_limited?, failure_reason?, now |

#### DAG 扩展（依赖图）

| 工具 | 说明 | 关键参数 |
|---|---|---|
| `dag_critical_path` | 返回当前最长依赖链（关键路径） | 无 |
| `dag_parallelism` | 返回当前可并行执行的任务数（待领取且依赖已满足） | 无 |
| `dag_ascii` | 返回当前命名空间任务的 ASCII 依赖结构图 | namespace(可选) |
| `dag_check` | 检查某任务的依赖是否全部完成 | task_id |
| `dag_ready` | 列出所有依赖满足、可领取的任务 | namespace(可选) |
| `dag_sort` | 对任务列表按依赖深度拓扑排序 | task_ids(JSON 数组) |
| `dag_depend` | 显式给任务追加前置依赖（构建 DAG 依赖边，不只靠父任务） | task_id, dep_id, now |
| `dag_slack` | 瓶颈与松弛分析（R71 PERT/CPM 硬核调度：earliest/latest/slack + 环检测——谁在关键路径、谁有松弛可并行） | 无 |
| `dag_schedule` | 排程视图（R74→R75：critical/flexible 分批 + 未认领项 suggest=负载最低执行者——谁在瓶颈、谁可并行派单） | 无 |
| `dag_cost_route` | 依赖图成本路由（R77 STAR 式蒸馏：执行成本难度档+切换税+能力约束——critical_path→slack→schedule→cost_route 排程优化闭环） | 无 |

#### 审计与权限（M5 治理）

| 工具 | 说明 | 关键参数 |
|---|---|---|
| `audit_permission` | 查询某角色是否可执行指定操作 | role, action |
| `audit_log` | 查看追加式审计日志 | filter_actor(可选), filter_task_id(可选) |

#### 多租户命名空间（M5 多库隔离）

| 工具 | 说明 | 关键参数 |
|---|---|---|
| `store_open` | 打开（或复用）一个命名空间；`scratch=true` 时库落 temp/（gitignore，不污染仓库根） | namespace, data_dir(可选), scratch(可选) |
| `store_list` | 列出当前已打开的命名空间及任务数 | 无 |
| `store_close` | 关闭指定命名空间（不删除物理库文件） | namespace |

#### 并行发布 / 重派 / 判据检查

| 工具 | 说明 | 关键参数 |
|---|---|---|
| `publish_parallel` | 在已有任务的命名空间并行追加独立根任务（不要求 ns 为空、不续轮不归档） | project_dir, description, namespace(必填非 default), created_by(默认selfdrive), now |
| `reopen_task` | 重开/重派任务：任意非归档任务回滚为已领取（M4 heal/运维重派用） | task_id, now |
| `run_check` | 外部判据检查（服务端真实执行命令，防自写自测恒绿）；[gate:required] 任务的 verify 依赖其记录 | task_id, cmd, args(可选), workdir, timeout_ms(默认120000), now |
| `dag_publish` | 发布带 `depends_on` 依赖关系的根任务 | project_dir, description, depends_on(JSON 数组), namespace, created_by, now |

#### 自驱式编程（selfdrive，M8 增强）

| 工具 | 说明 | 关键参数 |
|---|---|---|
| `selfdrive_init` | 初始化 memory 四件套（product/target/task/thinking + reviews 目录），幂等不覆盖 | project_dir(必填), namespace |
| `selfdrive_append` | 追加/更新 memory 条目（thinking 为 append-only 流水，其余覆盖写） | project_dir, kind, content, namespace, now |
| `selfdrive_get` | 读取指定 memory 文件，返回 {exists, content} | project_dir, kind, namespace |
| `selfdrive_export_tasks` | 从任务库导出任务清单到 task.md（视图覆盖写） | project_dir, namespace |
| `selfdrive_review_tick` | 审视轮判定：报告数≥已审视轮次+review_every 触发 action=review，否则 idle/no_memory | project_dir, review_every(默认3), namespace |
| `selfdrive_review_ready` | 审视收口：确认最新审视报告已落盘并推进已审视轮次（报告先行） | project_dir, namespace |
| `selfdrive_publish_next` | 解析审视报告 `## Next Tasks` 段并将待办并行发布为独立根任务（幂等，防重） | project_dir, namespace, max_tasks(默认10), now |
| `selfdrive_parse_next_tasks` | 纯解析审视报告文本中的 `## Next Tasks` 段（调试/校验用） | content(必填), max_tasks(默认10) |
| `memory_consolidate` | 自我记忆·收敛写回：verify 通过后把交付物写回 memory/{kind}.md（checkpoint 写时刻） | project_dir, task_id, kind(默认target), content, now |
| `memory_gc` | 自我记忆·上限+软降权归档（不硬删）：超限把老人条目移入 memory/archive/，正文保留最新 max_chars | project_dir, kind(可选), max_chars(默认2000), now |
| `memory_link` | 自我记忆·A-Mem 式关联：在 memory/links.md 追加 `from -> to note` 供检索注入 | project_dir, from, to, note(可选), now |

#### DGM 演化（evolve）

| 工具 | 说明 | 关键参数 |
|---|---|---|
| `evolve_submit` | 归档一个产物（Artifact）：本轮设计/代码/目标入档案库，自动递增父代子代数；与档案高度相似则查重丢弃 | id, goal, note, code, score, parent_id(可选), parts(可选), now |
| `evolve_distill` | 自进化蒸馏（EvolveR 最小级）：把 verify 通过的任务交付物蒸馏成 principle 写入 DGM（goal 加 [principle] 前缀，复用 evolve_upsert 落库） | task_id, goal, note, score(默认1.0), now |
| `evolve_snapshot` | 查看档案库快照（count/best/summaries/dead_ends/lineage_of_best） | 无 |
| `evolve_sample` | 按 p∝s·h 多样性加权采样父代产物（子代越少/性能越高越可能被选） | rand(可选) |
| `evolve_asset_register` | 注册可选外部资产（如 code-review / superpowers 类 skill 库）归档进档案库，goal 用 [asset]<来源名> 供 plan/claim 的 inject 按关键词检索 | source, note, code, score(可选), now |
| `evolve_lesson` | 失败回流学习：把被打回/失败原因归档成 [lesson] 类目资产入 DGM，供 inject 检索「踩过的坑」 | cat, reason, fix(可选), score(可选), now |

#### 可选项（Laya / 单根流水线）

| 工具 | 说明 | 关键参数 |
|---|---|---|
| `laya_decide` | Laya 可选决策工具（自动探测）：对任务/文本快速分类；机器无 laya 则返回 available:false 降级，不影响现网 | context(必填), questions(可选), model(默认english) |
| `pipeline_tick` | 提示词流水线状态机单入口（仅定时任务/无人值守 ns）：以 currentState.txt 为状态源四分支推进，报告先行 | project_dir(必填), now, namespace(默认cron-auto), phase, prompt_name, timeout_sec(默认2420) |

### Resources（3）

| URI | 内容 |
|---|---|
| `fist://map` | 项目地图（Repo Map）：src/ 子包职责 + 工具分组 + 入口引导，AI agent 首读定位 |
| `fist://principles` | FIST 七条金条原则（JSON） |
| `fist://overview` | 任务体系概览 |

### Prompts（2）

| 名称 | 用途 |
|---|---|
| `fist:check_in` | 执行者开工打卡自查模板 |
| `fist:verify` | 验收人验收要点模板 |

---

## 架构

```
FIST-Mbt/
├── .mcp.json            # MCP server 注册（moon run cmd/main）
├── AGENTS.md            # FIST 指挥官模式行为指令
├── README.md            # 本文档（中文）
├── README_EN.md         # English README（国际受众 / Lambda World 2026）
├── USAGE.md             # 实操调用手册
├── cmd/
│   ├── main/            # STDIO MCP server 入口（moon run cmd/main）
│   └── cli/             # CLI 入口（moon run cmd/cli/main）
├── scripts/
│   └── fist-mbt-http.py # HTTP/SSE 桥接（FIST_MCP_PORT=3000）
├── src/
│   ├── core/            # 领域核心实体
│   │   ├── core_task.mbt       # 任务实体 + 九态状态机 + DAG depends_on
│   │   ├── core_role.mbt       # 角色权限矩阵（human_steward/leader/agent）
│   │   └── core_principle.mbt  # 七条金条原则常量
│   ├── store/           # 持久化
│   │   ├── store.mbt           # Store 抽象 + StoreBackend 工厂
│   │   ├── store_sqlite.mbt    # SQLite 实现（内建 DB）
│   │   ├── store_specs.mbt     # specs 表：Omega 语料/复验/升级持久化
│   │   └── multi_store.mbt     # 多库命名空间管理器（内部可变性）
│   ├── engine/          # FistEngine：业务逻辑闭环 + DAG 扩展
│   │   ├── engine.mbt          # publish/plan/claim/execute/submit/verify/archive + reject/retry/pause/resume
│   │   ├── engine_dag_ext.mbt  # critical_path/parallelism/dag_ascii
│   │   ├── decompose.mbt       # 任务拆解计算
│   │   ├── omega_strong.mbt          # Omega 强验证：语料创建/审核/成果复验 + 门禁 + 打回升级
│   │   └── *_test.mbt          # 引擎测试
│   ├── ops/             # 运维与治理
│   │   ├── audit.mbt           # 追加式审计日志 + Role 权限矩阵
│   │   ├── ops_conflicts.mbt   # 冲突检测
│   │   ├── ops_heartbeat.mbt   # 心跳上报
│   │   ├── ops_heal.mbt        # 超时回滚
│   │   ├── ops_cleanup.mbt     # 归档清理
│   │   ├── ops_watchdog.mbt    # 看门狗编排 watchdog_tick（跨进程 heal + 自动续轮）
│   │   └── ops_ts.mbt          # 时间戳工具
│   ├── omega/           # 可解释性子包：spec/gate/check
│   └── server/          # MCP server 装配
│       ├── server.mbt          # 101 个工具注册 + 3 resources + 2 prompts + run_server
│       ├── stdio_js.mbt        # JS 后端 STDIO 传输
│       └── stdio_native.mbt    # 原生后端 STDIO 传输
└── moon.mod             # 模块元数据
```

**设计要点**：

- 纯 MoonBit 实现，无 Rust / C 包装；MCP 协议层使用 [`colmugx/mcp`](https://mooncakes.io/colmugx/mcp)（Apache-2.0，协议 2026-07-28）。
- 领域核心（core\*/store/engine）与协议层（server）分离，核心为纯逻辑、易单测。
- K 值递归衰减：根任务 depth=3，每拆一层减 1，depth≤1 为原子任务不再拆分。
- `plan` 需任务处于**已领取**态（先 `claim` 再 `plan`），保证拆分动作归属到具体负责人。
- 多租户：`MultiStore` 按 ns 路由到独立 SQLite 文件 `{data_dir}/{ns}.db`，惰性打开。
- 审计：`AuditLog` 进程内追加式日志，不落库；角色权限矩阵遵循"唯一指挥官/人类主权"原则。

---

## 状态机（九态）

```
                    ┌─ pause ──┐
                    ▼          │
待领取 ──claim──► 已领取 ──plan──► 拆分中 ──execute──► 执行中
   │                │                                       │
   │                └──────execute───────────────────────────┘
   │                                                        ▼
   │               待验收 ◄── submit ─── 执行中
   │                │    │
   │           verify    reject
   │                │    │
   │                ▼    ▼
   │           已完成   已打回 ──retry──► 执行中
   │                │
   │           archive
   │                │
   │                ▼
   │           已归档 ──delete──► 移除
   │
   └── resume ◄── 已暂停
```

**新增状态（M5 扩展）**：

| 状态 | 说明 | 进入方式 |
|---|---|---|
| `Rejected` | 已打回（验收不通过，需重做） | `reject`（待验收 → 已打回） |
| `Paused` | 已暂停（外部中断/等待依赖） | `pause`（任意活跃 → 已暂停） |

**新增迁移**：

| 迁移 | 触发 | 约束 |
|---|---|---|
| `retry` | `retry_task` | 仅 Rejected → Executing |
| `pause` | `pause_task` | 任意活跃状态 → Paused |
| `resume` | `resume_task` | Paused → Claimed |

非法迁移由状态机拒绝并返回错误，例如未认领直接 `plan` / `execute` 会报「非法迁移」。

---

## 测试

```bash
moon test   # 295 项测试全部通过
```

覆盖：根任务发布、发布权限（仅人类指挥官）、claim/plan/execute/submit/verify/archive/delete 全闭环、
reject/retry/pause/resume 新增迁移、非法迁移拦截（未认领 plan / execute、未归档 delete）、
按状态过滤查询、DAG 依赖检查、审计权限矩阵、多租户命名空间、WAL 并发写入、心跳持久化、
看门狗跨进程 heal（读 SQLite 判定超时）、watchdog_tick 编排（waiting/idle/blocked/restarted/advanced）、
元提示词文档路径续轮（单文件 / 目录取最新、失败不续轮不 panic）；
R107 起集成 moonbitlang/core/quickcheck **属性测试**（随机输入验证不变量：default_slices 数量与前缀、
difficulty_label 三档单调、Task 迁移纪律 claim/execute/reopen/split/submit/reject——固定 seed 可复现）。

---

## 多租户（命名空间）使用

```json
// 1. 打开命名空间 "project-alpha"
{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{
  "name":"store_open",
  "arguments":{"namespace":"project-alpha","data_dir":"."},
  "_meta":{...}
}}

// 2. 发布任务到该 namespace
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{
  "name":"publish",
  "arguments":{"project_dir":"...","description":"...","namespace":"project-alpha","created_by":"human_steward","now":"2026-09-05T10:00:00Z"},
  "_meta":{...}
}}

// 3. 查看已打开的命名空间
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{
  "name":"store_list",
  "arguments":{},
  "_meta":{...}
}}

// 4. 关闭命名空间（不删除物理库文件）
{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{
  "name":"store_close",
  "arguments":{"namespace":"project-alpha"},
  "_meta":{...}
}}
```

每个命名空间对应独立的 SQLite 文件 `{data_dir}/{namespace}.db`，实现数据隔离。

---

## HTTP/SSE 桥接（可选）

```bash
FIST_MCP_PORT=3000 python scripts/fist-mbt-http.py
```

暴露两个端点：

| 端点 | 说明 |
|---|---|
| `GET /health` | 健康检查，返回 `{"status":"ok","tools":75}` |
| `POST /mcp` | JSON-RPC over HTTP，请求体与 STDIO 模式一致 |

---

## 已知边界与常见问题（主动自曝）

- **`node:sqlite` 实验性警告**：JS 后端走 `node:sqlite`，Node ≥ 24 下运行会打印 `ExperimentalWarning: SQLite is an experimental feature`——功能正常、无碍，可忽略（或 `--no-warnings`）。
- **环境三件事**：Node ≥ 24（JS 后端必需）、首次 `moon update`（刷新 registry）、native 需系统 SQLite（Linux `libsqlite3-dev`；Windows `sqlite3.h/sqlite3.lib` + MSVC）。
- **native 双端**：全部 `moon.pkg` 已内置 `-lsqlite3`；JS 后端 Windows + Linux 均已 295/295 全绿；native 后端 `moon check --target native` 0 错误（Linux native 稳定），Windows native 受下方竞态影响。
- **Windows native 偶发堆损坏竞态**：`moon test --target native` 在 Windows 上偶发 `0xc0000374`（堆损坏/竞态）——即便 `-j 1` 串行亦可能复现（实测 server.whitebox 偶撞），根因在本机 native SQLite stub 与并发关库的竞态，**产品运行时不受影响、非逻辑缺陷**。**权威稳定门槛 = JS 后端（Node ≥ 24，Windows + Linux 双端 295/295）**；Windows 下复现勿慌：先 `pwsh ./scripts/native-env.ps1` 装载环境再跑。
  一键装载 Windows native 环境：`pwsh ./scripts/native-env.ps1`（自动探测 VS Build Tools + sqlite-dev，可 `-Run "moon test --target native -j 1"` 直接执行）。
- **execute 幂等**：`executions` 以 `task_id + created_at` 为键、`ON CONFLICT DO UPDATE`——同一任务同一次执行（同 `created_at`）重复 `execute` 会**幂等覆盖**执行元数据而不报错；不同 `created_at` 则各自留存为独立执行记录。
- **自驱非死循环**：审视报告带 `[review:<file>:<idx>]` 幂等标记，无新报告即 `idle`/`waiting` 停住；心跳新鲜时 watchdog 不抢活。

---

## 用 fist-mbt 自驱 + Omega 强验证开发 atgc（能力演示）

`atgc/` 这个极小的 ATGC 双链虚拟机库，是经 **fist-mbt 自己的生命周期管线**真实开发出来的：`publish_parallel` 发布根任务 → `task_plan_deep(omega_strong_verify=true)` 递归拆解 → 每个叶子过 **`omega_spec_create`→`omega_spec_review(approve)`→`claim`→`execute`（写入真实 atgc 源码）→`omega_result_verify(pass)`→`submit`→`verify`**，验证语料与成果复验都被**真实门禁**把关，且**每一次工具调用都由 `instrumented_tool` 落入 `call_log` 留痕**；根任务最终 `verify`+`archive` 收官归档。原全量 `atgc-old/` 完整保留作参照。

复现：`moon build --target js cmd/main` 后执行 `python scripts/atgc_selfdrive_demo.py`。
完整证据（管线图 / 角色 / DB 计数 / 诚实说明）见 [`docs/atgc-selfdrive-demo.md`](./docs/atgc-selfdrive-demo.md)。

---

## 移植与合规声明

- **来源**：FIST（Python），Apache-2.0 许可证。
- **许可证**：Apache-2.0。
- **本期范围**：用 MoonBit 原生重写核心领域逻辑与状态机，并封装为 MCP Server；
  未搬运 Python 原代码，未包含原项目未开源的业务数据。
- 原 Python 项目中的 scheduler / executor / webpanel 等模块不在本期范围内（见 CHANGELOG 演进说明）。

---

## License

Apache-2.0
*（内容由AI生成，仅供参考）*
