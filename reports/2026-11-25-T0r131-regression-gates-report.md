# T0r131「八：回归与门禁」交付报告

| 项 | 值 |
|---|---|
| 任务 | T0r131 · ns `autoplan` · depth=3 · priority 中 |
| 执行身份 | codeforce |
| 约束 | 只读盘点 / 最小改动；产出物写明路径 |
| 计划真源 | `fist-mbt/plan/active/2026-11-25-fist-auto-model.md:75-78`（条目「八：回归与门禁」）；裁决 A1–A4 见该文件「裁决项」节 |
| 验收判据（计划原文） | 补全新增改动不破坏既有工具面：`check_tools_sync` / `check_plugin_sync` / `moon test --target js` 全绿；工具数真源不变（除非确需新增工具并同步声明） |
| 执行时间窗（本机） | 2026-11-25 20:50–21:00 |
| 结果 | **三条门禁逐条留痕完成；其中门禁③的红格已定位为账本在册的预存缺陷（BUG-657），非本次改动引入** |

## 一、结果摘要（先给答案）

1. **工具数真源未变**：真源 `src/server/server.mbt` 注册 **197** 个工具，与 AGENTS/README/deliverable/scoring_rubric 及
   `docs/AGENTS-mcp-inventory.md`（21 组 ΣN=197）、插件态四宿主（64 生成文件）、运行面 `tools/list` 实测四处一致。
   本次改动面（`scripts/fist_gateway.py`、`scripts/_laya_rota.py`）**全部在 Python 脚本侧，零 MCP 工具注册面改动**
   ⇒ 「除非确需新增工具并同步声明」这一例外条款**未被触发**。
2. **门禁①`check_tools_sync`：PASS（rc=0）**。
3. **门禁②`check_plugin_sync`：PASS（rc=0）**，`gen_plugins.py --check` 复核亦 OK（197 工具 / v0.3.15）。
4. **门禁③`moon test --target js`：2127 / 2127 passed, failed 0**（清理 fixture 残留后的读数，见 §2.3 的口径声明）。
   首跑在**未清理的工作树**上读到 **2126 / 2127（failed 1）**，红格经复现定位为账本 **BUG-657**（在册 OPEN）：
   `src/store/multi_store_bug649_wbtest.mbt` 固定 db 路径且不清理 ⇒ 每跑一次追加一行 ⇒ 基线恒红。

## 二、三条门禁逐条留痕

| # | 门禁 | 命令 | 读数（原样） | rc | 判定 |
|---|---|---|---|---|---|
| ① | 工具清单单一真源 | `python scripts/check_tools_sync.py` | `PASS 工具单一真源一致：server.mbt 注册 197 个，AGENTS/README/deliverable/scoring_rubric 对齐；R3b/R7 扫现状面 182 份，历史面豁免 25 份（CHANGELOG 历史段/旧版 improvement-plan）；R8 清单分组 21 组 ΣN=197（已与实测 197 对表）` | 0 | **PASS** |
| ② | 一源四态·插件态 | `python scripts/check_plugin_sync.py` | `PASS 插件态一致：4 宿主 / 64 个生成文件 / 197 工具 / v0.3.15 / 启动参数真源 .mcp.dev.json`＋`J 面覆盖：6 个面（J1..J6）全部被 --selftest 认领` | 0 | **PASS** |
| ②补 | 生成器侧复核 | `python scripts/gen_plugins.py --check` | `OK 插件态与真源一致（197 工具 / v0.3.15）｜启动参数真源取到 .mcp.dev.json` | 0 | **PASS** |
| ③ | 全量 JS 测试 | `python scripts/moon_test_env.py --target js` | 首跑（残留未清）：`Total tests 2127 / passed 2126 / failed 1`；<br>清理残留后：`Total tests: 2127, passed: 2127, failed: 0.` | 入口 rc=0 | **PASS（口径见 §2.3）** |
| 真源 | 运行面双向对表 | MCP `tools/list`（127.0.0.1:18649） | `live_tools_list_count = 197` | — | 与离线真源一致 |

### 2.1 门禁③入口与读数纪律

按 BUG-142（`moon test` 退出码不可靠），判绿**以汇总行为准**。本轮使用常驻入口
`scripts/moon_test_env.py`（按目录剔 PATH 垫片、校验真实 `node.exe`），实测读数：

```
ROOT：E:\IDEProjects\AI\FIST-Mbt
PATH 垫片目录：0 个
node 解析：C:\Program Files\nodejs\node.exe（真实 node）
执行：moon test --target js --target js
汇总：Total tests 2127 / passed 2127 / failed 0
Total tests: 2127, passed: 2127, failed: 0.
```

### 2.2 首跑那 1 格红：根因定位（受控复现，非推断）

| 步骤 | 动作 | 读数 |
|---|---|---|
| 1 | 首跑全量 | `failed 1`，失败行 `src/store/multi_store_bug649_wbtest.mbt:17 ("bug649_default_routes_to_main") failed: Error: BUG-649：get(default) 拿到的不是主库句柄（审计行读不出，实得 2 条）` |
| 2 | 直查库 | `.fist-mbt/tmp/bug649-main.db` 的 `task_events` 中 `task_id='T-BUG649'` 有 **2 条完全相同的行** |
| 3 | 移出残留库（不删，备份至 `temp/bug649-main.residual.bak` / `temp/bug649-quarantine/`）后**定向单跑**该测试 | `Total tests: 2, passed: 2, failed: 0.` |
| 4 | 再跑一次全量 | 同一格**再次**红，直查库行数由 2 → 追加累积 ⇒ 坐实「每跑一次追加一行」 |
| 5 | 再次隔离残留库后跑全量 | `Total tests: 2127, passed: 2127, failed: 0.` |

机理与账本 **BUG-657**（`memory/bugs.md:16351-16356`，freebuff 2026-11-24 上报，状态 **OPEN**）逐字同型：
固定 db 路径 + 无前置/后置清理 ⇒ 残留行累积 ⇒ 基线恒红。**该红与本次改动面（Python 脚本）无任何因果**，
且它在任何「跑过一次的工作树」上都恒红（CI 首次干净克隆不受影响，本地持续污染）。

### 2.3 门禁③的口径声明（必须如实回报，不许含混）

- 本任务的门禁③判据是「全绿」。**工作树裸跑不是全绿**（2126/2127），原因是在册缺陷 BUG-657，不是本次回归。
- 因此本报告的绿是 **「清理 BUG-657 fixture 残留后的读数」**：2127/2127。这一点不掩盖、不美化。
- 建议（不在本单范围）：按账本修复方向把 `multi_store_bug649_wbtest.mbt` 迁到 `bug462_unique_db("bug649")`
  （helper 在 `src/store/bug462_fixture_wbtest.mbt`），或首尾清理固定路径，并加「跑两次仍须绿」的变异对照。
  在该单落地前，本地任何全量 JS 门的读数都要先排除这一格，否则会持续掩盖其它真实失败。

### 2.4 本次改动面与工具数真源的隔离证明

| 面 | 本次改动 | 是否触及工具数真源 |
|---|---|---|
| `scripts/fist_gateway.py` | `+595 / -2`（工作树未提交 WIP） | 否（纯 Python HTTP 网关） |
| `scripts/_laya_rota.py` | 未跟踪新件（T0r127 轮转策略） | 否（`_` 前缀辅助模块） |
| `scripts/test_laya_rota.py` | 未跟踪新件（T0r127 验收五格） | 否 |
| `src/server/server.mbt` | 工作树 diff **仅 2 行注释**（BUG-493 注记澄清：「工具数 182→183」标注为历史增量、非当前总数） | **否**——diff 中不含任何 `name:` / `tool_groups` / register 面变化 |

工作树 diff 原文（`git diff -- src/server/server.mbt`）唯一改动：

```diff
-  // 工具数 182→183。原否决理由「生产 0 使用者 ⇒ 收益为负」随本地消息池落地失效。
+  // 工具数 182→183（历史增量注记，非当前总数；当前工具数以
+  // scripts/_tool_registry.py 的注册表真源为准）。原否决理由「生产 0 使用者 ⇒ 收益为负」随本地消息池落地失效。
```

⇒ 「工具数真源不变」这一条**有四处独立读数 + 一处 diff 级证明**。

## 三、资源消耗

| 项 | 量 |
|---|---|
| 读取 | 计划文件 1、账本 2 段、T0r124/125/126/128/129 报告 5、源码 3（`multi_store_bug649_wbtest.mbt` / `_laya_rota.py` / `server.mbt` diff）、`_tool_registry.py` |
| 实跑命令 | 门禁①1、门禁②1＋生成器复核 1、全量 JS 4（首跑/重跑/定向/终跑）、直查 SQLite 3、`git diff`／`git status` 若干 |
| 后台作业 | `bash_start` ×4（bg-1..bg-4），均已回收结果 |
| 新建文件 | 本报告 1（`reports/2026-11-25-T0r131-regression-gates-report.md`） |
| 业务代码改动 | **0**（符合「只读盘点/最小改动」） |
| 隔离的临时产物 | `.fist-mbt/tmp/bug649-main.db*` 移至 `temp/bug649-quarantine/`；备份 `temp/bug649-main.residual.bak`（两者均在 `.gitignore` 面内：`/.fist-mbt/` L238、`temp/` L29） |
| MCP 调用 | get×2 / claim×1（回「非法迁移：当前已领取」）/ tools/list×1 / 后续 run_check・submit・verify |

## 四、任务分配记录

单 agent（codeforce）自执行——本任务本质是「跑三条既定门禁 + 逐条留痕」，无可独立再分的子任务，
未派子代理（避免多一轮模型开销而无产出增益）。

## 五、遗留风险

| # | 风险 | 性质 | 处置 |
|---|---|---|---|
| R1 | **BUG-657 使本地全量 JS 门恒红**（2127 中稳定占 1 格） | 在册 OPEN，非本单引入 | 本单只留痕与定位；修复另立（迁 `bug462_unique_db`） |
| R2 | 本轮全部读数基于**工作树当前态**（含大量他方未提交 WIP：`fist_gateway.py` +595 行、`_laya_rota.py` 新件等）；**HEAD 态未复跑** | 口径边界 | 若要求「提交面态」绿，须在 WIP 收口后复跑一次 |
| R3 | `scripts/_laya_rota.py` / `scripts/test_laya_rota.py` 为**未跟踪新件**，未进提交面；`run_guards.py` 电池未点名（`_` 前缀豁免），`test_laya_rota.py` 无执行面登记 | 执行面缺口 | 属 T0r127 收口范围，本单不扩范围 |
| R4 | native 面**未覆盖**（Windows 全项目 native build/test 必崩，账本 BUG-527 与版本无关） | 已知边界 | 本计划三条门禁只要求 JS 面 |
| R5 | `src/store/multi_store_bug649_wbtest.mbt` 与 `src/store/store_sqlite_wbtest.mbt` 在工作树均有未提交改动（前者经核为纯 `moon fmt` 换行、无语义变更） | 他方 WIP | 未代改、未代提交 |

## 六、后续建议

1. **优先修 BUG-657**（它是本轮唯一红格的根因，且持续污染本地所有验证门）：迁 `bug462_unique_db` + 变异对照。
2. T0r127（执行中）收口时，把 `_laya_rota.py` / `test_laya_rota.py` 一并纳入提交面与 `run_guards` 登记，
   并让 `test_laya_rota.py` 的五格（跳过 busy / 跳过 cooldown / 空池安全返回 / 失败顺延 / 窗口到期重置）
   有可复跑入口。
3. P20 批次收口后跑一次「干净树全量 JS」作为最终回归读数（本报告已给出工作树态读数与口径）。

## 七、超额内容（超出三条门禁但对结论必要）

- 用「HEAD 版 vs 工作树版 `server.mbt` 工具名集合差」做过一次程序化对比：两侧均为同一集合，
  **新增 0 / 删除 0**（第一版正则未命中注册面写法，故改用 diff 面逐行核验，两条证据一致）。
- 直查 SQLite 坐实残留行数（2 条）与「每跑追加一行」的累积行为，而非仅凭错误文案推断。

## 八、来源

- 计划真源：`fist-mbt/plan/active/2026-11-25-fist-auto-model.md:75-78`（工作项八）、`:80-85`（裁决 A1–A4）、`:87-92`（红线）
- 账本：`memory/bugs.md:16297-16303`（BUG-649，FIXED）、`:16351-16356`（BUG-657，OPEN）
- 实测：本报告 §2 各格读数（本机 2026-11-25 20:50–21:00，UTC 戳见各命令回执）
- 相关前序报告：`reports/2026-11-25-T0r124-fist-auto-design-report.md`、`reports/2026-11-25-fist-auto-realcompletion-report.md`、`reports/2026-11-25-T0r126-candidate-pool-assembly.md`、`reports/2026-11-25-T0r128-http-residency-auth-report.md`、`reports/2026-11-25-T0r129-accounting-observability-report.md`
