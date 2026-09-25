# 获奖提升 · R33 派单免手传（selfdrive_dispatch 自动抽取所需能力）

> 日期：2026-09-25｜目标：把获奖概率再往上提——先调研、再环视薄弱点，拿来主义 + 更好的 AI 项目管理工具。
> 本轮续接 R32：**83 MCP 工具 + 3 resources + 2 prompts，测试 230/230（Windows + WSL 双端全绿）**。

## 一、调研先行（拿来主义）
- 闭环 R32：`selfdrive_dispatch` 需调用方手传 `want` 才走能力路由；要让"Marketplace 自动派单"真正 hands-free，需在 want 缺省时从任务描述自动抽取所需能力。

## 二、本轮落地
- **新增 server 私有 `auto_need(desc)`**：扫任务描述里出现的「已注册执行者能力标签」，取最长的那个作 need（最具体）；复用 `exec_reg.list`/`abilities_of`（单真源）+ `String::contains` 最简抽取（与 R30 覆盖语义一致）。
- **`selfdrive_dispatch` 增强**：显式 `want` 优先（零回归）；`want` 空时用 `auto_need`，返回 `need_auto=true` 标记。
- 无工具数/测试数变化（83 / 230）——同工具行为增强，由 E2E 覆盖。

## 三、结果摘要
| 项 | 值 |
|---|---|
| MCP 工具 | **83**（不变，同工具增强） |
| 测试 | **`moon test --target js` 230/230**（不变） |
| E2E | `dispatch_verify.py` 追加免手传用例：另发「编排调度器」任务 → `selfdrive_dispatch`(不传 want) → `need_auto=true`、自动抽取 `want=编排`、仍派给 exec-DP、已领取 **MCP-DISPATCH-VERIFY PASS** |
| 回归 | 0（显式 want 优先） |
| 文档 | 仅 AGENTS `selfdrive_dispatch` 行补 R33 免手传说明（计数不变） |

## 四、资源消耗
- 工具链：`moon check --target js` / `moon build --target js cmd/main` / `moon test --target js -j 1`；
- 无新增依赖/表；E2E 运行后 `git checkout -- fist-mbt.db` 恢复 + `cleanup --check` CLEAN。

## 五、任务分配记录
- R33 主代理直做（server 助手 + dispatch 增强 + E2E 追加），自审三关（typecheck+build+E2E）。

## 六、遗留风险
- `auto_need` 用"能力标签子串 + 最长命中"的启发式，未做同义/分词；对描述不含任何已注册标签的任务回退自领（符合预期）。词嵌入/LLM 抽取列为远期。
- 派单直接写"认领"，无人值守友好；人机混合建议配 reserve_scope/权限矩阵（同 R32 遗留）。

## 七、后续建议（按强度）
1. `watchdog_tick` 无人值守"无活跃任务"分支接 `selfdrive_dispatch`（免 want）：把能力派单并入自动续推，构成完整自驱闭环；
2. plan_deep 深化 LADDER"先生成简单变体再逆推原题"；
3. README CI 徽章实时化（静态 230/230 → workflow 生成，减少手工同步）。

## 八、超额内容（相对任务边界）
- 无。

## 九、来源
- 源码：src/server/server.mbt（`auto_need` + dispatch 免手传分支）、scripts/dispatch_verify.py。
- 复用：executor pkg ExecutorRegistry::list/abilities_of、engine.triage/claim。

*（内容由AI生成，仅供参考）*