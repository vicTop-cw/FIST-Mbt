# 获奖提升 · R16 汇报：获奖自驱 DEMO（一条命令串演增强能力链）

> 日期：2026-09-25｜目标 pillar：结构化项目（让 agent 读项目一目了然）＋ 计划性增强（递归拆解）＋ 项目整洁；并兑现"自我迭代过程需作为 DEMO 呈现"硬要求。

## 结果摘要
- 新增 `scripts/award_demo.py`：**一条命令（`python scripts/award_demo.py`）串演 15 轮自驱增强叠加的完整能力链**，作为评审直接可跑的 DEMO：
  ① `tools/list=77` → ② `fist://map`（先有地图，agent 首读即定位） → ③ `store_open(scratch)` 独立命名空间 → ④ `task_plan_deep(gradient=true)` 难度梯度递归拆解 → ⑤ 认领→执行→提交→验收闭环 → ⑥ `task_challenge`（Challenger 上难，`[challenge]` 溯源 + 重要度升档） → ⑦ `evolve_critic`（Critic 防漂移评审） → ⑧ `reserve_scope/check`（多 agent 并发预订） → ⑨ `status_summary` + `board_ascii`（项目脉冲 + 实时看板）。
- **自洽整洁**：脚本结尾自动跑 `cleanup_artifacts.py` 删临时区，再加 `--check` 守卫"仓库根仅 fist-mbt.db、temp/ 无残留"。
- 实证输出（一次实跑）：递归拆解 3 子任务叶带难度梯度；生命周期→已完成；Challenger→新根 `[challenge]` 重要度升"高"；Critic→放行（L4，新颖度 84%）；预订 `held_by=exec_demo`；`status_summary` 总 11；`board_ascii`≈13 行；**MCP-AWARD-DEMO PASS** + 结尾 **CLEAN**。
- 验证：`moon test --target js` **215/215** 全绿（本轮仅新增脚本，无源码改动）；工具数保持 **77**、测试数保持 **215**。

## 资源消耗
- 新增：`scripts/award_demo.py`（纯标准库，MCP STDIO 链路，约 130 行）。
- 修改：`scripts/README.md`（登记 award_demo.py）；`memory/2026-09-25.md`（R16）。
- 演示落数据：命名空间 `award-demo` 一簇任务写入交付库 fist-mbt.db（作为评审可查的自我驱动轨迹），临时库结尾自动清除。

## 任务分配记录
- 直接实现（指挥官终审制）：DEMO 串联既有工具，无需新能力；实机验证一条命令全链路 PASS + 结尾 CLEAN（金条八）。未走 FIST 任务循环（纯编排脚本）。

## 遗留风险
- DEMO 在生命周期工具上使用的是引擎默认库（命名空间仅作元数据），因此演示任务落的是交付库 `fist-mbt.db`，会随演示累加任务（属"自驱轨迹留痕"预期）；若评审机器不希望累积，可用 `moon test` 之外的独立命名空间或手动清理。
- 演示的"叶子任务带难度梯度"依赖 `gradient=true`，模板化标注（位置三分档），非按真实体量估计（既有 R12 取舍）。

## 后续建议
- 下一可借力点：
  1. **难度校准**：把 `decide_difficulty` 接进 `task_plan_deep gradient` 标签，让拆解难度更真实（小能力增强）；
  2. **测试落盘收敛到系统 tmp**（`@fs.tmpdir`），从源头杜绝生成物（中等改造，可选）；
  3. **Marketplace / Dynamic 能力路由**（远期）。

## 超额内容
- 结尾的 `cleanup_artifacts.py --check` 自动守卫让 DEMO 即演示又自证"仓库整洁"，评审无需手动清理。

## 来源
- 串联工具：`task_plan_deep`(R12)/`task_challenge`(R14)/`evolve_critic`(R13)/`reserve_*`(R10)/`status_summary`(R8-R9)/`board_ascii`(R7)/`fist://map`(R1)/`cleanup_artifacts`(R15)。
- 代码：`scripts/award_demo.py`、`scripts/README.md`。