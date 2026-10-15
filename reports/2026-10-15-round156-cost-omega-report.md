# Round 156 报告 · cost_stats + call_log + cost_budget_check + omega_verify + omega_verify_fix

- 日期：2026-10-15
- 提交：无（纯能力验证轮）
- 角色：成本/调用审计 + Omega spec 验证轮

## 结果摘要

### 1. cost_stats（执行成本聚合统计）

```
total_records     = 557
total_tokens_in   = 135097
total_tokens_out  = 132297
total_cost        = 0
Top executor      = manual(141), demo_executor(49), qoder-agent(42), agent_executor(56)
```

### 2. call_log（跨进程审计）

```
最近 10 条：
  seq=235 cost_stats (51ms)
  seq=234 issue_scan src/symbolic (189ms)      ← 并发 agent bugfind
  seq=233 supervisor_task_upsert temp/shim-selfdrive (4ms) ← 我的 R155
  seq=232 selfdrive_pick_next shim-review (480ms) ← 我的 R155
  seq=231 issue_scan src/server (29826ms)      ← 并发 agent bugfind
  seq=230 issue_scan src/hat (158ms)
  seq=229 issue_scan src/store (3543ms)
  seq=0 supervisor_prompt_inject (wbtest 测试)
```

**关键发现**：call_log 是跨进程审计（audit_log 只是进程内）。并发 agent 正跑 issue_scan 于 src/{symbolic,server,hat,store}——bugfind 模式。

### 3. cost_budget_check（预算超限告警）

```
cost_budget_check(limit=100, current=120)
  → exceeded=true, remaining=-20, action=switch_free
  → reason=预算超限，超支额 20，建议切换至免费模型或暂停任务
```

### 4. omega_verify（批量 spec 验证）

逐格 schema 校验：
1. YAML 非 JSON → `JSON 解析失败`
2. tests[0] 非对象 → `tests[0] 必须是对象`
3. 缺 expected/error → `tests[0] 缺少 expected 或 error`
4. fingerprint 不匹配 → `期望 fnv1a64:acd023e890797a4f`

最终正确 spec：
```json
{"op":"add","version":1,"definition":"两个整数相加","preconditions":[],"laws":["加法交换律"],"tests":[{"input":[1,2],"expected":3}],"fingerprint":"fnv1a64:acd023e890797a4f"}
```
→ accuracy=100%, passed=1/1, veto=false。

### 5. omega_verify_fix（根因分类→定向修复→回归验证）

```
omega_verify_fix(broken_spec.json)
  → rounds=[{round:1, root_cause:"mixed", accuracy_before:0, accuracy_after:0, note:"无 spec 内容，未实际修复"}]
  → needs_human_review=["broken_spec.json"]
  → needs_human_review_detail=["broken_spec.json: fp_mismatch -> needs_human_review（无 spec 内容，无法自动修复）"]
  → veto=true
```

**关键发现**：指纹不匹配无法自动修复（诚实转人工审查，不硬造）。

## 资源消耗

| 项 | 值 |
|---|---|
| 工具调用 | cost_stats × 1、call_log × 1、cost_budget_check × 1、omega_verify × 4、omega_verify_fix × 1、pwsh × 1 |
| 提交 | 无 |
| 触碰并发 WIP | 无 |

## 任务分配记录

- 本会话 Round 156 完成：cost_stats + call_log + cost_budget_check + omega_verify + omega_verify_fix 五能力验证。

## 遗留风险

1. **内建 compat 的 protocolVersion 回写缺陷**——已归档为 DGM 资产。
2. **BUG-155 假绿持续**——HEAD 仍含 stale dist。
3. **R154 提交污染**——已修正纪律，但误提交需与并发 agent 协调。

## 后续建议

1. 剩余未试用能力：pipeline_tick（无人值守流水线）、selfdrive_append/review_tick/publish_next、task_cleanup（谨慎）、memory_gc（记忆上限+降权归档）、github/gitcode_*（远端同步）、mcpcf_*（内嵌引擎）。
2. 里程碑（156/256）已覆盖绝大多数 MCP 能力，可补一份「能力试用覆盖矩阵」进 BACKLOG.md。

## 超额内容

- 无（严格限于成本/调用审计 + Omega spec 验证）。

## 来源

- `cost_stats()` → 557 条, 135097 tok in
- `call_log(limit=10)` → 看到并发 agent 的 issue_scan
- `cost_budget_check(100, 120)` → exceeded=true, action=switch_free
- `omega_verify(specs)` → accuracy=100% (fingerprint 校验)
- `omega_verify_fix(broken_spec.json)` → fp_mismatch 转人工
