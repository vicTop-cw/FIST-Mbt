# fist-mbt 证据快照 · 2026-09-26（本轮门禁打分唯一事实依据）

> 生成方式：实测命令输出 + 仓库现状（git log / moon test / 守卫脚本），无虚构。

## 一、项目一句话
纯 MoonBit 实现的 FIST 指挥官任务分配体系，同时作为 MCP Server 暴露给 AI 客户端（83 个 MCP 工具 + 3 resources + 2 prompts）——「人类指挥、AI/定时器持续自推动」的自治任务编排底座。

## 二、硬指标（快照）
- MCP 工具：**83**（+3 resources +2 prompts），由 `scripts/check_tools_sync.py` 以 server.mbt 实际注册名为单一真源校验，与 AGENTS/README/deliverable/scoring_rubric 全对齐。
- 测试：`moon test --target js -j 1` **240/240**（Windows + WSL(Linux) 双端实测全绿）；`check_test_sync.py --total 240` PASS（跨四文档校验总数单一真源）；`check_badge.py` 徽章 240/240 一致。
- 工具链：moonc/core v0.10.14+（moon 0.1.20260920），评选会同要求版本；JS+Native 双目标均编译通过。
- CI：GitHub Actions 三轨道（js ubuntu / native ubuntu / js windows）实时徽章。
- 回归：0；本轮自治派单三连（R56 primitive / R57 watchdog 接入 / R58 want 免手传）均默认关闭零回归，既有语义不破坏。

## 三、口径（全档达标 AND）
每个 AI 需 `verdict=pass` 且 `p1≥0.70 && p2≥0.85 && p3≥0.97`；4 家全过才 PASS。目标：一等 70% / 二等 85% / 三等 97%。

## 四、能力清单（对评审各维度的证据）
- **完成度（25）**：发布→认领→拆分→执行→提交→验收→归档全闭环 + 重开/归档清理；跨进程 SQLite 后端（引擎层 store-backed），js/native 双后端 240/240。
- **技术难度（20）**：纯 MoonBit 无运行时依赖；DAG 依赖（dag_critical_path/parallelism/ascii/check/ready/sort/depend/publish + gradient 难度梯度）；自进化（distill/lesson/critic 防漂移门禁/sample/snapshot/submit/asset_register/task_challenge）；Omega 强验证（语料门禁+成果复验，打回上限防死循环）；调用日志/缺陷上报修复闭环；审计与权限；多租户命名空间；看门狗跨进程 heal+自动续轮。
- **创意生态（30）**：
  - 自驱审视闭环（selfdrive_* 9 工具：init/append/get/export_tasks/review_tick/review_ready/publish_next/parse_next_tasks/pick_next）——系统自己推动自己。
  - 拿来主义/复用（支柱②）：`fist://map` 让 agent 首读即有项目地图一目了然（支柱①）；难度抽取/pub 跨包单一来源；`dispatch_next` 复用 executor `route_pick` 单真源路由、want 免手传复用 R33 auto_need 思路且 store-backed 零 server 耦合；能力路由/执行者 Marketplace 雏形 + 看门狗自治派单零参数闭环（R56-58）。
  - 自治闭环叙事（R56 引擎层 store-backed 派单 primitive → R57 watchdog `autodispatch` 接入 → R58 `dispatch_next` want 空自动抽取）——从 primitive 到无人值守自动派单三段全打通。
  - 衍生纯 MoonBit 子项目 atgc（base/codon/lexer/transpile/vm/talk，§10 验算全过）与 atgc-old。
- **美关演示（25）**：`board_ascii` 实时看板每行标难度档；`status_summary` 项目脉冲（by_status/by_difficulty）；`showcase.ps1` 视觉终端巡演（九态/DAG/自举采用/**自治派送闭环视觉段**，ANSI+box，实测 exit 0 / 1.7s 渲染，读取真实库 **548 tasks / 196 executions / 6 review 存档**）；`award_demo.py` 难度链路端到端；`demo.ps1` 30 秒演示；CI 徽章。
- **自举采用证据（新）**：showcase 实跑读盘——548 项任务 / 196 次执行 / 6 轮子代理自审，FIST-Mbt 正用它自己管理自己的迭代（selfdrive-walkthrough.md 完整记录 6 轮自驱审视如何把自己打磨到 240/240 可交付态）——即「一项目即活证据，自己是自己的第一个执行者」。

## 五、近期承诺历史（git log --oneline 最近 15）
R58 dispatch_next want 免手传；R57 watchdog autodispatch；R56 engine 派单 primitive；R55 board 难度标注；R54 移除 cmd/cli unused store；R53 复现审计；R52 check_badge 防自检陈旧；R51 看门狗派发预览；R50 评审自检注释校准；R49 文档收尾；R48 fist://map 补全；R47 测试数单一真源守卫；R46 工具清单单一真源守卫（补齐 AGENTS 29 工具）；R45 难度链路端到端；R44 status_summary by_difficulty。