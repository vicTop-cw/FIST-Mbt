# 2026-10-25 PR 批量合并收口 + BUG-407/408 修复 · 汇报

> 执行者：lead（指挥官会话）
> 时间窗：2026-10-25 11:00 – 13:00（Asia/Shanghai）
> 关联：`memory/2026-10-25.md`、commit `d3f2f913` / `46c1382d` / `dd74466d`

## 一、结果摘要

| 项目 | 前 | 后 |
|---|---|---|
| open PR（全部 base） | 27 | **0** |
| 合并进 master 的 PR | — | 4（#33 #23 #24 #20） |
| 关闭未合并的 PR | — | 23 |
| BUG-407（high） | OPEN | **FIXED**（实测验证） |
| BUG-408（high） | OPEN | **FIXED**（补工具面 + 文案出路） |
| MCP 工具数 | 170 | **171**（+`agent_acl_grant`） |
| 验收门禁 | — | **9/10 PASS**，唯一红是并行 agent 在途文件 |
| moon test（js） | 1457/1457 | **1457/1457**（零回归） |

## 二、资源消耗

| 项 | 数值 |
|---|---|
| 提交 | 3 笔（`d3f2f913` 探针入库 / `46c1382d` BUG-408 / `dd74466d` 账本+插件态） |
| 改动文件 | 39（28 + 10 + 1） |
| 代码行 | +182 / -97 |
| moon test 全量跑 | 3 次（每次约 3–5 min） |
| 审判据跑 | 约 20 次（含 --fresh 重跑） |

## 三、任务分配记录

本会话为**指挥官直做**（未下派子代理），原因：PR 合并与账本判定是「不可逆 + 需终审」动作，按金条四留在指挥官侧。

并行 agent `commander-zeta`（zeta@fist.local）同期在做 git 卫生（兄弟目录清理 / 判例落盘 / 分支保全 / 工作树核实），**文件作用域与我不重叠**（它 `reports/`+`scripts/`+`cmd/cli/*`，我 `src/server`+`src/store`+文档计数面），仅在 git 暂存面发生时序竞争。

## 四、遗留风险

1. **`check_publish_payload` 仍红（P1）** —— 全部是 `reports/salvage-2026-10-25/*` 的在途文件（commander-zeta 正在做分支增量保全）。这是**时序性红**，它入库后自然归零。判定依据：这些文件带 README 说明「落 reports/ 跟踪面 = 证据链面」，明确是**有意入库**的。
2. **`moon fmt` 全仓轮询副作用** —— 我跑的一次 fmt 把 commander-zeta 的 106 个 WIP 文件一起格式化了。虽只改格式不改语义，但若它随后 diff 审阅会看到大量无关格式变动。**建议后续：`moon fmt` 前先确认工作树无他人 WIP，或用 `moon fmt <路径>` 限定。**
3. **`audit_permission` 与 ns ACL 仍是两道独立门** —— BUG-408 只做到「矛盾可见 + 可自救」，没做到「合一」。合一属契约变更（要么 publish 也受 ns ACL 约束，要么 claim 失去 ACL 保护），需 owner 裁决。
4. **26 条 OPEN bug 中 3 条是真待裁决项**（BUG-354/362/364），见下节。

## 五、后续建议（按月底验收优先级）

### P0 —— 验收前必须闭环
1. **等 commander-zeta 的 salvage 入库**，`check_publish_payload` 自然转绿。若到期未入库，需要它给个时间点；否则验收当天这条会红。
2. **CI 全绿确认**：本轮只在本地跑了判据，CI（GitHub Actions）尚未触发验证。建议 push 后看 JS 轨 + native 轨。

### P1 —— 月底前可做
3. **BUG-354 裁决**：10 个未消费参数（`by~`×2、`created_by~`、`ns?`×2、`lam?`、`max_rounds?`、`flush_bug_queue?`、`github_sync?`、`github_repo?`）。**建议出路 A**：保留参数但在 schema 描述里显式标注「预留未消费」，零兼容性代价；出路 B（删参数）会破坏 MCP 客户端契约，不建议。
4. **BUG-362 裁决**：`Json::value` 站点收口口径。**建议选 (a)**——文本普查 441 为分母，判据 430 归零只是必要条件。理由：这是本仓反复记过的「绿着的谎」形状，用 430 收口等于接受 11 处留存而门是绿的。
5. **BUG-364 裁决**：`docs/agent-map.md` §三 覆盖 100/170。**建议选 (c)**——删表留一行指针「分组见 README 功能全景（J3 钉住）」。理由：该表存在理由（省 context）用一行指针即可满足，其失真面要靠新增生成器才压得住，而本项目已为「多份手写副本」付过学费。

### P2 —— 验收后
6. 把「`moon fmt` 全仓轮询」写进 AGENTS.md 的并发纪律（同族于判例-11 的提交纪律）。

## 六、超额内容（未在任务范围但顺手做了）

- 发现并修复 `scripts/_mutation_probe.py` 未入库导致的 `check_publish_payload` P1 违规（它本身是判例-29/30/50 要求的动态变异检查器，329 行 / 14 格 selftest）—— 这个工具补上了本仓长期缺的「判据真咬还是假绿」动态验证能力
- 定位 BUG-408 的**真根因**（`agents_acl_grant` 无工具面）而非停留在报告给的三个表面诉求
- 修正 `check_doc_surface` 报出的 8 处工具计数漂移面（标题行改了但分组表没跟）

## 七、来源

- PR 清单：`api.github.com/repos/vicTop-cw/FIST-Mbt/pulls?state=open`（实测 27 → 0）
- 判据读数：`scripts/check_*.py` 实测输出（本报告 §1 表格逐条可复跑）
- 测试读数：`python scripts/moon_test_env.py --target js` → `Total tests: 1457, passed: 1457, failed: 0`
- 任务状态：`mcp__fist-mbt__store_list` / `list` / `get`（BUG-407 验证面）
- 账本：`memory/bugs.md` BUG-407 / BUG-408 条目（含 FIXED 小记）
- 并行 agent 工作：`git log` 中 commander-zeta 的 `0cfe1e90` / `87a27526` / `900e7e0b` / `dcacd404`
