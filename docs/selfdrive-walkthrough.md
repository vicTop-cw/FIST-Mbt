# FIST-Mbt 端到端自驱 DEMO（Walkthrough）

> 本文是**真实运行留存**：FIST-Mbt 用它自己的**自驱式（selfdrive）+ 递归拆解 + 九态状态机**把自己打磨到可交付态的过程回放。
> 全部命令/JSON 均为本机 + WSL 实机执行过的真实 trace，非虚构。

## 0. 三个入口（评审 3 分钟能看完）

| 入口 | 命令 | 演示内容 |
|---|---|---|
| 自驱动能 | `moon run cmd/main` → `selfdrive_*` | 审视报告 → 幂等发布 → 自我推进 |
| 状态机闭环 | 见 §2 | publish → plan → claim → execute → submit → verify → archive |
| 一键 CLI | `moon run cmd/cli` | publish → plan → list |

## 1. 自驱闭环：用审视报告驱动"下一步"（真实 trace）

按 `templates/review_meta_prompt.md`，把要推进的任务固化成审视报告 `memory/reviews/yyyyMMdd.HH.mm.ss.md`，含 `## Next Tasks` 段；`selfdrive_publish_next` 解析并**并行发布为独立根任务**。

**本 repo 实际发生**（为冲刺黑客松前 10，把 5 个打磨瓶颈 A–E 发布为自驱任务）：

```
selfdrive_init(project_dir=.:fist-mbt)            → 建 memory 四件套 + reviews 目录
写  memory/reviews/20260924.14.10.00.md            → ## Next Tasks（A–E 共 5 条）
selfdrive_review_tick(review_every=1)             → rounds/pending 就绪
selfdrive_publish_next(max_tasks=5, ns=top10-iter) → action=published, 发布 5 / 跳过 0
```

发布出的自驱根任务（每条内嵌 `[review:20260924.14.10.00.md:N]` 幂等标记，重复调用会被跳过）：

| id | 任务 | 变更 |
|---|---|---|
| `T0r33` | A：README 顶部一句话卖点 + 为何 MoonBit | README 顶部重写 |
| `T0r34` | B：端到端自驱 walkthrough（本文） | docs/selfdrive-walkthrough.md |
| `T0r35` | C：CI native 必绿 + 补 Windows 轨道 | .github/workflows/ci.yml |
| `T0r36` | D：低门槛可复现 + 自检入口 | README 环境要求 |
| `T0r37` | E：主动自曝边界 | README/相关文档 |

## 2. 九态状态机闭环（真实 trace：任务 A）

对 `T0r33` 依次调用 MCP 工具，状态逐个迁移：

```
publish   → 待领取
claim     → 已领取    assignee=fist-selfdrive
execute   → 执行中    deliverable=README 卖点改写
submit    → 待验收
verify    → 已完成    completed_by=fist-selfdrive
archive   → 已归档（可再归档）
```

这证明：**系统用它自己的状态机/权限/审计完成了一次真实的自我迭代闭环**。

## 3. 为什么这本身就是 DEMO

- **自驱 ≠ 死循环**：审视报告被 `[review:file:idx]` 消费后幂等跳过；无新报告即 `idle`/`waiting` 停住（见 docs「自驱 vs watchdog」）。
- **递归拆解**：每条根任务可经 `task_plan_deep` 继续拆成多层子任务树。
- **跨环境可信**：136 项测试 JS+Native 在 Windows + WSL(Linux) 双端全绿（见 README 环境要求）。

## 4. 评审一键验证路径

```bash
moon update                      # 首次刷新 registry
moon run cmd/cli/main            # 一键 publish→plan→list 演示
moon run cmd/main                # 启动 MCP server，可走 selfdrive_* 自驱闭环
```

*（内容由AI生成，仅供参考）*