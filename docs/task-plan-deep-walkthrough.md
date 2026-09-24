# FIST-Mbt 递归拆解（task_plan_deep）演示

> 证明 **selfdrive 发布的自驱任务 + task_plan_deep 递归拆解** 组合可用。
> 本文记录一次真实递归拆解 trace（非虚构）。

## 1. 组合链路

```
selfdrive_publish_next（审视报告 → 发布自驱根任务）
  └─ task_plan_deep（对根任务递归拆成多层子任务树，写库）
       └─ 子任务进入待领取 / 供 claim → execute → verify 继续闭环
```

即：自驱/任意根任务都可被 `task_plan_deep` 递归拆解成整棵多层子树，而不是只有一层。

## 2. 真实 trace（一次调用）

对自驱/演示任务 `T0r41` 调用：

```
moon run cmd/main → tools/call
  name: task_plan_deep
  args: { task_id: "T0r41", split_n: 2, by: "fist-selfdrive" }
```

返回（真实）：`T0r41` 被拆成 **2 个中层**，每个中层又各拆 **2 个叶子**，形成三层子树：

```
T0r41                        （根）
├─ T0r41.1   （depth 2，非原子）
│   ├─ T0r41.1.1  （depth 1，叶子）
│   └─ T0r41.1.2  （depth 1，叶子）
└─ T0r41.2   （depth 2，非原子）
    ├─ T0r41.2.1  （depth 1，叶子）
    └─ T0r41.2.2  （depth 1，叶子）
```

拆解的每个节点都真实落库（可在同一 namespace 用 `list` / `get` 查到），可继续派发执行。

## 3. 搭配自驱的意义

- 审视报告里的 `Next Task` 先经 `selfdrive_publish_next` 发布为**独立根任务**；
- 若任务较大，用 `task_plan_deep` 递归拆成多层 —— 让"自我迭代"不仅能横向批量发任务，还能对单个任务纵向拆细；
- 幂等由 `[review:file:idx]` 保证，自发发的任务不重复。

## 4. 复用入口

- `task_plan_deep(task_id, split_n?, by?, spec?, omega_strong_verify?)`
  - 有 `spec.laws` 时以 laws 为切割依据；无 spec 时按机械切片。
- 对已完成/归档的任务拒绝拆分（状态机校验）。
- 详见 README「MCP 暴露面 - 运维」与 AGENTS。

*（内容由AI生成，仅供参考）*