# fist-mbt 参赛证据快照（2026-09-24 第2.5波后）

> 本快照为 4-AI 概率门禁的唯一事实依据。只含可核实事实，不含自吹。
> 评审口径：某一证据可用「事实 + 合理外推」支撑即给分（稍宽一档）。

## 1. 项目身份与发布状态
- 纯 MoonBit 实现的 MCP Server：把多智能体任务编排框架「FIST 指挥官任务分配体系」从 Python 原生重写为 MoonBit，未搬运 Python 代码，许可证 Apache-2.0。
- **已发布至 mooncakes 生态**：`vicTop-cw/fist-mbt@0.2.4`（`moon publish` 返回 200 OK；首跑 409 版本重复后换新版本成功）。
- GitHub 公开仓库 `github.com/vicTop-cw/FIST-Mbt`，含 15+ 实质 commits，README 顶部带实时 CI 徽章（js/ubuntu、native/ubuntu、js/windows 三轨道绿色）。

## 2. 规模与测试可复现
- **61 个 MCP 工具** + 2 Resources + 2 Prompts；`moon check` 0 错误。
- **165 项测试用例 js 全绿**（本人已实跑 `moon test --target js` → 165/165）；JS 与 Native 双后端；CI 三轨道绿色徽章（native 以 CI/ubuntu 为准）。
- 30 秒一键演示 `scripts/demo.ps1` 实测 PASS（拉起 MCP server，tools/list 61 工具 + publish + get 状态断言）。
- 一把自检 `scripts/mcp_smoke.py` 实测 PASS：断言 61 工具、发布命中 task_id、get 命中且状态待领取。

## 3. 核心能力（57→现 61 工具，全生命周期）
- 生命周期：九态状态机 / 父任务自动上卷 / K 值递归衰减 / 非法迁移拦截 / publish_parallel 并行发布。
- DAG 依赖图：关键路径 / 并行度 / 拓扑排序 / 依赖检查 / ASCII 可视化 / ready 列表。
- 智能调度：L1-L4 自适应分级 / 成本档路由 / 可替换执行器抽象层。
- Omega 强验证：spec JSON 一票否决 + 自动修复循环 + 超限转人工。
- 运维治理：冲突检测 / 心跳上报 / 超时回滚 heal / 归档清理 / 审计日志 / 看门狗编排。
- 多租户：命名空间隔离到独立 SQLite（WAL），惰性开/关，跨命名空间成本汇总。
- **自我记忆与自进化**：memory_consolidate/gc/link + evolve_distill（验收通过任务蒸馏为原则）+ 可计算评分 scoring.mbt。
- **AI 自驱式编程闭环**：selfdrive_* 8 工具（审视 → 拆解 → 发布 自收敛），MCP 端到端验证跑通。
- **自搜索**：self_search.mbt 注入式外部搜索 + 候选分析/判重/可移植评估。

## 4. 发布前质量硬化（评审通过）
- 用 open-code-review（官方 code-review 引擎）对全套脚本/CI/githooks/gitignore 审查并修复 40 项问题：HTTP 并发串线竞态修复、cron stderr 管道死锁、客户端/服务端 timeout 错位对齐、非原子状态写改 tmp+replace、CI 最小权限 / checkout 钉 commit SHA / concurrency / timeout-minutes / 工具链 cache、pre-commit set -e。
- 用 ocr-local（20 条 MoonBit 专项规则 + 逐处人工判伪阳性）审查核心源码，修复系统性 `moonbit-result-discard`：`update_task/upsert_spec` 的 `ignore()` 静默吞错 13 处改为 match 传播 Err，消除状态机与 SQLite 持久化漂移；移除 core_task 死代码。抽查复核：baseline 亦复现的 Windows native 堆损坏 flake 为已知环境边界，非本次回归。
- 新增一页《项目申报书》PDF（赛事验收必过项）与 mooncakes 包 readme（README.mbt.md，与 moon.mod readme 字段对齐）。

## 5. 文档即实现 + 无硬编码 + 可复现
- `ARCHITECTURE.md` 一页架构（9 模块关系）；`docs/evolve.md`、`docs/laya.md`、`docs/features/*`、`templates/*`、`memory/research/`（调研库，含近 3 月竞品与未来扩展）、`BACKLOG.md`（P 优先级队列）。
- 源码无绝对路径硬编码（相对路径/环境变量），`memory/research/recent-market.md` 已收集近 3 月新增 MoonBit 项目与潜在竞品、未来扩展。

## 6. 已知边界（如实）
- Windows 本地 native 全量测试偶发 `0xc0000374`（堆损坏/竞态），为已记录的环境已知边界，js 看门禁、native 以 CI/ubuntu 为准。
- 依赖 `moonbitlang/async@0.21.0` 暂未升 0.22.3（需要更新的 moon 工具链，属环境前置，不影响正确性——项目代码未用其 Headers/Http API）。