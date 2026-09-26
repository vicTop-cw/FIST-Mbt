# DAG Operations

FIST-Mbt tracks task dependencies as a Directed Acyclic Graph (DAG).

## Dependency Model

```moonbit
pub struct Task {
  // ...
  pub depends_on : Array[String]  // IDs of tasks that must complete first
}
```

## Claim Gates

A task can only be claimed if all its dependencies are satisfied:

```moonbit
fn FistEngine::deps_satisfied(self : FistEngine, task_id : String) -> Bool {
  let task = self.store.get_task(task_id)
  for dep_id in task.depends_on {
    let dep = self.store.get_task(dep_id)
    if dep.is_none() || !dep.get_status().is_completed() {
      return false
    }
  }
  true
}
```

## DAG Tools

### dag_critical_path
Returns the longest dependency chain (critical path).

### dag_parallelism
Returns the number of tasks that can run in parallel.

### dag_ascii
Returns ASCII visualization of the dependency graph.

### dag_check
Checks if all dependencies for a task are complete.

### dag_ready
Lists tasks ready to be claimed (dependencies satisfied).

### dag_sort
Returns topological sort of tasks.

## Example Graph

```
T0 (root)
├── T0.1 ──→ T0.1.1
│           └──→ T0.1.2
└── T0.2 ──→ T0.2.1
    ↑
    depends_on: [T0.1]
```

Here, T0.2 depends on T0.1 completing before it can start.

## Engine Methods

```moonbit
// Get children of a task
engine.children_of(task_id)

// Check if all subtasks completed
engine.all_subtasks_completed(parent_task)

// List ready tasks (deps satisfied)
engine.dag_ready()
```
