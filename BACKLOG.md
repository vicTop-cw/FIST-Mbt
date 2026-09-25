# fist-mbt BACKLOG（P 优先级待办队列）

> 本文档为 selfdrive 审视/门禁的净拉取源：Next Tasks 应从这里取。
> 由三份调研去重收敛生成：`memory/research/competition.md`、`memory/research/five-directions.md`、`memory/research/future-roadmap.md`。
> 状态枚举 `pending | done`。锚点事实：**91 工具 / 259 测试**（`moon test --target js` Windows+WSL 双端全绿）/ JS+Native 双后端 / CI 三绿 / evolve 已在测试内。计数同步见 `scripts/check_tools_sync.py` / `check_test_sync.py`。

| P级 | 事项 | 来源 | 状态 | 对应review/commit |
|-----|------|------|------|-------------------|
| P0 | 补「30 秒体验」一键演示：README 段落 + scripts/demo 一键脚本（一行命令通起），对冲 MCP 接线门槛 | competition/§四 P0-4 + future-roadmap/近 | done(scripts/demo.ps1 已加并实测 61 工具 PASS；README 终版 0930 接段落) | - |
| P0 | 清理 README 顶部 AIGC 元数据标记，避免被误判为纯 AI 生成 | competition/§四 P0-2 + future-roadmap/近 | done(README/AGENTS 顶部 AIGC 块已移除，R86) | commit `9f13284` 后 R86 |
| P0 | 升级 moonbitlang/async 至 0.22.3（处理 Headers breaking change）并升 x 至 0.5.5 | competition/§四 P0-3 | blocked: 需 moon 工具链 ≥0.1.20260921(现 0.1.20260904); async 0.22.3 自身用 eprintln 被本 core 移除; moon upgrade 需交互 TTY; 项目代码未用 Headers/Http(仅 js_async)非正确性必需 | - |
| P0 | 创建 scoring.mbt P0（coverage/fingerprint_ok/schema_ok/accuracy 分项评分，≥7 测试）打通自进化闭环 | competition/§四 P1-5 + future-roadmap/近 | pending | - |
| P0 | 验证 evolve 模块构建+测试（已并入 148 测试内、双端全绿、CI 三轨道绿） | competition/§四 P0-1 | done | commit `88a781f` |
| P1 | 下一页项目申报书 PDF（方向/价值/亮点/生态贡献/验证步骤），补齐第一印象材料 | competition/§四 P1-6 + future-roadmap/近 | done(gen_apply_pdf.py 生成 A4 单页, simhei CJK, 已生成 项目申报书.pdf 个人档不入库) | commit(gen_apply_pdf) |
| P1 | 在 mooncakes.io 发布（moon publish），坐实生态贡献 | competition/§四 P1-7 + future-roadmap/近 | done(v0.2.4 已发布; 首跑 409 版本重复已换 0.2.4) | commit `a373267` |
| P1 | Agent Contract 7 字段：Objective/Constraints/Tool policy/Stop conditions/Escalation/State discipline/Evidence 注入 ops_selfdrive | five-directions/§一 | pending | - |
| P1 | Tool Use Rubric：pipeline 生成 prompt 时注入工具使用硬规则降 tool 幻觉 | five-directions/§一 | pending | - |
| P1 | "Did it work?" 输出验证：除"是否运行"外校验输出是否有效 | five-directions/§一 | pending | - |
| P2 | 局部补偿替代全局 replanning：history-aware local compensation 控级联效应 | five-directions/§一 | pending | - |
| P2 | 全局目标校验：每子任务完成后校验是否偏离根目标（non-redundancy） | five-directions/§一 | pending | - |
| P2 | 集成 moonbitlang/core/quickcheck 属性测试替代部分硬编码断言 | competition/§四 P2-8 + five-directions/§六 + future-roadmap/中 | pending | - |
| P2 | 评估 mizchi/llm 纯 MoonBit 客户端替代 Python sidecar（进一步纯化） | competition/§四 P2-9 + §六 + future-roadmap/中 | pending | - |
| P2 | 补充 ARCHITECTURE.md（9 模块关系图 + 数据流 + MCP 协议层），降低概念门槛 | competition/§四 P2-10 + future-roadmap/中 | pending | - |
| P2 | Interleaved 分支：据子任务执行反馈回退改 plan，而非拆完即弃 | five-directions/§一 | pending | - |
| P2 | Transactional transition：invariant 失败整笔拒绝、状态 A 回稳 | five-directions/§一 | pending | - |
| P2 | Pre-execution audit gate：can_execute 之后、execute 之前插入 gate interception | five-directions/§一 | pending | - |
| P2 | Evaluator-Optimizer schema：feedback 收敛为 Defects/Evidence/Fix/Acceptance 四段式 | five-directions/§一 | pending | - |
| P2 | 多维度健康指标：除存活外检查 CPU/内存/任务积压/最近成功（4 类检查） | five-directions/§一 | pending | - |
| P2 | Circuit Breaker 三态：Closed/Open/Half-Open 对外部调用快速失败 | five-directions/§一 | pending | - |
| P2 | 集成 moonbitlang/core/diff 展示报告对比、测试 diff | competition/§六 + future-roadmap/中 | pending | - |
| P2 | Dashboard/ASCII 可视化输出（状态流转、DAG 依赖图 JSON→图） | future-roadmap/中 | pending | - |
| P3 | 创建 P5 self_search.mbt（search_external + analyze_mechanism + portability_assessment 外部检索入库） | competition/§四 P3-11 + future-roadmap/远 | pending | - |
| P3 | 补充 English README（面向 Lambda World 2026 国际受众） | competition/§四 P3-12 + future-roadmap/近 | pending | - |
| P3 | 里程碑式渐进：decompose 前先生成粗粒度里程碑再逐步细化 | five-directions/§一 | pending | - |
| P3 | 可编程策略集：将 Omega gate 8 种 $assert 扩展为支持用户自定义 invariant | five-directions/§一 | pending | - |
| P3 | Runtime monitoring：按执行 trace 对 LTL 属性低开销认证 | five-directions/§一 | pending | - |
| P3 | 毫秒级符号逻辑引擎按布尔约束拦截 planned action | five-directions/§一 | pending | - |
| P3 | Phi Accrual 概率式检测：按心跳历史分布算 φ 值替代固定 timeout | five-directions/§一 | done(phi_accrual 工具 R89：φ=-log10(P 心跳晚到)，σ=0 指数回退+正态建模+尾部渐近，engine_phi_test +3；心跳间隔历史持久化+watchdog 端到端接入留后续) | commit(6fdede1 后 R89) |
| P3 | Saga 补偿事务 + durable action log：并发动作前写 append-only 日志、失败按 LIFO 补偿 | five-directions/§一 | pending | - |
| P3 | Scoring 驱动的自动进化闭环（mutation/skill_lib/curriculum）无人值守自进化 | future-roadmap/远 | pending | - |
| P3 | 与 moonclaw/posoco/官方 MCP SDK 差异化共处：定位"完整 MCP Server+编排+自进化" | future-roadmap/远 | pending | - |
| - | gaato/github API 客户端，供 self_search 模块使用 | competition/§六 | pending | - |
| - | colmugx/posoco 参考 Agent 框架六边形架构设计 | competition/§六 | pending | - |
| - | colmugx/mcp 已依赖（fist-mbt MCP 协议库），保留 | competition/§六 | done | - |

> 去重说明：competition/§四 与 five-directions/§一、future-roadmap 各方向的重复项（如 quickcheck、mizchi/llm、ARCHITECTURE、self_search、英文 README）已按主题合并为单行；状态以当前源码/记忆库是否确认实现为准，未确认一律 pending，待逐项核对后再转 done 或删除。