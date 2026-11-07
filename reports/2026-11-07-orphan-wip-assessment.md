# 唤醒轮 198 · 孤儿 WIP 完整性评估（只读 + 独立复验）

- 日期：2026-11-07（FIST-Mbt-ExploreWatchdog 唤醒轮 198）
- 评估对象：aider 车道孤儿 WIP——**第十七轮同规模**（10 文件 +6144/-6025，HEAD 084c555a1，
  另 2 个新未跟踪文件；轮 195 已钉实 aider 进程不存在，孤儿态维持）
- 评估方式：**纯只读**（git diff + 新文件通读 + 独立复跑判据/测试），未对 WIP 任何文件做改动

## WIP 定性修正（本轮新发现）

轮 188~197 将此 WIP 定性为「BUG-580/581 修复**中间态**」。本轮通读 diff 与账本后修正为
**已终审收口批**——账本（memory/bugs.md WIP diff）里已带「终审读数（统帅复跑，非车道自述转抄）」
段，内容五项：

1. **BUG-580 修复（C1+C2 双层）**
   - C1：`engine_supervisor.mbt` `iso_to_epoch` 返回 `Int32?`→`Int64?`（9999 年 epoch ≈2.5e11
     秒，Int32 静默绕回成负 ⇒ `ts_ok` 判假 ⇒ 存在的提醒被静默清零）；`stale_cut`/`pending_cut`
     阈值乘法一并 Int64 化
   - C2：`supervisor_tools.mbt` MCP 工具层负阈值显式 `Err(ToolError)`（不 fail-quiet）+
     引擎层负阈值返回带 `error` 字段的空结果（保护 `ops_commissar` 等直接调用方）
   - 回归锁：新 `engine_supervisor_bug580_wbtest.mbt` 4 格（远未来不清零 / epoch 数值等价 /
     负阈值拒绝 / 正常路径零回归，文件头带三处变异对照设计）+ `engine_supervisor_parse_wbtest.mbt`
     差值断言随签名升 `Int64?`
2. **BUG-581 修复**：`server.mbt` issue_scan 描述串「+20 条融合——共 31 条」→「+22 条融合
   （补过宽 catch / 未用变量 / 重复除零）——共 33 条」，与 `scan_rules()` 现数 33 个唯一 id 对齐
3. **BUG-565 后续第二层守卫**：新 `scripts/check_foreign_ledger_entries.py`（外来条目**白名单棘轮**：
   foreign 39 条 + meta 2 条基线，只红基线外新增；与既有 `check_bug_ledger_scope.py` 同对象不同契约）
   + `run_guards.py` 两格注册（判据本体 + `--selftest`）+ `scripts/README.md` 文档条目
4. **BUG-582 立账**：`check_selftest_hermetic` 既有红（155 处全在既有脚本，本批新增脚本贡献 0 处）OPEN
5. **文档面 + dist**：README/README_EN 测试徽章 2032→2036（日期归属 2026-11-07）、
   守卫族自述同步、dist 重烤（12018 行）

## 独立复验（本轮实跑，全绿，非转抄账本宣称）

| 验证面 | 读数 |
|---|---|
| 全量 `python scripts/moon_test_env.py --target js` | **Total tests: 2036, passed: 2036, failed: 0，rc=0**（基线 2032 + 新增 4 格，与账本终审读数一致） |
| `scripts/check_fmt_gate.py` | PASS（moon fmt --check rc=0） |
| `scripts/check_dist_snapshot.py` | PASS（版本面 0.3.11==moon.mod；描述面 175/178 命中） |
| `scripts/check_foreign_ledger_entries.py --selftest` | **15/15 格，rc=0**（含 3 处变异对照 + 未知旗标/拼错旗标拒绝 + 抬头文法与 gen_plugins parity 格） |

## 提交阻断缺口（3 项，全部机械，无新代码写作）

1. **gen_plugins 重投影未跑**：账本计数面已变（580/581 OPEN→FIXED、582 OPEN ⇒ 待修 -1、
   总计数推进），cl7 律要求与账本改动**同批**重投影；WIP 的 `plugins/` 面零 diff ⇒ 未跑。
2. **2 个新未跟踪文件未入提交面**：`scripts/check_foreign_ledger_entries.py`、
   `src/engine/engine_supervisor_bug580_wbtest.mbt`。
3. **需 `commit_scoped.sh` scoped 提交**（仓纪律：commit 必带明确路径；申报面 12 文件）。

## owner 决策输入更新（三选一，轮 195 首报）

- **① 本统帅车道续写收口——风险画像下调**：不再是「续写未完成修复」，而是「替一个已复验全绿
  的批次收尾最后 3 步机械动作」（跑 `gen_plugins` → 核 cl7 rc=0 → `commit_scoped.sh` 12 文件），
  **全程零新代码写作**。需要 owner 解禁授权（src/**、scripts/run_guards.py + 2 新文件）。
- ② 新起车道接手：等价工作量，无额外收益。
- ③ owner 自行处置：WIP 自轮 188 起悬挂已约 7 小时零变化。

> 本评估全程未触碰 WIP 文件；`_build` 构建缓存为测试副产物（gitignore 面）。
