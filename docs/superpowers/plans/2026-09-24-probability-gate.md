# 冲榜概率门禁 + 调研库 + 方法论固化 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) 或 superpowers:executing-plans 按任务逐项实施。步骤用 checkbox（`- [ ]`）。
>
> 依据 spec：`docs/superpowers/specs/2026-09-24-probability-gate-design.md`。
> **质量标准（主/次）见 READ FIRST**。

**Goal:** 把「4-AI 概率自评分门禁 + 调研库 + BACKLOG + 方法论固化」落地，并跑通一次真实门禁。
**Architecture:** 全为「文档 + 1 个 python 门禁脚本」，不改任何 MCP 工具；门禁用 4 个 AI（AI1=self 会话 / AI2=atomcode-LongCat / AI3=codearts-盘古 / AI4=atomcode-kimi-k3）顺序打分、全档达标（p1≥60&p2≥80&p3≥95）AND 聚合。
**Tech Stack:** Python（std/subprocess）、MoonBit（回归门禁 `moon test`）、CLI：`atomcode -p` / `codearts`（headless）、Markdown。

---

## READ FIRST — 质量标准（主/次，每个任务/每次门禁必过）

**主（阻断性硬门槛；不达标即打回）：**
- M1 无硬编码：无盘符/`/home`/`/Users`；路径相对或参数化。
- M2 无任何回归：既有 148 项测试语义不变。
- M3 测试全绿：`moon test --target js` + `--target native`（Windows 用 `-j 1`）双端全绿。
- M4 功能兼容：不改既有 MCP 工具参数/返回/语义。
- M5 任意机器结果可完全复现：`moon update && moon run/test` 即同结果；不依赖本机私有路径/会话。

**次（期望性，非阻断但失分项）：** M6 文档即实现——文档与实际一致，改实现同步文档。
**落点：** 每个任务 done 前先过 M1/M5 检查，再 `moon test` 确认 M2/M3。

---

## File Structure

| 文件 | 职责 |
|---|---|
| `memory/research/five-directions.md` | 五方向 18 条机制蒸馏表（新） |
| `memory/research/competition.md` | 参赛评估 P0-P3 去重（新） |
| `memory/research/recent-market.md` | 近 3 月市场/竞品/评审偏好证据底座（新） |
| `memory/research/future-roadmap.md` | 可扩展清单（新） |
| `memory/research/index.md` | 检索索引（新） |
| `BACKLOG.md` | P 优先级待办队列（新，仓库根） |
| `templates/review_meta_prompt.md` | 审视模板加「调研先行检查」「## 调研参考」（改） |
| `docs/polish-plan.md` | §二闭环强化 + §四质量标准（改） |
| `scripts/_ai_prompt.md` | 统一 rubric 提示词（新） |
| `scripts/score_gate.py` | 4-AI 顺序门禁 runner（新） |
| `scripts/_score_probe.py` | CLI dry-run 探测助手（新，跑完可删） |
| `memory/research/score-20260924.md` | 首跑门禁留痕（新） |

---

### Task 1: 调研库 five-directions 蒸馏 + competition 去重

**Files:**
- Create: `memory/research/five-directions.md`
- Create: `memory/research/competition.md`

- [ ] **Step 1: 写 five-directions.md（18 条机制蒸馏表）**

内容结构（Markdown 表格，不复制报告原文，只蒸馏）：
- 表头：`| 方向 | 机制 | 来源 | 对应模块 | 优先级 | BACKLOG引用 | 状态 |`
- 全部 18 行照 `C:\Users\victo\.openclaw\workspace\fist-mbt五方向业界调研报告_20260924-1430.md`「五、综合」表抄入，状态列标 `pending`；已由前几轮覆盖的（如心beat 的「Did it work?」现状）标 `done` 并注明。
- 顶部注明「来源报告 + 蒸馏日期」。

- [ ] **Step 2: 写 competition.md（P0-P3 去重）**

- 表头：`| P级 | 事项 | 建议来源 | 当前态 | 状态 |`
- 依 `C:\Users\victo\.openclaw\workspace\fist-mbt参赛评估与加强建议_20260924-1438.md` 的 P0-P3，去重对齐当前事实（61 工具/148 测试/CI 三绿）：如「验证 evolve」标 `done(已在148测试)`；README AIGC 清理、async 升级、30秒演示、scoring.mbt、申报书 PDF、mooncakes 发布、quickcheck、mizchi/llm、ARCHITECTURE、英文 README 各自当前态据实标。

- [ ] **Step 3: 主标准快检**：两文件无盘符/绝对路径（M1）；无既有测试受影响（M2）。

- [ ] **Step 4: Commit**

```bash
git add memory/research/five-directions.md memory/research/competition.md
git commit -m "research: 五方向机制蒸馏 + 参赛评估P0-P3去重入调研库"
```

---

### Task 2: 调研库 recent-market + future-roadmap + index

**Files:**
- Create: `memory/research/recent-market.md`
- Create: `memory/research/future-roadmap.md`
- Create: `memory/research/index.md`

- [ ] **Step 1: recent-market.md（近 3 月证据底座）**
  - 一节「近 3 个月 mooncakes 新增/相关项目」：从 `mooncakes.io` + 前两报告 §二 生态表摘取与 fist-mbt 相关项（如 mizchi/llm、colmugx/posoco、bitflow、github 客户端、quickcheck 等）。
  - 一节「同类竞品/评审偏好」：MCP server / agent 编排在 MoonBit 生态稀缺性、评审可能偏好（可视化/直接体验）。给出客观事实与差距。

- [ ] **Step 2: future-roadmap.md（可扩展清单）**
  - 依据 spec §三 + BACKLOG 待办，列「近期(验收前) / 中期(季度评选) / 远期」三档；每条给理由（为何增分）。

- [ ] **Step 3: index.md（检索索引）**
  - 表头：`| 条目 | 方向 | 关键词 | 优先级 | 状态 | 来源 |`
  - 收录：selffit-research / five-directions / competition / recent-market / future-roadmap / score 各一行；状态据实。

- [ ] **Step 4: 主标准快检**（M1 无盘符；M2 无回归）。

- [ ] **Step 5: Commit**

```bash
git add memory/research/
git commit -m "research: 证据底座+roadmap+index 入调研库"
```

---

### Task 3: BACKLOG.md（P 优先级待办队列）

**Files:**
- Create: `BACKLOG.md`

- [ ] **Step 1: 写 BACKLOG.md**
  - 表头：`| P级 | 事项 | 来源 | 状态 | 对应review/commit |`
  - 把二报告 + spec 的 P0-P3/done 项统一收敛（去重），如：
    - `P0 | 30秒体验/演示脚本 | competition | pending | -`
    - `P0 | scoring.mbt(自进化闭环) | competition | pending | -`
    - `P1 | Agent Contract 7字段 + Tool Use Rubric | five-directions | pending | -`
    - `P1 | Did-it-work 输出验证 | five-directions | pending | -`
    - `P0 | 清理 README AIGC 标记 | competition | pending | -`
    - `P0 | async 0.21→0.22.3 升级 | competition | pending | -`
    - `done | evolve 验证(148测试内) | competition | done | 70u... `
  - 状态枚举 `pending | claimed | done`；done 保留为证据。

- [ ] **Step 2: 主标准快检**（M1 无盘符；M2 无回归）。

- [ ] **Step 3: Commit**

```bash
git add BACKLOG.md
git commit -m "backlog: P 优先级待办队列（自驱净拉取源）"
```

---

### Task 4: 方法论固化（审视模板 + polish-plan §二/§四）

**Files:**
- Modify: `templates/review_meta_prompt.md`
- Modify: `docs/polish-plan.md`

- [ ] **Step 1: review_meta_prompt.md 加「调研先行检查」**
  - 在「Step 2 — 复盘与定位下一步」小节内追加一段：
    ```
    ### 调研先行检查（必做）
    选 Next Tasks 前，先读 memory/research/index.md 与 BACKLOG.md：
    - 若候选任务触及已有调研条目 → 在 Next Tasks 描述里附带 `[调研:index条目]` 引用；
    - 若触及全新功能区且无调研条目 → 在 Next Tasks 顶部加一条 `[调研：<主题>——按 memory/research/ 模板沉淀可移植机制后再实施]` 作为前置任务。
    ```
  - 在「## Next Tasks」结构示例的 `## 阻塞与风险` 之后、`## Next Tasks` 之前加可选行 `## 调研参考\n（本次引用：<index条目+可选 BACKLOG 项>）`。

- [ ] **Step 2: polish-plan.md §二 强化闭环 + §四 质量标准**
  - §二 方法论段后追加一句：「凡与目标项目相关的功能都应先调研（memory/research/）再迭代；每轮收敛前跑 4-AI 概率门禁，未全档达标不进下轮。」
  - §四 验收标准替换为 spec「七·A 质量标准（主次）」的 1–5 + 6；去掉过时 `135` 引用，改为「当前双端全绿数（148）」。

- [ ] **Step 3: 主标准快检 + 回归**：改的是 md 模板与文档，运行 `moon test --target js` 仍 148/148（M2/M3）；`grep` 文档确认无残留 `57 个工具`/`135`（M6/M1）。

- [ ] **Step 4: Commit**

```bash
git add templates/review_meta_prompt.md docs/polish-plan.md
git commit -m "meta: 审视模板调研先行 + polish-plan 质量标准主次"
```

---

### Task 5: rubric 提示词 _ai_prompt.md + 门禁 runner score_gate.py

**Files:**
- Create: `scripts/_ai_prompt.md`
- Create: `scripts/score_gate.py`

- [ ] **Step 1: 写 _ai_prompt.md（统一 rubric）**
  内容含：角色（评审 2026 MoonBit 黑客松参赛项目 fist-mbt）、评分维度加权表（完成度25/技术难度20/创意生态30/美观演示25）「稍宽一档」口径、给定证据快照路径、**规定输出**：先输出 `SCORE_JSON:{"p1":0.xx,"p2":0.xx,"p3":0.xx,"verdict":"pass"|"fail","reason":"..."}`（p1/p2/p3 为 0~1 概率），再补充 ≤150 字理由。写明「全档达标口径：p1≥0.60 && p2≥0.80 && p3≥0.95 才 pass」。禁止自吹，给证据。

- [ ] **Step 2: 写 score_gate.py（顺序拉起 4 AI，AND 汇总，fail-open）**
  - 变量由命令行/env 注入（不在代码里写盘符路径）：
    - `--evidence` 证据快照路径；`--ai1-json` AI1（你自身）的 `{p1,p2,p3,verdict}`（由外层传入；或 `--ai1-note` 让我产出）。
    - 对 AI2/AI3/AI4 用可配置命令模板（env `SCORE_AI2_CMD/SCORE_AI3_CMD/SCORE_AI4_CMD`，默认 `atomcode -p` / `codearts -p`），`subprocess.run(..., timeout=180)`，从 stdout 抓 `SCORE_JSON:{...}`。
    - 逐条 `json.loads`；缺 AI 的 `p` 或 parse 失败 → 该 AI 记 `error`，**不降级为 pass**。
    - AND：`pass = all(ai['verdict']=='pass' and p1>=0.60 and p2>=0.80 and p3>=0.95 for ai in [AI1..AI4])`。
    - 输出 `AI1..AI4 得分表 + PASS=是/否 + 每家 verdict/p/error`，退出码 0（PASS）/1（FAIL or any error）。

- [ ] **Step 3: dry-run 4 CLI（探测真实命令/输出）**

Run（Tail 每个，超时 180s）:
```bash
python scripts/_score_probe.py --cmd "echo PROBE"   # 骨架先通
# 然后逐个真实 CLI dry-run，确认 -p/headless 实际可用、输出含 SCORE_JSON
```
Expected：探测助手能在有限时间内return exit code + 首段 stdout；对不可用的 CLI 如实标记 `UNAVAILABLE`（写进 score 留痕），**不视为通过**。

- [ ] **Step 4: 主标准快检 + 回归**：脚本/提示词无盘符（M1）；`moon test --target js` 148/148 不受影响（M2/M3）。

- [ ] **Step 5: Commit**

```bash
git add scripts/_ai_prompt.md scripts/score_gate.py scripts/_score_probe.py
git commit -m "gate: 4-AI 概率门禁 runner + rubric 提示词（全档达标 AND 聚合）"
```

---

### Task 6: 首跑门禁 + 留痕 + 收尾同步

**Files:**
- Create: `memory/research/score-20260924.md`
- Modify: `memory/2026-09-24.md`

- [ ] **Step 1: 准备证据快照**：把近期 `git log --oneline -30`、`moon test --target js` 148/148、CI 三绿、BACKLOG 现状、index.md 汇总成一个临时 `memory/research/_snapshot.md`。

- [ ] **Step 2: 收集 AI1 打分**：由我（AI1）按 rubber 产出 `{p1,p2,p3,verdict}` 并给出。

- [ ] **Step 3: 跑门禁**

Run:
```bash
python scripts/score_gate.py --evidence memory/research/_snapshot.md --ai1-json '{"p1":..,"p2":..,"p3":..,"verdict":"pass"}'
```
Expected：按顺序驱动 AI2/AI3/AI4，输出各家 verdict/p/error + `PASS=是/否`；任一 `UNAVAILABLE`/error → `PASS=否` 并据实列出。

- [ ] **Step 4: 写 score-20260924.md 留痕**：4 家逐项 table（AI/载体/verdict/p1p2p3/error/时间），结论 PASS 或 FAIL 及原因；若 FAIL，写「下一轮自驱逐项来源（BACKLOG 顶部 N 条）」。

- [ ] **Step 5: 清理临时文件**：删 `scripts/_score_probe.py`、`memory/research/_snapshot.md`（如无保留价值）。

- [ ] **Step 6: 收尾提交 + 同步**

```bash
git add memory/research/score-20260924.md memory/2026-09-24.md scripts/_score_probe.py scripts/_snapshot.md
git commit -m "gate-run: 4-AI 门禁首跑留痕（PASS/FAIL 据实）"
git push origin master
```

- [ ] **Step 7: 终验**：`moon test --target js` 148/148；`git status` 干净；远端 CI 三绿。

---

## Self-Review（writing-plans 自查）

- **Spec coverage**：spec §三→Task1/2；§四→Task3；§五→Task4；§六→Task5；§2.5/2.6+§八→Task6；§七·A 质量标准 → READ FIRST（贯穿所有任务）。
- **Placeholder**：`ai1-json` 的 p1/p2/p3 值在 Task6 由我实测填（非占位符，是运行时输入）；`_score_probe.py` 内容在 Task5 Step3 写实；无 TBD/TODO。
- **Type consistency**：`score_gate.py` 契约 `{p1,p2,p3,verdict}` 与 `_ai_prompt.md` 的 `SCORE_JSON` 一致；各任务文件路径一致。