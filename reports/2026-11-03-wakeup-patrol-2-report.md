# 2026-11-03 · 唤醒轮巡检 2（BUG-565 发现 + B 半修复验证 + A 半挂 owner）· 报告

## 结果摘要
本轮不是零改动巡检：上轮观察到的「另一 agent 的 WIP」里藏着**对方自书的引擎 bug 报告**（vq 勘误）⇒ 立 **BUG-565（OPEN，新账挂起待入账）**。两症状：
- **A 跨项目账本误落**：根因是设计边界（server cwd 被 launcher 钉在 REPO + 绝对路径被 fail-closed 拒绝）⇒ 三案决策单挂 owner（推荐 B 白名单案）。
- **B 网关静默失败**（`FIST_MBT_REPO` 指无网关项目 ⇒ `fist-mbt call` rc=1 **零输出**）：指挥官本轮修毕——2 行补丁在仓内副本完成语法 + 复现 + 回归三重实测；部署回拷一条命令因审批门禁（`writes outside the workspace` 未批）挂起，不重试。
Round C 队列维持全灭（复核无变化）；3 条旧 OPEN（527/538/542）仍全 owner 门控；WIP 自 00:23 起冻结。

## 巡检读数
| # | 面 | 读数 | 判定 |
|---|---|---|---|
| 1 | WIP 活性 | `memory/bugs.md` mtime 仍 00:23；diff +131→+138 行（00:23 补 BUG-564 + 两段勘误 + 1 段 FIXED 状态节） | 冻结，对方 agent 空闲 |
| 2 | WIP 内容定性 | 21 条外来条目（BUG-544~564，本仓路径零命中）+ 对方自书勘误「保留本树、append-only、以勘误为准」+ 已搬移 vq 仓 | 污染风险从「预测」升级为「已定性 + 对方已声明处置」 |
| 3 | AGENTS.md WIP | 1 行：判例指针 32~42→32~43 | 已核对判例-43 存在（`docs/AGENTS-precedents.md:260`）⇒ 指针一致，无害 |
| 4 | 预算尺 | `check_instruction_budget.py`：AGENTS.md（WIP 版）50,239 字节 PASS | 无截断风险。注：尺自报预算 65,536，AGENTS 散文写 65,244（差 292B）——以尺为准，未动（散文面属 WIP 文件，禁区） |
| 5 | 计数面漂移 | `bug_list` 工作树实测 `count=550` vs AGENTS 现状面 528 | WIP 已在漂（21 外来条目 + 解析面差 1）；cl7 探针本轮被门禁误判拒（见 §新观察） |

## BUG-565 验证读数（B 半，全实测）
| # | 检查 | 读数 |
|---|---|---|
| 1 | 修前复现（FIST_MBT_REPO=vq，`call bug_list`） | rc=1，**0 字节**（`temp/bug565_prefix_out.txt`）——与对方勘误描述吻合 |
| 2 | 补丁面 | 2 处（quiet 对 FATAL 放行 + spawn 失败补 FATAL 前缀），仓内副本 `temp/serve-launcher-patched.cjs`，底本 `temp/serve-launcher-orig.cjs` |
| 3 | `node --check` | PASS |
| 4 | 修后复现（同命令） | rc=1 + **82 字节自述** `FATAL gateway not found: E:\IDEProjects\AI\vq\scripts\fist.py` |
| 5 | 回归 `version`（CLI 路由） | rc=0，v0.3.11 |
| 6 | 回归 `call bug_list`（默认 REPO） | rc=0，370,440 字节，`resolved_path`/`server_cwd` 正确 |

## 新观察
- **审批门禁误判**：无凭据的 `python scripts/check_plugin_sync.py`（cl7）被判 `bash (credential access)` 拒。cl7 读数本轮缺位；**复发即立账**（守卫族被无声缩小 = 判例-33 同族）。
- 部署副本 launcher 在 repo 外（BUG-470 R4 既定事实）⇒ B 半生效以「审批过的回拷」为前提，生效前 vq 型调用方仍会撞 rc=1 零输出。

## 任务分配记录
- 无 MCP 任务发布 / 无子代理委派：B 半为指挥官执行的部署面小修（2 行 + 验证闭环，委派反而引入无 shell 成员无法验证的断层）；A 半属安全设计决策，按角色边界出决策单挂 owner（`reports/2026-11-03-bug565-project-dir-decision-sheet.md` §4）。
- 记账：BUG-565 入账文本已备（决策单 §6），**挂起**——`memory/bugs.md` 与 AGENTS 计数面均在 WIP，`git commit -- <path>` 会连带提交 21 条外来条目污染计数面；WIP 收口后同批入账 + 计数面 + `gen_plugins` 投影。

## 遗留风险
1. launcher 部署未打补丁（B 半未生效于生产）——部署命令已备好（决策单 §3），一条审批即可落地。
2. WIP 收口后 21 条外来条目「永久保留本树」（对方勘误声明）⇒ 计数面必重裁（决策单 §5.2 三候选），裁决前计数面维持现状。
3. 审批门禁对守卫族命令的误判若复发，巡检探针面被无声缩小。
4. 3 条旧 OPEN 维持 owner 门控（BUG-527 上游 issue / BUG-538 连接器重连 / BUG-542 A-B 裁决），无变化。

## 后续建议
1. **owner 一句话裁决 BUG-565 §4**：A/B/C 三选一（推荐 B 白名单案）——B 通过即派子代理执行 + 终审。
2. **owner 裁决计数面**（§5.2 候选 i/ii/iii）：与 WIP 收口联动。
3. 下一轮：WIP 已收口 ⇒ 同批入账 BUG-565 + 计数面重投影 + 补 cl7 读数；未收口 ⇒ 补 cl7 探针（若门禁恢复）+ 观察 WIP 是否复活。
4. 若门禁误判复发 ⇒ 立账（守卫族被门禁误吞）。

## 超额内容
无。

## 来源
- 盘面：`git status` / `git diff --stat` / WIP 只读核对（bugs.md +138 行、AGENTS.md 1 行、warning-ledger 26 行）
- 代码面：`src/server/bugreport.mbt`（29-46/310/327/435-440/525-528）/ `%LOCALAPPDATA%\FIST-Mbt\serve-launcher.cjs`（quiet/runGateway/runChild）/ `scripts/fist.py`（247-251 spawn 无 cwd 注入、stderr=DEVNULL）
- 判据（本轮实跑）：`check_instruction_budget.py` PASS；`bug_list` 经 launcher 副本实调（count=550）；`cl7` 被门禁拒（缺位）
- 证据件（本地 temp/，gitignore 面）：`bug565_prefix_out.txt`（0B）/ `bug565_postfix_out.txt`（82B）/ `serve-launcher-orig.cjs` / `serve-launcher-patched.cjs`
- 决策单：`reports/2026-11-03-bug565-project-dir-decision-sheet.md`
- 日期：2026-11-03
