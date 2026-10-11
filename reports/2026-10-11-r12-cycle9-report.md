# FIST-Mbt 四模式流水线自我迭代 · Round 9 汇报

- 轮次：**Round 9**（12 轮完整重复中的第 9 轮）
- 日期：2026-10-11（Asia/Shanghai）/ 2026-10-10（server UTC）
- 组合环：`bugfind-fix-polish-verify-r12`
- 指挥官终审：全部亲自复核
- 状态：**完整闭环**

---

## 结果摘要

| 项 | 结果 |
|---|---|
| bugfind | **5 CONFIRMED 新缺陷**（3 medium + 2 low，**算法/纯函数面**）+ 4 中低/疑似 + 4 观察 |
| fix_and_merge | **5/5 修复**（BUG-205 走「描述修正」降级路径） |
| polish | cl7 / doc_surface / tools_sync / 卫生 全 PASS |
| verify | 指挥官独立复核全过 |
| 全量测试 | **686 / 686 通过**（零新增测试，基线不动） |
| moon check | **0 errors** |
| engine 测试 | 148 / 148 |
| 缺陷账本 | BUG-202~206 入账，**5/5 FIXED**（同一笔小记 `### FIXED(2026-10-10T19:22:43Z / BUG-202, BUG-203, BUG-204, BUG-205, BUG-206)`） |

### 本轮关键结论：**转向算法面后首次挖到真 bug——契约面封口的价值兑现**

Round 8 沉淀「契约面已实质封口」，本轮**转向纯函数/算法/数学/状态机面**（此前未审计），立即挖到 **5 个真实算法正确性缺陷**——这正是前 8 轮扫契约面扫不到的类型。**这证明 Round 8 的判断是对的：不是「没 bug」了，是「那类 bug 修完了」，需要换面。**

### 5 条缺陷（3 medium + 2 low，均我逐条源码 + 数学推演复核）

| BUG | 严重度 | 缺陷 | 修法 |
|---|---|---|---|
| **BUG-202** | medium | **`complexity_assess` 把 UTF-8 字节数当码点数**：L326 `description.to_array().length()` 返回字节，但 L330 注释「码点，中文不按字节虚高」与 L334 basis「码点→+N」都声称码点——**注释与实现相悖**。中文 1 字=3 字节，阈值 `>=200→+1`/`>=600→+2` 系统性高估 1 档，`explore` 模式路由错档 | `let chars = description.length()`（码点） |
| **BUG-203** | medium | **`loop_tick` max_rounds off-by-one**：L195 `next_round > lp.max_rounds`，max_rounds=1 时 round=1 放行、round=2 才停 → **实际跑 2 轮**。作为「硬上限（安全网）」失效一格，无人值守流水线多跑一整轮 | `if next_round >= lp.max_rounds` |
| **BUG-204** | medium | **`dag_mc` `mc_finish` 环重复计数**：L103 环命中 `Some(_) => return dur.get(id)`（返回节点自身 dur），A→B→A 推导 A best=**2·dur[A]+dur[B]**（A 计 2 次）→ MC 完工分布与 criticality 全部失真 | 环命中 `return -1` 哨兵（dur≥0 ⇒ f+own=own-1≤own≤best，环路径不参与 max） |
| **BUG-205** | low | **`circuit_fail` 失败窗口顺延**：L30 `now_secs - last_fail_ts > w` 锚定**最后一次失败**而非窗口起点——失败 t=0/10/59、t=61 再失败时计 4 次（真窗口应为 3），窗口永不真正过期，熔断延迟触发 | **降级路径**：工具描述（server.mbt L3977）+ struct 注释改为准确语义「顺延/连败窗口——距上次失败超 window_secs 即重置计数为 1，否则 +1，非严格滚动时间窗」 |
| **BUG-206** | low | **`plan_revise` 子任务直接 depends_on 根时误判 dep_undone**：L1108 `if id == root_task_id { continue }` 使根不入 cat 桶，L1111 `cat.get(id) is Some(_)` 对依赖根的子任务恒 None → 落入 `_ => dep_undone = true`，即使根已完成 | L1128 `_ => if d == root_task_id { () } else { dep_undone = true }`（根能被 plan_revise 分析即视为已完成依赖） |

### 为什么是算法面

- **D1（字节/码点）是典型「注释与实现相悖」的假绿**：单测用短描述测不出阈值跨档，作者误信注释以为实现按码点走。**只有跨语言读者**（知道 `String::to_array()` 返回 UTF-8 字节数组、`length()` 返回码点数）才看得出。本轮最有价值的一条，且触发面覆盖本项目常态中文任务描述。
- **D2（max_rounds off-by-one）是安全网类缺陷**：`ops_loop_wbtest.mbt` 现有用例只断言 `should_stop` 布尔与 `stop_reason` 含 "max_rounds"，**不断言轮数精确值**，故 off-by-one 从未暴露。
- **D3（dag_mc 环重复计数）是 DAG 递归经典陷阱**：`dag_mc` 测试语料均为无环 DAG，故从未触发。

### BUG-205 的降级决策（指挥官批准）

bugfind 判 D4 为「窗口顺延导致失败计数高估、熔断延迟」中低危。fix 子代理核查后判定**真修复需 `circuit_breakers` 加 `first_fail_ts` 列**（`cb_get` 返回 7 元组 / `cb_save` 写 10 列，`store_sqlite.mbt` L1559-1659；现 schema 仅 `CREATE TABLE IF NOT EXISTS`，无迁移机制）+ 改 `store_sqlite`/`store.mbt`/`engine_circuit` 三处签名 + 影响既有 circuit 测试——**对 LOW bug 不值**。

**决策：走描述修正路径**——把工具描述与注释改为准确语义。理由：①顺延/连败窗口语义对熔断器**可接受甚至有利**（持续故障更快熔断，符合熔断意图）；②严格滚动窗是理论更优，但需迁移成本；③低危 bug 不值得引入 schema 迁移风险。**真滚动窗单独立任务**（如后续轮次需要）。

**插曲**：首版描述里写了 Markdown 粗体 `**顺延/连败窗口**`，MoonBit 把字符串字面量内的 `**` 当插值/前缀解析 → `moon test` 编译失败 `Error: [3002]` server.mbt:3977:225、exit 1。已去掉 `**` 纯文本化，编译恢复。**这是 MoonBit 的一个实坑：工具描述字符串里禁写 `**` 等 Markdown 标记**——值得沉淀。

---

## 资源消耗

| 资源 | 说明 |
|---|---|
| 子代理 1 | bugfind：算法/纯函数面（src/router + src/engine 算法 + src/ops 状态机），全程只读 |
| 子代理 2 | fix_and_merge：5/5 修复 + 收口判据 |
| 指挥官 | 逐条源码核实 5 条 CONFIRMED（读 ops_modes L326 / ops_loop L195 / dag_mc L102-103 / circuit L30 / plan_revise L1108/L1111）+ 独立复跑全量判据 + 12 锚点回归 grep + 复核 score~ 回归锚点（子代理误报漏检，我独立确认 L3159/3211/3272/3289 全在位） |
| 全量 `moon test --target js` | 686 测试 |
| `moon check` | 33 tasks, 0 errors |
| 未用 | issue_scan、moon build、live MCP 实调 |

---

## 任务分配记录

| 环节 | 承担者 | 交付 |
|---|---|---|
| bugfind | 子代理（只读） | 3 CONFIRMED + 4 中低/疑似 + 4 观察 + 11 回归锚点确认 |
| 指挥官核实 | 指挥官 | 逐条读源码核实 5 条 CONFIRMED，2 条从 疑似 升级（D4/D5） |
| fix_and_merge | 子代理 | 5/5 修复（4 处算法 + 1 处描述修正） |
| polish | 子代理 + 指挥官复核 | cl7 / doc_surface / tools_sync / 卫生 全 PASS |
| verify | 指挥官 | 独立复跑全量 + 逐条读源码核实 + 12 锚点回归 grep |
| 终审 | 指挥官 | 5/5 核实 + BUG-205 降级决策 + 独立复跑判据 + 回归确认 |
| 记忆/汇报 | 指挥官 | memory/2026-10-11.md + 本汇报 |

---

## 遗留风险

1. **BUG-205 真滚动窗未修**：仅文档化准确语义，实现仍是顺延/连败窗口。**需 `circuit_breakers` 加 `first_fail_ts` 列 + 迁移机制**才能真修，建议单独立任务。当前语义对熔断器可接受。
2. **BUG-204 未新增测试**：`engine_dag_mc.mbt` 与 `dag_mc_test.mbt` 当前 ` M`（并发 WIP），子代理只 edit 了 L106 那一行、未新增测试以防冲突。**环路径无回归锁**——若后续轮次要锁，需在无并发时补一条 A→B→A 用例。
3. **BUG-202/203 未新增测试**：现有测试恰好不断言（短描述不跨阈值 / 只断言 should_stop 不查轮数），故行为锁定靠现有测试的「反向绿」。若需正锁，建议补「67 码点中文 vs 67 ASCII 同分」「max_rounds=1 只跑 1 轮」两条。
4. **engine_dag_mc.mbt 并发 WIP**：git status 显示 ` M`，fix 子代理确认其 WIP diff 只含 BUG-182 文档注释（L129-130），L103 环分支未被并发改动；但**后续轮次仍须每轮 grep 确认**。
5. **未覆盖面**（算法面本轮未深扫）：`src/store`（SQL 后端）、`src/evolve`（Jaccard/tokens）、`src/executor`（cli_argv）、`src/server`（各 MCP 工具接线）。**Round 10 可转向这些面**或深扫算法面剩余区。
6. **MCP server 为过期二进制**（PID 34528）：所有判定基于源码 + 单元测试。
7. 既知债务：omega_strong fmt debt / engine_dag_ext L859-866 doc 缺 rejected（4 轮遗留）/ Cycle 4 丢失 ~45 行 WIP / server.mbt 文末多余空行 / board_ascii_test fmt。BUG-142 仍 OPEN。
8. **MoonBit 工具描述字符串禁写 `**`**（本轮插曲）：任何工具描述/注释字符串里出现 Markdown 粗体 `**` 会被 MoonBit 当插值解析导致编译失败。沉淀到 memory。

---

## 后续建议

1. **Round 10 继续算法面深扫**：本轮只扫了 src/router + src/engine 部分 + src/ops。剩余：`src/store`（SQL 后端，事务/索引/隔离）、`src/evolve`（Jaccard 计算、token 切分）、`src/executor`（cli_argv 安全）、src/engine 剩余算法（cost_budget_split 背包、audit_permission 权限、hats rate）。
2. **补 3 条算法回归锁**（无并发时）：BUG-202 字节/码点对比锁、BUG-203 max_rounds=1 单轮锁、BUG-204 A→B→A 环锁。这是本轮 5 条修复的「正锁」，比现有测试的「反向绿」更可靠。
3. **BUG-205 真窗口单独立任务**：若确需严格滚动时间窗，做 circuit_breakers 加列迁移。
4. **沉淀 MoonBit 字符串 `**` 陷阱**到 memory：工具描述/注释字符串里写 Markdown 粗体会编译失败。
5. **重启 MCP server**（PID 34528 过期）后做 live 回归：`mode_list` / `loop_create` / `loop_tick` / `dag_mc` 成环输入 / `circuit_fail` 顺延窗口。**本轮不做**（纪律）。
6. **每轮终审必须独立重跑** `moon test` + `moon check` + `check_plugin_sync`，不靠 fix 子代理自述。

---

## 超额内容

- **算法面转向的验证价值**：前 8 轮集中在 schema/契约面（Round 6 命中参数丢弃族、Round 7/8 全量扫零命中），一度让 bugfind 看似「无病可寻」。Round 8 明确转向算法面，Round 9 立即命中 5 条真实算法正确性 bug——**包括 1 条「注释与实现相悖」的假绿（BUG-202）**，这种缺陷只在换到「读实现 + 读注释 + 跨语言知识」的视角才看得见。**审计质量的关键不是覆盖同一面多轮，而是换面**。
- **D1（BUG-202）是典型「单测假绿」**：作者误信注释「码点」，用短描述测试，永远测不出阈值跨档。**注释与实现相悖是最危险的假绿来源**——因为注释本身就是"作者以为的实现"，单测以注释为期望就永远绿。本轮 bugfind 子代理特别指出「只有跨语言读者（知道 `to_array()` 返回字节）才看得出」——这是跨语言视角的独特价值。
- **BUG-203 是「安全网缺陷」**：max_rounds 是无人值守流水线的硬上限安全网，off-by-one 让它失效一格。单测只断言布尔不查轮数精确值——**布尔断言掩盖数值 off-by-one**，是单测覆盖盲区。
- **BUG-204 的修复论证**：选 `-1` 哨兵而非 `Int.MIN_VALUE`（与 own 相加溢出）或 `Option`（改动签名过重）。**「dur≥0 ⇒ f+own=own-1≤own≤best，环路径不可能胜出」是正确性论证**，且 `visiting.remove(id); memo.set(id, best)` 仍以非环 best 落 memo，哨兵不污染 memo——**哨兵的选择要论证为什么它不会污染后续状态**，不只是「返回一个怪值」。
- **BUG-205 的降级决策**：这是**指挥官级判断**——真修需 schema 迁移（加列 + 双后端改签名 + 影响既有测试），对 LOW bug 不值。**降级为文档化准确语义**，并诚实标注「真滚动窗单独立任务」。**不是每个 bug 都值得最大成本修复**，分级处置是成本意识。
- **~~MoonBit `**` 陷阱~~（Round 10 已更正——本条结论错误，勿沿用）**：工具描述字符串里写 Markdown 粗体 `**` 会被 MoonBit 当插值/前缀解析 → 编译失败。**这是本项目专属实坑**（因为工具描述是中文 Markdown 风格），值得沉淀到 memory，防止后续轮次重复踩。**⚠ Round 10 核实此主张错误**：`src/server/server.mbt` **60 行含 `**`**（含多个工具描述字符串，如 L296 `audit_log`）且项目编译通过（moon check 0 errors、686/686）——**`**` 不阻编译**。Round 9 的 `Error: [3002]` server.mbt:3977:225 真实原因不是 `**`，是 fix 子代理当时的编辑在别处引入真正语法/插值问题，把移除 `**` 与编译恢复的时间点**误归因**了。**教训：子代理的因果归因不可盲信，须验证其普遍性（本仓 60 处反例可证伪）；指挥官终审不能只验证"现在绿了"，还要验证"归因是否成立"。**

---

## 来源

- 缺陷清单：`memory/bugs.md`（BUG-202~206，5/5 FIXED）
- 修复落点：`src/ops/ops_modes.mbt` L328 / `src/ops/ops_loop.mbt` L197 / `src/engine/engine_dag_mc.mbt` L106 / `src/engine/engine_circuit.mbt` doc + `src/server/server.mbt` L3977 / `src/engine/engine_dag_ext.mbt` L1128
- bugfind 子代理回传（3 CONFIRMED + 4 疑似 + 4 观察 + 11 回归锚点 + 未覆盖面）
- fix_and_merge 子代理回传（5/5 修复证据 + 收口读数 + 回归锚点 + BUG-205 降级理由 + `**` 插曲）
- 指挥官终审：读源码 ops_modes L326/L328 / ops_loop L195/L197 / dag_mc L102-106/L112 / circuit L30 / plan_revise L1108/L1111/L1125/L1128 + 独立复跑全量判据 + 12 锚点回归 grep + score~ 锚点独立确认（子代理误报漏检，实际 L3159/3211/3272/3289 全在位）
