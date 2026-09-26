# SKILL: project-standards — AI 项目开发规范（默认内置 + FIST 专项）

> 形态：skill（本文档）｜MCP 工具 `project_standards`｜CLI `python scripts/fist.py call project_standards`
> 用途：给 AI agent 一套**应该怎么开发**的基线规范——不是约束，是默认最优实践清单。
> 10 条硬规范 + 6 项三形态 checklist，新功能上线前必须对照自检。

## 何时用

- **新功能上线前**：对照 checklist（cl1-cl6）跑一遍，缺哪补哪——MCP 注册了？CLI 封装了？skill 文档写了？
- **Code Review**：首审命名（动宾结构？语义化参数？），再审三形态对齐。
- **任务启动前**：读规范清单，避免"想到哪写到哪"——重任务先拆 DAG，不是直接开干。
- **评审自证**：`python scripts/fist.py call project_standards` 输出可审计的规范基线。

## 怎么调

### MCP 形态
```
tools/call project_standards
  { "project_type": "moontbit_mcp", "include_checklist": true }
```
返回 `{ version: "R114", general_rules[5], fist_specific_rules[5], checklist[6], count_total: 10 }`。
- `project_type` 给上下文标注（默认 `"moontbit_mcp"`）。
- `include_checklist`（默认 `true`）附带三形态验收 checklist。

### CLI 形态
```bash
python scripts/fist.py call project_standards --include-checklist true
python scripts/fist.py call project_standards --project-type my_ai_project --include-checklist false
```
不需要 build——`fist.py` 会自动拉起 MCP server。

### 三形态关系
- **单真源 = MoonBit 实现**（`src/server/project_standards.mbt`）：纯计算、零依赖、不碰 store/文件/网络。
- MCP 工具直接调它；CLI 通过 `fist.py call` 路由。
- skill（本文档）教 agent 何时用、怎么对照 checklist 自检。

## 规范书（10 条）

### 通用 5 条（跨项目复用）

| id | severity | 标题 | why |
|---|---|---|---|
| r1-doc-as-impl | hard | 文档即实现 | 接口 doc 注释 + README 速查表；验收先过文档再验功能 |
| r2-single-source | hard | 一源三态，单真源优先 | 核心逻辑写在单一运行时；CLI/Skill/MCP 薄封装，禁止复制业务逻辑 |
| r3-deterministic-first | hard | 确定性优先于语义性 | issue_scan/output_validate/phi_accrual 全部确定性实现；LLM 只决策不判定 |
| r4-zero-regression | hard | 增量零回归 | 每加一功能全量测试必过；临时脚本任务完必须清理 |
| r5-self-evolve | medium | 自我迭代优于一次性构建 | 先做最小可用，用 evolve/task_challenge 边做边学 |

### FIST 专项 5 条（强制遵守）

| id | severity | 标题 | why |
|---|---|---|---|
| f1-use-fist-self | hard | 必须使用 FIST 自身能力迭代 | PR 必须有 FIST 任务发布记录（task_id/root_task_id）；不用自身能力打回重做 |
| f2-three-forms-aligned | hard | 三形态必须对齐 | 新 MCP 工具 = 同步 CLI + skill 文档；缺一打回 |
| f3-evidence-ladder | hard | 证据梯至少爬 L4 | verify 前必须 output_validate verdict=pass |
| f4-task-dag | medium | 重任务先拆 DAG | 跨 3 文件/5 人日以上 → publish + task_plan_deep → dag_ready 执行 |
| f5-naming-clarity | medium | 工具命名即文档 | 动宾结构、语义化参数名；aggressive rename 也接受 |

## 三形态 Checklist（6 项硬门）

| id | gate | 问题 |
|---|---|---|
| cl1-mcp-exists | hard | MCP 工具注册了（server.mbt instrumented_tool 块）？ |
| cl2-cli-exists | hard | CLI 封装到位（独立脚本或 fist.py call 可路由）？ |
| cl3-skill-doc | hard | skill 文档写了（docs/xxx-skill.md 说明何时用/怎么用/怎么闭环）？ |
| cl4-tests-pass | hard | moon test 全绿？新增功能的测试覆盖了正/负路径？ |
| cl5-ov-pass | hard | 交付物过了 output_validate L4 硬门？verdict=pass？ |
| cl6-doc-sync | medium | README / AGENTS.md 计数与工具数同步？ |

## 闭环（checklist → 执行 → 验收）

1. **上线前自检**：对照 cl1-cl6 逐项打勾，缺哪补哪。
2. **output_validate 当硬门**：把 checklist 里的问题转成 artifacts（如 `{"path":"docs/output-validate-skill.md","contains":"何时用"}`），喂 `output_validate` 验证。
3. **verify 终检**：`verify` 前必须 `output_validate verdict=pass` + 规范 checklist 全过。

## 已知边界

- 纯计算、零依赖、不碰 store/文件/网络——好测、纯、可复现。
- 规范是**默认清单**，可通过 `project_type` 参数标注上下文，但当前不支持自定义追加（未来可加 `extra_rules` 参数）。
- severity 分级仅供参考，`hard`/`medium` 是建议——实际门禁强度由调用方（CLI/CI/agent）决定。
