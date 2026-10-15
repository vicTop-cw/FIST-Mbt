# Round 162 报告 · github_queue_status + mcpcf.circuit + selfdrive_publish_next

- 日期：2026-10-15
- 提交：无（纯能力验证轮）
- 角色：远端队列 + 内嵌熔断器 + 审视发布轮

## 结果摘要

### 1. github_queue_status（BUG-74 同族）

```
github_queue_status(project_dir=temp/shim-selfdrive)
  → total=0, path=temp/shim-selfdrive/memory/bugs_pending_github.json

github_queue_status(project_dir=.)
  → total=0, path=./memory/bugs_pending_github.json
```

**关键发现**：total=0 只说明队列文件为空。BUG-74 点名：env 未启用（github_env_check enabled=false）故无入队记录——「没有待同步」≠「没有 bug 待上报」。

### 2. mcpcf.circuit（内嵌熔断器）

```
mcpcf.circuit(circuit=embedded-demo, ns=shim-review)
  → state=closed, failures=0, threshold=3, allow_call=true, probe_limit=1

mcpcf.circuit(action=fail, circuit=embedded-demo)
  → state=closed, failures=1, allow_call=true
```

**关键发现**：与主 `circuit_status` 同族但走内嵌引擎。Closed 窗内失败计数达阈值（3）才转 Open。

### 3. selfdrive_publish_next（审视发布）

```
selfdrive_publish_next(project_dir=temp/shim-selfdrive)
  → action=wait
  → note=memory/reviews/ 下无审视报告，无可发布任务
```

**关键发现**：报告先行——无审视报告则 wait，不空转。

## 资源消耗

| 项 | 值 |
|---|---|
| 工具调用 | github_queue_status × 2、mcpcf.circuit × 2、selfdrive_publish_next × 1、pwsh × 1 |
| 提交 | 无 |
| 触碰并发 WIP | 无 |

## 任务分配记录

- 本会话 Round 162 完成：github_queue_status + mcpcf.circuit + selfdrive_publish_next 三能力验证。

## 遗留风险

1. **内建 compat 的 protocolVersion 回写缺陷**——已归档为 DGM 资产。
2. **BUG-155 假绿持续**——HEAD 仍含 stale dist。
3. **R154 提交污染**——已修正纪律，但误提交需与并发 agent 协调。

## 后续建议

1. 剩余未试用能力：task_cleanup（谨慎，删除性）、github_flush_plan、mcpcf 其余子命令（已覆盖 report/review/run_batch/verify/watchdog/circuit/ops_init）。
2. 里程碑（162/256）已覆盖绝大多数 MCP 能力，可补一份「能力试用覆盖矩阵」进 BACKLOG.md。

## 超额内容

- 无（严格限于远端队列 + 内嵌熔断器 + 审视发布）。

## 来源

- `github_queue_status(temp/shim-selfdrive)` → total=0
- `github_queue_status(.)` → total=0
- `mcpcf.circuit(embedded-demo)` → closed, failures=1
- `selfdrive_publish_next(temp/shim-selfdrive)` → wait
