# FIST-Mbt · R12 遗留处置（followup-2 · leftovers）

- **日期**：2026-10-11
- **驱动**：`advance`（按指挥官「解决遗留」）
- **范围**：仅动我名下的文件（temp/、新守卫脚本）；**未触碰并发 WIP 的任何 ` M` 文件**

> **追加（终审时点 09:00）**：①发现并诊断了 `scripts/gen_plugins.py` L245 的 Python 3.11 SyntaxError（详见第五节）——**并发 agent 在我诊断期间自己修好了**（与我打算的修法逐字一致：提列表推导出 f-string + 修正则 `r"\{\{...\}\}"`）；②账本已从 217 条推进到 **BUG-1~220 共 219 条、0 待修**（并发 agent 收口）；③守卫族全 5 项 **PASS**。

## 结果摘要

R12 收口后我列的四项遗留，本轮处置结果：

| 遗留项 | 处置 | 结果 |
|---|---|---|
| temp/ 本次验证残留 | 清理 | ✅ 全清（live_regress_*、cli.js.bak-*、lr_cost_budget.py） |
| 守卫仅首发 severity | 扩 status（散文形） | ✅ 双形式自证通过 |
| BUG-205 / BUG-142 仍 OPEN | 核实：**账本已是 FIXED** | ✅ 已由并发 agent 处理（我此前报告过期） |
| 并发 WIP 收敛后重建 server | 判定不在并发中重建 | ✅ 文档化建议 |

## 一 · temp/ 清理

删除：`temp/live_regress_r12.db`(+shm/wal)、`temp/live_regress_r12.py`、`temp/cli.js.bak-20261011-0815`、`temp/lr_cost_budget.py`。

**清理前先验证无持有者**：扫描 node 进程是否仍持有临时库——唯一命中的 PID 29768 是**我自己 shell 进程**（正则自匹配到命令文本里的 `live_regress`），非真持有者。删除成功，校验 `[OK] 全部清理干净`。

## 二 · 守卫扩 status（散文形）

**发现**：`bug_mark_status` 的工具描述**不像** `report_bug.severity` 那样把 enum 值写在参数子句里，而是写在正文散文「状态闭集 = OPEN/FIXED/DUPLICATE/FALSE_POSITIVE」，参数子句只写 `status(必填，FIXED 会被拒)` 不带列表——**只盯参数子句会漏掉这一面**。

**改进**：`ENUM_REGISTRY` 第 6 列（值列表子句正则）从「只认 `参数(可选 …)`」泛化为「两种形共用同一逻辑：正则抓值串 → 按 `/` 切 → 逐值比对闭集」。新增条目：

| 工具.参数 | 闭集函数 | 子句形式 |
|---|---|---|
| `report_bug.severity` | `bugreport.mbt::bug_severities` | 参数子句 `severity(可选 …)` |
| `bug_mark_status.status` | `bugreport.mbt::bug_status_closed` | 散文形 `状态闭集 = …`（值串截止到括号/句末，避免把「（真源 memory/bugs.md…）」说明词带进来） |

**selftest 扩到两格**（不只 severity）：
- 第一格：severity 子句形——合成 `severity(可选 open/…)` 必红 ✓
- **第二格（新增）**：status 散文形——合成 `状态闭集 = OPEN/FIXED/CLOSED` 必红，抓住 `bug_mark_status.status 描述列了闭集外的值 CLOSED` ✓
- 干净输入（当前描述）不误红 ✓；闭集解析不到自拒 exit 2 保持 ✓

结果：`PASS 描述侧 enum 同步`（exit 0）+ 双格 `SELFTEST OK`（exit 0）。selftest 临时文件自清理（temp/ 无残留）。

**后续可扩**：`mode`（PipelineMode，但 `ops_modes.mbt` 是并发 WIP，待稳定后登记）；`verdict`（omega，描述用「approve 通过 / 其它值视为打回」非闭集枚举，登记价值低）。

## 三 · BUG-205 / BUG-142 核实（此前报告过期）

我上一份 followup 报告写「BUG-205 / BUG-142 仍 OPEN」——**这是过期记忆**。live `bug_list` 核实：

- **BUG-205 [low] FIXED**（小记 2026-10-10T19:22:43Z，与 BUG-202/203/204/206 同笔）。真源 `engine_circuit.mbt` L8-9 已如实注释：**「不是严格的滚动时间窗计数（实现只持久化 last_fail_ts，无 first_fail_ts，故窗口起点取'上次失败'）」**——这是 R11 的降级决策（文档化准确语义），未做加列迁移。**结论：按 R11 决策保持文档化，符合终态**；若要真滚动窗（first_fail_ts 列 + 迁移），仍是独立任务，且 `engine_circuit.mbt` 是并发 WIP，本轮不碰。
- **BUG-142 [high] FIXED**（小记 2026-10-10T23:38:31Z，evidence 落下一行）。真源：commit 3fbda56 新增 `check_moon_test_summary`/`stdout` 自动解析「Total tests」汇总行 + `ov_parse_int` 解析器；key 名含 `moon_test` 时 `failed>0` 或缺汇总行一律 fail，**不信 exit 0**；新增测试 ov_17~ov_20（20/20）；全量 690/690。**这正是我一直采用的口径**（以 `Total tests: N, passed: N, failed: 0` 汇总行为准），修复是真实而非标题翻转。

`open_with_linked_done=0`（bug_list）——无「账本说没修、任务库说修完了」的矛盾。

## 四 · server 重建（并发中不重建）

**陈旧度实测**：cli.js 构建 10-11 08:18，源码 LastWrite——
- 覆盖 ✓：server.mbt 04:40 / cost_tool.mbt 04:15 / omega_tool.mbt 04:15 / engine_circuit.mbt 03:18 / store_sqlite.mbt 03:42 / ops_modes.mbt 03:14
- **落后**：`src/router/model_router.mbt` 08:37（**并发 agent 刚改，即 BUG-217/218 类 overflow 修复**）

当前 server PID 41248 仍活、跑我 08:18 的构建（已含 BUG-211~214 修复）。**唯一落后项是 model_router.mbt 的并发 WIP**——该文件仍在被并发 agent 编辑，现在重建会捕获**半成品**（可能语义不完整），且并发 agent 继续改会让 server 再落后。

**决定：不在并发中重建**。建议：等 `model_router.mbt` 的 overflow 修复稳定后（并发 agent 完成或账本把它标 FIXED），一次 `moon build --target js` + `patch_esm_main.py` + 重启，让 server 覆盖最新修复。**这是并发协调问题，不是我能安全解决的范围。**

## 五 · 顺带发现：`scripts/gen_plugins.py` L245 Python 3.11 SyntaxError

复跑守卫族时 cl7 FAIL，追查发现 **`gen_plugins.py`（cl7 生成器，已提交的稳定码，`git status` 干净）在默认 `python`(3.11.8) 下整模块编译失败**：

```
SyntaxError: f-string expression part cannot include a backslash
```

**根因（L245 双 bug）**——原码：
```python
die(f"正文残留未替换占位符：{[s for s in re.findall(r'\\{\\{[A-Z_]+\\}\\}', out)]}")
```
1. **Python 3.12 前 f-string 表达式不允许反斜杠**：列表推导里嵌的 `r'\\{...}'` 触发 SyntaxError ⇒ 本仓默认 `python`(3.11.8) 连解析都过不去，cl7 生成器整体不可用（换 `python3`(3.13.14) 才能编译，属隐式换栈掩盖）。
2. **正则双重转义**：`r'\\{` 匹配的是「反斜杠+`{`」，**根本匹配不到占位符 `{{VAR}}`**（实测 `re.findall(r'\\{\\{[A-Z_]+\\}\\}', '{{FOO}}')` → `[]`，正确 `r'\{\{[A-Z_]+\}\}'` → `['{{FOO}}']`）⇒ 残留了也查不出（假绿）。

**处置**：我在诊断期间，**并发 agent 自己提交了修复**（L245 现为 `remaining = re.findall(r"\{\{[A-Z_]+\}\}", out)` + `die(f"正文残留未替换占位符：{remaining}")`）——与我打算的修法**逐字一致**。验证：默认 python 3.11 编译通过 ✓、gen_plugins 跑通、cl7 PASS。

**教训**：①**Python 版本敏感**——f-string 语法 3.12 前收窄，脚本要跨版本就得避免在 f-string 表达式里嵌含反斜杠的推导；②**判据自身的正则也要自证**（此处 `\\{` 双重转义让整格守卫失效，属「判据失灵而不自知」；`check_plugin_sync` 是唯一会「子进程重跑生成器」的守卫，所以它先红了出来，其余守卫看不到这一格）。

## 证据（本轮）

- `check_desc_enum_sync.py` 正常：`PASS 描述侧 enum 同步`（exit 0）
- `check_desc_enum_sync.py --selftest`：双格 `SELFTEST OK`（exit 0）
- `bug_list`：count=217，`open_with_linked_done=0`
- `git status`：并发 WIP 21 个文件 ` M`（server.mbt/cost_tool.mbt/omega_tool.mbt/engine_circuit.mbt/store_sqlite.mbt/model_router.mbt/ops_modes.mbt 等）——**均未触碰**
- temp/ 清理校验：`[OK] 全部清理干净`

## 遗留风险（本轮收敛后所剩）

1. **model_router.mbt 的 overflow 修复**（BUG-217/218 类）仍在并发 WIP；server 落后于它，待稳定后重建。**这是唯一真正的遗留**。
2. **BUG-205 真滚动窗**：按 R11 决策保持文档化（engine_circuit.mbt L8-9 已如实注释）；要升级需 `first_fail_ts` 列迁移，独立任务。
3. **守卫可再扩**：`mode`（待 ops_modes.mbt 稳定）；`verdict`（非闭集枚举，登记价值低，可不做）。
4. **并发 WIP 未合并**：21 个文件 ` M` 是并发 agent 的工作，我未触碰；它们合并/稳定后需重跑 gen_plugins（cl7）+ 重建 server。

## 来源

- 守卫源码：`scripts/check_desc_enum_sync.py`（ENUM_REGISTRY 扩 status、selftest 扩第二格）
- 闭集真源：`src/server/bugreport.mbt`（L454 `bug_status_closed`、L14-20 `bug_severities`）
- BUG-205 真源：`src/engine/engine_circuit.mbt` L8-9（文档化准确语义注释）
- BUG-142 真源：`memory/bugs.md` BUG-142 FIXED 小记（commit 3fbda56，moon_test 汇总行解析）
- 账本：`memory/bugs.md`（BUG-1~217 共 217 条，`open_with_linked_done=0`）
- 构建陈旧度：cli.js LastWrite 08:18 vs 各源码 LastWrite