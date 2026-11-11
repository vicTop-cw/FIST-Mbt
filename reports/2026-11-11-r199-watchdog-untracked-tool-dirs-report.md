# 轮 199 唤醒巡检报告（untracked 工具目录换面 + 外部产物 ignore 打磨 + r198 报告补提交）

- **时间**：2026-11-11 21:00（UTC 13:00 记账）
- **轮次**：r199（ExploreWatchdog）
- **前序**：r198（其报告本轮补提交为 abd576c30）

## 并发 WIP 状态

| 项 | 读数 |
|---|---|
| mtime（承重 3 文件） | `src/server/mcpcf_embed_bug583_wbtest.mbt` 14:29 / `scripts/run_guards.py` 14:33 / `AGENTS.md` 14:34（本轮实测）|
| 冻结时长 | ~6.7h（14:35 → 21:00）|
| diff 足迹 | 与 r198 基线一致（15 文件 +281/−64，无暂存）|
| 新提交 | r198 报告补提交 abd576c30；r193 738831411 后仍零功能性提交 |
| 状态位 | 已知挂起，r193 已升级 owner 决策，按既定不再重复上报 |

**禁区遵守**：WIP 的 15 个文件本轮未 touch（只读 + `git status`/`git check-ignore`/`git ls-files` 观测）。
`.gitignore` 不在 WIP 足迹内，故本轮 ignore 打磨不触碰并发 WIP 的收口面。

## Round C 队列

确认过期（r195/r196/r197/r198 已核实，不重复）：BUG-527 owner 否决（e0ef45c5e 回滚）/ BUG-530 已 FIXED（3699f012a）/ check_usage_tool_count 已注册（run_guards.py:175）。

## 换面巡检：untracked 工具目录面（r194–198 未扫过的新面）

**为什么换这一面**：r197 只扫了 stray DB，r198 只看了 WIP diff 足迹；`git status` 里那批
`.aider.*` / `.qoder/` / `.workbuddy/` untracked 项**前几轮都没单独定性**。本轮补这一面。

### 先纠一个误读（本轮自纠）

初看 `git check-ignore -v` 输出，曾误判 `.qoder/`、`.workbuddy/`「已 ignore」（它打了两行命中、
却又 rc=1）。用 **ground truth**（`git status --porcelain --ignored` 逐路径 + `git ls-files --others
--exclude-standard`）复核：**这五项本轮之前一个都没被 ignore**（全部 `??`）。`check-ignore` 那两行
是格式/行号 quirk（归到 `.gitignore:260` 空行），**rc=1 才是真相**。⇒ 判 gitignore 状态一律以
`git status --ignored` / `git ls-files --exclude-standard` 为准，别信 `check-ignore` 的行号自述。

### 各 untracked 项定性（复核后真相）

| untracked 项 | 复核前是否 ignore | 内容 | 定性 |
|---|---|---|---|
| `.aider.chat.history.md` / `.aider.input.history` | 否 | Aider 对话/输入历史 | 外部 AI 工具（Aider）机本地产物 |
| `.qoder/worktrees/agent-general-purpose-{04625cfe,14fed5fe,773233d4,bb4c9125,ff4ebfe9}/` | 否 | **5 个 Qoder agent worktree** | 外部 AI 工具（Qoder）机本地产物；`du -sh` 60s 超时 ⇒ 体量大（疑含完整 repo checkout）|
| `.workbuddy/memory/2026-11-03.md` | 否 | WorkBuddy 记忆文件（8 天前）| 外部 AI 工具（WorkBuddy）机本地产物 |
| `fist-mbt.db `（尾随空格、0 字节）| 否（不匹配 `*.db`）| r197 已定性 stray DB | 外部来源非代码缺陷，维持不立账不删 |

**判读**：四项（除 stray DB 外三组）全是**外部 AI 编码工具触碰本仓留下的机本地产物**，非本仓代码
缺陷 ⇒ 与 stray DB 同族，**不立账**。但**未被 ignore** ⇒ 持续污染 `git status` untracked 面（噪音）。

### 打磨动作（本轮已做 + 已验证）

项目对「本机工具产物」有**明确判例**：`.opencode/`（line 256-259，2026-11-02 治理）、watchdog 三件
脚手架（line 261-267，2026-11-09 治理）都是补 `.gitignore` 挡住、不删文件。本轮照判例对三组外部
工具产物补 ignore：

```
/.aider*
/.qoder/
/.workbuddy/
```

**验证**：`git status --short` 的 untracked 面里 `.aider*`/`.qoder/`/`.workbuddy/` 已全部消失（只剩
`fist-mbt.db ` stray）；`git check-ignore .aider.chat.history.md .qoder .workbuddy` 三路径全命中 rc=0。
`.gitignore` 不在 WIP 足迹，改动用 `commit_scoped.sh -- .gitignore` 单独收口，不与并发 WIP 抢面。

> 处置权说明：本打磨**只加 ignore、不删文件**（同判例），且 `.gitignore` 非 WIP 文件；若 owner 认为
> 某组产物应保留跟踪，删掉对应行即可回退（ignore 是可逆面）。

## 已探面汇总（避免重复）

| 轮 | 面 | 结果 |
|---|---|---|
| r194 | OFM 端点 + byte-slice | 容忍诊断 / PASS |
| r195 | check_host_installable + byte budget | PASS / PASS |
| r196 | NUL-byte（src+scripts）| 干净 |
| r197 | untracked / stray-DB | 1 项 0 字节异常（已定性，不立账不删）|
| r198 | WIP diff 足迹 + WIP 定性 | 15 文件 +281/−64 冻结、方向合法，半成品可评估 |
| **r199** | **untracked 工具目录 + ignore 打磨 + r198 补提交** | **三组外部工具产物（含 5 个 Qoder worktree）定性并补 ignore（已验证）；r198 报告补提交 abd576c30** |

## FIST 闭环

ns `iter-1111r199w`：publish（T0，BUG-411 两道门警告）→ acl_grant（wd-r199 can_write=true，
granted_rows 22f9ecb06436b7b1）→ claim（已领取）→ execute（执行中，deliverable 指本报告）→
submit（待验收）→ verify（**已完成**，completed_by=wd-r199）⇒ **全链绿，T0 收口**。

**网关 API 修正**（自纠实测，已回写 memory）：`claim/execute/submit/verify` 除 `--namespace` 外
**还必须显式带 `--task-id`**（缺了当场 `missing required property: task_id`）——memory 旧注只写
`--namespace`，漏了 `--task-id` 必填这一格。

## 结果摘要

- 并发 WIP 冻结 ~6.7h 无变化（15 文件 +281/−64），维持 r193 已升级 owner 的已知挂起，不重复上报。
- Round C 队列确认过期，无可执行项。
- 新面（untracked 工具目录）：三组外部 AI 工具产物（Aider 历史 / Qoder 5 个 worktree / WorkBuddy 记忆）
  定性为机本地产物（不立账），因未被 ignore 而污染 git status ⇒ **本轮照 `.opencode/` 判例补
  `.gitignore`（已验证生效、可逆）**；`fist-mbt.db ` stray 维持 r197 定性不立账不删。
- 补收 r198 上轮漏提交的巡检报告（abd576c30）。

## 资源消耗

- 模型：qwen3.8-27b（本会话）；工具：git（status/log/check-ignore/ls-files）+ `python scripts/fist.py`
  （FIST 网关 6 调用 + 1 次 task_id 自纠重试）+ 文件读写。未 spawn 子代理（本轮为巡检/记账/小打磨，
  无可分配实质工作——WIP 占用、Round C 过期；ignore 打磨是判例照办的单文件小改，直接收口比派单快）。

## 任务分配记录

- 本轮无子代理派单。原因：可分配实质工作（修 bug / Round C）全被并发 WIP 占用或已过期；本轮实质是
  「巡检新面 + 记账 + 收口漏提交 + 判例照办的 ignore 小打磨」，属指挥官亲自面（金条四：分流/终审/
  沉淀/汇报；ignore 单文件小改按判例直接收口）。

## 遗留风险

- WIP 挂起 ~6.7h（15 文件 +281/−64 成型未收口），等 owner A~D 裁决（不重复上报；r198 已给增量信息：
  BUG-591⑤/BUG-588② 加固面、方向合法量成型）。
- `fist-mbt.db `（尾随空格、0 字节）仍未跟踪未忽略：WIP 收口时建议一并清掉（本轮未删——外部产物、
  非缺陷，删不改本轮结论）。
- 本地领先远端 128+ commit（历史积压，推与否归 owner）。

## 后续建议

- 若 owner 判定 WIP 一路已死：直接评估收口那 281 行（r198 定性：方向对、量成型，不必作废）。
- ignore 面如需回退：删本轮在 `.gitignore` 加的三行即可（可逆）。
- 建议 owner 知会 Qoder/WorkBuddy/Aider 的使用方：这些工具的机本地产物已挡出 git 跟踪面，不再污染 status。

## 超额内容

无（ignore 打磨本身即为本轮针对新发现的具体动作，非超额；按「勿空转」未追加其它面）。

## 来源

- 本仓 `git status --short` / `git status --porcelain --ignored` / `git ls-files --others --exclude-standard` /
  `git check-ignore` / `git log --oneline` 实测（2026-11-11 21:00）。
- `python scripts/fist.py call` 七次回执（含 1 次 task_id 自纠）（2026-11-11）。
- `.gitignore` 实测（line 15 `*.db` / line 256-259 `.opencode/` / line 261-267 watchdog 脚手架判例）。
- r198 报告（reports/2026-11-11-r198-watchdog-wip-footprint-report.md）。
