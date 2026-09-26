# FIST-Mbt 打磨收尾汇报：issue_scan 规则驱动源码扫描

- 日期：2026-09-26
- 阶段：打磨收尾（暂停新增机制，全力查漏补缺）

## 结果摘要
1. **深度审计无真缺陷**：ocr-local（兄弟项目）静态规则命中全为误报/安全模式；17 处高危边界抽查（除零/越界/unwrap/子串）全部安全；Kahn 拓扑、rows[0]、MC 统计、Phi、gate 均有守卫。既有 JS 后端 317/317 为权威门槛。
2. **新增 `issue_scan` MCP 工具（104th）**：把「找目标项目潜问题」固化为 fist-mbt 自身能力——内建 10 条 MoonBit 高危规则，递归扫描 .mbt，产出 findings + 聚合；命中可直接喂 `report_bug` 形成"扫描→上报→修复"闭环。免外部二进制、无绝对路径硬编码。**三形态齐全**（MCP 工具 + `scripts/issue_scan.py` CLI + `docs/issue-scan-skill.md` skill，扫描逻辑单真源在 MoonBit）。
3. **降噪打磨**：`include_tests`（默认 false）只扫产品代码跳过测试文件——src 扫描 105文件/207命中 → **65 文件 / 87 命中**（high 25→8、string-index 108→18），工具聚焦产品代码、可信度大增。
4. **自举演示**：用 fist-mbt 自身生命周期（publish_parallel → task_plan_deep 递归拆解）编排打磨工作，MCP 链路真实可调。
5. **全绿**：`moon test --target js -j 1` 317/317；`mcp_smoke.py` PASS（104 工具 + issue_scan 命中校验）；守卫族 check_tools(104)/test(317)/scripts_index 全 PASS。
6. **决策分支模块**（打磨方向：功能太多难决策 / 复杂多任务不知用哪些功能）：新增 `laya_route` 纯计算模块 + 扩展 `laya_decide`——有 Laya→sidecar 决定难度/机制；无 Laya→规则式确定性分支（关键词打分选 `feature_route` + 复杂度启发式 `split_n`）。无新工具（避免计数 churn）。
7. **issue_scan 挂进无人值守**：`templates/cron_pipeline_meta_prompt.md` 模板注入「分支④先 issue_scan 找潜问题 → 真缺陷 report_bug(publish_task=true) 自动发布修复根任务」，找潜问题成无人值守常态。
8. **Agent Contract 7 字段注入自驱任务**（five-directions P1）：`sd_agent_contract` 纯函数 + `selfdrive_publish_next` 接入——每个自驱发布根任务带 Objective/Constraints/Tool policy/Stop/Escalation/State/Evidence 执行契约，强化自驱执行纪律、零回归。

## 资源消耗
- 代码新增：`src/server/issue_scan.mbt`（~290 行）+ `issue_scan_test.mbt`（4 测试）+ `src/server/laya_route.mbt`（决策分支）+ `laya_route_test.mbt`（5 测试）+ `sd_agent_contract`（契约注入，ops_selfdrive）+ 契约测试
- 修改：`server.mbt`（注册 +1 工具 + include_tests 参数 + laya_decide 扩展）、`mcp_smoke.py`（+issue_scan 校验、104）、`scripts/issue_scan.py`（CLI）、`ops_selfdrive.mbt`（契约注入）、`AGENTS.md`、`docs/agent-map.md`、`docs/deliverable.md`（+功能轮 70）、`templates/cron_pipeline_meta_prompt.md`（issue_scan 接入无人值守）、memory 快照
- 测试：317（307→317，+10）

## 任务分配记录
- 深度审计子代理（general-purpose, 0ff2e232）：17 处高危边界判定安全
- 我（指挥官）亲读：registry rows[0]、engine Kahn 拓扑
- 我（指挥官）实现：issue_scan 纯逻辑 + include_tests 降噪 + 测试 + CLI/skill 三形态 + 注册 + 文档校准 + 自举演示

## 遗留风险
- `issue_scan` 为字面量 needle 匹配（非正则/语法树），存在误报与漏报：命中需 agent 读上下文判真伪（与 ocr-local 一致的模式）；`unprotected-division` 等规则对已守卫除数仍会命中（如 `if total>0` 内 `/ total`），需 agent 判定
- skill 形态为站内文档（docs/issue-scan-skill.md），未打包进外部 agent 技能注册系统（.codeartsdoer/skills 为空）——可后续用 skill-creator 固化
- Windows native 竞态（`-j 1` 缓解）、node:sqlite 实验性警告——既有遗留

## 后续建议
- 把 issue_scan 挂进无人值守流水线（pipeline_tick/watchdog_tick 的分支里扫描+上报），让"找问题"成为常态自驱行为
- 用 issue_scan 扫一次真实兄弟项目目录（ocr-local 的 MoonBit 包），验证跨项目泛化
- 沉淀规则到 memory/research/，形成可扩展规则库（rules_file 参数已预留）

## 超额内容
- 无（严格按打磨收尾边界）

## 来源
- ocr-local 规则：e:\IDEProjects\AI\ocr-local\rules\moonbit-rules.json
- 本仓库：memory/2026-09-26.md、src/server/issue_scan.mbt、docs/deliverable.md
