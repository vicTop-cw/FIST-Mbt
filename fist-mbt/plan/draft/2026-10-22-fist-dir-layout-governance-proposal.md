---
status: 已定案
decided_by: human_steward
decided_at: 2026-10-22T15:10:00+08:00
decision: approved
proposed_by: lead
---
# 提案：FIST-Mbt 双层目录治理（`.fist-mbt/` 机器独有 + `fist-mbt/` 团队共享）

## 一、为何需要（背景与乱象）

1. **计划治理缺位**：agent 把纯计划（如 `docs/archive/2026-10-16-future-plan.md`，含方案对比/里程碑，原置于 `reports/` 后归档）直接塞进 `reports/`，绕过"提案→定案→执行"流程。实测 `reports/` 混入 13+ 计划类文件，`docs/` 另有 12 个 plan——**计划无统一位置、无状态字段、无定案门禁**。
2. **机器独有工件污染主仓根**：95 个 `*.db`（含 `fist-mbt.db` 14.6MB）+ 37 个 `temp_*/build*.log` + 3 个 `.cron_state_*.json` + 10 个杂目录（`__pycache__/ _build/ _scratch/ logs/ backup/ temp/…`）散落根目录。这些是**每台机器各自不同**的运行时态，不该进主仓。
3. **同机任务池藏在 `.git/fist/`**：在 `.git` 内部 → 不进版本控制、普通文件树不可见。
4. **`improvement-plan-20261010.md` 未覆盖上述治理缺口**：grep `提案|定案|治理|proposal` 零命中。

## 二、目标

把 fist-mbt 工件按"机器边界 / 团队边界"归入**两个顶层文件夹**，并补齐**计划治理流程（提案→定案→执行→归档）**，用门禁取代人肉遵守。

## 三、目标布局

### 3.1 `.fist-mbt/` — 机器独有（gitignored，不进主仓）
```
.fist-mbt/
├── data/                      # SQLite 库 + 模型路由状态
├── pool/                      # 同机任务池（自 .git/fist 迁来）
├── state/                     # cron/已处理状态
├── logs/
├── tmp/                       # 临时文件（temp_*、build*.log）
├── cache/                     # 构建缓存/__pycache__
├── lock/                      # 文件锁
└── README.md
```
`.gitignore` 一行 `.fist-mbt/` 整体忽略。**每机一份、可随意删。**

### 3.2 `fist-mbt/` — 团队共享（committed，随主仓走）
```
fist-mbt/
├── memory/  reports/  plans/  docs/  templates/  scripts/  plugins/  assets/
└── plans/{decisions/, archived/}     # 治理核心
```
**团队共享、git 跟踪。** `reports/` 只放完成汇报；计划进 `plans/`。

### 3.3 计划治理状态机
```
Agent 提案 → plans/*-proposal.md (status: 提案中)
  → 指挥官定案 (approve/reject/defer) → plans/decisions/ 留痕
    → approve → 发布任务到 fist-mbt DB
    → 完成 → 报告进 reports/ + 计划移入 plans/archived/
    → reject/defer → 标记状态，不发布
```

**硬规则**：
1. 计划只进 `plans/`；`reports/` 只放完成汇报。
2. 未定案（`status != 已定案`）禁止发布任务（门禁）。
3. 定案权仅 `human_steward`；agent 只提不定。
4. 临时文件只进 `.fist-mbt/tmp/`，绝不进 `src/`、`docs/`、`plans/`。

## 四、实现阶段（各一次提交）

| 阶段 | 内容 | 压力 | 归属 |
|---|---|---|---|
| Phase 1 | `.fist-mbt/` 骨架 + 机器独有工件迁移（95 db/37 temp/10 dir/.git/fist/cron state）+ gitignore + `MultiStore` 默认 data_dir 改 `.fist-mbt/data` | 高 | 副机 |
| Phase 2 | `fist-mbt/` 骨架 + 团队共享工件 `git mv` + 全仓引用更新 | 高 | 副机 |
| Phase 3 | 计划治理：迁移 `reports/` 13 个计划 → `plans/`，补 `proposal_status` 字段 | 中 | agent 自取 |
| Phase 4 | 工具与门禁：`fist-init.py` + `check_fist_layout.py` + `check_plan_location.py` + `fist_init`/`plan_publish` MCP 工具 | 高 | 副机 |
| Phase 5 | 迁移 `improvement-plan` 治理节 + 全量验收回归 | 中 | agent 自取 |

## 五、验收清单

- [ ] 主仓根 `ls *.db temp_*` 返回空
- [ ] `.gitignore` 含 `.fist-mbt/`
- [ ] `fist-mbt/{memory,reports,plans,plans/decisions,plans/archived,docs,templates,scripts,plugins,assets}` 全在且 git 跟踪
- [ ] `fist-mbt/reports/` 无 plan 类文件
- [ ] 每份 `plans/*-proposal.md` 头部含 `status/decided_by/decision` 三字段
- [ ] `check_fist_layout` / `check_plan_location` 双守卫过
- [ ] `moon test --target js` 全绿（基线或 `--update` 后新基线）
- [ ] `fist-init` 在空目录生成完整双骨架

## 六、边界

1. 不破坏 1358 JS 测试（DB 路径改默认须让测试显式传路径）。
2. 旧根级 `*.db` 首次运行自动迁入 `.fist-mbt/data/`（幂等）。
3. `git mv` 保留历史；大目录注意 rename 检测。
4. 多机同步：`fist-mbt/` 靠 git，`.fist-mbt/` 靠每机 `fist-init` 自建。
5. `_cron_*.py` 归属逐一判断（可复用进 `scripts/`，机器专属进 `.fist-mbt/scripts/`）。
6. 计划门禁默认关闭（`enforce_plan_gate=false`），直到既有计划补完状态字段。
7. 迁移在基于最新 `gitcode/main`（`b465915f`）的新分支进行，不污染当前工作树。

## 七、定案记录

- 本提案由 `lead` 提出，经指挥官 `human_steward` 于 2026-10-22 批准。
- 定案后按 Phase 1→5 拆分为任务发布到 fist-mbt DB，重的交副机。
- 本文件移入 `docs/plans/` 作为治理框架的**第 1 份已定案提案**（原 `fist-mbt/plans/`，2026-10-24 迁移）。
