# 获奖提升 · R29 挑战题防漂移门禁 + R28 脚本区整洁

> 日期：2026-09-25｜目标：把获奖概率再往上提——先调研、再环视薄弱点，规划性增强 + 拿来主义 + 项目整洁。
> 本轮续接已完成 R27：**79 MCP 工具 + 3 resources + 2 prompts，测试 223/223（Windows + WSL 双端全绿）**。

## 一、调研先行（拿来主义）
- 后台子代理 WebSearch 实取 2025-2026 生态/论文，蒸馏至 `memory/research/ecosystem-borrow.md` §五：
  SAGE（Critic 过滤题目防课程漂移）、R-Few（few-shot 锚点 ground + 在线难度课程，缓解 diversity collapse）、
  SPICE、MCP SEP-1686 Task 原语、Claude Code workflow/report_findings、RepoMap、AGENTS.md 研究。
- 结论：R13 的 `evolve_critic` 只审 principle/lesson；R14 的 `task_challenge` 生成的"挑战题"自身未过门禁——
  正是 SAGE Critic 该过滤的"题目"。确定为本轮工程（低投入、高差异化、补护城河）。

## 二、本轮落地
### R29：挑战题防漂移门禁（`task_challenge critic=true`）
- `task_challenge` 新增可选 `critic`（DGM 档案库，缺省 None = 旧行为零回归）：挑战变体发布为根任务前，
  先经 `critic_review`（与 `evolve_critic` **同一单一真源**，纯计算）评审——与档案库既有资产重合 ≥ 0.70
  判"疑似课程漂移/同质坍缩" → **自动降档**尝试其余策略（generalize→unhint→constrain→scale）；
  **全部策略皆漂移 → 拒发**（不出新根任务，Err 带评审原因）。非漂移但稳健性偏低不阻断（挑战题偏新颖/高风险）。
- 实现点：`engine_challenge.mbt` 重构 `challenge` 加 `critic?` 参数 + `pick_frame`/`review_sim`/`ch_desc`；
  server handler 加 `critic` bool 参数（开启时 `sync_db_lessons` 同步 DB 教训再判全量）。
- **验证**：单测 +3（空库放行 / 当前策略漂移降档 generalize / 全部漂移拒发），`moon test --target js` **223/223**；
  E2E `task_challenge_verify.py` 追加 `critic=true` **MCP-TASK-CHALLENGE-VERIFY PASS**（tools/list=79）。

### R28：脚本区整洁（项目整洁支柱）
- 清除被 git 跟踪的临时残留 `_score_probe.py`、`_probe_result.md`（plan 文档本声明"跑完可删"）；
- `_ai_prompt.md` 实为 `score_gate.py` 的正式评分 rubric → 正式化改名为 `scoring_rubric.md`（无前缀=正式工具），
  同步 3 处引用 + rubric 内陈旧计数（67→79/223）+ scripts/README 分类表 & 陈旧工具计数 77/76/77→79。

## 三、结果摘要
| 项 | 值 |
|---|---|
| MCP 工具 | **79**（R29 仅加参数，零回归，不新增工具） |
| 测试 | **`moon test --target js` 223/223**（220→223，+3） |
| E2E | task_challenge_verify（含 critic=true）PASS、tools/list=79 |
| 回归 | 0（critic 缺省关闭，旧 challenge 语义不变） |
| 文档 | README/AGENTS/ARCHITECTURE/deliverable/agent-map/项目申报书/scoring_rubric 计数全量同步 |

## 四、资源消耗
- 工具链：`moon check --target js` / `moon test --target js -j 1` / `moon build --target js cmd/main` / `moon info && moon fmt`；
- 无新增依赖、无新表；后台调研子代理 1 次（8 tools）。

## 五、任务分配记录
- 调研：子代理（WebSearch 生态/论文）→ 主代理蒸馏；
- R28：主代理审计 + `git rm/mv` + 引用同步；
- R29：主代理设计/实现（含自审 typecheck+tests+E2E 三关）。

## 六、遗留风险
- `critic` 门禁的"漂移"以 Jaccard 词集重合 ≥0.70 判（沿用 `evolve_critic` 口径），对纯规则帧为保守安全网；
  真实 LLM 生成变体的漂移探测属框架级（需词嵌入），列为远期，当前"拒发重复挑战题"已足够防同模坍缩。
- Windows native 竞态仍为工具链边界（权威门槛 = JS 双端 + Linux native），如实保留于 README 已知边界。

## 七、后续建议（按强度）
1. **Marketplace/Dynamic 能力路由**：executor 注册能力标签 → router 按 want+负载分配（`pick_next` 已是取单端）。
2. `plan_deep` 深化 LADDER"先生成简单变体再逆推原题"；挑战题门禁可接难档分级在线课程（R-Few/SPICE）。
3. 交付物结构化回传（仿 report_findings）：约束 `execute` 的 deliverable JSON 契约。
4. README CI 徽章实时化（静态 223/223 → workflow 生成）。

## 八、超额内容（相对任务边界）
- 顺手修正 README 主文案"78 个 MCP 工具"→79、agent-map"一键自检 75"→79 两处陈旧计数（文档即实现扫尾）。

## 九、来源
- 调研：memory/research/ecosystem-borrow.md；子代理 WebSearch（SAGE/R-Few/SPICE/MCP SEP-1686/RepoMap）。
- 源码：src/engine/engine_challenge.mbt、src/server/server.mbt、engine_challenge_test.mbt、scripts/task_challenge_verify.py。

*（内容由AI生成，仅供参考）*