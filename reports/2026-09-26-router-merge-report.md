---
标题: 合并 fist-model-router + aider/atomcode 执行器（六模式自驱轮 · Round R6）
日期: 2026-09-26
命名空间: router-merge
模式顺序: 推进(合并) → 寻虫 → 修复 → 验证 → 打磨 → 清整
开关: laya=开 · issue_up=开(BUG-52~60) · call_log=开 · omega=开
---

# 结果摘要

把兄弟项目 `fist-model-router` 的模型路由能力并进 FIST-Mbt 主仓，同时把它依赖的**外部编码执行器**
（aider / atomcode，源自衍生项目 FIST 的 `executor/*.py`）改造成 MoonBit 侧的可审参数层，
全程用 FIST 自己的六模式流水线推进，四个自驱开关全开。

| 指标 | 合并前 | 合并后 | 口径 |
|---|---|---|---|
| MCP 工具 | 116 | **120** | `server.mbt` 注册数（`check_tools_sync` 实测） |
| JS 测试 | 406 | **439** | `moon test --target js` 实测（本轮新增 32 项回归锁） |
| 守卫族 | 6 | 6（扩面不改数） | 六守卫 rc=0 |
| 插件态 | 四宿主 | 四宿主已重投影 | `check_plugin_sync`（cl7）绿 |
| 任务树 | — | 21 节点全部「已完成」 | `status_summary.by_status` |

新增能力面（4 个工具）：
`model_route`（决策+记账+落盘）、`model_router_status`（只读）、`model_router_reset`（清窗口/硬复位）、
`executor_run`（真跑外部执行器，含 `dry_run`）。

分层落点（一源四态 r2）：决策与状态 schema = `src/router/`（纯计算零 IO）；argv 形状 = `src/executor/cli_argv.mbt`
（纯计算、可审）；必须带 IO 的三件事（落盘、服务端盖章时钟、spawn）= `src/server/model_router_ops.mbt`；
CLI = `scripts/fist.py call <tool>`（薄封装，实跑过）；Skill = `docs/model-router-skill.md`；
Plugin = `scripts/gen_plugins.py` 投影四宿主。

# 资源消耗

- 真实调用留痕（`call_log`，非回忆）：`model_route` 34 次、`executor_run` 24 次、`model_router_status` / `model_router_reset` 各 4 次；
  本轮 `report_bug` 9 条、`output_validate` 9 次、`laya_decide` 6 次、`issue_scan` 2 次。
- 外部执行器**没有真跑**：aider/atomcode 两台 CLI 都在本机 PATH 里（实测 `E:\Tools\aider-venv\...\aider.exe`、
  `C:\Users\victo\AppData\Local\AtomCode\atomcode.exe`），真跑会启动外部 agent 烧真实配额，
  所以调用面只验证到 `dry_run` 的 argv 与全部拒绝路径，`executed=false` 由判据 E05 反证（未产生任何副作用文件）。
- `cost_stats` 本轮为 0：合并没有产生 token 记账（未给 execute 传 tokens，配额语义是"次数"）。

# 任务分配记录

- 根任务 `T0r360`（advance 模式）由指挥官发布，`task_plan_deep` 递归拆解：`split_n=4` + `gradient` +
  `reinject_context` + `boundary_probe` + `omega_strong_verify`，得到 5 个中层节点 × 3 叶 = 15 叶（含 5 条边界审视叶）。
- `laya_decide` sidecar 不可用（退出码 -1）⇒ 走内建确定性回退（`source: fallback`，feature_route=排程路由，split_n=4），
  这是回退分支的一次真实活证据。
- 执行方式：本轮由指挥官**单遍执行**、未逐叶派发（如实记账，每叶交付文案里都写明了这一点）；
  15 叶 + 5 父 + 1 根全部经 `claim → execute → submit → omega(语料+成果复验) → verify` 走完，终态
  `by_status={已完成: 21}`。

# 缺陷闭合（9 条，全部挂 FIXED 小记）

| id | 一句话 | 锁 |
|---|---|---|
| BUG-52 | 上游时间↔秒用 365 天/31 天近似，5h 窗口跨月闰年判偏 | rt_1 / rt_2 |
| BUG-53 | 上游 `current_model()` 空池索引 `[0]` panic | rt_4 / rt_5 / mo_3 |
| BUG-54 | 坏状态里负游标经 `%` 落负下标（实测 `-7 % 2 = -1`）⇒ panic | rs_3（夹紧 + 点名） |
| BUG-55 | `config_json` 解析失败被当成"没传配置"，静默用默认池 | 调用面 S04 |
| BUG-56 | `usage_report.current_model` 报游标位而非选中模型，同响应自相矛盾 | rt_13（成对）/ rs_1 / S03c |
| BUG-57 | `issue_scan.py --include-tests false` 反被当开启 | 实测 include_tests=False |
| BUG-58 | 守卫族在 GBK 控制台抛 UnicodeEncodeError，traceback 冒充红色 | 六守卫免 PYTHONIOENCODING 直跑 PASS |
| BUG-60 | `evolve_critic` 默认参数下门禁永不可满足（中性 0.5 加权后上限 0.75 < 0.85），`task_challenge(critic=true)` 恒拒 | `critic_test` 三判据成对锁 |
| BUG-59 | 父节点自动提升「待验收」时不带交付物 ⇒ 与 Omega 成果复验门禁互锁，只能 reject→retry 绕 | `engine_promote_r6_test` 两条 |

其中 54/55/56 是**本轮新代码自己的缺陷**（不是上游带来的），57/58/59 是既有工具链/引擎的结构性问题。

# 验证结论（证据梯 L4）

- `moon test --target js`：**439 passed / 439 total / 0 failed**（`temp/verify_r1.py` 子进程重跑，不读旧日志）。
- 六守卫 rc=0：tools_sync / test_sync / badge / scripts_index / plugin_sync(cl7) / doc_surface(J1~J8 + selftest)。
- 调用面冒烟 `temp/router_smoke.py`：**27/27**（含"schema 里没有 now 参数"、"绝对路径与 `..` 必拒"、
  "非法 config_json 必报错"、"dry_run 零副作用"、"未知执行器拒绝并列出可用集"）。
- `output_validate` verdict=**pass**（23 件产物 + 外部判据，含 BUG-59/60 的锁与本轮 CHANGELOG/报告自身），并按纪律配了一条**必然违例**的对照
  （要求一个绝不该出现的 needle）确认判据会发红 —— 第一轮它真的发红了一次，抓出我写错的 needle。

# 遗留风险

1. **`executor_run` 的真跑路径未在真实外部 agent 上验证**（有意为之，见「资源消耗」）。第一次真跑建议
   `dry_run=true` 先看 argv，再显式去掉；失败会返回 `ok=false` + 可诊断 hint，不会静默成功。
2. **配额语义是"次数"不是 token/金额**：`cost_estimate` 是占位（atomcode 0.0 / aider -1.0 表示未知），
   不能拿它做预算决策，预算侧仍应看 `cost_stats` / `progress_gate`。
3. **默认池里写死了一批模型名**（`RouterConfig::default()`，无密钥）：换供应商需要传 `config_json` 或改默认，
   目前是"配置优先、默认兜底"，不会静默改路由。
4. **BUG-50/51 仍 OPEN**（上一轮遗留）：`check_test_sync` 只核对白名单 4 份文档；`report_bug` 与 `run_check`
   的 project_dir 路径口径相反。本轮没有扩这两处判据。
5. `model_router_*` 的状态文件落在 `{project_dir}/memory/`，与 bug 账本同目录但不同文件；
   `project_dir` 禁越界 ⇒ 路由账出不了任务库（与 BUG-53 记账双轨同源，见记忆）。

# 后续建议

1. 给 `selfdrive_pick_next` / `watchdog_tick(autodispatch=true)` 接上 `model_route`：无人值守派单前先问一次路由，
   把"用哪个模型"从 agent 自选变成可复现决策（现在的接线点已经在了：`executor_run` 的 `model` 留空即路由）。
2. 把 BUG-50/51 两条判据缺口与本轮的"CLI↔MCP 参数语义漂移"（BUG-57 一类）合成一条守卫生：
   对所有 `scripts/*.py` 生成的参数，自动与 `tools/list` 的 schema 对一遍（J8 已有模板侧的同类实现可复用）。
3. 真跑 aider/atomcode 之前，先在人确认下跑一单 `dry_run` → 去掉 dry_run 的最小任务，观察退出码与
   `output_validate` L4 是否真能拿到产物。

# 超额内容（做在要求之外的事，如实列）

- 修了引擎级 BUG-59（父节点归并互锁）并补 2 条回归测试 —— 不在"合并路由器"的要求里，是收尾任务树时撞上的。
- 给 `executor_run` 加了 `dry_run` 可选参数（默认 false 零回归），因为它把宿主命令能力暴露到了 MCP 面，
  不留"先看命令再决定跑不跑"的口子不合理。
- 顺手修了守卫族与 `issue_scan.py` 的两个工具链缺陷（BUG-57/58），因为它们直接影响本轮判据的可信度。
- 没做的事：不 bump 版本（0.3.0 仍标 unreleased，本轮并入同段）、不做任何 git 写操作、不动依赖。

# 来源

- 上游代码：`E:\IDEProjects\AI\fist-model-router\src\{model_router,router_ext}.mbt`（802 行 / 3 文件）
- 执行器参数形状：`E:\IDEProjects\AI\FIST\executor\{aider_executor,atomcode_executor}.py`
- 本轮判据与证据：`temp/router_smoke.py`(27/27)、`temp/verify_r1.json`、`temp/js_test_r7.log`(439/439)、
  `temp/bugfind_r1.py`（BUG-52~58）、`temp/bug59_and_unstick.py`（BUG-59 + 父节点收口）、
  `temp/close_tree_r1.py`（21 节点生命周期）、`temp/{ledger_fixed_r1,emit_docs_r1,bump_test_count}.py`
- 规范依据：`AI-DEVELOPMENT-STANDARD.md`（R116）§4 cl1~cl7、§3 自我迭代四开关判据表
