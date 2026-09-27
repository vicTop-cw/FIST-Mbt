# FIST Methodology

FIST is a commander task allocation methodology. FIST-Mbt is a MoonBit implementation.

## Golden Principles (金条)

1. **唯一指挥官**: Single commander, no concurrent conflicting orders
2. **分层递归**: Hierarchical decomposition (K-value depth)
3. **状态机驱动**: Seven-state lifecycle with explicit transitions
4. **验收主权**: Human verification required for completion
5. **记忆沉淀**: All tasks produce deliverables and logs
6. **不可逆保护**: Archive/delete require human authority
7. **冲突检测**: Claim conflicts are detected and resolved

## Task Lifecycle

```
publish → plan → claim → execute → submit → verify → complete → archive
                            ↑________↓
                            reject (retry)
```

## States

| State | Chinese | Description |
|-------|---------|-------------|
| Pending | 待领取 | Available for claiming |
| Claimed | 已领取 | Agent has claimed |
| Splitting | 拆分中 | Being decomposed into subtasks |
| Executing | 执行中 | Agent is working |
| Reviewing | 待验收 | Deliverable submitted, awaiting verification |
| Completed | 已完成 | Verified by human |
| Archived | 已归档 | Frozen, cannot be modified |
| Rejected | 已打回 | Failed verification, needs retry |
| Paused | 已暂停 | External interruption or waiting for dependency |

## K-Value (Decomposition Depth)

- Root task: K = 3
- Each decomposition level: K decreases by 1
- K <= 1: atomic task (leaf), cannot be split further

## Task ID Hierarchy

```
T0           (root)
├── T0.1     (first child)
│   ├── T0.1.1
│   └── T0.1.2
└── T0.2
    └── T0.2.1
```

## MCP Tools

Not listed here any more — a hand-copied second inventory is exactly what rotted
(it sat at "41 total" while the registry had grown to 120; BUG-67).
The only projections of the registry are:

- `SKILL.md` §Tool count & categories — 120 tools, grouped as
  生命周期 14、查询 2、运维·编排 14、自驱闭环 9、运维·验证·规范 15、模型路由·外部执行器 4、衍生 3、看板·DAG·规划 22、自我记忆·自进化 11、Marketplace·能力路由 5、审计·多租户 5、GitHub 同步·缺陷外发 8、开发模式与模板 2、Omega 强验证 6
- README §功能全景 (repo) — the grouping source, pinned against `tools/list`
  by `scripts/check_doc_surface.py` J4 and re-checked at plugin-generation time

`tools/list` on a running server is the live truth; anything else is a copy.
