# FIST-Mbt Watchdog 整改计划

> 日期：2026-09-17  
> 状态：待执行  
> 根因定位：`watchdog_tick` 消费判定死锁 + 冷启动路径缺失

---

## 一、问题现象

Pentad 项目 `pentad-tick-b54ec9` 定时调度器运行约 25 小时（2026-09-15 22:52 → 2026-09-16 23:23），每 45 分钟唤醒一次，累计产出 **17 份 Gen_Prompts/yyyyMMdd.HH.mm.ss.md 提示词文件**，但：

- `cron-auto.db` 中 0 tasks / 0 specs / 0 runs / 0 heartbeats / 0 archive
- **从未发布过任何根任务**
- 代码零修改，编译仍失败（`Token::Hash` 未定义）
- 调度器在分支④（生成提示词）死循环，永不进入分支③（接新根任务）

---

## 二、根因分析

### 2.1 死锁链条

```
meta_prompt.md 判定规则：
  R == none（从未有过根任务）且 U == 空（无已完成根任务）
  → 按保守规则：U 为空 → 判定为「已消费」
  → 走分支④：生成新提示词
  → 不 publish，不调用 watchdog_tick 续轮
  → 下一轮：R 仍 none，U 仍空 → 再次生成新提示词
  → ∞ 循环
```

### 2.2 两个独立缺陷

| # | 缺陷 | 位置 | 后果 |
|---|---|---|---|
| **Bug-1** | `_meta_prompt.md` 消费判定：`R == none && U == 空` 时错误判定为「已消费」 | Pentad/Gen_Prompts/_meta_prompt.md 第 140-141 行 | 冷启动时永远无法进入分支③发布第一个根任务 |
| **Bug-2** | `watchdog_tick` 无法冷启动：没有 `pending_advance`（已完成根任务）时无法发布新轮次；`publish` 工具要求 `created_by=human_steward`，watchdog 无冷启动入口 | FIST-Mbt/src/engine/engine.mbt `publish_next_round`（第 445-498 行）+ src/ops/ops_watchdog.mbt 第 276-303 行 | 即使 meta_prompt 判定正确，首次任务仍无法通过 watchdog_tick 发布 |

### 2.3 设计矛盾

- `publish` 工具限 `created_by ∈ {human_steward, human}`（engine.mbt:43）—— 防止自动流程冒充人类发布
- `publish_next_round` 限 `ns != "default"` 且必须有 `pending_advance`（已完成根任务）—— 防止无载体续轮
- 但 `_meta_prompt.md` 冷启动兜底路径要求「代人类指挥官发布首轮根任务」（第 163-176 行），而分支判定又永远走不到这里

**结论：系统从未设计过「首次冷启动」路径。**

---

## 三、整改目标

1. **打破死锁**：让调度器在 `R == none && U == 空` 时能正确进入冷启动发布
2. **建立冷启动通道**：为 `watchdog_tick` 增加「无已完成根任务时仍可发布首轮」的能力
3. **可验证**：修复后手动触发一次 tick，`cron-auto.db` 应出现 1 条根任务

---

## 四、整改方案

### 4.1 Bug-1 修复：消费判定规则（Pentad/Gen_Prompts/_meta_prompt.md）

**当前逻辑（第 138-141 行）：**
```
- R 为 none → 未消费
- P 晚于 R → 未消费
- 否则 → 已消费
- 兜底规则：U 非空→未消费，U 为空→已消费  ← BUG
```

**修改为：**
```
- R 为 none → 未消费（冷启动，从未有过根任务）
- P 晚于 R → 未消费
- 否则 → 已消费
- 兜底规则：R 为 none → 未消费；R 非空且 P ≤ R → 已消费（删除 U 非空/为空分支）
```

**核心改动**：删除 `U 非空/为空` 兜底规则，改为仅依赖 `R`（最近根任务时间）与 `P`（最新提示词时间）的比较。`R == none` 一律视为「未消费」。

### 4.2 Bug-2 修复：冷启动发布路径（FIST-Mbt 代码）

#### 方案 A（推荐）：新增 `cold_start` 参数给 `watchdog_tick`

在 `ops_watchdog.mbt` 中增加一个可选参数 `cold_start? : Bool = false`。

当 `cold_start = true` 且 `pending_advance = None` 时：
- 跳过「必须存在已完成根任务」的前置检查
- 直接调用 `engine.publish_next_round` 的内部逻辑（仅发布新任务，不标记旧任务）
- 或者复用 `publish` 工具，但由 `watchdog_tick` 内部以 `created_by = "watchdog"` 写入审计日志

**engine.mbt 改动：**

```moonbit
/// 冷启动发布（无上一轮根任务时创建首个任务）
/// 仅用于 cron-auto 等自动化命名空间，语义等同「人类指挥官发布首轮」
/// 但审计日志标记为 watchdog 自动发布
pub fn FistEngine::cold_publish(
  self : FistEngine,
  ns~ : String,
  description~ : String,
  created_by~ : String,  // 允许 "watchdog"
  project_dir~ : String,
  now~ : String,
) -> Result[String, String] {
  if ns == "" || ns == "default" {
    return Err("冷启动发布仅限定时任务命名空间")
  }
  // 检查该 ns 是否已有任务，避免重复发布
  if !self.list_in_ns(ns).is_empty() {
    return Err("命名空间已存在任务，请使用 publish_next_round")
  }
  let id = root_task_id()  // "T0"
  let t = @core.Task::new(
    id~,
    project_dir~,
    description~,
    depth=3,
    split_n=3,
    created_at=now,
    ns~,
  )
  match self.store.create_task(t) {
    Ok(_) => Ok(id)
    Err(e) => Err(e)
  }
}
```

**ops_watchdog.mbt 改动：**

```moonbit
pub fn watchdog_tick(
  engine : @engine.FistEngine,
  now : String,
  timeout_sec? : Int = 600,
  ns? : String = "",
  next_description? : String = "",
  next_created_by? : String = "watchdog",
  meta_prompt_path? : String = "",
  cold_start? : Bool = false,        // ← 新增
) -> Result[Json, String] {
  // ... 原有逻辑 ...

  // 续轮阶段（修改后）
  if ns != "" && next_description != "" {
    match pending_advance {
      Some(prev) => /* 原有 publish_next_round 逻辑 */
      None => {
        // 冷启动：无已完成根任务时，发布首个任务
        if cold_start {
          match engine.cold_publish(
            ns~,
            description=next_description,
            created_by=next_created_by,
            project_dir=/* 从 engine 获取 */,
            now~,
          ) {
            Ok(new_id) => return Ok(tick_json("advanced", ...))
            Err(_) => ()
          }
        }
      }
    }
  }
}
```

**server.mbt 改动：**

在 `watchdog_tick` tool schema 中增加 `cold_start` 参数，传递给 `@ops.watchdog_tick`。

#### 方案 B（备选）：不修改 FIST-Mbt，仅在 _meta_prompt.md 中直接调用 `publish` 工具

分支③的冷启动路径（当前第 163-176 行已存在）使用 `publish`：

```
publish({
  project_dir: "E:/IDEProjects/AI/Pentad",
  description: "<最新提示词全文>",
  namespace: "cron-auto",
  created_by: "human_steward",
  now: "<当前时间>"
})
```

**问题**：`publish` 限 `created_by=human_steward`，这要求调度器「冒充」人类发布。审计上不够干净，但功能上可以工作。

### 4.3 推荐方案：A + _meta_prompt.md 联动修复

- FIST-Mbt 侧：实现 4.2 方案 A（新增 `cold_start` 参数 + `cold_publish` 方法）
- Pentad 侧：修复 Bug-1 的消费判定规则，分支③调用 `watchdog_tick` 时增加 `cold_start=true`

---

## 五、文件改动清单

| 文件 | 改动 |
|---|---|
| `src/engine/engine.mbt` | 新增 `FistEngine::cold_publish` 方法 |
| `src/ops/ops_watchdog.mbt` | `watchdog_tick` 增加 `cold_start` 参数 + None 分支冷启动逻辑 |
| `src/server/server.mbt` | `watchdog_tick` tool schema 增加 `cold_start` 参数 |
| `src/ops/ops_watchdog_test.mbt` | 新增冷启动用例（ns 空库 → cold_start=true → 出现 T0） |
| `src/engine/engine_test.mbt`（或新建） | 新增 `cold_publish` 单测 |
| `Pentad/Gen_Prompts/_meta_prompt.md` | 修改第 138-141 行消费判定规则 |

---

## 六、验证方案

### 6.1 单元测试

```moonbit
// 冷启动场景：空库 → watchdog_tick(cold_start=true) → 出现 T0
test "cold_start_creates_first_root_task" {
  let e = FistEngine::new()
  let now = "2026-09-17T10:00:00Z"
  let args = {
    "now": now,
    "namespace": "cron-auto",
    "next_description": "测试冷启动任务",
    "meta_prompt_path": "E:/IDEProjects/AI/Pentad/Gen_Prompts",
    "cold_start": true,
  }
  let j = watchdog_tick(e, args)
  assert_eq(j.action, "advanced")
  assert_eq(e.list_in_ns("cron-auto").length(), 1)
  assert_eq(e.get_task("T0").is_some(), true)
}
```

### 6.2 集成验证（手动）

```bash
# 1. 重新启用调度器
# 2. 等待下一轮唤醒
# 3. 检查 cron-auto.db
python3 -c "import sqlite3; c=sqlite3.connect('E:/IDEProjects/AI/FIST-Mbt/cron-auto.db'); print(c.execute('SELECT id, status, ns FROM tasks').fetchall())"
# 期望：[('T0', '待领取', 'cron-auto')]
```

---

## 七、风险评估

| 风险 | 缓解 |
|---|---|
| `cold_publish` 被误用于 default ns | 已在方法内限制 `ns != "default"` |
| 重复调用 cold_start 导致多个 T0 | 检查 `list_in_ns(ns).is_empty()`，已有任务则拒绝 |
| 审计追踪混淆自动/人工发布 | `cold_publish` 不写 `created_by` 到 Task 字段（Task 无此字段），仅在发布时记录 `next_created_by` |

---

## 八、执行计划

| 阶段 | 内容 | 预估 |
|---|---|---|
| Phase 1 | 实现 `cold_publish` + 单测 | 1-2 小时 |
| Phase 2 | 修改 `watchdog_tick` + 冷启动分支 + 单测 | 1 小时 |
| Phase 3 | 修改 `server.mbt` tool schema | 30 分钟 |
| Phase 4 | 修改 `_meta_prompt.md` 消费判定规则 | 30 分钟 |
| Phase 5 | 全量 `moon test` + 手动集成验证 | 1 小时 |
| **合计** | | **4-5 小时** |

---

*本文档由 AtomCode 生成，基于 FIST-Mbt 源码实际分析。*
