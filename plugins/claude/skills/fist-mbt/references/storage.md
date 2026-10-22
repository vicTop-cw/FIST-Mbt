# Storage

FIST-Mbt supports two storage backends: in-memory and SQLite.

## StoreBackend Interface

Defined in `store/store.mbt`:

```moonbit
pub struct StoreBackend {
  // Task CRUD
  create_task : (Task) -> Result[Unit, String]
  get_task : (String) -> Task?
  update_task : (Task) -> Result[Unit, String]
  list_tasks : () -> Array[Task]
  list_tasks_in : (String) -> Array[Task]

  // Heartbeat
  write_heartbeat : (String, String, String, String) -> Result[Unit, String]
  delete_heartbeat : (String) -> Result[Unit, String]
  list_all_heartbeats : () -> Array[(String, String, String, String)]

  // Executions (cost tracking)
  record_execution : (...) -> Result[Unit, String]
  cost_stats : () -> Json

  // Omega specs
  omega_create_spec : (...) -> Result[Unit, String]
  omega_review_spec : (...) -> Result[Unit, String]
  omega_get_spec : (String) -> Json?
  omega_list_specs : () -> Array[Json]

  // Gate (external verification)
  gate_record : (...) -> Result[Unit, String]
  gate_check : (String) -> Json?

  // Multi-tenant
  open_ns : (String) -> Result[Unit, String]
  list_ns : () -> Array[String]
  close_ns : (String) -> Result[Unit, String]
}
```

## Backends

### In-Memory

```moonbit
@store.StoreBackend::memory()
```

- Default for testing
- No persistence
- Fast for smoke tests

### SQLite

```moonbit
@store.SqliteStore::open("path/to/db.sqlite")
```

- Uses `mizchi/sqlite` package
- Persists tasks, heartbeats, executions, omega specs, gate records
- Tables: `tasks`, `heartbeats`, `executions`, `omega_specs`, `gate_records`

## Engine Creation

```moonbit
// Memory engine
let engine = FistEngine::new()

// SQLite engine
let engine = FistEngine::open_sqlite("fist.db")?
```

## Schema (SQLite)

### tasks table
- id, parent_id, project_dir, ns, priority, importance, depth, split_n, status, assignee, description, deliverable, created_at, updated_at, completed_by, cleanup_mode, depends_on

### executions table
- task_id, executor, model, tokens_in, tokens_out, cost, duration_ms, rate_limited, failure_reason, created_at

### omega_specs table
- task_id, author, content, max_rounds, created_at, status, review_reason

### gate_records table
- task_id, check_result, created_at
