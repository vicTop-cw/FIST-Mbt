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

## MCP Tools (41 total)

### Lifecycle (12)
- `publish`, `plan`, `claim`, `execute`, `submit`, `verify`, `reject`, `retry`, `pause`, `resume`, `archive`, `delete`

### Query (2)
- `list`, `get`

### Operations (6)
- `task_plan_deep`, `conflicts_check`, `heartbeat`, `heal`, `watchdog_tick`, `task_cleanup`

### DAG (6)
- `dag_critical_path`, `dag_parallelism`, `dag_ascii`, `dag_check`, `dag_ready`, `dag_sort`

### Audit (2)
- `audit_permission`, `audit_log`

### Multi-tenant (3)
- `store_open`, `store_list`, `store_close`

### Omega (4, optional)
- `omega_spec_create`, `omega_spec_review`, `omega_result_verify`, `omega_status`
