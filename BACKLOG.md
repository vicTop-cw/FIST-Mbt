---
topics: [backlog]
doc_kind: note
created: 2026-09-24
---

# Feature Roadmap

> **Rules**: Only active Features (idea/spec/in-progress/review). Move to done after completion.
> Details in `docs/features/Fxxx-*.md`.

## Done

| # | Feature | Status | Owner | Link |
|---|---------|--------|-------|------|
| F000 | AI 自驱式编程 MCP 功能（selfdrive_* 8 工具 + memory 四件套 + 审视轮闭环） | done | fist-mbt | `docs/features/F000-selfdrive.md` |
| F001 | list 工具增加 namespace 过滤参数 | done | fist-mbt | `docs/features/F001-list-namespace.md` |
| F002 | list 状态过滤 + 命名空间隔离盲区优化 | done | fist-mbt | `docs/features/F001-list-namespace.md` |
| F003 | reopen_task 暴露为 MCP 运维工具 | done | fist-mbt | `docs/features/F003-reopen-task.md` |
| F004 | selfdrive 审视闭环接入 watchdog_tick 单入口 | done | fist-mbt | `docs/features/F004-selfdrive-watchdog.md` |
| F005 | 根任务 id 生成并发防死循环保护 | done | fist-mbt | `docs/features/F005-id-concurrency.md` |
| F006 | 测试 temp/ 残留污染修复（用例幂等可重复跑） | in-progress | fist-mbt | `docs/features/F006-test-residue.md` |
| F007 | native 构建 sqlite3.h 环境要求文档 | done | fist-mbt | `docs/features/F007-native-env.md` |

> F000-F007 由 fist-mbt 自身功能（publish_parallel + watchdog_tick 自驱整合）驱动完成，见 `reports/2026-09-24-self-iter-report.md`。

*（内容由AI生成，仅供参考）*