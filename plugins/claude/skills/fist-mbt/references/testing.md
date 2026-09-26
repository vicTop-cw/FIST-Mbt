# Testing Patterns

## Test Organization

- **Blackbox tests**: `*_test.mbt` — tests against public API only
- **Whitebox tests**: `*_wbtest.mbt` — tests with access to internal fields

## Running Tests

```bash
moon test              # Run all tests
moon test --update     # Update snapshots
moon test src/engine   # Run engine tests only
```

## Snapshot Testing

MoonBit supports snapshot testing. When outputs change:

```bash
moon test --update     # Refresh all snapshots
```

## Test Structure Example

```moonbit
// In engine_dag_ext_test.mbt
test "dag_critical_path works" {
  let engine = FistEngine::new()
  // Setup tasks...
  let path = engine.dag_critical_path()
  assert_eq(path.length(), 3)
}
```

## Test Utilities

### Creating Test Tasks

```moonbit
let task = @core.Task::new(
  id="T0",
  project_dir="/tmp/test",
  description="test task",
  created_at="2024-01-01T00:00:00Z",
)
```

### Using SQLite in Tests

```moonbit
let store = @store.SqliteStore::open(":memory:")?
let engine = FistEngine::new(store=@store.StoreBackend::sqlite(store))
```

## Coverage

No built-in coverage tool in MoonBit. Use test count and manual inspection.

## CI Integration

Tests run via `moon test` in CI. See `.github/workflows/` for examples.
