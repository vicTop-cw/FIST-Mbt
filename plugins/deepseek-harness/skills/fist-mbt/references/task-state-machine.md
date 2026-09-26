# Task State Machine

## TaskStatus Enum

```moonbit
pub enum TaskStatus {
  Pending      // 待领取
  Claimed      // 已领取
  Splitting    // 拆分中
  Executing    // 执行中
  Reviewing    // 待验收
  Completed    // 已完成
  Archived     // 已归档
  Rejected     // 已打回
  Paused       // 已暂停
}
```

## State Predicates

| Predicate | True for |
|-----------|----------|
| `can_split` | Pending, Claimed, Splitting, Rejected |
| `can_execute` | Claimed, Splitting, Executing, Rejected |
| `is_active` | Pending, Claimed, Splitting, Executing, Reviewing |
| `is_completed` | Completed |
| `is_rejected` | Rejected |
| `is_paused` | Paused |

## Transitions

| From | To | Method | Actor |
|------|-----|--------|-------|
| Pending | Claimed | `claim(assignee)` | Any agent |
| Claimed | Splitting | `split()` | Commander |
| Pending/Claimed/Splitting | Splitting | `mark_decomposing()` | AO decomposer |
| Splitting/Claimed | Executing | `execute()` | Executor |
| Executing | Reviewing | `submit()` | Executor |
| Reviewing | Completed | `complete(verifier)` | Human verifier |
| Completed | Archived | `archive()` | Human steward |
| Rejected | Claimed | `reopen()` | System |
| Paused | Claimed | `resume()` | System |
| Reviewing | Rejected | `reject(reason)` | Verifier |
| Rejected | Executing | `retry()` | Executor |
| Any active | Paused | `pause()` | System |
| Any | Claimed | `reopen()` | System |

## Illegal Transitions

All illegal transitions return `Err("非法迁移: ...")`. Examples:
- `claim()` on non-Pending task
- `split()` on non-Claimed task
- `complete()` on non-Reviewing task
- `archive()` on non-Completed task (unless auto-completed first)

## Task Struct

```moonbit
pub struct Task {
  pub id : String           // e.g., "T0", "T0.1"
  pub parent_id : String?   // None for root
  pub project_dir : String
  pub ns : String           // namespace (default "default")
  pub priority : String
  pub importance : String
  pub depth : Int           // K-value
  pub split_n : Int         // default 3
  pub status : TaskStatus
  pub assignee : String?
  pub description : String
  pub deliverable : String
  pub created_at : String
  pub updated_at : String
  pub completed_by : String?
  pub cleanup_mode : String
  pub depends_on : Array[String]  // dependency task IDs
}
```

## Key Methods

```moonbit
// Status queries
task.is_leaf()          // depth <= 1
task.get_status()
task.get_depth()
task.get_parent()

// State transitions (return Result[Task, String])
task.claim(assignee)
task.split()
task.execute()
task.submit()
task.complete(verifier)
task.archive()
task.reject(reason?)
task.retry()
task.pause()
task.resume()
task.reopen()

// Utility
task.to_json()
task.with_deliverable(deliverable, now)
```
