# 自驱式编程 · 全模式走查账本（2026-10-11，goal: 所有模式走一遍 + 开关全开）

> 目标项目：`E:/IDEProjects/AI/FIST-Mbt`（= MCP server cwd，工具入参 `project_dir="."`）。
> 顺序决策（由跑查 agent 自定）：advance → polish → verify → bugfind → fix_and_merge → tidy → explore。
> 理由：先建新能力 → 再打磨 → 再查完备 → 再找虫 → 再修既有/找到的问题 → 再清整 → 最后 explore 从其余 6 个模式里按复杂度自选，可复用前五轮的产出做并行域。

## 开关矩阵（"全开"的定义，逐模式打钩）

| 开关 | m1 advance | m2 polish | m3 verify | m4 bugfind | m5 fix_and_merge | m6 tidy | m7 explore |
|---|---|---|---|---|---|---|---|
| task_plan_deep: gradient | ON | ON | ON | ON | ON | ON | ON |
| task_plan_deep: gradient_dag（真实 depends_on 边） | ON | ON | ON | ON | ON | ON | ON |
| task_plan_deep: boundary_probe（边界 owner 叶） | ON | ON | ON | ON | ON | ON | ON |
| task_plan_deep: reinject_context（父计划回注） | ON | ON | ON | ON | ON | ON | ON |
| plan 决策面 laya_auto ⇔ decide_split_n（互斥） | laya_auto | decide_split_n | laya_auto | decide_split_n | laya_auto | decide_split_n | decide_by+difficulty |
| task_plan_deep: calibrate（难度校准数组） | ON | ON | ON | ON | ON | ON | ON |
| task_plan_deep: omega_strong_verify（强验证链） | ON | ON | ON | ON | ON | ON | ON |
| claim: inject 档案资产注入 | ON | ON | ON | ON | ON | ON | ON |
| watchdog_tick: phi_gate + autodispatch | ON | ON | ON | ON | ON | ON | ON |
| watchdog_tick: flush_bug_queue | 见 BUG-210 诚实降级（GitHub/GitCode 未启用，不会假成功） | 同左 | 同左 | 同左 | 同左 | 同左 | 同左 |
| watchdog_tick/pipeline_tick: mode 模板 | advance | polish | verify | bugfind | fix_and_merge | tidy | explore |
| 执行面 run_check（外部判据落库） | 用 | 用 | 用（核心） | 用 | 用 | 用 | 用 |
| 交付面 output_validate（L4 证据梯） | 用 | 用 | 用 | 用 | 用 | 用 | 用 |
| 治理面 reserve_scope + conflicts_check | ON | ON | ON | ON | ON | ON | ON（并行域判定用） |
| 教训资产 evolve_lesson / evolve_distill | 视产出 | 视产出 | 视产出 | 视产出 | 视产出 | 视产出 | 视产出 |

## 逐模式状态

| 模式 | ns | 根任务 | 状态 | 关键证据 |
|---|---|---|---|---|
| m1 advance | fist-modes-r1 | T0r572（BACKLOG P1 Agent Contract 七字段注入 ops_selfdrive）| 进行中 | 基线 moon test js: 742/742 failed 0；tree 16 节点（梯度+DAG+边界+回注+omega 全开）；watchdog_tick phi_gate 生效 |
| m2 polish | - | - | 未启动 | - |
| m3 verify | - | - | 未启动 | check_tools_sync PASS 136 工具；check_test_sync 需 `--total <实测总数>` 参数（recon 已跑通用法）|
| m4 bugfind | - | - | 未启动 | issue_scan(src)=77 hits（h0/m28/l49），bugfind 模式里逐条人肉复核后才可入账 |
| m5 fix_and_merge | - | - | 未启动 | GitHub/GitCode token 缺失 ⇒ 远端合并面诚实降级为"仅本地修复+记账"，不得报假成功 |
| m6 tidy | - | - | 未启动 | - |
| m7 explore | - | - | 未启动 | 按复杂度评分自选子模式；并行前提=文件作用域两两不相交（reserve_scope+conflicts_check）|

## 教训/备注

- 开关全开的树会膨胀：gradient_ladder+reinject_context+boundary_probe ⇒ 每叶 2 层梯度 + 边界四问 + 父计划回注，描述很长；16 节点已够本演示轮使用，后续模式继续保持全开（目的正是全开关实测）。
- BUG-210 记忆：flush_bug_queue 在 token 未配置时是 plan-only，严禁回 any_success=true 类假结论；本走查如实标注"未启用"。
- 守卫判据读数先行：`check_test_sync.py` 必须带 `--total`（实测 742）才有效，裸跑报"无法从参数/日志解析测试总数"。
