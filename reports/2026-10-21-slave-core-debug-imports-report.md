# 副机报告 · 0071 核心包隐式 import 清零（T0r32 / BUG-375）

- 日期：2026-10-21
- 分支：`slave/fix/core-debug-imports-0071`（基点 `e9a714f`，强制 `slave/` 前缀）
- 任务：T0r32
- 台账：BUG-375（FIXED）
- 交付面：`src/evolve/moon.pkg`、`src/router/moon.pkg`、`src/store/moon.pkg`（各 +1 行）

## 结果摘要

1. **清零一族 warning**：`moon check --target js` 的 `0071 core_package_not_imported` 从 **23 条 → 0 条**，总 warning **578 → 555**，errors 仍为 0。
2. **改动只有三行**：三个包的 `moon.pkg` import 块各补 `"moonbitlang/core/debug",`。23 条命中散在 9 份 `.mbt`（`src/evolve/curriculum.mbt` 2、`src/router` 8 份共 16、`src/store` 3 份共 5），但 `moon.pkg` 是包级声明，一份清单覆盖同包全部文件。
3. **零语义改动**：未动任何 `.mbt`、`.mbti`；`moon test --target js` 保持 **1340 / 1340 / 0**。
4. **接口面零变化**：`moon check`/`moon test` 重写的 24 份 `.mbti` 全部 `git restore`；其中 evolve/router/store 三份归一后为纯 Int32 拼写抖动，证明补 import 不改变 `.mbti` 内容。

## 证据（真实读数）

| 项 | 命令 / 判据 | 读数 | 证据文件 |
|---|---|---|---|
| warning 面（改前） | `moon check --target js` | 578 warnings / 0 errors；0071 = 23 | `temp/t31_check_full.log` |
| warning 面（改后） | `moon check --target js` | **555 warnings / 0 errors**；0071 = 0 | `temp/t32_check_full.log` |
| 分族分布 | `grep -oE 'Warning \([a-z0-9_]+\)'` | deprecated 473 / test_unqualified_package 30 / unused_value 24 / unused_constructor 12 / unused_package 3 / struct_never_constructed 3 / result_error_return 3 / unused_try 2 / unused_field 2 / missing_pattern_arguments 2 / deprecated_syntax 1（仅 0071 由 23→0） | `temp/t32_check_full.log` |
| 测试面 | `moon test --target js` | `Total tests: 1340, passed: 1340, failed: 0` | `temp/t32_test_full.log` |
| 包清单守卫 | `check_pkg_imports.py` | PASS（26 份 moon.pkg / 33 条本地 import） | 会话输出 |
| 接口守卫 | `check_mbti_sync.py` | PASS（24 份 / 655 条声明） | 会话输出 |
| 打包面 | `check_publish_payload.py` | PASS（1183 件 / 未跟踪 0） | 会话输出 |
| 守卫电池 | `run_guards.py` | 38 格 / 失败 5 / SKIP 5 / 缺执行面的尺 0（与改前逐格相同） | `temp/t32_battery.log` |

### 预存红（本单未引入、未代修）

| 守卫 | rc | 成因 |
|---|---|---|
| `check_scripts_index.py` | 1 | 6 个脚本未在 `scripts/README.md` 登记 |
| `check_exit_code_contract.py --selftest` | 2 | 判据自检 4 格不通过（天花板常量 16 vs 现读 0；三支校准脚本仍为串式退出） |
| `check_plugin_sync.py` | 1 | 下游 `gen_plugins` 被账本重复编号挡住 |
| `gen_plugins.py --check` | 2 | 账本 5 组重复编号（BUG-183/192/328/329/330 各×2） |
| `check_plan_landing.py --gate` | 1 | 历史计划面文档缺失/移动超上限 |

## 分析

- **为什么能只改三行**：0071 的报错单位是「使用点」，但声明单位是「包」。23 条命中全部落在三个包里，且缺失的都是同一个核心包 `moonbitlang/core/debug`（`println`/`dump` 的归属包）——所以三份包清单就能一次收干净，不需要逐文件改。
- **为什么不会反噬 `unused_package`**：显式 import 与编译器隐式注入并存，只要确有使用点就不算未用。实测该族 3→3 不变，是对这条判断的直接验证。
- **为什么要逐族对比**：只看总数 578→555 无法区分「清掉 23 条 0071」与「清掉 A 族又引入 B 族」。逐格表里其余 10 族一格不动，才能证明这一单是纯减法（BUG-344 定律：判据只认复跑分布）。
- **为什么 restore 全部 `.mbti`**：三份相关 `.mbti` 归一后与 HEAD 相同（生成器不记录核心包 import 顺序），另四份真实差异来自宿主 stale 与 R49 的函数新增，与这一单无关；按既有口径不把接口面搅进 warning 清理单。

## 资源消耗

- 模型：本地副机 agent（无外部计费）；成本 0。
- 本单 token 估算：输入约 6 万 / 输出约 0.9 万。
- 本单耗时：约 12 分钟（含全量 check / test 与电池复跑）。

## 任务分配记录

- T0r32：`publish --created-by human_steward` → `claim --assignee slave-agent` → 实现与验证 → `execute`（读数入 deliverable）→ `submit` → `verify --verifier commander`。
- 无二次分包；未触碰不可逆操作。

## 遗留风险

1. **555 条 warning 仍在**：其中 `deprecated` 473 条以 `Json::value` 为主，按 BUG-356 的口径属 owner 决策项；本单只清 0071，不宣称「warning 已清零」。
2. **5 条预存红未动**（见上表），每条都需要单独单元；账本重复编号是 `gen_plugins` / `check_plugin_sync` 转绿的前置。
3. **`.mbti` 抖动会复现**（BUG-330）：每次 `moon check`/`moon test` 都会重写，需继续按「归一证明纯拼写 → restore」处理。
4. **本机 `moon fmt` 仍 ICE**（`\\?\` 路径），只能逐件 `moonfmt.exe`；本单未改 `.mbt`，格式化面无新增风险。

## 后续建议

1. 下一顺位：`test_unqualified_package` 30 条（测试面逐包加 `@pkg` 限定，注意快照与导入顺序）。
2. `unused_value` 24 条与 `unused_constructor` 12 条属删除/改名档，按金条四先出方案再动。
3. 账本重复编号与 `check_scripts_index` 两项预存红可各自立单元，互不依赖。

## 超额内容

- 顺手把 `0071` 的「使用点 vs 声明点」对照关系写成逐包清单（9 份 `.mbt` → 3 份 `moon.pkg`），可作为后续同族迁移的模板。
- 复跑了完整电池并逐格对比，确认本单没有把任何 SKIP 变成 FAIL、也没有让预存红的读数漂移。

## 来源

- 台账：`memory/bugs.md` BUG-375
- 日志：`memory/2026-10-21.md` R50 段
- 证据：`temp/t32_check_full.log`、`temp/t32_test_full.log`、`temp/t32_battery.log`、基线 `temp/t31_check_full.log`
- 提交面：待本单 commit（`slave/fix/core-debug-imports-0071`），推送 gitcode 后由 owner 开 MR
