T0r322 -> BUG-38  同族：BUG-37 臆造名单 / BUG-33 无人读广告 / BUG-38 臆造调用——契约说谎三连
Round4-验证段(T0r382) -> Round5-修复段(BUG-74/BUG-75)  验证段入账未修的两条：返回契约缺失 + 判据无诊断回执；两条都要配成对锁（必红 + 必不误抓）
shim -> bug-161-bug-163-mcp-compat  外部 shim 是 BUG-161/163 的当前缓解方案；内建 compat 层由并发 agent 负责，当前未提交且缺陷（protocolVersion 回写 + 丢通知）
is_finite -> Double-finite-check  MoonBit Double 无 is_finite 方法。等价替代：`n == n`（NaN 时 false，n>=X 已排除 NaN）。并发 agent 在 router_config/router_state 引入 is_finite 导致编译失败（BUG-193）。
组合模式 47 能力善用 -> fist-mbt v0.3.8  Round 17-49 全程用发布版 fist-mbt 能力（自证：dag_analysis/cost_budget_split/goal_drift_check/text_diff/plan_revise/dag_parallelism/dag_critical_path/dag_ready/saga_rollback 等 47 项），组合模式[打磨,寻虫,修复,验证,清整,推进] 自驱收口
S6-0 TargetIR 数值契约 -> S6-1 TargetIR 设计草图  S6-1 设计严格对齐 S6-0 runtime.rs 的 DType/promote 契约与 G4 门禁
S6-1 TargetIR 设计草图 -> S6-6 双后端数值对齐测试目录  S6-6 对拍用例矩阵直接消费 S6-1 的 TIR 节点与 DType; 三方(Interp/Cranelift/LLVM)比对
S6-6 双后端数值对齐测试目录 -> S6-7 原生入口集成方案  S6-7 将 S6-6 的对拍矩阵作为端到端验收; 默认 Interp 零回归
并发前缘形态 (fist-allmodes/fist-opt-20261016/tnr-polish) -> 任务台账口径 (状态机形态决定推进语义)  R205-209 实证：三前缘任务台账形态各异 —— fist-allmodes 121 任务/3 档(待领取/已领取/已完成 直连)、fist-opt-20261016 21 任务/6 档(含拆分中/执行中)、tnr-polish 8 任务/仅待领取(agent 绕开任务台账直接干活)。形态差异提示「claim≠progress」的根因：已领取冻结 DAG 链上就绪集(dag_ready 11→2)。
