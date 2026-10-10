# task_triage 的 skill 路由增强（improvement-plan 20261010 §5.2-4）

> 目标：把 `task_triage` 从"只按能力关键词(want)排序"升级为"额外按 **skill 命中度** 排序"，
> 并在 `suggestion` 里按 **SKILL→MODE 建议表** 给出一条建议的开发模式。
> 落点：`src/engine/engine_triage.mbt`（引擎）、`src/engine/engine_triage_skill_test.mbt`（测试）、
> `src/server/server.mbt`（MCP 工具注册，仅加一个可选参数）。

## 一、为什么加 skill 路由

`task_triage` 已有的 `want` 只做**能力标签**路由（"这个 agent 擅长啥就先领啥"），它是**执行者视角**。
`skill` 是**开发方法论视角**：任务描述里若提到"tdd""系统化调试""code-review"，说明这一单适合用
"测试驱动 / 寻虫 / 验证"那类模式去跑。把 skill 库变成排序信号 + 模式建议，让"下一单该用什么模式"也一并给出，
`agent` 无需自己再猜一次。

两条路由正交且都不强控：`want` 是"谁能干"，`skill` 是"该怎么干"。

## 二、接口契约

```
task_triage(
  namespace : String (可选，空=全部),
  agent     : String (可选，默认 "self"),
  want      : String (可选，能力关键词),
  skill     : String (可选，逗号分隔 skill 关键词；空串=不做 skill 路由 零回归),
) -> {
  count, ns, agent, want, skill,
  tasks: [ { id, ns, priority, importance, difficulty, depth, desc, depends_on, skill_hits } ],
  suggestion?: { task_id, ns, reason, skill, mode },
}
```

- 顶层恒带 `skill`（回显本次传入的 skill 串）。
- 每个 `tasks` 行**恒带** `skill_hits`：`Array[String]`，命中 skill 的关键词（原样大小写）；`skill=""` 时为空数组。
- `suggestion` **恒带** `skill`（命中的关键词，无命中为空串）与 `mode`（SKILL→MODE 建议表给出的模式，无命中为空串）。

## 三、排序位置

```
能力匹配(want)  →  skill 命中度(skill 非空时)  →  优先级 → 重要度 → 深度 → id
```

- `want` 与 `skill` 都命中的，排在两者都未命中的之前。
- `skill` 命中度用**命中关键词个数**（`skill_hits.length()`）比较，多的在前；个数相同再按第一个命中关键词字典序（稳定、可复现）。
- **`skill=""` 时完全不进入排序分支**，排序与输出与旧版逐字一致（零回归锁）。

## 四、skill_hit 纯计算

`skill_hit(desc, keys) -> (Int, Array[String])`：对每个 key 做**大小写不敏感的子串匹配**
（key 与 desc 都 lowercase 后 `contains`），返回命中条数与命中的原样关键词列表。

- 关键词由 `skill` 按逗号切开、trim、去空得到。
- **不做分词**：关键词可能含 `-`（如 `grill-me`、`test-driven-development`），分词会拆断匹配。

## 五、SKILL→MODE 建议表（只匹配关键词前缀）

| skill 关键词（前缀） | 建议 mode |
|---|---|
| `tdd` / `test-driven-development` | `fix_and_merge` |
| `systematic-debugging` / `debugging` | `bugfind` |
| `requesting-code-review` / `code-review` | `verify` |
| `subagent-driven-development` | `advance` |
| `spike` / `explore` | `explore` |
| `plan` | `advance` |
| `research-paper-writing` | `polish` |
| `ideation` | `explore` |
| `grill-me` | `verify` |
| `superpowers` | `advance` |
| 未命中 | `""`（不给模式） |

匹配语义：把传入关键词 lowercase 后，按上表顺序做 `starts_with(prefix)`，命中即返回该 mode。
未命中返回空串（`suggestion.mode == ""`），调用方据此判断"这条没有模式建议"。

## 六、调用与零回归

- 引擎签名用 MoonBit **可选带标参数**：`triage(..., skill? : String = "")`、`pick_next(..., skill? : String = "")`。
  既有位置调用（如 `engine.triage(ns, agent, want)`、`self.triage(...)`、`e.pick_next(..., "now")`）**不改即用**，默认 `""`。
- 新调用面显式传标：`e.triage("", "agent", "", skill="tdd")` 或 `engine.triage(ns, agent, want, skill~)`。
- MCP 工具注册只**新增**一个 `skill` 的 `string_prop`（可选），handler 里 `get_str(args, "skill")` 后透传给引擎。

## 七、验证

```bash
moon test --target js -p src/engine
moon test --target js -p src/server
moon test --target js        # 全量，以 "Total tests: N, passed: N, failed: 0" 为准（BUG-142：moon test 退出码不可靠）
```

测试覆盖（`src/engine/engine_triage_skill_test.mbt`，黑盒走公开 `triage` API）：

1. **正路径**：发布含 `tdd` 与含 `ideation` 两条任务（同 priority/importance/depth），`skill="tdd"` 时
   tdd 那条排头部、`skill_hits` 含 `"tdd"`、`suggestion.mode == "fix_and_merge"`、顶层 `skill` 回显。
2. **零回归锁**：`skill=""` 与不传 `skill` 排序完全一致；所有行 `skill_hits` 为空数组；`suggestion.mode` 键存在但为空串。
3. **大小写不敏感**：desc 含 `TDD` 而 `skill="tdd"` 仍命中。
4. **不误报**：描述无关时 `skill="grill-me"` 不命中、`mode` 为空；描述真含 `grill-me` 时命中且 `mode == "verify"`。
