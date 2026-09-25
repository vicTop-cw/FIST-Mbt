# 获奖提升 · R38 CI 仓库整洁守卫（cleanup_artifacts --check 接入 JS 轨）

> 日期：2026-09-25｜目标：把获奖概率再往上提——先调研、再环视薄弱点，项目整洁（第三支柱）设为 CI 硬约束。
> 本轮续接 R37：**83 MCP 工具 + 3 resources + 2 prompts，测试 230/230（Windows + WSL 双端全绿）**。

## 一、调研先行（审计缺口）
- R34 已把"徽章 ≠ 实测"变成 CI 门禁；但"仓库整洁（除交付库外无生成物）"仍只靠本地人工 `cleanup_artifacts --check`，未上 CI——测试/演示残留可能随每个 push 进提交。

## 二、本轮落地
- **接入（纯 CI，零代码/计数变化 83/230）**：`.github/workflows/ci.yml` JS 轨在 badge guard 之后加 `Cleanliness guard` 步骤：`python3 scripts/cleanup_artifacts.py && python3 scripts/cleanup_artifacts.py --check`——先清测试/演示残留，再断言仓库根仅 `fist-mbt.db`、`temp/` 无残留，非 0 退出即 FAIL。

## 三、结果摘要
| 项 | 值 |
|---|---|
| MCP 工具 | **83**（不变） |
| 测试 | **`moon test --target js` 230/230**（不变） |
| CI | JS 轨新增"Cleanliness guard"步骤（仓库仅交付库才通过） |
| 验证 | 本地 `cleanup_artifacts.py --check` 退出码 0（CLEAN） |
| 回归 | 0 |
| 文档 | 无计数涟漪 |

## 四、资源消耗
- 仅 ci.yml 编辑 + 本地 `cleanup_artifacts.py --check` 验证；无构建/依赖。

## 五、任务分配记录
- R38 主代理直做，自审：本地 --check 退出码 0。

## 六、遗留风险
- 测试一定会在 CI 生成 .db（gitignore 不进提交），由 Cleanliness guard 在吞掉前清理 + 校验；若某 target 生成非根目录 .db 需后续按需扩展清理规则。

## 七、后续建议（按强度）
1. `watchdog_tick` 无人值守接 `selfdrive_dispatch`（完成自驱闭环）；
2. "更简单变体→本体"做成显式 DAG 前置依赖；
3. 分组/轮表单一真源化。

## 八、超额内容（相对任务边界）
- 无。

## 九、来源
- 源码/文档：.github/workflows/ci.yml、scripts/cleanup_artifacts.py。

*（内容由AI生成，仅供参考）*