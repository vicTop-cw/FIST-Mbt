---
AIGC:
    Label: "1"
    ContentProducer: 001191440300708461136T1XGW3
    ProduceID: 9f2a11add43fbf12a546606fb2b962ab_3478f49aadc911f18f50525400aeaaa3
    ReservedCode1: UCtjPi/qzgiroN4PMrjIVlzuHMfI98c7mm60xhvrTPPUHjZXEpUZV8XHCuEYbpdZ3OD9XxQIm/tFvcccH0RgNPkm85ETVCPAjcly4M7XSc2HLVB7fBPWvmD6Hmpbv0w7HogxEV001JezjkwyMiYCN8eOV9AtTiFJw9dq3d8syr8Mnlyo8yXKJ5WQ5jY=
    ContentPropagator: 001191440300708461136T1XGW3
    PropagateID: 9f2a11add43fbf12a546606fb2b962ab_3478f49aadc911f18f50525400aeaaa3
    ReservedCode2: UCtjPi/qzgiroN4PMrjIVlzuHMfI98c7mm60xhvrTPPUHjZXEpUZV8XHCuEYbpdZ3OD9XxQIm/tFvcccH0RgNPkm85ETVCPAjcly4M7XSc2HLVB7fBPWvmD6Hmpbv0w7HogxEV001JezjkwyMiYCN8eOV9AtTiFJw9dq3d8syr8Mnlyo8yXKJ5WQ5jY=
---

# FIST-Mbt 使用文档（USAGE）

> 版本：`vicTop-cw/fist-mbt@0.1.0`（MoonBit，MCP Server）
> 日期：2026-09-11 ｜ 定位：**实操调用手册**。README.md 是项目概览，本文件是「如何真正用它」的手把手文档，
> 全部示例均来自本机实机运行（JSON-RPC over STDIO）的真实输出，非凭空构造。

---

## 1. 它是什么

FIST 指挥官任务分配体系（原 Python 版 `E:\IDEProjects\AI\FIST`）的 **纯 MoonBit 原生重写 + MCP 化** 作品
（2026 MoonBit 九月黑客松）。对外暴露一个 **STDIO 传输的 MCP Server**，任何 MCP 客户端拉起可执行文件后，
即可通过标准 `tools/call` 完成任务的 **发布 → 认领 → 拆分 → 执行 → 提交 → 验收 → 归档** 完整闭环。

协议层使用 [`colmugx/mcp`](https://mooncakes.io/colmugx/mcp)（Apache-2.0，协议版本 `2026-07-28`）。

---

## 2. 前置与构建

依赖：MoonBit 工具链 ≥ `0.1.20260827`（需支持 `errdefer` 与 `async`）。

```bash
moon check                  # 类型检查
moon build --target native  # 原生后端
moon build --target js      # JS 后端（Node 运行）
moon test                   # 核心状态机单测（7 项）
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
    cwd="E:/IDEProjects/AI/FIST-Mbt",
    stdin=subprocess.PIPE, stdout=subprocess.PIPE,
    text=True, encoding="utf-8", errors="replace", bufsize=1,
)
def rpc(method, **payload):
    params = {"_meta": META}; params.update(payload)
    req = {"jsonrpc":"2.0","id":"1","method":method,"params":params}
    proc.stdin.write(json.dumps(req, ensure_ascii=False)+"\n"); proc.stdin.flush()
    return json.loads(proc.stdout.readline())
```

---

## 5. 最小调用示例

发布一个根任务（仅限人类指挥官）：

```json
{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{
  "name":"publish",
  "arguments":{
    "project_dir":"E:/proj/demo",
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

---

## 6. 15 个 MCP 工具手册

> 参数表取自本机 `tools/list` 返回的真实 Schema。

### 6.1 生命周期七件套（对应七态状态机）

| 工具 | 说明 | 参数 |
|---|---|---|
| `publish` | 发布根任务（仅 human_steward/human） | project_dir(必) description(必) created_by(选,默认human_steward) now(选) |
| `claim` | 认领任务（待领取→已领取） | task_id(必) assignee(必) now(选) |
| `plan` | 对已认领任务拆出一层子任务 | task_id(必) split_n(选,默认3) by(选) now(选) |
| `execute` | 记录执行交付物（→执行中） | task_id(必) deliverable(必) now(选) |
| `submit` | 提交验收（→待验收） | task_id(必) now(选) |
| `verify` | 验收通过（→已完成，父任务自动上卷） | task_id(必) verifier(必) now(选) |
| `archive` | 归档（仅人类指挥官） | task_id(必) by(选) now(选) |
| `delete` | 删除已归档任务 | task_id(必) |

### 6.2 查询

| 工具 | 说明 | 参数 |
|---|---|---|
| `list` | 列出全部任务，可按状态过滤 | status(选,中文状态名) |
| `get` | 查询单个任务详情 | task_id(必) |

### 6.3 深拆与运维五件套

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

---

## 7. 端到端真实闭环（本机实录）

干净目录下启动 server（新库），完整跑一遍「发布→认领→拆分→3 子任务闭环→父验收→归档→查询」：

| 步骤 | 调用 | 真实结果 |
|---|---|---|
| 1 | `publish(project_dir="E:/proj/usage-demo", description="FIST-Mbt USAGE 文档实机演示任务", created_by="human_steward")` | `{"task_id":"T0","message":"已发布根任务"}` |
| 2 | `claim(task_id="T0", assignee="AI_Marvis")` | 返回任务对象，`status="已领取"`, `assignee="AI_Marvis"` |
| 3 | `plan(task_id="T0", split_n=3, by="AI_Marvis")` | `["T0.1","T0.2","T0.3"]`（子任务 depth=2） |
| 4 | 对 `T0.1` / `T0.2` / `T0.3` 逐个 `claim → execute → submit → verify` | 逐个返回任务对象，`status="已完成"`，`completed_by="human_steward"` |
| 5 | `verify(task_id="T0", verifier="human_steward")` | 父任务：`status="已完成"`（子任务全绿后父自动上卷） |
| 6 | `archive(task_id="T0", by="human_steward")` | 父任务：`status="已归档"`，`cleanup_mode="deferred"` |
| 7 | `list` | 返回全部 4 个任务：T0 已归档、T0.1/T0.2/T0.3 已完成 |

**验证结论**：publish → plan → claim/execute/submit/verify（叶子）+ verify（父自动上卷）→ archive 全链真实跑通，
任务自动持久化到 `fist-mbt.db`。

> 补充实测：`tools/list` 返回 15 个工具；`resources/read(fist://principles)` 返回七条金条 JSON；
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

## 9. 状态机（七态）与迁移规则

```
待领取 --claim--> 已领取 --plan--> 拆分中 --execute--> 执行中
已领取 --execute--> 执行中
执行中 --submit--> 待验收 --verify--> 已完成 --archive--> 已归档 --delete--> 移除
待验收 --reopen--> 已领取（被打回重做）
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

---

## 12. 一句话总结

FIST-Mbt = 用纯 MoonBit 实现的 FIST 指挥官任务编排 + MCP STDIO Server。
对 AI 客户端而言：**pub/claim/plan + spec 深拆 → 子任务闭环 → verify 上卷 → archive**，
一路 `tools/call` 即可完成多智能体任务的发布、认领、拆分、执行、验收、归档全生命周期管理。
*（内容由AI生成，仅供参考）*
