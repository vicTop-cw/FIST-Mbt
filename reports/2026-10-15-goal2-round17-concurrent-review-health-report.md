# Goal-2 Round 17 报告 · 并发改动复核 + 项目健康快照 + 交付物硬门验证

- 日期：2026-10-15
- 目标：使用 fist-mbt 全程开发，持续【寻虫-修复-验证-推进】循环轮转
- 交付：无新增文件（复核轮）

## 结果摘要

### 1. 并发 agent 跨过边界改了 router_caf.mbt（防御性修复）

并发 agent 对 `caf_stats` 加了 `total>0` 守卫：

```moonbit
// 前：
avg_cost: model_cost_sum[i] / model_totals[i].to_double()
// 后：
avg_cost: if model_totals[i] > 0 {
  model_cost_sum[i] / model_totals[i].to_double()
} else {
  0.0
}
```

**分析**：`model_totals[i]` 从实现看最小为 1（新模型初始化 +1，非空记录每条 +1），
守卫实际是**死代码**——不可达。但它是有益的防御性编程：
即使未来实现变化（如加 filter/初始化改 0）也不会 divide-by-zero。

**验证**：我的 135 个 CAF 测试仍全绿（并发改动不破坏兼容）。

### 2. 并发 agent 尚未开始 P2c 接线

`model_router_ops.mbt` 的 WIP diff 是 API 适配（`ends_with`→`has_suffix`、
`workdir=project_dir`→`workdir=""`），**无 `caf_` 引用**。
并发 agent 尚未接 CAF 记忆到 pick 流程。

### 3. project_health 快照

```
grade: attention（有阻塞任务或残留）
total_tasks: 2382
in_flight: 595, ready: 1173（大量积压）
done: 499, done_no_artifact: 2（= baseline 2，无新增）
blocked: 7, reviewing: 59, archived: 49
```

7 个 blocked 任务：T0r86.1.1/1.2、T0r87.1.1/1.2、T0r88.1.1/1.2、T0r501。

### 4. output_validate 验证 R16 交付物

`scripts/caf_p2c_ab_preflight.py`：**l4-pass**（存在/非空/invariant 全通过）。

## 验证细节

```
Total tests: 135, passed: 135, failed: 0.
```

## 资源消耗

| 项 | 值 |
|---|---|
| FIST MCP 工具调用 | 2（project_health + output_validate） |
| 新增文件 | 0（纯复核轮） |

## 遗留风险

1. P2c 接线仍被并发 agent WIP 阻塞（model_router_ops.mbt，26 文件）。
2. 并发 agent 已跨过边界改 router_caf.mbt——若将来他们改 router_caf.mbt 的 API 签名，
   需要重新跑 moon info 生成 .mbti。

## 后续建议

1. Round 18：若 WIP 释放 → 按修正后设计文档实施 P2c（真源位置已核准）。
2. Round 18：并发 agent 改了 router_caf.mbt，需**持续跟踪**其改动是否引入行为变化。
3. Round 18：可考虑加一条 `caf_stats_zero_total_guard` 测试（虽然守卫不可达，但锁住不崩溃）。

## 超额内容

- 无。

## 来源

- `git diff src/router/router_caf.mbt`（并发 agent 改动）
- `git diff src/server/model_router_ops.mbt`（并发 agent 改动，无 caf_ 引用）
- `mcp__fist-mbt__project_health`
- `mcp__fist-mbt__output_validate`（scripts/caf_p2c_ab_preflight.py）
