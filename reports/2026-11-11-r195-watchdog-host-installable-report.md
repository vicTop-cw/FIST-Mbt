# 唤醒巡检轮 2026-11-11 · Round 195（ExploreWatchdog）

## 结果摘要
- **并发 WIP 仍卡 ≈ 4h，r193 后无 owner 裁决，按 r194 建议维持「已知挂起等裁决」不重复上报**：
  - 本轮时点 18:34，5 份承重 WIP 文件 mtime 仍冻结在 **14:29~14:35**（与轮 193/194 现读逐字节相同）；
    `git log 738831411..HEAD` 为空（**r193 报告后零新提交**），`git status --short` 仍 15 tracked M + 5 untracked
    （同一份 WIP：BUG-583 测试 + `e2e_acceptance_recheck` + `run_guards` + 12 文档，未收口、未推进）。
  - 轮 193 已把该项定量坐实为「mtime 硬证据卡死」并升级 owner 决策（A 持有会话接手 / B 交指挥官代收口 /
    C git stash 清场 / D 确认挂起）；轮 194 起已**停止逐轮重复上报**同一份静止 WIP——本轮维持该状态位，
    不重推导、不重复展开。
- **换面巡检（本轮真换面 = r194 点名的 `check_host_installable`，避开已探过的 OFM / byte-slice / mcp_smoke 三面）**：
  - **宿主可装性守卫**（`scripts/check_host_installable.py`，cl7 的补丁）：
    - `--selftest`：**SELFTEST OK**，rc=0（DSH 严格档：相对路径 / `timeout_ms` / reconnect 键名 / 未定义占位符
      必红；干净 DSH + 默认模板 + 宽松档 不误红；输入面退化自拒；字段白名单反解自真源）。**尺没坏**。
    - 全量判据：**PASS**，rc=0。三条**信息级 WARN**（不计入 exit 1）：`.mcp.json` / `.mcp.dev.json` /
      `plugins/claude/.mcp.json` 的 `fist-mbt` 用 `timeout_ms`——D2 宽松档合法键，部分客户端按自身 schema
      忽略该字段，「是否改真源由人终审」。⇒ **非新缺陷**，属守卫设计内容忍面。
  - **AGENTS.md 字节预算**（`scripts/check_instruction_budget.py`，因 AGENTS.md 正在 WIP 里被改，顺路核一眼）：
    **PASS**，rc=0——`AGENTS.md = 50303 字节 / 预算 65536（实际注入上限 50303），全部章节可见`。WIP 态下预算面健康。
- **本轮无新缺陷入账**（无新 BUG）。`timeout_ms` 三处 WARN 属 D2 宽松档合法态、不立账（立账即恒挂装饰单）；
  仅在「遗留风险」点一句给 owner 知情。

## 为什么这轮不算空转
轮 194 的「后续建议」明确为 Round 195 定了面——**换 `check_host_installable`（或 NUL-byte 专项），避开已探过的
OFM / byte-slice / mcp_smoke 三面**。本轮正是执行它：跑了 r188~194 从未探过的**宿主可装性真面**（含 selftest
证尺可红可绿 + 退化自拒），并顺路核了 WIP 态下的 AGENTS.md 字节预算。两个新面都给出真实读数
（host_installable = PASS rc=0 + selftest OK / 字节预算 = PASS），而非再跑已收敛的 mcp_smoke（memory 记同源
PASS，勿空转）或再复读同一份静止 WIP。

## 资源消耗
- ~8 次 bash（git status / log / rev-list / mtime 现读、ledger + guards 核读验证 memory 三项过期论断、
  check_host_installable selftest + 全量、check_instruction_budget 真跑、fist.py 网关 publish→acl_grant→
  claim→execute→submit→verify 全链）；无子代理（读态 + 探活 + 单命令记账属指挥官本职）。

## 任务分配记录
- 无派发。FIST 闭环记账（ns `iter-1111r195w`）：publish T0（`project-dir` 必填）→
  `agent_acl_grant(commander, ns=iter-1111r195w, can_write)`（BUG-411 两道独立门，ns 库隔离）→
  claim → execute（deliverable=本发现）→ submit（显式 `agent=commander`）→ verify（`verifier=commander`）
  ⇒ T0 `已完成`（completed_by=commander）。
- **本轮实证/复证网关细节（供后续唤醒轮少踩坑）**：claim / execute / submit / verify 四步**除身份键
  （claim=assignee、execute=agent+deliverable、submit=agent、verify=verifier）外，还必须带 `--task-id T0`**
  ——记忆里的「身份键」只说清了「谁」，没说清「哪个任务」；本轮首跑漏 `--task-id` 被网关 required 自纠当场点出
  （`missing required property: task_id`），补上后全链收口。publish 仍走 `human_steward` 特权路径（回执 WARN
  提示 claim 会被 ns ACL 拒，故 claim 前必先 acl_grant）。

## 遗留风险 / 待 owner 决策
1. **并发 WIP 已知挂起（等裁决，≈4h）**：15 tracked M + 5 untracked（BUG-583 测试 + `e2e_acceptance_recheck`
   + `run_guards` + 12 文档），mtime 冻结 14:35、HEAD 仍 `738831411`（r193 后零新提交）。轮 193 已列 A~D 四案，
   **待 owner 任一裁决**；本轮维持「已知挂起」状态位、不重复上报（除非 owner 给出 A~D 裁决或 mtime 再次移动）。
   裁决前本仓纪律仍不碰该 WIP（禁区：不 commit / stash / 改动 / 丢弃）。
2. **`timeout_ms` 三处信息级 WARN（知情项，非账）**：`.mcp.json` / `.mcp.dev.json` / `plugins/claude/.mcp.json`
   的 `fist-mbt` 用 `timeout_ms`，D2 宽松档合法、部分客户端按自身 schema 忽略。是否改真源（换 `toolCallTimeoutMs`
   或保留）属 owner 接线终审，未代改。
3. **本地领先远端 128 commit（历史积压，知情项）**：`git rev-list --left-right --count origin/main...HEAD` =
   `0 128`（远端 main 全包含在本地，本地多 128 个未推）。**非本轮要处理的面**——推 128 个 commit 是 owner
   决策（且当前有并发 WIP 挂起，推送面归属需 owner 定），看门狗巡检职责内不擅自推。
4. OFM 端点 18326 vs 18899 配置漂移（轮 194 已记知情项）/ master 镜像无自动化维护（R180 已知态）——维持原状，不重复展开。

## 后续建议
- Round 196：继续**换面**（下轮拟 **NUL-byte 专项**——r194 列的两个 r195 候选里 check_host_installable 已用，
  留 NUL-byte 给下一轮；或视 owner 对 WIP 的裁决转向收口协助），避开已探过的 OFM / byte-slice / mcp_smoke /
  host_installable 四面；并发 WIP 维持「已知挂起等裁决」不重复上报，除非 owner 给出 A~D 裁决或 mtime 再次移动。
- 若 owner 认可「`timeout_ms` 应回正 / 该常驻告警」，把三处 `fist-mbt` 的 `timeout_ms` 校正（或把
  `check_host_installable` 对 `timeout_ms` 从 info WARN 提级）——owner 决定，未代改。

## 超额内容
- 无。

## 来源
- 用户 prompt（Windows 计划任务 FIST-Mbt-ExploreWatchdog 每 30 分钟唤醒）+ AGENTS.md 提交纪律 +
  轮 194 报告（`reports/2026-11-11-r194-watchdog-ofm-byte-report.md`，含本轮「换面 = check_host_installable /
  NUL-byte」指令与「停止重复上报」指令）+ 5 份 WIP 文件 mtime 现读 + `git log 738831411..HEAD` +
  `git rev-list --left-right --count` + `check_host_installable.py`（selftest + 全量）/
  `check_instruction_budget.py` 真跑读数 + `fist.py` 网关全链回执 + memory 唤醒轮记账
  （Round C 队列过期：BUG-530 已修 / check_usage_tool_count 已注册 run_guards.py:175 / BUG-527 摘 cc-link-flags
  被 owner 否决回滚 e0ef45c5e）。
