# 副机报告 · 0025 黑盒测试包限定清零（T0r33 / BUG-376）

- 日期：2026-10-21
- 分支：`slave/fix/test-unqualified-package-0025`（基点 `fda6b07`，强制 `slave/` 前缀）
- 任务：T0r33
- 台账：BUG-376（FIXED）
- 交付面：5 个黑盒测试文件（engine 2 份 / evidence 1 份 / omega 1 份 / server 1 份），30 处补 `@pkg.` 限定

## 结果摘要

1. **清零一族 warning**：`moon check --target js` 的 `0025 test_unqualified_package` 从 **30 条 → 0 条**，总 warning **555 → 525**，errors 仍为 0。
2. **只动测试面**：5 个 `_test.mbt` 补 `@engine.` / `@evidence.` / `@omega.` / `@server.` 限定；零 `moon.pkg` 改动、零产品代码改动。
3. **零语义改动**：`moon test --target js` 保持 **1340 / 1340 / 0**；所有测试断言与输入一字未改。
4. **格式面收口**：`moon fmt` 在本机仍 ICE，按既有绕法逐件 `moonfmt.exe` 比对；evidence 两处闭包加前缀后越界，按 moonfmt 输出拆行后复验零差异。

## 证据（真实读数）

| 项 | 命令 / 判据 | 读数 | 证据文件 |
|---|---|---|---|
| warning 面（改前） | `moon check --target js` | 555 warnings / 0 errors；0025 = 30 | `temp/t32_check_full.log` |
| warning 面（改后） | `moon check --target js` | **525 warnings / 0 errors**；0025 = 0 | `temp/t33_check_final.log` |
| 分族分布 | `grep -o 'Warning: \[NNNN\]'` | 0020 473 不变；0025 30→0；0002 14 / 0006 12 / 0001 10 / 0029 3 / 0009 3 / 0078 3 全部逐格不变 | `temp/t33_check_final.log` |
| 测试面 | `moon test --target js` | `Total tests: 1340, passed: 1340, failed: 0` | `temp/t33_test_full.log` |
| 格式面 | `moonfmt.exe <file>` 逐份 CR 归一比对 | 5/5 零差异 | 会话输出 |
| 行尾面 | 字节统计 | 5 份文件 CRLF、bare LF 0 | 会话输出 |
| 守卫电池 | `run_guards.py` | 38 格 / 失败 5 / SKIP 5 / 缺执行面的尺 0（与改前逐格相同） | `temp/t33_battery.log` |

### 预存红（本单未引入、未代修）

| 守卫 | rc | 成因 |
|---|---|---|
| `check_scripts_index.py` | 1 | 6 个脚本未在 `scripts/README.md` 登记 |
| `check_exit_code_contract.py --selftest` | 2 | 判据自检 4 格不通过（天花板常量 16 vs 现读 0；三支校准脚本仍为串式退出） |
| `check_plugin_sync.py` | 1 | 下游 `gen_plugins` 被账本重复编号挡住 |
| `gen_plugins.py --check` | 2 | 账本 5 组重复编号（BUG-183/192/328/329/330 各×2） |
| `check_plan_landing.py --gate` | 1 | 历史计划面文档缺失/移动超上限 |

## 分析

- **为什么补 `@pkg.` 不需要改 `moon.pkg`**：黑盒测试端对自身包有隐式导入（编译器提示里直接给出 `@evidence.Spec` 这类别名），`src/evidence/moon.pkg` 甚至没有 import 块也能解析。限定只是把隐式引用改成显式，不新增依赖。
- **为什么 30 条要分 5 份文件**：0025 的报告单位是「使用点」，每个符号每处引用各报一条；engine 的 `FistEngine` 出现在返回类型与参数类型上（5 处），evidence 的 7 个符号共 21 处，omega / server 各 3 / 1 处。
- **为什么要逐族对比**：只看总数 555→525 无法区分「清掉 30 条 0025」与「清掉 A 族又引入 B 族」。逐格表里 0020 仍 473、其余族一格不动，才能证明这一单是纯减法（BUG-344 定律）。
- **为什么有一份文件 +4/−2**：`let fixer = fn(s : @evidence.Spec) -> String? { Some(...) }` 与 `verifier` 两行加前缀后越过行宽阈值，moonfmt 要求闭包体换行；照输出落盘属纯格式，不是额外改动。

## 资源消耗

- 模型：本地副机 agent（无外部计费）；成本 0。
- 本单 token 估算：输入约 5 万 / 输出约 0.7 万。
- 本单耗时：约 10 分钟（含全量 check / test 与电池复跑）。

## 任务分配记录

- T0r33：`publish --created-by human_steward` → `claim --assignee slave-agent` → 实现与验证 → `execute`（读数入 deliverable）→ `submit` → `verify --verifier commander`。
- 无二次分包；未触碰不可逆操作。

## 遗留风险

1. **525 条 warning 仍在**：其中 `deprecated` 473 条以 `Json::value` 为主，按 BUG-356 属 owner 决策项；本单只清 0025，不宣称「warning 已清零」。
2. **5 条预存红未动**（见上表），每条都需要单独单元。
3. **`.mbti` 抖动会复现**（BUG-330）：每次 `moon check`/`moon test` 都会重写，本单按既有口径全部 restore、未入提交。
4. **本机 `moon fmt` 仍 ICE**（`\\?\` 路径），只能逐件 `moonfmt.exe`；本单改动的 5 份文件已逐份验证。

## 后续建议

1. `unused_value` 与 `unused_constructor` 两族属删除/改名档，按金条四先出方案再动。
2. `deprecated` 473 条仍以 `Json::value` 为主，属 owner 决策项，不自行铺开。
3. 剩余 0001 / 0009 / 0078 等小族可再分单，但应先读族义确认是否含语义改动，不按条数盲吃。

## 超额内容

- 全量重跑了 check / test / 电池三面，并逐族、逐格对比改前改后，确认没有把 SKIP 变 FAIL、也没有让预存红读数漂移。
- 把 0025 的「符号 → 所属包 → 命中文件」对照整理进台账 detail，可作为后续同族迁移的模板。

## 来源

- 台账：`memory/bugs.md` BUG-376
- 日志：`memory/2026-10-21.md` R51 段
- 证据：`temp/t33_check_final.log`、`temp/t33_test_full.log`、`temp/t33_battery.log`、基线 `temp/t32_check_full.log`
- 提交面：待本单 commit（`slave/fix/test-unqualified-package-0025`），推送 gitcode 后由 owner 开 MR
