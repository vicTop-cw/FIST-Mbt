# 调研记档：参赛评估与加强建议（去重蒸馏）

> 来源报告：fist-mbt 参赛评估与加强建议（QClaw，2026-09-24 14:38）
> 蒸馏日期：2026-09-24
> 说明：不复制原文、只蒸馏可执行建议。基于当前事实核对（fist-mbt 现为 61 个 MCP 工具 / 148 项测试 / JS+Native 双端全绿 / CI 三轨道绿 / evolve 已在 148 测试内）；已覆盖标 done(已覆盖)，未确认标 pending。

## 一、P0–P3 建议清单

| P级 | 事项 | 建议来源 | 当前态 | 状态 |
|-----|------|---------|--------|------|
| P0 | 验证 evolve 模块构建+测试 | 参赛评估 §四 P0-1 | 已并入 148 测试内，CI 三轨道 js×2+native 全绿，双端通过 | done(已覆盖) |
| P0 | 清理 README 顶部 AIGC 元数据标记，避免被误判为纯 AI 生成 | 参赛评估 §四 P0-2 | 未确认 README 是否已移除 AIGC 块 | pending(tbd) |
| P0 | 升级 moonbitlang/async 至 0.22.3（处理 Headers breaking change）并升 x 至 0.5.5 | 参赛评估 §四 P0-3 | 未知当前依赖是否已升级 | pending(tbd) |
| P0 | 补充"30 秒体验"演示：一行命令 + MCP 客户端示例 + 一键 demo 脚本 | 参赛评估 §四 P0-4 | 未确认是否有 scripts/demo.* 一键演示 | pending(tbd) |
| P1 | 创建 P0 scoring.mbt（coverage/fingerprint_ok/schema_ok/accuracy 分项评分，≥7 测试） | 参赛评估 §四 P1-5 | 未知 scoring 是否已落地 | pending(tbd) |
| P1 | 补充一页项目申报书 PDF（方向/价值/亮点/生态贡献/验证步骤） | 参赛评估 §四 P1-6 | 未知是否已产出申报书 | pending(tbd) |
| P1 | 在 mooncakes.io 发布（moon publish，坐实生态贡献） | 参赛评估 §四 P1-7 | 未知是否已发布 | pending(tbd) |
| P2 | 集成 moonbitlang/core/quickcheck 属性测试替代部分硬编码断言 | 参赛评估 §四 P2-8 + §六 | 未知是否已引入 quickcheck | pending(tbd) |
| P2 | 评估 mizchi/llm 纯 MoonBit 客户端替代 Python sidecar（进一步纯化） | 参赛评估 §四 P2-9 + §六 | 未知是否已替换 | pending(tbd) |
| P2 | 补充 ARCHITECTURE.md（9 模块关系图 + 数据流 + MCP 协议层） | 参赛评估 §四 P2-10 | 未知是否已产出架构文档 | pending(tbd) |
| P3 | 创建 P5 self_search.mbt（参考五方向调研：search_external + analyze_mechanism + portability_assessment） | 参赛评估 §四 P3-11 | 未知 self_search 是否已启动 | pending(tbd) |
| P3 | 补充 English README（面向 Lambda World 2026 国际受众） | 参赛评估 §四 P3-12 | 未知是否已有英文 README | pending(tbd) |

## 二、生态可集成清单（§六 去重保留，未实现均标 pending）

| 包 | 可借鉴/集成点 | 优先级 | 当前态 | 状态 |
|----|-------------|--------|--------|------|
| moonbitlang/core/diff | 报告对比、测试 diff 展示 | P2 | 未知 | pending |
| gaato/github | GitHub API 客户端，self_search 模块可用 | P3 | 未知 | pending |
| colmugx/posoco | 参考 Agent 框架六边形架构设计 | P3（仅参考） | 未知 | pending |
| colmugx/mcp | 已依赖（fist-mbt 的 MCP 协议库） | - | 已集成于 MCP Server 层 | done(已覆盖) |

## 三、蒸馏结论

P0 四项中"验证 evolve"已由当前事实覆盖（done）；其余 P0/P1/P2/P3 建议当前态多数未能从记忆库确认，一律标 pending(tbd)，待逐项核对源码/文档后再转 done 或删除。赛事目标"前 10"关键看：验收通过（必要条件）+ 演示体验 + 申报书质量 + 生态发布，前三项仍待补足。

## 来源
QClaw《fist-mbt 参赛评估与加强建议_20260924-1438.md》§四（P0–P3 建议 12 条）+ §六（生态可集成清单）；当前事实按任务给定（61 工具 / 148 测试 / 双端全绿 / CI 三轨道绿 / evolve 已入测试）。