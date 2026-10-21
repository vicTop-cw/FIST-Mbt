# 副机报告 · 0029 unused_package 清零（T0r35 / BUG-378）

- 日期：2026-10-21
- 分支：`slave/fix/unused-import-0029`（基点 `f8f8b21`，强制 `slave/` 前缀）
- 任务：T0r35
- 台账：BUG-378（FIXED）
- 交付面：`src/ops/moon.pkg`、`cmd/commissar/moon.pkg`（2 文件，净 −2 行 +4 行）

## 结果摘要

1. **0029 全族清零**：`moon check --target js` 的 `0029 unused_package` 从 **3 条 → 0 条**，总 warning **520 → 517**，errors 仍为 0。
2. **两档处置**：`src/ops` 的 `src/store` 只被黑盒测试引用 → 收进 `for "test"`；`src/ops` 与 `cmd/commissar` 的 `moonbitlang/core/json` 整包零引用 → 直删。
3. **测试零回归**：`moon test --target js` 保持 **1340 / 1340 / 0**。
4. **零 `.mbt` 改动**：只动两份包清单，`Json` 走默认 prelude 的既有事实经 0 errors 实证。

## 证据（真实读数）

| 项 | 命令 / 判据 | 读数 | 证据文件 |
|---|---|---|---|
| warning 面（改前） | `moon check --target js` | 520 warnings / 0 errors；0029 = 3 | `temp/t34_check_full.log` |
| warning 面（改后） | `moon check --target js` | **517 warnings / 0 errors**；0029 = 0 | `temp/t35_check_full.log` |
| 分族分布（改后） | `grep -oE 'Warning \[[0-9]+\]'` | 0020 473 / 0006 12 / 0002 11 / 0001 10 / 0009 3 / 0078 3 / 0007 2 / 0023 2 / 0027 1 | `temp/t35_check_full.log` |
| 测试面 | `moon test --target js` | `Total tests: 1340, passed: 1340, failed: 0` | `temp/t35_test_full.log` |
| 包清单守卫 | `check_pkg_imports.py` | PASS（26 份 moon.pkg / 33 条本地 import） | 会话输出 |
| 守卫电池 | `run_guards.py` | 38 格 / 失败 5 / SKIP 5 / 缺执行面的尺 0（与改前逐格相同） | `temp/t35_battery.log` |

### 预存红（本单未引入、未代修）

| 守卫 | rc | 成因 |
|---|---|---|
| `check_scripts_index.py` | 1 | 6 个脚本未在 `scripts/README.md` 登记 |
| `check_exit_code_contract.py --selftest` | 2 | 判据自检 4 格不通过（天花板常量 16 vs 现读 0；三支校准脚本仍为串式退出） |
| `check_plugin_sync.py` | 1 | 下游 `gen_plugins` 被账本重复编号挡住 |
| `gen_plugins.py --check` | 2 | 账本 5 组重复编号（BUG-183/192/328/329/330 各×2） |
| `check_plan_landing.py --gate` | 1 | 历史计划面文档缺失/移动超上限 |

## 分析

- **为什么不能直删 store**：0029 的判定把「主单元」与「测试单元」合起来看，但 import 声明是包级的。主单元零 `@store` 引用 → 报 unused；而 `ops_watchdog_test.mbt` 的 `@store.SqliteStore::open` 又真实依赖它。直删会让黑盒测试编译红，`for "test"` 是唯一两全解（BUG-342 / R22 已立此口径）。
- **为什么 core/json 可以直删**：`Json` 在 `src/ops/audit.mbt` 与 `cmd/commissar/main.mbt` 里都写作不带 `@` 的前缀形式，说明它来自默认 prelude；显式 import 纯属冗余。删后 0 errors 是对这条判断的直接验证。
- **为什么逐族对比**：总数 520→517 只能说明减了 3，逐格表才证明减的正好是 0029，其余 8 族一格不动（BUG-344 定律）。

## 资源消耗

- 模型：本地副机 agent（无外部计费）；成本 0。
- 本单 token 估算：输入约 4.5 万 / 输出约 0.7 万。
- 本单耗时：约 8 分钟（含两次全量 check / test 与电池）。

## 任务分配记录

- T0r35：`publish --created-by human_steward` → `claim --assignee slave-agent` → 实现与验证 → `execute`（读数入 deliverable）→ `submit` → `verify --verifier commander`。
- 无二次分包；未触碰不可逆操作。

## 遗留风险

1. **517 条 warning 仍在**：`deprecated` 473 条以 `Json::value` 为主，按 BUG-356 属 owner 决策项；本单只清 0029，不宣称「warning 已清零」。
2. **5 条预存红未动**（见上表），每条都需要单独单元；账本重复编号是 `gen_plugins` / `check_plugin_sync` 转绿的前置。
3. **`for "test"` 的依赖面会随测试增删漂移**：将来若删除 `ops_watchdog_test.mbt` 的 SQLite 用例，这条 test import 会变成新的 0029；反之若主单元开始用 store，则应把它提回主 import 块。
4. **`.mbti` 抖动会复现**（BUG-330）：每次 `moon check`/`moon test` 都会重写，需继续按 `git restore -- '*.mbti'` 处理。

## 后续建议

1. 下一顺位：`0007 unused_field` 2 条（`DebateSession.topic/hats` 只写不读，删字段需同步 convene 构造与一条白盒测试）。
2. `0001 unused function` 10 条中测试辅助函数可先清（低风险），产品代码部分按金条四先出方案。
3. `0009 struct_never_constructed` 3 条是 `pub struct` 面，删除会改公开接口，须先确认无外部消费者再动。

## 超额内容

- 把 0029 的「主单元 vs 测试单元」判定差写成取舍说明：这是本族最容易误删的一格，也是后续同族清理的模板。
- 复跑完整电池并逐格对比，确认本单没有把任何 SKIP 变成 FAIL、也没有让预存红的读数漂移。

## 来源

- 台账：`memory/bugs.md` BUG-378
- 日志：`memory/2026-10-21.md` R53 段
- 证据：`temp/t35_check_full.log`、`temp/t35_test_full.log`、`temp/t35_battery.log`、基线 `temp/t34_check_full.log`
- 提交面：待本单 commit（`slave/fix/unused-import-0029`），推送 gitcode 后由 owner 开 MR
