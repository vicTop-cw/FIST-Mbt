# debate-skill.md · 六顶思维帽讨论（fist-mbt）

> **真源**：`src/ops/ops_hats.mbt`（纯计算，零依赖，方向三 P1-b）
> **对应计划**：`docs/improvement-plan-20261010.md` §4
> **单真源纪律**：帽子字符串 → 枚举 → 角色模板只通过 `ops_hats` 解析，`debate_*` 工具 / CLI / 文档三态都不得另写一套。

---

## 1. 这是什么

**六顶思维帽**（Edward de Bono）把对同一议题的分析拆成六个正交视角。本模块把每一顶帽子实现为**一个 subagent**：输入 = 议题 + 本帽子的角色指令模板，输出 = 结构化结论。fist-mbt 只做**多帽一致性聚合**（确定性计算，无 LLM 自评），**最终裁决权留在指挥官/用户**。

**为什么要有它**：单指挥官裁决容易陷入单一视角。多视角证据收敛能暴露单点盲区，但**多帽一致 ≠ 结论正确**——它只说明视角收敛，不代用户拍板。

---

## 2. 六顶帽子

| id | 中文名 | 视角 | 输出关键字段 |
|---|---|---|---|
| `white` | 白帽 · 事实 | 客观数据，不下判断、不给建议 | `evidence`, `defects` |
| `red` | 红帽 · 直觉 | 当下的感觉、直觉、审美，不解释理由 | `feeling`, `intuition` |
| `black` | 黑帽 · 风险 | 失败模式、风险、反例、成本 | `defects`, `evidence` |
| `yellow` | 黄帽 · 收益 | 好处、机会、价值、可行性 | `fix`, `acceptance` |
| `green` | 绿帽 · 创意 | 新方案、替代、想象力、可能性 | `fix`, `defects` |
| `blue` | 蓝帽 · 过程 | 收敛、组织、下一步、帽子本身 | `acceptance`, `evidence` |

**默认 3 顶**（决策点 D3）：`white` + `black` + `yellow`。其余为可选扩展。

每顶帽子有**禁做事项**（`hat_forbid`）：黑帽不许提收益、黄帽不许提风险、绿帽不许做可行性分析等——六帽最怕七顶帽子说同一句话。

---

## 3. 工具

| 工具 | 参数 | 返回 |
|---|---|---|
| `hat_list` | 无 | 6 顶帽子的 id / 中文名 / 主题色 / 输出字段 / 角色指令 / 禁做事项 |
| `debate_convene` | `question`（议题，必填非空）、`hats`（逗号分隔帽子 id，可选，默认 `white,black,yellow`） | 会议 id + 每顶帽子的角色指令正文（可直接交给 subagent） |
| `debate_register` | `session_id`、`hat_id`、`verdict`（`pass`/`reject`/`abstain`）、`evidence`（必填非空） | 该帽结论是否有效（`valid_verdict`）+ 当前已登记数 |
| `debate_verdict` | `session_id`、`threshold`（可选，默认 0.6） | 聚合结果：`total` / `agree` / `rate` / `threshold` / `pass` |

### 3.1 帽子字符串解析

- 大小写敏感（trim 后逐字匹配），`WHITE` 视为非法而非静默转小写。
- 批量解析任一非法即整批 `Err`（避免部分生效造成半桶结论）。

### 3.2 会议状态（诚实边界）

会议状态保存在 **server 进程内存**（`Map[session_id, debate_session]`），**不新开库表**（见计划证伪 B：审计已有 `call_log` / `audit_log` 现成通道）。这意味着：

- 同一进程内 `debate_convene` → `debate_register` × N → `debate_verdict` 是完整闭环。
- **跨进程 / server 重启后会议状态丢失**——需要持久结论请把 `debate_verdict` 的输出记入 `memory/YYYY-MM-DD.md` 或 `call_log`。
- 会议 id 由服务端盖章（不接受调用方注入），格式 `debate-<yyyyMMdd>-<nnn>`。

---

## 4. 一致性聚合（确定性）

```
rate = agree / total
pass = rate >= threshold
```

- `agree` 只统计 `verdict == "pass"` 的帽子；`abstain` 与 `reject` 都不算达成一致。
- `threshold` 默认 **0.6**：三帽中至少两帽一致才视为收敛。
- `threshold <= 0` 或 `> 1` 时回退默认 0.6；`total == 0` 时 `pass = false`。
- `pass = true` **仅表示视角一致性**，不是自动放行——最终裁决权在指挥官/用户。

---

## 5. 与既有机制协同

| 机制 | 协同方式 |
|---|---|
| `eval_feedback` | 帽子输出字段对齐其四段式契约（Defects / Evidence / Fix / Acceptance），结论可直接喂给它归一 |
| `evolve_critic` | 帽子结论聚合结果可交 critic 做同质化过滤（重合 ≥70% 判课程漂移/重复） |
| `goal_drift_check` | 用 jaccard 判各帽结论是否漂移出议题范围或互相冗余 |
| `task_triage` | 帽子视角可作为任务路由信号（如黑帽命中 → 建议走 `bugfind` 模式） |
| `mode_list` | 同族注册表：`hat_list` 与 `mode_list` 结构一致，都是「枚举 → 元数据 → 模板」 |

---

## 6. 端到端使用流

1. **召集**：`debate_convene(question="是否在方向三引入 grill-me skill", hats="white,black,yellow")` → 拿到 3 顶帽子的角色指令。
2. **并行跑帽**：把每顶帽子的角色指令 + 议题各交给一个 subagent，收集结构化结论。
3. **登记**：对每顶帽子 `debate_register(session_id=..., hat_id=..., verdict=..., evidence=...)`。
4. **聚合**：`debate_verdict(session_id=...)` → 看 `pass` 与 `rate`。
5. **用户拍板**：指挥官/用户基于聚合结果做最终裁决；不满足就加帽（red/green/blue）或换议题重跑。

---

## 7. 白盒锁

`src/ops/ops_hats_wbtest.mbt` 钉住：

- 6 顶帽子可解析、默认集 = white+black+yellow。
- 非法字符串整批 `Err`；`WHITE` 不是 `white`。
- 每顶帽子的 `hat_role` / `hat_forbid` / `hat_output_keys` 非空且互不相同（防漂移）。
- `debate_summary` 阈值计算正确（含 total=0、threshold 越界回退）。
- `valid_verdict` 拒绝空 evidence 与非法 verdict。

---

## 8. 相关

- `src/ops/ops_hats.mbt`（真源）
- `src/ops/ops_hats_wbtest.mbt`（白盒锁）
- `src/server/server.mbt`（`hat_list` / `debate_convene` / `debate_register` / `debate_verdict` 工具注册）
- `docs/improvement-plan-20261010.md` §4