# 调用日志 + bug 上报修复闭环（call-log & bugs）

> 竞赛展示特性：持久记录每一次工具调用的"入参 + 结果"，并能把一次运行时失败
> 上报成 OPEN 状态的 bug 账目，交回 FIST 的自驱/定时流水线认领修复，形成
> **发现 bug → report_bug → 自驱认领修复 → verify → 发版** 的闭环。

## 1. `call_log` 表（持久化调用日志）

每次工具调用（best-effort）都记一条，涵盖"是哪次调用 + 入参 + 结果"：
谁可以据此复盘某次调用为何出错。

DDL（`src/store/store_sqlite.mbt` 的 `create_schema`，与 executions/heartbeats 同一模式）：

```sql
CREATE TABLE IF NOT EXISTS call_log (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  seq         INTEGER,          -- 调用序号（近似时间戳）
  ts          TEXT,             -- 时间戳（YYYY-MM-DDTHH:MM:SSZ）
  tool        TEXT,             -- 工具名
  caller      TEXT,             -- 调用者（created_by）
  ns          TEXT,             -- 命名空间（namespace / ns）
  params_json TEXT,             -- 入参（args.stringify()）
  result_json TEXT,             -- 结果（Err→错误信息 / Ok→"ok" 占位）
  ok          INTEGER,          -- 1=Ok / 0=Err
  runtime_ms  INTEGER           -- 本次调用墙钟耗时（毫秒）
)
```

接口（双后端统一，`src/store/store.mbt`）：

- `StoreBackend::write_call_log(ts~, tool~, caller~, ns~, params_json~, result_json~, ok~, runtime_ms~, seq~) -> Result[Unit, String]`
  - `MemoryStore`：进程内 array，软上限 ~500（超限丢最早一条）；
  - `SqliteStore`：INSERT 到 `call_log` 表（best-effort）。
- `StoreBackend::recent_call_logs(limit~ = 50) -> Array[Json]`：读取最近 N 条（新的在前）。
- 引擎侧委托：`FistEngine::store_write_call_log(...)` / `FistEngine::store_recent_call_logs(...)`。

导出/查询工具：`call_log`（MCP 工具）直接返回 `engine.store_recent_call_logs(limit)`。

## 2. 自动日志包装（`instrumented_tool`）

`colmugx/mcp` 的 `.tool(name, desc, schema, handler)` 的 handler 类型为
`async (Json) -> Result[@mcp.ToolResult, @mcp_types.MCPError]`（同步也可被 async 吸收）。
由于 MoonBit 不能为外部类型 `MCPServer` 新增方法，本项目以**自由函数**
`instrumented_tool(s, name, desc, schema, handler)` 等价注册一个工具，内部用
`_instrument(name, handler)` 包一层：

```moonbit
/// 包装 handler：度量耗时、捕获入参/结果、best-effort 记日志、原样返回结果。
fn _instrument(tool, handler) -> handler_type {
  async fn(args) {
    let t0 = @env.now().to_int()
    let params_json = args.stringify()
    let r = handler(args)
    let runtime_ms = @env.now().to_int() - t0
    let (result_json, ok) = match r {
      Err(e) => (e.message(), false)   // Err 记录真实错误
      Ok(_)  => ("ok", true)           // Ok 结果文本在外部不可读（ToolResult 字段私有），以 "ok" 占位
    }
    _log_call(tool, args, params_json, result_json, ok, runtime_ms, t0)
    r                                       // 原结果原样返回，绝不改动
  }
}
```

`_log_call` 经 `engine.store_write_call_log(...)` best-effort 落库，**任何写入失败都被吞掉**，
不影响原工具调用的返回与结果。`run_server()` 内每个工具注册都走 `s1 = instrumented_tool(s1, ...)`，
因此**所有工具调用默认 auto-log**（含新增的 `call_log` / `report_bug` / `bug_list` 自身）。

> 说明：Ok 路径的 `result_json` 为 "ok" 占位——因为 `ToolResult` 的 `content`/`is_error`
> 字段是私有的，外部包无法读取；Err 路径则记录真实错误信息（`MCPError::message()`）。

## 3. `report_bug` / `bug_list`（bug 账本）

- `report_bug(project_dir, summary, detail?, severity?, ref_call_id?, reported_by?, publish_task=true/false, now?)`
  - 校验 `project_dir`（拒绝绝对路径 / `..` 穿越 / 盘符）与 `severity`（allowlist：
    `open/critical/high/medium/low`，默认 `open`）。
  - 把一条结构化条目追加到 `{project_dir}/memory/bugs.md`（自动建 `memory/` 目录），格式：
    `## BUG-<seq> [<ts>] [<severity>] OPEN` + `- summary:` / `- detail:` / `- ref_call:` / `- reported_by:` 字段；
    `seq` 从既有条目的最大 `BUG-n` 递增（无则从 1 起）。
  - `publish_task=false`（默认，低风险）只落账；`publish_task=true` 时还调用
    `engine.publish_parallel(ns="bugs", description="修复 bug: <summary>", ...)`
    发布为 `bugs` 命名空间下的独立根任务，返回里带 `task_id`，供自驱/定时流水线认领。
  - 返回 `{bug_id, status:"OPEN", path, task_id?}`。
- `bug_list(project_dir)`：解析 `memory/bugs.md` 为
  `{id, ts, severity, status, summary}` 数组（含 status 的条目均返回），供扫描待修复 bug。
- 关闭（status → CLOSED）由修复方 agent 直接编辑条目完成（不提供独立 `bug_ack`，保持最小足迹）。

## 4. 闭环示例（"发现 bug → 上报 → 修复 → 发版"）

1. 某工具调用返回 Err → 该调用已被 `call_log` 记录（`call_log` 工具可查到 seq/入参/结果）。
2. 客户/agent 调用：
   `report_bug(project_dir="myproj", summary="verify 崩溃", detail="栈回溯…", severity="high", ref_call_id="<seq>", publish_task=true)`
   → 追加 `BUG-3 [..] [high] OPEN` 到 `memory/bugs.md`，并发布根任务 `修复 bug: verify 崩溃`（ns=bugs）。
3. FIST 自驱/定时流水线 `bug_list(project_dir)` 扫到 OPEN 的 `BUG-3` → 按 `ref_call_id` / `summary`
   定位问题 → 认领 `bugs` 命名空间任务 → 修复 → `submit` / `verify` 通过。
4. 修复 agent 编辑 `memory/bugs.md` 把 `BUG-3` 状态置为 `CLOSED`，账本闭合。
5. 回归验证（`moon test`）后发版 —— 全链路形成 "发现 → 上报 → 修复 → 验收 → 发版" 闭环。