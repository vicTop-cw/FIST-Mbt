# 副机报告 · 0021/0002 语法小族清零（T0r34 / BUG-377）

- 日期：2026-10-21
- 分支：`slave/fix/syntax-micro-families`（基点 `a9f2372`，强制 `slave/` 前缀）
- 任务：T0r34
- 台账：BUG-377（FIXED）
- 交付面：`src/omega/omega_tool.mbt`、`src/evidence/evidence_test.mbt`、`src/server/ocr_scan.mbt`（3 文件 5 行）

## 结果摘要

1. **两族清零/收敛**：`moon check --target js` 的 `0021 missing_pattern_arguments` 从 **2 条 → 0 条**，`0002 unused_value` 从 **14 条 → 11 条**（吃掉 3 条局部/闭包绑定）；总 warning **525 → 520**，errors 仍为 0。
2. **改动只有 5 行**：两处 `Some(Number(n))` → `Some(Number(n, ..))`；三处未用绑定改 `_` 前缀（`_fname` / `_s` / `_fake_notice`）。零签名位、零 `pub` 面、零语义改动。
3. **测试零回归**：`moon test --target js` 保持 **1340 / 1340 / 0**。
4. **一处试改回退**：`src/router/star_gate.mbt` 的 `derive(Show)`（0027 最后 1 条）剥掉后整包编译红，按预案 `git restore`；该条属既有留档承重面（BUG-351 / R27），本单不碰。

## 证据（真实读数）

| 项 | 命令 / 判据 | 读数 | 证据文件 |
|---|---|---|---|
| warning 面（改前） | `moon check --target js` | 525 warnings / 0 errors；0021 = 2、0002 = 14 | `temp/t33_check_final.log` |
| warning 面（改后） | `moon check --target js` | **520 warnings / 0 errors**；0021 = 0、0002 = 11 | `temp/t34_check_full.log` |
| 分族分布（改后） | `grep -oE 'Warning \[[0-9]+\]'` | 0020 473 / 0006 12 / 0002 11 / 0001 10 / 0029 3 / 0009 3 / 0078 3 / 0007 2 / 0023 2 / 0027 1 | `temp/t34_check_full.log` |
| 测试面 | `moon test --target js` | `Total tests: 1340, passed: 1340, failed: 0` | `temp/t34_test_full.log` |
| 格式面 | `moonfmt.exe` 逐份比对（CR 归一） | 3 份全 FMT-OK；bare LF 0 | 会话输出 |
| 守卫电池 | `run_guards.py` | 38 格 / 失败 5 / SKIP 5 / 缺执行面的尺 0（与改前逐格相同） | `temp/t34_battery.log` |

### 预存红（本单未引入、未代修）

| 守卫 | rc | 成因 |
|---|---|---|
| `check_scripts_index.py` | 1 | 6 个脚本未在 `scripts/README.md` 登记 |
| `check_exit_code_contract.py --selftest` | 2 | 判据自检 4 格不通过（天花板常量 16 vs 现读 0；三支校准脚本仍为串式退出） |
| `check_plugin_sync.py` | 1 | 下游 `gen_plugins` 被账本重复编号挡住 |
| `gen_plugins.py --check` | 2 | 账本 5 组重复编号（BUG-183/192/328/329/330 各×2） |
| `check_plan_landing.py --gate` | 1 | 历史计划面文档缺失/移动超上限 |

## 分析

- **0021 为什么值得单吃**：`Json::Number` 带 `repr` 第二参，`Some(Number(n))` 只写一半参数就是 `missing_pattern_arguments`；编译器建议原文是 "To ignore them, add `..` to the end of argument list"，所以 `Number(n, ..)` 是语义等价的最小修法，不涉及数值表示。
- **0002 为什么只动局部绑定**：三处全是闭包形参/解构绑定，`_` 前缀是 MoonBit 对「有意不用」的正规标注；同族的参数位存量（`~`/`?` 与位置参数）会改调用面，按 BUG-354 既有结论不机械改名，留给单独单元。
- **0027 为什么试了就回退**：剥 `derive(Show)` 后同文件的 `pub extend StarVerdict with Show::{to_string, output}` 失去 trait 实现，编译器直接报 20 条 4015/4018；且 BUG-351 / R27 已实测该类型被生产 `to_json` 与 19 处白盒 inspect 依赖，属承重面留档——本单按「不碰承重面」原则回退，不扩大战线。
- **为什么要逐族对比**：总数 525→520 只能说明减了 5，逐格表证明减的正好是 0021 的 2 条与 0002 的 3 条，其余 8 族一格不动（BUG-344 定律：判据只认复跑分布）。

## 资源消耗

- 模型：本地副机 agent（无外部计费）；成本 0。
- 本单 token 估算：输入约 5.5 万 / 输出约 0.8 万。
- 本单耗时：约 10 分钟（含一次 22 errors 的试改回退与两次全量 check）。

## 任务分配记录

- T0r34：`publish --created-by human_steward` → `claim --assignee slave-agent` → 实现与验证 → `execute`（读数入 deliverable）→ `submit` → `verify --verifier commander`。
- 无二次分包；未触碰不可逆操作。

## 遗留风险

1. **520 条 warning 仍在**：`deprecated` 473 条以 `Json::value` 为主，按 BUG-356 的口径属 owner 决策项；本单只清两小族，不宣称「warning 已清零」。
2. **5 条预存红未动**（见上表），每条都需要单独单元；账本重复编号是 `gen_plugins` / `check_plugin_sync` 转绿的前置。
3. **`.mbti` 抖动会复现**（BUG-330）：每次 `moon check`/`moon test` 都会重写，需继续按 `git restore -- '*.mbti'` 处理；本单未改任何接口面。
4. **0027 的 StarVerdict 1 条会一直留在计数里**：它是文档化的承重面留档，后续任何「0027 归零」的声明都应先处理该类型的 `Show` 手工实现与调用面兼容性。

## 后续建议

1. 下一顺位：`unused_constructor` 12 条（`src` 内枚举构造器删除/改名档，按金条四先出方案）。
2. `0001` 10 条与 `0007` 2 条同属删除/改名档，可与上一项合并评估但应分包。
3. `0002` 参数位存量与 `0023 unused_try` 2 条：前者改调用面、后者与 store_sqlite 的 catch 兜底注释冲突，各自单独出方案。

## 超额内容

- 把 0027 的「试改 → 编译红 → 回退」全过程记录进账本与日志：这是对 BUG-351 留档结论的一次现场复核，证明当初的排除不是拍脑袋，而是 `Show` trait 实现与 `extend` 语法强耦合。
- 复跑完整电池并逐格对比，确认本单没有把任何 SKIP 变成 FAIL、也没有让预存红的读数漂移。

## 来源

- 台账：`memory/bugs.md` BUG-377
- 日志：`memory/2026-10-21.md` R52 段
- 证据：`temp/t34_check_full.log`、`temp/t34_test_full.log`、`temp/t34_battery.log`、基线 `temp/t33_check_final.log`
- 提交面：待本单 commit（`slave/fix/syntax-micro-families`），推送 gitcode 后由 owner 开 MR
