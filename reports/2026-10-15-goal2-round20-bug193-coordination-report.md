# Goal-2 Round 20 报告 · BUG-193 未修且扩散 + 引导注入 + 关联沉淀

- 日期：2026-10-15
- 目标：使用 fist-mbt 全程开发，持续【寻虫-修复-验证-推进】循环轮转
- 交付：无新增文件（协调轮）

## 结果摘要

### 1. BUG-193 未修且扩散

- `router_config.mbt` 仍 WIP（并发 agent 未提交修复）
- 错误从 3 处降到 **2 处**（router_config 的 133/148 已修，219 未修）
- **但扩散到 router_state.mbt:45**（并发 agent 在新文件又引入了 is_finite）

```
> Error: [4015] × 2
       router_config.mbt:219  Type Double has no method is_finite
       router_state.mbt:45    Type Double has no method is_finite
```

### 2. 引导注入（supervisor_prompt_inject）

用 FIST MCP 的超级管家工具向项目 `fist-mbt` 注入引导（`sg-2`, queued）：

- 明确指出 `is_finite` 不可用
- 给出等价替代：`n == n`（NaN 时 false，`n >= X` 已排除 NaN）
- 示例代码

### 3. 关联沉淀（memory_link）

在 memory/links.md 建立 `is_finite` → `Double-finite-check` 关联：

> MoonBit Double 无 is_finite 方法。等价替代：`n == n`（NaN 时 false，n>=X 已排除 NaN）。
> 并发 agent 在 router_config/router_state 引入 is_finite 导致编译失败（BUG-193）。

未来遇到同类问题的 agent 可通过 links 检索到这条经验。

## 验证细节

```
moon check src/router → 2 errors (Error [4015])
  router_config.mbt:219  Type Double has no method is_finite
  router_state.mbt:45    Type Double has no method is_finite
```

## 资源消耗

| 项 | 值 |
|---|---|
| FIST MCP 工具调用 | 2（supervisor_prompt_inject + memory_link） |
| 新增文件 | 0（协调轮） |

## 遗留风险

1. 全仓编译仍失败（router_config + router_state 各 1 处）。
2. 我的 2 条 caf_stats 锁测试（R19）仍无法运行。
3. 并发 agent 在逐个修，但新文件又引入同类错误——提示**系统性误用**（可能他们用了某个模板/工具生成代码）。

## 后续建议

1. 并发 agent 消费 `sg-2` 引导后：全仓搜 `is_finite` 确认清干净。
2. 并发 agent 修复后：跑 `moon test --target js src/router` 验证我的 2 条新测试。
3. 修复后跑全仓回归（基线 1112/1112）。
4. 系统性根因：并发 agent 可能用了 LLM 生成的代码模板（is_finite 是 Python/Java 习惯），建议他们在生成器里加"MoonBit Double 无 is_finite"的知识。

## 超额内容

- 无。

## 来源

- `moon check src/router` → 2 errors (Error [4015])
- `mcp__fist-mbt__supervisor_prompt_inject` → sg-2（queued）
- `mcp__fist-mbt__memory_link` → is_finite ↔ Double-finite-check
