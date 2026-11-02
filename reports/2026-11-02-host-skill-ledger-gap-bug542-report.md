# 统帅批·续17 报告：宿主副本漂移缺口核实 + BUG-542 立账（2026-11-02）

## 结果摘要
- 缺口核实：本机宿主技能副本（atomcode/codearts 的 `fist-mbt` SKILL.md）ledger 计数**逐字滞后**于仓内真源——宿主 516 条/8 待修（mtime 2026-11-01 11:12 冻结），仓内 526 条/2 待修；条目数落后 10 条，待修数多 6 条。
- **关键证据**：本提示系统注入的 fist-mbt skill 描述 ledger 行（516/8）与宿主副本**逐字一致** ⇒ 证明 harness 每轮读的是宿主本地快照，而非仓内真源。
- BUG-542 立账：BUG-540/541 已被 J19/J18 占用（已 FIXED），顺延 **BUG-542** 登记（守卫盲区型 OPEN）。
- 边界文档落地：`docs/known-boundaries.md` 新增 §3.3 明写宿主副本滞后是已知面 + 出路两档（A 同步脚本 / B 边界文档登记）。

## 证据
| 来源 | ledger 行 | mtime |
|---|---|---|
| atomcode 宿主副本 `~/.atomcode/skills/fist-mbt/SKILL.md` | `BUG-1~531 共 516 条 / 8 待修` | 2026-11-01 11:12（9910 字节） |
| codearts 宿主副本 `~/.codeartsdoer/skills/fist-mbt/SKILL.md` | 同上（逐字一致） | 2026-11-01 11:12 |
| 仓内投影真源 `plugins/atomcode/skills/fist-mbt/SKILL.md` | `BUG-1~541 共 526 条 / 2 待修` | 仓内 HEAD |
| harness 注入（本提示 fist-mbt skill 描述） | `BUG-1~531 共 516 条 / 8 待修` | — |

## 任务分配记录
- 缺口核实：统帅直接执行（纯读面操作，不派单）。
- BUG-542 立账：统帅落账（memory/bugs.md 追加 + docs/known-boundaries.md §3.3）。

## 资源消耗
- 1 轮会话、6 次工具交互、2 处文件改动。

## 遗留风险
- BUG-542 出路需 owner 裁决：A) 写 `scripts/sync_host_skills.py`（本机耦合、不可 CI 自证）或 B) 边界文档登记（当前实际状态）。
- 若选 A，新脚本需同批给执行面（case/expected/EXEMPT_RULES 三选一）—— 判例-5 纪律。

## 后续建议
- 等 owner 裁决 BUG-542 出路后落地；在裁决前，边界文档 §3.3 已让读到 skill 描述的人不被 516/8 骗。
- 续18 唤醒优先查 Round C 解禁状态（BUG-538 心跳车道 src/server 六文件 WIP 占用），按 Round B 报告「遗留风险」节队列推进。

## 超额内容
- 无。

## 来源
- `git log --oneline -3`（HEAD cda20e0da = origin/main，双绿）
- `git status --short`（另一 agent 的 J19 工作：AGENTS.md/AI-DEVELOPMENT-STANDARD.md/scripts/check_doc_surface.py/templates/pipeline_mode_tidy.md 四份真改动，不碰；plugins/ 7 份纯 CRLF 幻影）
- 双宿主副本 ls -la + ledger grep 亲测
- harness 注入面本提示 fist-mbt skill description 直接核对
- memory/bugs.md BUG-542 条目 + docs/known-boundaries.md §3.3
