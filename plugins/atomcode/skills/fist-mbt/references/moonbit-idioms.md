# MoonBit Idioms for FIST-Mbt

## Block Style

FIST-Mbt uses MoonBit block style with `///|` separators:

```moonbit
///| First block
pub fn foo() -> Unit { ... }

///| Second block (order doesn't matter)
pub struct Bar { ... }
```

## Result Type

State transitions return `Result[T, String]`:

```moonbit
pub fn Task::claim(self : Task, assignee~ : String) -> Result[Task, String] {
  match self.status {
    Pending => Ok({ ..self, status: Claimed })
    _ => Err("非法迁移: claim 要求状态 [待领取]")
  }
}
```

## Optional Parameters

```moonbit
// Default values with ?
pub fn Task::new(
  id~ : String,
  description? : String = "",
  depth? : Int = 3,
) -> Task { ... }

// Nullable with ?
pub fn Task::from_db(
  assignee : String?,  // can be None
) -> Task { ... }
```

## Pattern Matching

```moonbit
match self.status {
  Pending => "待领取"
  Claimed => "已领取"
  _ => "未知"
}

// With guard
match task {
  Some(t) if t.get_status().is_active() => ...
  _ => ...
}
```

## JSON Handling

```moonbit
// Build JSON object
let m : Map[String, Json] = Map([])
m.set("id", Json::string(self.id))
m.set("status", Json::string(self.status.to_string()))
Json::object(m)

// Parse (if needed)
let json = Json::parse(str)?
```

## Store Pattern

Engine holds store as abstract backend:

```moonbit
pub struct FistEngine {
  store : @store.StoreBackend
}

// Delegation
pub fn FistEngine::list_all(self : FistEngine) -> Array[@core.Task] {
  self.store.list_tasks()
}
```

## Ignore Void Returns

```moonbit
// For Result[Unit, String] that we don't care about
ignore(self.store.update_task(task))
```

## Testing

- Whitebox tests: `*_wbtest.mbt` (can access private fields)
- Blackbox tests: `*_test.mbt` (public API only)
- Snapshot testing: `moon test --update` to refresh

## Common Commands

```bash
moon check          # Type check
moon test           # Run tests
moon build          # Build
moon fmt            # Format
moon info           # Update .mbti interfaces
moon ide doc        # Get documentation
moon tree           # Show package tree
```
