# 2026-10-14 · 工具计数当前面漂移系统性审计 + 修复（Round 109）

## 结果摘要

**一句话**：按建议 #2「穷尽同类扫描面」，全仓系统性扫了一遍"被 git 跟踪、含工具计数自述、但不在 J14 扫描面"的
文件，发现**一个漂移集群**：`templates/tool_use_rubric.md`（提示词模板）报「暴露 134 个工具」、
`README.md` 命令示例报「134 MCP tools」、`src/server/laya_route.mbt` 报「104 工具」、
`dist/fist-mbt.js` 报「148」（上轮 BUG-155 已报）——真源是 **166**。
修复了 2 处**非投影当前面**（提示词模板 + 源码注释），报告了 README（投影文件）与 check_plugin_sync 红（并发 WIP）。

## 发现：守卫全绿 ≠ 没有漂移面

`check_doc_surface` J14 只扫 `src/server/server.mbt` + `cmd/cli/help_topics.mbt` + `ARCHITECTURE.md` 三面。
**凡是被 git 跟踪、含工具计数自述、但不在 J14 扫描面的文件，计数漂移都无人认领**——与 BUG-136 同族。

全仓 grep `(\d+)\s*(?:个|MCP)?\s*(?:工具|tools?|MCP tools)`（排除 166），得 **166 个候选**——绝大多数是
`memory/`、`reports/`、`docs/` 的**历史记录**（历史计数本就该是旧数，非缺陷）。筛掉历史面，当前面候选：

| 当前面 | 自述 | 真源 | 性质 | 处置 |
|---|---|---|---|---|
| `templates/tool_use_rubric.md` | **134** | 166 | **提示词模板**（注入 agent，最高影响） | **已修** |
| `src/server/laya_route.mbt` | **104** | 166 | 源码 doc comment | **已修** |
| `README.md` L158 | **134** | 166 | 命令示例注释 | 投影文件，未直接改 |
| `dist/fist-mbt.js` | **148** | 166 | 发货正文 | BUG-155 已报 |

## 关键认知：最高影响面是提示词模板

`templates/tool_use_rubric.md` 是 **pipeline 分支 A 第 4 步「按固定结构撰写」时原样追加到提示词末尾**的模板，
「逐字保留、不得改写」。它告诉被驱动的 agent「本项目暴露 134 个工具」，而真源是 166——
**agent 被告知少了 32 个工具**，这直接削弱 tool 幻觉防护的确定性清单基础。属"文档即实现"最高影响缺陷。

## 交付

### ① 修复提示词模板（commit `44e4d4e`）
`templates/tool_use_rubric.md` L13：「暴露 134 个工具」→「暴露 166 个工具」。
LF-only 保留（`check_template_ctrl` PASS，11 份只含 LF/TAB）。

### ② 修复源码 doc comment（commit `44e4d4e`）
`src/server/laya_route.mbt` L3：「104 工具」→「166 工具」。`moon fmt --check` rc=0，diff 只动注释。

### ③ 记录 README 为投影文件（不直接改）
`gen_plugins.py` 把 README.md 列为投影文件之一 ⇒ 直接改会被重生成覆盖。
README 计数主张应由投影真源决定，不是手改散文。已在上轮提交尝试中被回滚，确认此路不通。

## 并发 WIP 观测（用户点名"注意有其他 agent 同步开发"）

**`check_plugin_sync` 当前红**（9 文件与真源投影不一致：README.md + 4×SKILL.md + deepseek-harness 2 件），
`gen_plugins.py --check` 退出码 1。**判定：并发 agent 未提交 WIP 导致**——证据：
① HEAD~1（`63d1017`，我上轮 commit）已 FAIL；② `tool_use_rubric.md` 不在 gen_plugins 投影面（grep 0 提及），
我改模板不构成投影差；③ 并发 agent 在加 router 工具（工作树 13 个未提交文件集中在 `src/router/*`），
真源工具数/分组变了而插件投影未重生成。**未触碰 plugins/，未代修。**

## 验证（金条八：实际运行）

| 项 | 结果 |
|---|---|
| 真源注册表 `_tool_registry.py` | **166 个**（扫 35 份 src/server/*.mbt） |
| `templates/tool_use_rubric.md` 修复 | L13 = 「暴露 166 个工具」✓ |
| `src/server/laya_route.mbt` 修复 | L3 = 「166 工具」✓ |
| `git show HEAD:tool_use_rubric.md` blob | 「166 个工具」（确认入 blob，非仅工作树） |
| `git show HEAD:laya_route.mbt` blob | 「166 工具」 |
| `moon fmt --check src/server/laya_route.mbt` | rc=0 |
| `check_template_ctrl` | PASS（11 份 LF/TAB） |
| `check_doc_surface` / `check_tools_sync` / `check_scripts_index` | PASS |
| `check_plugin_sync` | FAIL（并发 agent WIP，非我引入） |
| 三端同步 | `44e4d4e` |

## 资源消耗

- 2 个提交：`44e4d4e`（模板+源码注释修复）
- 1 次系统性扫描脚本（`temp/scan_counts.py`，全仓 git 跟踪面 grep 计数自述）
- 0 `src/router/*` 触碰；0 plugins/ 触碰

## 任务分配记录

指挥官亲自：
- **设计系统性扫描**：不只查已知面，而是用 grep 从 git 跟踪面反查所有"含工具计数自述"的文件，
  再按"历史 vs 当前"筛——避免只见树木（已知的 dist/）不见森林（还有模板/源码/README）
- **判定最高影响面**：模板 > 源码注释 > README > dist（按是否注入 agent / 是否用户面 / 是否发货正文排序）
- **识别投影文件并收手**：发现 README.md 被 gen_plugins 投影后，**不再直接改**（上轮直接改被回滚，确认此路不通）
- **区分并发 WIP 与自我回归**：用"HEAD~1 是否也红 + 我改的文件是否在投影面"双重判据，
  认定 check_plugin_sync 红属并发 agent，不代修、不越权触碰 plugins/

## 遗留风险

1. **`check_plugin_sync` 红**：并发 agent 加 router 工具未重生成插件投影 ⇒ CI 会红。需他们收口或我方协助重投影（**不主动**，避免覆盖其 WIP）。
2. **README.md 计数主张未修**：投影文件，需在投影真源层修（gen_plugins 的输入），不是散文层。
3. **同类"不在 J14 扫描面"的当前面可能还有**：本轮已系统扫过 git 跟踪面，但**未跟踪但发货的面**（如安装器下载的 `_release` zip 里的产物）不在射程，无法静态扫。
4. **历史面计数不追**：memory/、reports/、docs/ 的历史计数是当时事实，非缺陷，不去改。

## 后续建议

1. **`templates/tool_use_rubric.md` 的 166 应纳入一源四态**：它是注入 agent 的高影响面，建议把
   "提示词模板里的工具总数 == 真源"纳入 J8 或新增子判据，防再漂。
2. **并发 agent 收口后重跑插件投影**：router 工具落定 → `gen_plugins.py` → check_plugin_sync 归绿。
3. **`dist/fist-mbt.js` 仍待 owner 裁决**（BUG-155 三选一）。

## 超额内容

- **量化了漂移面分布**：全仓 166 个"含工具计数自述且≠166"的文件，绝大多数是历史记录（正确），
  当前面只 4 个（模板/源码/README/dist）。说明"计数自述漂移"**主要在历史面，当前面已收敛**，只有
  dist/ 因遗留产物未跟上——这是上轮 BUG-155 的定位。
- **发现"投影文件不可直接改"这一层**：README.md 既是 check_doc_surface 扫描面、又是 gen_plugins 投影面，
  两层语义冲突——文档守卫要它手写正确，投影要它被重写。这是多面契约的重叠区，值得记入长期记忆。

## 来源

- 真源：`scripts/_tool_registry.py`（166 个，扫 35 份 src/server/*.mbt）
- 修复：`templates/tool_use_rubric.md` L13、`src/server/laya_route.mbt` L3
- 投影面：`scripts/gen_plugins.py`（README.md 属投影文件）
- 守卫：`scripts/check_doc_surface.py` J14（三面）、`scripts/check_template_ctrl.py`、`scripts/check_plugin_sync.py`
- 上轮遗留：`memory/bugs.md` BUG-155（dist/fist-mbt.js 148 vs 166）
