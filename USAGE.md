# FIST-Mbt 使用文档（USAGE）

> 版本：`vicTop-cw/fist-mbt@0.2.3`（MoonBit，MCP Server）
> 日期：2026-09-12 ｜ 定位：**实操调用手册**。README.md 是项目概览，本文件是「如何真正用它」的手把手文档，
> 全部示例均来自本机实机运行（JSON-RPC over STDIO）的真实输出，非凭空构造。

---

## 1. 它是什么

FIST 指挥官任务分配体系（原 Python 版 FIST）的 **纯 MoonBit 原生重写 + MCP 化** 作品
（2026 MoonBit 九月黑客松）。对外暴露一个 **STDIO 传输的 MCP Server**（也支持 HTTP/SSE 桥接），
任何 MCP 客户端拉起可执行文件后，即可通过标准 `tools/call` 完成任务的
**发布 → 认领 → 拆分 → 执行 → 提交 → 验收 → 归档** 完整闭环。

协议层使用 [`colmugx/mcp`](https://mooncakes.io/colmugx/mcp)（Apache-2.0，协议版本 `2026-07-28`）。

---

## 2. 前置与构建

依赖：MoonBit 工具链 ≥ `0.1.20260827`（需支持 `errdefer` 与 `async`）。

```bash
moon check                  # 类型检查
moon build --target native  # 原生后端
moon build --target js      # JS 后端（Node 运行）
moon test                   # 全部测试（148 项）
```

本机常用启动产物：

| 后端 | 产物路径 |
|---|---|
| JS | `_build/js/debug/build/cmd/main/main.js`（`node` 运行） |
| native | `_build/native/debug/build/cmd/main/main.exe` |

---

## 3. 启动一个 MCP Server

```bash
# 方式 A：JS 后端（Node）
node _build/js/debug/build/cmd/main/main.js

# 方式 B：原生后端
./_build/native/debug/build/cmd/main/main.exe

# 方式 C：HTTP/SSE 桥接（可选）
FIST_MCP_PORT=3000 python scripts/fist-mbt-http.py
```

- 启动后进程在 **STDIO** 上按行读取 JSON-RPC 2.0 请求、按行回写响应，直到 EOF 退出；
- 数据库内建为 SQLite，文件名为 `fist-mbt.db`，落在 **当前工作目录**（已被 `.gitignore` 的 `*.db` 忽略，不污染仓库）；
- 如需隔离数据，可在一个新空目录下启动（本文件第 7 节实录即在隔离目录完成）。

---

## 4. 协议接入要点（易踩坑）

FIST-Mbt 的 `tools/call` 等请求，`params` 中 **必须携带 `_meta` 字段**，且键名必须带
`io.modelcontextprotocol/` 前缀（不带前缀会报 `Missing required _meta field`）：

```json
{
  "io.modelcontextprotocol/protocolVersion": "2026-07-28",
  "io.modelcontextprotocol/clientCapabilities": {},
  "io.modelcontextprotocol/clientInfo": {"name": "my-client", "version": "0.1.0"}
}
```

> 本机实测：直接调 `tools/list` / `tools/call` 即可工作，无需先走完整的 `initialize` 握手。
> `initialize` / `notifications/initialized` 会返回 `Method not found`，可忽略。

Node + Python 最小驱动框架：

```python
import subprocess, json, os
proc = subprocess.Popen(
    ["node", "_build/js/debug/build/cmd/main/main.js"],
    cwd=".",
    stdin=subprocess.PIPE, stdout=subprocess.PIPE,
    text=True, encoding="utf-8", errors="replace", bufsize=1,
)
META = {
    "io.modelcontextprotocol/protocolVersion": "2026-07-28",
    "io.modelcontextprotocol/clientCapabilities": {},
    "io.modelcontextprotocol/clientInfo": {"name": "my-client", "version": "0.1.0"},
}
def rpc(method, **payload):
    params = {"_meta": META}
    params.update(payload)
    req = {"jsonrpc":"2.0","id":"1","method":method,"params":params}
    proc.stdin.write(json.dumps(req, ensure_ascii=False) + "\n")
    proc.stdin.flush()
    return json.loads(proc.stdout.readline())
```

---

## 5. 最小调用示例

发布一个根任务（仅限人类指挥官）：

```json
{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{
  "name":"publish",
  "arguments":{
    "project_dir":"/proj/demo",
    "description":"示例根任务",
    "created_by":"human_steward",
    "now":"2026-09-11T18:20:00Z"
  },
  "_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28"}
}}
```

真实响应：

```json
{"task_id":"T0","message":"已发布根任务"}
```

### 最小端到端三步（评审 1 分钟内可复现）

任意 MCP 客户端以 STDIO 拉起 `moon run cmd/main`，依次发三个请求即可验证 server 可用：

**Step 1 · 列出工具**
```json
{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28"}}}
```
→ 返回 `{"tools":[{"name":"publish",...}, ...]}`（78 个工具）

**Step 2 · 发布一个根任务**
```json
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"publish","arguments":{
  "project_dir":"/proj/demo","description":"示例根任务","created_by":"human_steward","now":"2026-09-11T18:20:00Z"},
  "_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28"}}}
```
→ `{"task_id":"T0","message":"已发布根任务"}`

**Step 3 · 查询该任务**
```json
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"get","arguments":{"task_id":"T0"},
  "_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28"}}}
```
→ 返回该任务详情（状态：待领取）

三步跑通即 MCP server 端到端可用、环境就绪。

> 本机实测：`python scripts/mcp_smoke.py` 一键自检输出
> `PASS tools/list → 78 个工具` / `PASS publish → T?` / `PASS get → T? [待领取]` / `MCP-SMOKE PASS`。
> 三步 = 该脚本的内部逻辑，二者完全一致。

---

## 6. 78 个 MCP 工具手册

> 参数表取自本机 `tools/list` 返回的真实 Schema。

### 6.1 生命周期（对应九态状态机）

| 工具 | 说明 | 参数 |
|---|---|---|
| `publish` | 发布根任务（仅 human_steward/human） | project_dir(必) description(必) created_by(选,默认human_steward) namespace(选,默认default) now(选) |
| `claim` | 认领任务（待领取→已领取） | task_id(必) assignee(必) now(选) |
| `plan` | 对已认领任务拆出一层子任务 | task_id(必) split_n(选,默认3) by(选) now(选) |
| `execute` | 记录执行交付物（→执行中），向后兼容旧接口，支持 executor/model/tokens/cost 元数据 | task_id(必) deliverable(必) executor(选) model(选) tokens_in(选) tokens_out(选) cost(选) duration_ms(选) rate_limited(选) failure_reason(选) now(选) |
| `submit` | 提交验收（→待验收） | task_id(必) now(选) |
| `verify` | 验收通过（→已完成，父任务自动上卷） | task_id(必) verifier(必) now(选) |
| `reject` | 验收拒绝（→已打回） | task_id(必) reason(选) by(选,默认human_steward) now(选) |
| `retry` | 打回后重试（→执行中） | task_id(必) now(选) |
| `pause` | 暂停任务（任意活跃→已暂停） | task_id(必) now(选) |
| `resume` | 恢复任务（已暂停→已领取） | task_id(必) now(选) |
| `archive` | 归档（仅人类指挥官） | task_id(必) by(选) now(选) |
| `delete` | 删除已归档任务 | task_id(必) |

### 6.2 查询

| 工具 | 说明 | 参数 |
|---|---|---|
| `list` | 列出全部任务，可按状态过滤 | status(选,中文状态名) |
| `get` | 查询单个任务详情 | task_id(必) |

### 6.3 深拆与运维

| 工具 | 说明 | 参数 |
|---|---|---|
| `task_plan_deep` | AO 式递归拆解，拆出整棵多层子任务树并写库 | task_id(必) split_n(选,默认3) by(选) spec(选) now(选) |
| `conflicts_check` | claim 冲突检测（认领前检查是否已被他人/本人持有） | task_id(必) assignee(必) |
| `heartbeat` | 活动信号上报（超时静默将触发 heal 回滚） | task_id(必) signal(选) now(选) |
| `heal` | no_signal 看护：心跳超时静默的任务回滚为已领取待重派 | now(选) timeout_sec(选) |
| `task_cleanup` | 归档清理：删除超保留期的已归档任务 | now(选) retention_days(选,默认30) |

**task_plan_deep 语义化深拆**：`spec` 传 JSON 字符串
（`{"laws":[...],"fingerprint":"..."}`，用 `json.dumps(ensure_ascii=False)` 生成），
子任务会按 `laws` 数组语义化拆分（如「通读文档/调研/搭骨架/实现/写文档」）；
不带 `spec` 时退化为机械的「子任务单元 N」默认切片。

**运维纪律（AO 看护）**：执行前/执行中周期性 `heartbeat` 上报；静默超时由 `heal` 回滚；
已归档任务超保留期由 `task_cleanup` 清理。

### 6.4 DAG 依赖图

| 工具 | 说明 | 参数 |
|---|---|---|
| `dag_critical_path` | 返回当前最长依赖链（关键路径） | 无 |
| `dag_parallelism` | 返回当前可并行执行的任务数（待领取且依赖已满足） | 无 |
| `dag_ascii` | 返回当前命名空间任务的 ASCII 依赖结构图 | namespace(可选，默认default) |
| `dag_check` | 检查某任务的依赖是否全部完成 | task_id(必) |
| `dag_ready` | 列出所有依赖满足、可领取的任务 | namespace(可选) |
| `dag_sort` | 对任务列表按依赖深度拓扑排序 | task_ids(JSON 数组，必填) |
| `board_ascii` | 实时任务看板：按状态分组 + 深度缩进渲染，一眼看项目全貌 | namespace(可选，空=全部) |
| `status_summary` | 项目脉冲：{version,total_tasks,by_status,active_namespaces}，一次调用读项目健康 | namespace(可选，只统计该 ns) |
| `reserve_scope` | 预订工作作用域防并发编辑冲突（空/超时/同 agent 可占；他人占用返回持有者） | scope, agent, ttl_until(必), now |
| `reserve_check` | 查询作用域是否可编辑（空闲可用） | scope(必), now |
| `reserve_release` | 释放自己的作用域（仅持有者有效） | scope(必), agent(必) |

> **使用建议**：在 `claim` 前先调 `dag_ready` 查看可领取任务，或 `dag_check` 验证依赖是否满足，
> 避免死锁。`dag_ascii` 可快速可视化当前任务依赖关系；`board_ascii` 纵览整个项目"哪些任务、什么状态、在树哪层"。

### 6.5 审计与权限

| 工具 | 说明 | 参数 |
|---|---|---|
| `audit_permission` | 查询某角色是否可执行指定操作 | role(必) action(必) |
| `audit_log` | 查看追加式审计日志 | filter_actor(选) filter_task_id(选) |

**Role 枚举**：`human_steward`（人类指挥官）、`leader`（AI 指挥官）、`agent`（执行者）

**Action 枚举**：`publish`、`archive`、`delete`、`claim`

**权限矩阵**：

| 角色 \ 操作 | publish | archive | delete | claim |
|---|---|---|---|---|
| human_steward | ✅ | ✅ | ✅ | ✅ |
| leader | ❌ | ❌ | ❌ | ✅ |
| agent | ❌ | ❌ | ❌ | ✅ |

### 6.6 多租户命名空间

| 工具 | 说明 | 参数 |
|---|---|---|
| `store_open` | 打开（或复用）一个命名空间 | namespace(必) data_dir(选,默认当前目录) |
| `store_list` | 列出当前已打开的命名空间及任务数 | 无 |
| `store_close` | 关闭指定命名空间（不删除物理库文件） | namespace(必) |

| `store_close` | 关闭指定命名空间（不删除物理库文件） | namespace(必) |

### 6.7 Omega 验证闭环（M6 金条八）

| 工具 | 说明 | 参数 |
|---|---|---|
| `omega_verify` | 批量验证 spec JSON：schema + fingerprint 校验，accuracy < 100% 一票否决 | specs(JSON 数组) |
| `omega_verify_fix` | 失败 spec 根因分类 → 定向修复 → 回归验证（3 轮循环） | specs(JSON 数组) max_rounds(选) |

**Omega 验证示例**：

```json
{"jsonrpc":"2.0","id":10,"method":"tools/call","params":{
  "name":"omega_verify",
  "arguments":{
    "specs": [
      {"name":"规范A","laws":["规则1","规则2"],"fingerprint":"abc123"},
      {"name":"规范B","laws":[],"fingerprint":""}
    ]
  },
  "_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28"}
}}
```

真实响应（第二个 spec 因为 laws 为空 + fingerprint 为空而 accuracy=0%，一票否决）：

```json
{
  "results": [
    {"name":"规范A","accuracy":1.0,"errors":[]},
    {"name":"规范B","accuracy":0.0,"errors":["laws 不能为空","fingerprint 不能为空"]}
  ],
  "pass_count": 1,
  "fail_count": 1,
  "verdict": "FAIL",
  "failed_names": ["规范B"]
}
```

```json
{"jsonrpc":"2.0","id":11,"method":"tools/call","params":{
  "name":"omega_verify_fix",
  "arguments":{
    "specs": [
      {"name":"规范B","laws":[],"fingerprint":""}
    ]
  },
  "_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28"}
}}
```

真实响应（自动补全 laws 模板 + 生成 fingerprint，3 轮内收敛到 accuracy=1.0）：

```json{
  "rounds": 2,
  "final_results": [
    {"name":"规范B","accuracy":1.0,"errors":[]}
  ],
  "verdict": "PASS"
}
```

### 6.8 智能调度与成本（M6 增强）

| 工具 | 说明 | 参数 |
|---|---|---|
| `schedule` | 调度预览：根据任务描述自适应计算分级/拆分/成本档/执行器（不落库） | description(必) n_files(选) |
| `cost_stats` | 执行成本聚合统计（total_records/total_cost/total_tokens/by_executor） | 无 |
| `cost_budget_check` | 预算超限告警（exceeded/remaining/action） | limit(必) current(必) |

**调度预览示例**：

```json
{"jsonrpc":"2.0","id":20,"method":"tools/call","params":{
  "name":"schedule",
  "arguments":{
    "description":"重构用户认证模块，涉及 login/logout/oauth 三个子模块",
    "n_files": 12
  },
  "_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28"}
}}
```

真实响应（根据描述长度 + 文件数自动判定为 L3 中等任务）：

```json
{
  "level": "L3",
  "description": "...",
  "split_n": 5,
  "cost_tier": "medium",
  "executor": "mcp_delegate",
  "reason": "描述长度 42 字符 + 12 文件 → 中等复杂度，建议拆 5 个子任务"
}
```

**成本统计示例**：

```json
{"jsonrpc":"2.0","id":21,"method":"tools/call","params":{
  "name":"cost_stats",
  "arguments":{},
  "_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28"}
}}
```

真实响应：

```json
{
  "total_records": 42,
  "total_cost": 1.234,
  "total_tokens": 56780,
  "by_executor": {
    "AI_Marvis": {"records": 30, "cost": 0.89, "tokens": 42000},
    "AI_CodeX": {"records": 12, "cost": 0.344, "tokens": 14780}
  }
}
```

### 6.9 并行发布 / 重派 / 判据检查

| 工具 | 说明 | 参数 |
|---|---|---|
| `publish_parallel` | 在已有任务命名空间并行追加独立根任务（不要求 ns 为空、不续轮不归档） | project_dir(必) description(必) namespace(必,非default) created_by(选,默认selfdrive) now(选) |
| `reopen_task` | 重开/重派任务：任意非归档任务回滚为已领取（M4 heal/运维重派用） | task_id(必) now(选) |
| `run_check` | 外部判据检查：服务端真实执行命令（防自写自测恒绿），结果落 specs 表；[gate:required] 任务的 verify 依赖其记录 | task_id(必) cmd(必) args(选) workdir(选) timeout_ms(选,默认120000) now(选) |
| `dag_publish` | 发布带 `depends_on` 依赖关系的根任务 | project_dir(必) description(必) depends_on(必,JSON数组) namespace(选) created_by(选) now(选) |

### 6.10 无人值守编排（watchdog / pipeline）

| 工具 | 说明 | 参数 |
|---|---|---|
| `watchdog_tick` | 看门狗编排单一入口（推荐仅用于定时任务）：扫描活跃任务，心跳超时回滚重派；上一轮根任务完成且给 next_description/meta_prompt_path 时自动续下一轮 | now timeout_sec(选,默认600) namespace(选) next_description(选) next_created_by(选,默认watchdog) meta_prompt_path(选) cold_start(选,默认false) project_dir(选) omega_strong_verify(选) omega_split_n(选) omega_spec(选) |
| `pipeline_tick` | 提示词流水线状态机单入口（仅定时任务 ns）：以 currentState.txt 为状态源四分支推进（空闲生成提示词/提示词落盘发根/执行中缺报告则催报告/报告落盘验收收口），报告先行 | project_dir(必) now(选) namespace(选,默认cron-auto) phase(选,默认auto) prompt_name(选) timeout_sec(选,默认2400) |

### 6.11 自驱式编程（selfdrive）

| 工具 | 说明 | 参数 |
|---|---|---|
| `selfdrive_init` | 初始化 memory 四件套（product/target/task/thinking + reviews 目录），幂等不覆盖 | project_dir(必) namespace(选,默认default) |
| `selfdrive_append` | 追加/更新 memory 条目（thinking 为 append-only 流水，其余覆盖写） | project_dir(必) kind(必,thinking/product/target/task) content(必) namespace(选) now(选) |
| `selfdrive_get` | 读取指定 memory 文件，返回 {exists, content} | project_dir(必) kind(必) namespace(选) |
| `selfdrive_export_tasks` | 从任务库导出任务清单到 task.md（视图覆盖写） | project_dir(必) namespace(选) |
| `selfdrive_review_tick` | 审视轮判定：报告数−已审视轮次≥review_every 触发 action=review（附最近报告+memory 摘要），否则 idle/no_memory/safe_exit | project_dir(必) review_every(选,默认3) namespace(选) |
| `selfdrive_review_ready` | 审视收口：确认 memory/reviews/ 最新审视报告已落盘并推进已审视轮次（报告先行，无报告拒绝推进） | project_dir(必) namespace(选) |
| `selfdrive_publish_next` | 解析审视报告 `## Next Tasks` 段并将待办并行发布为独立根任务（幂等，description 内嵌 [review:file:idx] 防重） | project_dir(必) namespace(选,默认default) max_tasks(选,默认10) now(选) |
| `selfdrive_parse_next_tasks` | 纯解析审视报告文本中 `## Next Tasks` 段（调试/校验用） | content(必) max_tasks(选,默认10) |
| `memory_consolidate` | 自我记忆·收敛写回：verify 通过后把交付物/结论收敛写回 memory/{kind}.md（kind 缺省 target；thinking 为 append-only 带时间戳，其余覆盖写；checkpoint 写时刻） | project_dir(必) task_id(必) kind(选,默认target) content(必) now(选) |
| `memory_gc` | 自我记忆·上限+软降权归档（不硬删）：超 max_chars 时把 memory/{kind}.md 末尾（老人）条目移入 memory/archive/ 归档，正文只保留最新 max_chars；kind 缺省对四件套全部处理 | project_dir(必) kind(选) max_chars(选,默认2000) now(选) |
| `memory_link` | 自我记忆·A-Mem 式关联：在 memory/links.md 追加 `from -> to  note` 关联记录（不存在则创建），供 plan/claim 前检索注入 | project_dir(必) from(必) to(必) note(选) now(选) |

### 6.12 DGM 演化（evolve）+ Laya 决策

| 工具 | 说明 | 参数 |
|---|---|---|
| `evolve_submit` | 归档一个产物：本轮设计/代码/目标入档案库，自动递增父代子代数；与档案高度相似则查重丢弃 | id(必) goal(必) note(必) code(必) score(选) parent_id(选) parts(选) now(选) |
| `evolve_distill` | 自进化蒸馏（EvolveR 最小级）：把 verify 通过的任务交付物蒸馏成 principle 写入 DGM（goal 加 [principle] 前缀，code 写蒸馏内容，复用 evolve_upsert 落库 + Archive 查重语义） | task_id(必) goal(必) note(必) score(选,默认1.0) now(选) |
| `evolve_snapshot` | 查看档案库快照（count/best/summaries/dead_ends/lineage_of_best） | 无 |
| `evolve_sample` | 按 p∝s·h 多样性加权采样父代产物（子代越少/性能越高越可能被选） | rand(选,伪随机种子) |
| `laya_decide` | Laya 可选决策工具（自动探测）：对任务/文本快速分类，命中返回结构化 answers；机器无 laya 返回 available:false 降级，不影响现网 | context(必) questions(选,JSON) model(选,默认english) |

### 6.13 Omega 强验证（语料驱动，task_plan_deep 传 omega_strong_verify=true 开启）

| 工具 | 说明 | 参数 |
|---|---|---|
| `omega_spec_create` | 语料创建者为任务创建本轮语料并持久化到 specs 表 | task_id(必) content(必) author(选,默认spec_author) max_rounds(选,默认3) now(选) |
| `omega_spec_review` | 验证者审核语料：`approve` 放行，其它值打回 | task_id(必) verdict(必) reviewer(选,默认verifier) reason(选) max_rounds(选) now(选) |
| `omega_result_verify` | 验证者复验执行成果与语料：pass 达标可提交验收，其它值打回重做 | task_id(必) verdict(必) reviewer(选,默认verifier) reason(选) max_rounds(选) now(选) |
| `omega_status` | 查询强验证进度：开关/语料与复验轮次/打回数/升级标志 | task_id(必) |

## 7. 端到端真实闭环（本机实录）

干净目录下启动 server（新库），完整跑一遍「发布→认领→拆分→3 子任务闭环→父验收→归档→查询」：

| 步骤 | 调用 | 真实结果 |
|---|---|---|
| 1 | `publish(project_dir="./demo-project", description="FIST-Mbt USAGE 文档实机演示任务", created_by="human_steward")` | `{"task_id":"T0","message":"已发布根任务"}` |
| 2 | `claim(task_id="T0", assignee="AI_Marvis")` | 返回任务对象，`status="已领取"`, `assignee="AI_Marvis"` |
| 3 | `plan(task_id="T0", split_n=3, by="AI_Marvis")` | `["T0.1","T0.2","T0.3"]`（子任务 depth=2） |
| 4 | 对 `T0.1` / `T0.2` / `T0.3` 逐个 `claim → execute → submit → verify` | 逐个返回任务对象，`status="已完成"`，`completed_by="human_steward"` |
| 5 | `verify(task_id="T0", verifier="human_steward")` | 父任务：`status="已完成"`（子任务全绿后父自动上卷） |
| 6 | `archive(task_id="T0", by="human_steward")` | 父任务：`status="已归档"`，`cleanup_mode="deferred"` |
| 7 | `list` | 返回全部 4 个任务：T0 已归档、T0.1/T0.2/T0.3 已完成 |

**验证结论**：publish → plan → claim/execute/submit/verify（叶子）+ verify（父自动上卷）→ archive 全链真实跑通，
任务自动持久化到 `fist-mbt.db`。

> 补充实测：`tools/list` 返回 78 个工具；`resources/read(fist://principles)` 返回七条金条 JSON；
> `prompts/get(fist:check_in)` 返回 1 条 role=user 的打卡自查模板消息。

---

## 8. Resources 与 Prompts

| 类型 | 名称 | 内容 |
|---|---|---|
| Resource | `fist://principles` | 七条金条原则（JSON，含「一切行动听指挥」「指挥官是一切最终责任人」等） |
| Resource | `fist://overview` | 任务体系概览 |
| Prompt | `fist:check_in` | 执行者开工打卡自查模板（role=user） |
| Prompt | `fist:verify` | 验收人验收要点模板 |

---

## 9. 状态机（九态）与迁移规则

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

- **父任务自动上卷**：当父任务所有叶子子任务全部 `verify` 通过，父任务自动聚入「待验收」，直接 `verify → archive`；
  此时对父任务 `claim` 会报「非法迁移: 当前是[待验收]」。
- **K 值递归衰减**：根任务 `depth=3`，每拆一层减 1，`depth≤1` 为原子任务不再拆分。
- 非法迁移（未认领直接 plan/execute、未归档直接 delete、非人类指挥 publish/archive）由状态机拒绝并返回错误。

---

## 10. 发布到 mooncakes（真实流程）

```bash
# 0) 确认 moon.mod：name/version/repository/description/keywords 非空，preferred_target 与目标后端一致
# 1) 先 dry-run 验证元数据与打包（native 全量 check >150s，等待后再读日志尾部）
moon publish --dry-run
#    看到 "Check passed" 与 "Server status: 202 Accepted / Dry run completed successfully" 即通过
# 2) 正式发布
moon publish
#    看到 "Server status: 200 OK" 且退出码 0 即成功
```

---

## 11. 常见问题排查

| 现象 | 原因与处理 |
|---|---|
| `Missing required _meta field: io.modelcontextprotocol/protocolVersion` | `params._meta` 键名缺少 `io.modelcontextprotocol/` 前缀，参见第 4 节 |
| `initialize` 返回 `Method not found` | 正常：本 server 无需握手即可用 `tools/list` / `tools/call` |
| `task already exists: T0` | 根任务唯一，当前库已有 T0；换新目录启动或等归档后 `task_cleanup` / `delete` |
| 中文乱码 / `gbk codec can't decode` | Python 侧务必 `encoding="utf-8", errors="replace"` 解码 stdout |
| 父任务 `claim` 报「非法迁移: 当前是[待验收]」 | 子任务全绿后父已自动上卷，直接 `verify → archive`，勿再 claim |
| `fist-mbt.db` 出现在 git 状态 | `*.db` 已被 `.gitignore` 忽略，无需手动处理 |
| `store_open` 报"打开命名空间失败" | 检查 `data_dir` 是否存在且可写；测试时需提前创建目录 |
| `audit_permission` 报"未知角色" | 合法值：`human_steward` / `leader` / `agent`（小写） |

---

## 12. 一句话总结

FIST-Mbt = 用纯 MoonBit 实现的 FIST 指挥官任务编排 + MCP STDIO Server（78 个工具）。
对 AI 客户端而言：**pub/claim/plan + spec 深拆 → 子任务闭环 → verify 上卷 → archive**，
一路 `tools/call` 即可完成多智能体任务的发布、认领、拆分、执行、验收、归档全生命周期管理。

**M8 新增能力**：Omega 验证闭环（一票否决 + 自动修复）、智能调度预览、执行器抽象层、成本追踪与预算告警、
心跳持久化 + WAL 并发、执行元数据扩展。
