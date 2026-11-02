# 2026-11-03 · 唤醒轮 3 巡检（WIP 双流定性 + bugs.md 收口警示）· 报告

## 结果摘要
WIP 仍未收口（bugs.md 自 00:23 冻结 ~1h40m）。本轮只读定性发现 WIP 是**双流混装**：司令-γ 的仓内还债批（git 沙箱 env 隔离 + warning 台账 48→50 + 判例指针）× vq agent 的 21 条误落（仅 bugs.md）。插件态 4 个 " M" 为 stat/EOL 残迹、零内容 diff。**收口警示（新）**：WIP 版插件 SKILL.md 计数面仍写 543/528，vs WIP bugs.md 564 抬头（实测 550）⇒ **bugs.md 若先提而计数面未重投影，cl7 当场红**。零代码改动、零新账。

## WIP 双流定性（只读，`git diff` 逐文件核对）
| 流 | 面 | 内容 | 归属判定 |
|---|---|---|---|
| ① 司令-γ 还债 | 4 把守卫脚本 | 5 处 git 子进程调用补 `env=isolated_git_env()`（check_reverse_diff×2 / simulate_head_commit×1 / whisperer×3 处函数）；`DIRTY_CEILING` 2→0（还债收口，judge_ratchet 常量律：债务还清常量改回 0，新尺忘隔离当场红） | 仓内合法 |
| ① 司令-γ 还债 | docs/warning-ledger.md | 48→50 条现算：新增 L10（`StringBuilder::new` @ executor_register_wbtest.mbt:41，**BUG-538 心跳判据夹具**，注明「当前正在 WIP」）+ L11（server/moon.pkg:20 async 预留依赖面）；旧 L1/L4/L6 行号重指；判据面登记 `check_warning_ledger.py` + `check_warning_ledger_reason.py`（此前「尚未写」） | 仓内合法 |
| ① 司令-γ 还债 | AGENTS.md（1 行） | 判例指针 32~42→32~43（判例-43 已在 HEAD：`docs/AGENTS-precedents.md:260`，指针一致） | 仓内合法 |
| ② vq 误落 | memory/bugs.md | 21 条外来（BUG-544~564）+ 2 段勘误 + 1 段 FIXED 状态节（+138 行） | 跨项目污染，归 BUG-565 决策单 §5.2 处置 |
| 残迹 | 插件态 4 文件 | `git diff --stat plugins/` = **0 行**（stat/EOL 残迹，零内容 diff） | 无需收口动作 |

## 收口警示（新 · 决定性事实）
- WIP 版插件 SKILL.md 计数面（atomcode/claude 两宿主 × fist-mbt/fist-commander 四份，`sort -u` 同线）：`ledger=BUG-1~543 共 528 条入账：3 条待修 / 486 条已修 / 13 条重复并入 / 26 条误报`
- WIP bugs.md 实测：564 抬头（轮 2 `bug_list` count=550，解析口径差 1 已知）
- ⇒ 收口时 `gen_plugins` 重投影必与 SKILL.md / AGENTS 计数面产生 diff ⇒ **bugs.md 先提而计数面未重投影 ⇒ cl7（投影一致）当场红**（与 2026-11-02「改 bugs.md ⇒ 同批重投影」一日两实证同形）。
- **拆批建议**：司令-γ 的 10 文件（不含 bugs.md）可独立收口一批；bugs.md 那批必须等 owner §5.2 计数面裁决（i 计数面扩到 564 打 foreign 标注 / ii 移 `memory/bugs-foreign/` 归档 / iii 勘误白名单排除）后同批提交（账本 + 计数面 + `gen_plugins` 投影）。

## 其他读数
- WIP 冻结 00:23（~1h40m）；无新提交（HEAD = ee7f32837，轮 2 本仓提交）。
- cl7 探针**不重试**：轮 2 已有受控读数（同批 `check_instruction_budget` PASS vs `check_plugin_sync` 被门禁判凭据访问拒 ⇒ 门禁误判与「脚本读凭据邻接配置」相关、非偶发）；本轮 cl7 结论改用零门禁风险的投影推定（上节）。
- Round C 队列维持全灭；3 条旧 OPEN（527/538/542）仍 owner 门控。注：司令-γ 的 L10 表明 **BUG-538 工程半（心跳判据夹具）仍在推进中**，与该单「等 owner 重连连接器」的运维半并行。

## 任务分配记录
无派单（无委派面：BUG-565 A 半 owner 门控、B 半已修毕待审批）；指挥官亲做只读定性 + 记账。

## 遗留风险
1. bugs.md 收口提交仍被 §5.2 计数面裁决卡住——先提即 cl7 红 + 计数面污染双红。
2. 21 条 vq 条目「永久保留本树」（对方勘误声明）⇒ 裁决决定计数面终态（i/ii/iii）。
3. 双流共享工作树：两 agent 并行提交时 `git commit -- <path>` 纪律必须严格——司令-γ 的收口**不得**把 bugs.md 的 vq 条目捎带进仓。
4. 3 条旧 OPEN 维持 owner 门控（527 上游 issue / 538 连接器重连 / 542 A-B 裁决）。

## 后续建议
1. owner 裁决 BUG-565 §4（推荐 B 白名单案）+ §3 部署三行命令审批——轮 2 两件事仍待，无变化。
2. 收口协调：把 §收口警示 的拆批建议传达给两 agent（bugs.md 批与还债批分离；bugs.md 批等 §5.2 裁决）。
3. 下一轮：WIP 已收口 ⇒ 核「bugs.md 批是否等裁决」+ 补 cl7 实跑读数；未收口 ⇒ 仅观察活性，不空转。

## 超额内容
无。

## 来源
- 盘面：`git status` / `git diff`（只读逐文件）/ mtime / `git diff --stat plugins/`（0 行）
- 判据：轮 2 实测留档（`bug_list` count=550 / `check_instruction_budget` PASS / cl7 门禁拒）；本轮投影推定（SKILL.md `ledger=` 行 × 4 份 sort -u）
- 决策单：`reports/2026-11-03-bug565-project-dir-decision-sheet.md` §5.2
- 日期：2026-11-03
