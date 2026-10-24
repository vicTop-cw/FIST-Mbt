# SKILL: loop-mode — 组合环编排（loop_create / loop_tick / loop_status）× 自驱七模式（mode_list / mode_templates）

> 形态：skill（本文档，一源四态第三态）｜MCP 工具 `loop_create` / `loop_tick` / `loop_status` + `mode_list` / `mode_templates`
> 真源：`src/ops/ops_loop.mbt`（`PipelineLoop` / `LoopTickResult` / `preset_loop` / 终止判定，纯计算零 IO）
> + `src/ops/ops_modes.mbt`（`all_modes` 7 模式注册表 + `mode_template_path`）
> + `src/server/server.mbt`（五个工具的 MCP 注册与参数 schema + 进程内 `LoopRegistry`）
> 用途：给"多步闭环怎么转、转到第几轮、何时停"一个确定性编排层（`loop_*`），给"每一步到底做什么、门禁键/禁用工具是什么"
> 一个确定性执行层（`mode_*`）——**loop 编排多步，mode 定义每步做什么**，两层分离、各管一段。

## 何时用

### A. 组合环编排（loop_create / loop_tick / loop_status）

- **把多个 mode 串成一个自动闭环**：一个环节里 `advance → bugfind → fix_and_merge → verify` 反复转 N 轮，健康度达标自动停，
  不必每拍手工决定"下一步跑哪个 mode"。
- **无人值守 / 定时唤醒**：定时任务里 `loop_tick` 一拍返回下一步该跑哪个 `next_mode`，交给 `pipeline_tick(mode=...)` 执行，
  直到 `goal_reached` / `max_rounds_hit` / `exceeded` 之一触发即停——"转几轮、何时收手"由环判据说了算。
- **预设开箱即用**：`preset` 一键展开，不必手拼 `steps`——`full-iterate`（四模式流水线）/ `fix-iterate`（寻虫→修复）/
  `build-verify`（开发→验证→打磨）三条最常用；`loop_create` 的 `steps` 也可完全自定义。
- **状态可见**：`loop_status` 一眼看当前环在哪一步（`next_step_idx`）、第几轮（`round`）、停没停（`should_stop` /
  `stop_reason` / `goal_reached` / `exceeded`）；不带 `name` 时列出所有已注册环的摘要。

### B. 自驱七模式（mode_list / mode_templates）

- **AI 选模式**：接到"继续开发 / 打磨 / 验证 / 寻虫 / 修复合并 / 清整 / 探索"这类自驱任务，先 `mode_list` 拿到 7 种模式的
  完整信息（含 `constraints` 门禁键与 `forbidden_tools`），按场景挑一个；`explore` 是唯一不亲自开发的 selector 模式。
- **开工前预检模板**：`mode_templates` 检查 `templates/pipeline_mode_*.md` 是否齐备（`missing` 非空就别开跑——模板缺席
  会让流水线 meta-prompt 拿不到正文）。
- **环的每个 step 选哪个 mode**：`loop_create` 的 `steps` 数组每一项都必须是 7 种合法 mode 之一；`mode_list` 是
  "合法 mode 全集 + 每种 mode 的门禁/禁用工具"的权威来源，自定义 `steps` 时照它挑。

## 怎么调

> 参数名 = schema 真名，不是杜撰。`loop_*` 三件套有状态（进程内 `LoopRegistry`），`mode_*` 两件套纯计算只读。

### A. 组合环 loop_create / loop_tick / loop_status

**`loop_create`** — 必填 `name`；`preset` 与 `steps` **二选一**（提供 `preset` 则覆盖 `steps`）：

| 参数 | 必填 | 默认 | 说明 |
|---|---|---|---|
| `name` | ✅ | — | 组合环唯一名称；重名直接报 `loop already exists: <name>` |
| `preset` | — | — | 预设环名：`fix-iterate` \| `build-verify` \| `full-iterate`（schema 点名 3 个）；提供则**覆盖 `steps`** |
| `steps` | — | — | step mode 数组，每项必须是 7 种合法 mode 之一：`advance`/`polish`/`verify`/`bugfind`/`fix_and_merge`/`tidy`/`explore`；与 `preset` 二选一，都缺报 `either steps or preset is required` |
| `max_rounds` | — | `5` | 硬上限轮数（安全网）；走 `get_int` 的 Int32 域饱和守卫（BUG-194：`1e300` 不被静默吞成 Int max） |
| `stop_on_goal` | — | `true` | 健康度 `healthy` + 零 `blocked_tasks` 即停（`goal_reached`） |
| `stop_on_exceeded` | — | `true` | `test_count` ↑10% 或 `open_bug` ↓50%（相对 baseline）即停（`exceeded`） |
| `baseline_test_count` | — | `0` | baseline 测试数（`exceeded` 判据基准） |
| `baseline_open_bug_count` | — | `0` | baseline 未关闭 bug 数（`exceeded` 判据基准） |

```
tools/call loop_create
  { "name": "self-iterate", "preset": "full-iterate" }
// 展开 steps = ["advance","bugfind","fix_and_merge","verify"]，max_rounds=5，
// stop_on_goal / stop_on_exceeded 均 true
// 返回 PipelineLoop 完整 JSON（loop_to_json）
```

```
tools/call loop_create
  { "name": "scan-fix", "steps": ["bugfind","fix_and_merge","verify"],
    "max_rounds": 8, "baseline_open_bug_count": 12, "stop_on_exceeded": true }
// 返回 PipelineLoop 完整 JSON
```

**`loop_tick`** — 必填 `name`；其余为"当前读数"（执行完 `next_mode` 后回灌下一拍）：

| 参数 | 必填 | 默认 | 说明 |
|---|---|---|---|
| `name` | ✅ | — | 已注册环名称；查不到报 `loop not found: <name>` |
| `project_health_grade` | — | `""` | 当前项目健康度：`healthy`/`attention`/`stalled`（`goal_reached` 需为 `healthy`） |
| `blocked_tasks` | — | `0` | 当前 blocked 任务数（`goal_reached` 需为 0） |
| `current_test_count` | — | `0` | 当前测试数（`exceeded` 判据：相对 baseline ↑10%+） |
| `current_open_bug_count` | — | `0` | 当前未关闭 bug 数（`exceeded` 判据：相对 baseline ↓50%+） |

返回 `LoopTickResult`：`next_mode` / `next_step_idx` / `next_round` / `should_stop` / `stop_reason` / `history` / `loop_after`。
**`next_mode` 是"下一步"要跑的 mode**（`steps[(current_idx+1)%len]`，BUG-144），不是"刚完成"那一步。

```
tools/call loop_tick
  { "name": "self-iterate", "project_health_grade": "healthy", "blocked_tasks": 0 }
// 首轮 round=0 一律不判 goal_reached / exceeded（BUG-162，健康度可能是占位值）→ 不停，next_mode 推进
// 跑满一轮后 round=1 再喂 healthy + 0 → should_stop=true, stop_reason="goal_reached: ..."
```

**`loop_status`** — 无 `name` 列出全部已注册环摘要（JSON 数组）；带 `name` 返回单环完整 JSON；查不到报 `loop not found`：

```
tools/call loop_status                              // 无 name → 全部环摘要数组
tools/call loop_status { "name": "self-iterate" }   // 单环完整 JSON
```

### B. 自驱七模式 mode_list / mode_templates

两个都是**无参数**（`schema({}, [])`），纯计算只读。

```
tools/call mode_list
// 返回 7 元素数组，每项 = { mode, name, description, constraints, template_path, forbidden_tools }
```

| `mode` | `name`（展示名） | `constraints` 门禁键 | `forbidden_tools` |
|---|---|---|---|
| `advance` | 持续开发新功能 | 无强制门禁键（默认模式） | — |
| `polish` | 打磨完善（不加新功能） | `forbid_new_features` | `publish` / `publish_parallel` / `dag_publish` |
| `verify` | API 枚举与完备性验证 | `require_api_enum` + `require_doc_check` | — |
| `bugfind` | 寻虫：issue_scan + 边界语料 | `require_issue_scan` + `require_test_corpus` + `require_ocr` | — |
| `fix_and_merge` | 修复 issues + 合并分支 | `require_github_token` | — |
| `tidy` | 项目打扫清整 | `forbid_new_code` | `publish` / `publish_parallel` / `dag_publish` |
| `explore` | 探索：按复杂度自选模式 | `require_complexity_scoring` + `allow_parallel_modes` + `require_disjoint_files` | —（selector，非 worker） |

> `template_path` 统一为 `templates/pipeline_mode_<mode>.md`；`mode_templates` 的名单从 `all_modes()` 反解、**不硬编码**
> （注册表加模式而这里漏检查就是"模板缺席没人报"，BUG-118 同族）。

```
tools/call mode_templates
// 返回
{ "templates": { "advance": true, "polish": true, "verify": true, "bugfind": true,
                 "fix_and_merge": true, "tidy": true, "explore": true }, "missing": [] }
```

## 已知边界

- **loop 是有状态编排层，mode 是纯读执行层**：`loop_*` 的状态落在**进程内 `LoopRegistry`**（`loop_reg`），进程重启即失、
  不落库——跨进程 / 跨会话要重新 `loop_create`；`mode_*` 无状态、纯计算只读，任何时刻可调。
- **`preset` schema 只点名 3 个，`preset_loop` 真接受 5 个**：MCP 的 `loop_create` 描述与 `preset` prop 只写
  `fix-iterate` / `build-verify` / `full-iterate`，但底层 `@ops.preset_loop` 还认 `perf-iterate`
  （`["advance","polish","verify","advance"]`）与 `scan-fix-verify`（`["bugfind","fix_and_merge","verify"]`）两个
  R12-R4 算子扩展预设——传得进去、能展开，只是 schema 没写。
- **`preset` 与 `steps` 二选一，`preset` 优先**：两者都传时 `preset` 覆盖 `steps`；都缺报 `either steps or preset is required`。
  `steps` 每项过 `validate_loop_steps` 校验，出现 7 种合法 mode 之外的值直接拒。
- **`max_rounds` 默认 5，`stop_on_goal` / `stop_on_exceeded` 默认 `true`**：`max_rounds` 走 `get_int` 覆盖默认 5
  （不能直接用其默认 3），复用 Int32 域饱和守卫（BUG-194）；两个 stop 开关缺省都开，想"转满 N 轮再停"要显式
  `stop_on_goal=false, stop_on_exceeded=false`。
- **首轮 round=0 不判 goal_reached / exceeded（BUG-162）**：终止判定 `next_round > 0` 才生效——第一拍喂的
  `project_health_grade` / `current_*_count` 很可能是占位值，所以先把环跑满一整轮（round 0→1）再给真实读数，
  才会触发 `goal_reached` / `exceeded`。
- **`next_mode` 是"下一步"不是"刚完成"（BUG-144）**：`loop_tick` 先算 `next_idx = (current_idx+1)%len` 再取 `steps[next_idx]`，
  返回的是"下一拍该跑哪个 mode"，server 层拿它去调 `pipeline_tick(mode=...)`。
- **终止优先级固定**：① `max_rounds` 硬上限（安全网）→ ② `goal_reached`（`healthy` + 零 blocked，`stop_on_goal` 且 round>0）
  → ③ `exceeded`（test ↑10% 或 open_bug ↓50% 相对 baseline，`stop_on_exceeded` 且 round>0）。上限优先，goal/exceeded 次之。
- **`explore` 是唯一不亲自开发的模式（selector）**：先给目标复杂度打分（0..5，复用难度单一抽取来源），再从其余 6 个单模式里
  **自选**一个去跑；它本身不产代码。
- **并行多模式的硬前提 = 文件作用域两两不相交**：只有每个候选模式都申报**非空**文件作用域、且两两不相交
  （`reserve_scope` 预订成功 + 认领前 `conflicts_check` 可认领）才允许并行，否则**退回单模式串行**；
  申报空作用域或作用域重叠都退回串行。
- **`loop_status` 无 `name` 时返回数组、带 `name` 时返回对象**：两种形态不一样，消费方要按"传没传 name"分流解析。

## 环与模式协同

> 一句话：**loop 是编排层——决定"下一步跑哪个 mode、转到第几轮、何时停"；mode 是执行层——决定"这一步做什么、门禁键/禁用工具是什么"。**
> 两层分离：`loop_tick` 只回一个 mode 字符串，不亲自执行；执行交给 `pipeline_tick(mode=...)`（由该 mode 的 meta-prompt 驱动）。

```
① 选模式全集（执行层清单）
   mode_list        → 7 种 mode 完整信息（constraints 门禁键 + forbidden_tools）
   mode_templates   → 预检每个 step 的 meta-prompt 模板齐备（missing 为空才开跑）

② 造环（编排层）：steps 每一项都是 ① 里合法的 mode 之一
   loop_create { "name": "self-iterate", "preset": "full-iterate" }
   // 或自定义 steps，把"开发→寻虫→修复合并→验证"串成一个闭环

③ 逐拍推进（编排层回 mode，执行层跑 mode）
   loop_tick { "name": "self-iterate", "project_health_grade": "...", ... }
     → next_mode="bugfind"（下一步该跑哪个 mode）
     → pipeline_tick(mode="bugfind")（server 层拿 next_mode 去执行该 mode 的 meta-prompt）
   每拍把执行后的真实读数（健康度 / blocked / test 数 / open bug 数）回灌给下一拍 loop_tick

④ 自动停（编排层判据）
   loop_tick → should_stop=true
      max_rounds_hit：转满 max_rounds 轮（安全网）
      goal_reached：healthy + 零 blocked（stop_on_goal，round>0）
      exceeded：test ↑10% 或 open_bug ↓50%（stop_on_exceeded，round>0）
   loop_status 收尾确认环停在第几轮、为什么停
```

**为什么这样分两层**：

- **编排层（loop）只关心顺序与终止**——不感知某个 mode 内部跑什么，所以 `PipelineMode` enum 零改动、加 mode 不用改编排代码；
  环的 `steps` 就是"一串 mode 名字"，换个 mode 组合就是另一条流水线。
- **执行层（mode）只关心单步做什么**——7 种 mode 各有 `constraints` 门禁键与 `forbidden_tools`，`explore` 还能自选子模式；
  它不感知自己在哪一环、第几轮，所以同一个 mode 既能单独跑、也能被 loop 串起来跑。
- **两层用 `next_mode` 一个字符串解耦**：loop 不 import mode 的实现，mode 不知道自己在环里。
  这就是 `ops_loop.mbt` 文件头那句"编排层 vs 执行层分离：loop_tick 返回下一步 mode 字符串，server 层用它调 `pipeline_tick(mode=...)`"的落点。

**explore 在环里的位置**：`explore` 是 selector 不是 worker——若把它放进 `steps`，它那一拍会先量复杂度（0..5）再自选一个单模式
去跑（等价于环里临时插一个"分支决策"）；要多个 mode 并行时仍受"文件作用域两两不相交"硬前提约束
（`reserve_scope` + `conflicts_check`），否则退回串行。
