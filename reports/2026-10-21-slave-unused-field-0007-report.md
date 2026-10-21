# 副机报告 · 0007 unused_field 清零（T0r36 / BUG-379）

- 日期：2026-10-21
- 分支：`slave/fix/unused-field-0007`（基点 `9f348f0`，强制 `slave/` 前缀）
- 任务：T0r36
- 台账：BUG-379（FIXED）
- 交付面：`src/server/server.mbt`、`src/server/debate_tools_wbtest.mbt`（2 文件 −4 行）

## 结果摘要

1. **0007 全族清零**：`moon check --target js` 的 `0007 unused_field` 从 **2 条 → 0 条**，总 warning **517 → 515**，errors 仍为 0。
2. **删除两个只写不读的私有字段**：`DebateSession.topic` / `hats` 只有 convene 写入、没有任何读点；同步删掉只为喂字段而存的 `hat_ids` 绑定。
3. **测试零回归**：`moon test --target js` 保持 **1340 / 1340 / 0**。
4. **公开接口零变化**：`DebateSession` 是 `priv struct`，`.mbti` 不记录，删除不外溢。

## 证据（真实读数）

| 项 | 命令 / 判据 | 读数 | 证据文件 |
|---|---|---|---|
| warning 面（改前） | `moon check --target js` | 517 warnings / 0 errors；0007 = 2 | `temp/t35_check_full.log` |
| warning 面（改后） | `moon check --target js` | **515 warnings / 0 errors**；0007 = 0 | `temp/t36_check_full.log` |
| 分族分布（改后） | `grep -oE 'Warning \[[0-9]+\]'` | 0020 473 / 0006 12 / 0002 11 / 0001 10 / 0009 3 / 0078 3 / 0023 2 / 0027 1 | `temp/t36_check_full.log` |
| 测试面 | `moon test --target js` | `Total tests: 1340, passed: 1340, failed: 0` | `temp/t36_test_full.log` |
| 格式面 | `moonfmt.exe` 逐份比对（CR 归一） | 2 份全 FMT-OK | 会话输出 |
| 守卫电池 | `run_guards.py` | 38 格 / 失败 5 / SKIP 5 / 缺执行面的尺 0（与改前逐格相同） | `temp/t36_battery.log` |

### 预存红（本单未引入、未代修）

| 守卫 | rc | 成因 |
|---|---|---|
| `check_scripts_index.py` | 1 | 6 个脚本未在 `scripts/README.md` 登记 |
| `check_exit_code_contract.py --selftest` | 2 | 判据自检 4 格不通过（天花板常量 16 vs 现读 0；三支校准脚本仍为串式退出） |
| `check_plugin_sync.py` | 1 | 下游 `gen_plugins` 被账本重复编号挡住 |
| `gen_plugins.py --check` | 2 | 账本 5 组重复编号（BUG-183/192/328/329/330 各×2） |
| `check_plan_landing.py --gate` | 1 | 历史计划面文档缺失/移动超上限 |

## 分析

- **为什么是「写入即遗忘」**：`debate_convene` 把 topic 和 hat_ids 存进会话，但 `debate_register` / `debate_verdict` 只用 `verdicts` 与 `threshold`，`created_at` 另有回显。两个字段没有任何读点，属于纯粹的历史残留，而不是「暂时没人用」。
- **为什么必须同批删 `hat_ids`**：它是 `parsed.map(fn(h) { @ops.hat_id(h) })` 的产物，唯一用途就是喂 `hats` 字段；只删字段会把它变成新的 0002。逐族对照里 0002 仍为 11，证明这个连带关系被处理干净了。
- **为什么第一版 check 红在 4091**：白盒测试里还有第二处 `DebateSession` 构造（`debate_tools_wbtest.mbt:104` 的侧写用例），grep 按 `DebateSession` 抓构造点时漏掉了这条匿名记录。编译器一次性列出 2 条 `fields not defined`，补齐后转绿——这条经历写进日志，提示后续同族清理以编译器枚举为准。

## 资源消耗

- 模型：本地副机 agent（无外部计费）；成本 0。
- 本单 token 估算：输入约 4.5 万 / 输出约 0.7 万。
- 本单耗时：约 9 分钟（含一次 2 errors 的构造点补齐与两次全量 check）。

## 任务分配记录

- T0r36：`publish --created-by human_steward` → `claim --assignee slave-agent` → 实现与验证 → `execute`（读数入 deliverable）→ `submit` → `verify --verifier commander`。
- 无二次分包；未触碰不可逆操作。

## 遗留风险

1. **515 条 warning 仍在**：`deprecated` 473 条以 `Json::value` 为主，按 BUG-356 属 owner 决策项；本单只清 0007。
2. **5 条预存红未动**（见上表），每条都需要单独单元；账本重复编号是 `gen_plugins` / `check_plugin_sync` 转绿的前置。
3. **会话调试信息变少**：`topic`/`hats` 删除后，从进程内会话表已看不到这两项；它们仍完整出现在 `debate_convene` 的回执里。若未来需要 `debate_status` 类查询，应在设计时重新引入字段并同时给出读点，而不是先存后忘。
4. **`.mbti` 抖动会复现**（BUG-330）：每次 `moon check`/`moon test` 都会重写，需继续按 `git restore -- '*.mbti'` 处理。

## 后续建议

1. 下一顺位：`0001 unused function` 10 条中的测试辅助函数（`mc_top_crit` 等）可先清，产品代码部分按金条四先出方案。
2. `0009 struct_never_constructed` 3 条是 `pub struct` 面（constraint 包），删除会改公开接口，须先确认无外部消费者。
3. `0078 result_error_return` 3 条是 `server.mbt` 的三个公开工具处理器，改 `raise` 会动签名与调用面，建议单独立项评估。

## 超额内容

- 把「grep 构造点 vs 编译器枚举」的差异写进报告与日志：本单第一版漏掉白盒匿名记录，正是后续同族清理最容易复发的失误。
- 复跑完整电池并逐格对比，确认本单没有把任何 SKIP 变成 FAIL、也没有让预存红的读数漂移。

## 来源

- 台账：`memory/bugs.md` BUG-379
- 日志：`memory/2026-10-21.md` R54 段
- 证据：`temp/t36_check_full.log`、`temp/t36_test_full.log`、`temp/t36_battery.log`、基线 `temp/t35_check_full.log`
- 提交面：待本单 commit（`slave/fix/unused-field-0007`），推送 gitcode 后由 owner 开 MR
