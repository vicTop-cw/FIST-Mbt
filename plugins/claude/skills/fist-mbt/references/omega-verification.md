# Omega Strong Verification

Omega is an optional spec-driven verification workflow for critical tasks.

## Overview

When `omega_strong_verify=true` is passed to `task_plan_deep`, each subtask enters a three-phase workflow:

1. **Spec Creation** (spec_author): Create verification spec
2. **Spec Review** (verifier): Review and approve/reject spec
3. **Execution + Result Verify**: Execute task and verify against spec

## Enabling

```moonbit
// Via MCP: task_plan_deep with omega_strong_verify=true
// Via Engine: engine.task_plan_deep(task_id, omega_strong_verify=true)
```

## Workflow

```
Spec Create → Spec Review → Execute → Result Verify
                  ↓               ↓
              Reject (redo)    Reject (retry)
```

## Tools

### omega_spec_create
- **Role**: spec_author
- **Params**: task_id, author, content, max_rounds?
- **Creates**: Record in `omega_specs` table

### omega_spec_review
- **Role**: verifier
- **Params**: task_id, reviewer, verdict, reason?
- **Verdict**: "approve" or other (reject)

### omega_result_verify
- **Role**: verifier
- **Params**: task_id, reviewer, verdict, reason?
- **Verdict**: "approve" or other (reject → retry)

### omega_status
- **Params**: task_id
- **Returns**: Progress (switch status, rounds, reject count, escalation flag)

## Rounds Limit

- Default: 3 rounds
- Maximum: 10 rounds
- Exceeding: Auto-escalation, task paused for human decision

## Gate (External Verification)

Separate from Omega, the `gate` check prevents "self-test always green":

- `[gate:required]` tasks must have a real server-side check record
- `run_check` results stored in `gate_records`
- Verified during `verify()` before completion

## Tables

### omega_specs
- task_id, author, content, max_rounds, created_at, status, review_reason

### gate_records
- task_id, check_result, created_at
